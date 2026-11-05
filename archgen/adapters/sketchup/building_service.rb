# frozen_string_literal: true

require 'securerandom'

module Archgen
  module Adapters
    module SketchUp
      BuildingSummary = Struct.new(:persistent_id, :building_uuid, :revision, :name, :plan_digest, :metrics, keyword_init: true)
      LoadedBuilding = Struct.new(:record, :config, keyword_init: true)
      Preview = Struct.new(:config, :plan, :projection, :plan_digest, keyword_init: true)

      # Résout, calcule, vérifie le contexte et tient la transaction. Seul propriétaire
      # de l'opération : writer, ressources et dépôt n'en démarrent jamais.
      class BuildingService
        DEFINITION_NAME = 'ARCHGEN bâtiment'

        def self.default(allow_internal: false)
          registry = Composition.registry
          raise ArgumentError, registry.errors.map(&:to_h).inspect unless registry.ok?

          materials = Composition.materials
          new(registry: registry.value, intake: Composition.intake, materials: materials.fetch('materials'),
              material_revision: materials.fetch('schema_version'), allow_internal: allow_internal)
        end

        def initialize(registry:, intake:, materials:, material_revision:, allow_internal: false, host: NativeHost,
                       writer: nil, repository: nil, uuid: -> { SecureRandom.uuid })
          @registry = registry
          @intake = intake
          @materials = materials
          @material_revision = material_revision
          @allow_internal = allow_internal
          @host = host
          @writer = writer || GeometryWriter.new(host: host)
          @repository = repository || ComponentRepository.new(host: host)
          @uuid = uuid
        end

        # Aucune écriture, aucune trace dans l'Undo. La cible arrive avec AG-013.
        def preview(draft:, model: nil, target: nil)
          prepared = prepare(draft)
          return prepared unless prepared.ok?

          config, plan = prepared.value
          Core::Result.ok(
            Preview.new(config: config, plan: plan, projection: Core::PlanProjection.call(plan),
                        plan_digest: Core::GeometryEngine.plan_digest(plan)),
            prepared.diagnostics
          )
        end

        # Une action réussie = une opération ; un rejet ne touche pas le document.
        def create(model:, draft:)
          prepared = prepare(draft)
          return prepared unless prepared.ok?

          context = context_problem(model)
          return Core::Result.fail([context]) if context

          config, plan = prepared.value
          written = in_operation(model, 'ARCHGEN : créer') { write_new_root(model, config, plan) }
          return written unless written.ok?

          Core::Result.ok(written.value, prepared.diagnostics)
        end

        # Lit une racine sans la modifier : aucun défaut réappliqué, aucune migration.
        def load_building(model:, persistent_id:)
          record = @repository.read(model, persistent_id: persistent_id)
          return record unless record.ok?

          config = Core::ConfigResolver.load_effective(
            record.value.metadata['config_json'], registry: @registry, intake: @intake, allow_internal: @allow_internal
          )
          return config unless config.ok?

          Core::Result.ok(LoadedBuilding.new(record: record.value, config: config.value), config.diagnostics)
        end

        private

        def prepare(draft)
          resolved = Core::ConfigResolver.resolve(draft, registry: @registry, intake: @intake, allow_internal: @allow_internal)
          return resolved unless resolved.ok?

          plan = Core::GeometryEngine.generate(resolved.value, materials: @materials)
          return Core::Result.fail(resolved.diagnostics + plan.diagnostics) unless plan.ok?

          Core::Result.ok([resolved.value, plan.value], resolved.diagnostics + plan.diagnostics)
        end

        # Pas d'écriture depuis un contexte d'édition de groupe ou de composant.
        def context_problem(model)
          return Core::Diagnostic.error('E_TARGET_STALE', '/model', reason: 'model_unavailable') unless model.valid?
          return nil unless model.active_path

          Core::Diagnostic.error('E_TARGET_STALE', '/model', reason: 'nested_edit_context')
        end

        def write_new_root(model, config, plan)
          resources = Resources.new(model, catalog: @materials, revision: @material_revision, host: @host)
          definition = model.definitions.add(DEFINITION_NAME)
          raise WriteError, 'Création de la définition refusée' unless definition

          @writer.write(plan, entities: definition.entities, resources: resources)
          digest = Core::GeometryEngine.plan_digest(plan)
          @writer.mark_definition(definition, plan_digest: digest)
          instance = @repository.insert(model, definition: definition)
          instance.name = config.to_h['name']
          metadata = metadata_for(config, digest)
          @repository.write_metadata(instance, metadata)
          unless @repository.read_metadata(instance) == metadata
            raise WriteError, 'Relecture des métadonnées incohérente'
          end

          BuildingSummary.new(persistent_id: instance.persistent_id, building_uuid: metadata['building_uuid'], revision: 1,
                              name: config.to_h['name'], plan_digest: digest, metrics: plan['metrics'])
        end

        def metadata_for(config, digest)
          {
            'metadata_version' => ComponentRepository::METADATA_VERSION,
            'building_uuid' => @uuid.call,
            'revision' => 1,
            'config_json' => Core::Canonical.dump(config.to_h),
            'plan_digest' => digest,
            'engine_version' => ENGINE_VERSION,
            'material_revision' => @material_revision
          }
        end

        # Les références ne sont rendues que si le commit réussit. Abandon appelé une seule
        # fois ; un abandon refusé est un incident bloquant, jamais un succès.
        def in_operation(model, name)
          return failure('operation_not_started') unless start(model, name)

          begin
            value = yield
          rescue StandardError => e
            return abort_with(model, 'write_failed', e)
          end
          return Core::Result.ok(value) if commit(model)

          abort_with(model, 'commit_failed', nil)
        end

        def start(model, name)
          model.start_operation(name, true)
        rescue StandardError
          false
        end

        def commit(model)
          model.commit_operation
        rescue StandardError
          false
        end

        def abort_with(model, reason, error)
          aborted = begin
            model.abort_operation
          rescue StandardError
            false
          end
          # Le message d'une exception native peut contenir des chemins personnels.
          params = error ? { error: error.class.name } : {}
          params[:detail] = error.message if error.is_a?(WriteError)
          return failure('abort_failed', cause: reason, **params) unless aborted

          failure(reason, **params)
        end

        def failure(reason, **params)
          Core::Result.fail([Core::Diagnostic.error('E_WRITE', '/model', reason: reason, **params)])
        end
      end
    end
  end
end
