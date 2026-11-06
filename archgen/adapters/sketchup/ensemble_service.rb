# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      EnsembleSummary = Struct.new(:persistent_id, :revision, :ensemble_digest, :metrics, :target, keyword_init: true)
      EnsemblePreview = Struct.new(:settings, :plan, :ensemble_digest, keyword_init: true)
      LoadedEnsemble = Struct.new(:record, :settings, :target, keyword_init: true)

      # Écrit et relit une racine d'ensemble (docs/ENSEMBLE_CONTRACT.md, Écriture et
      # persistance). Une validation = une opération, quel que soit le nombre de bâtiments.
      class EnsembleService
        DEFINITION_NAME = 'ARCHGEN ensemble'
        PARCEL_DEFINITION_NAME = 'ARCHGEN parcelle'
        ROOT_NAME = 'Ensemble ARCHGEN'
        METERS_PER_INCH = 0.0254

        def self.default(writer: nil)
          registry = Composition.registry
          raise ArgumentError, registry.errors.map(&:to_h).inspect unless registry.ok?

          materials = Composition.materials
          new(registry: registry.value, intake: Composition.intake, ensemble_intake: Composition.ensemble_intake,
              materials: materials.fetch('materials'), material_revision: materials.fetch('schema_version'), writer: writer)
        end

        def initialize(registry:, intake:, ensemble_intake:, materials:, material_revision:, host: NativeHost, writer: nil, repository: nil, limits: Core::EnsembleEngine::DEFAULT_LIMITS)
          @registry = registry
          @intake = intake
          @ensemble_intake = ensemble_intake
          @materials = materials
          @material_revision = material_revision
          @host = host
          @writer = writer || GeometryWriter.new(host: host)
          @repository = repository || EnsembleRepository.new(host: host)
          @roots = ComponentRepository.new(host: host)
          @limits = limits
          @guard = TransactionGuard.new
        end

        # Aucune écriture, aucune trace dans l'Undo.
        def preview(tree:)
          settings = @ensemble_intake.settings(tree)
          settings.ok? ? compute(settings.value) : settings
        end

        # origin_m : le premier point du tracé, dans le repère du modèle.
        def create(model:, tree:, origin_m:)
          computed = preview(tree: tree)
          return computed unless computed.ok?

          problem = context_problem(model) || origin_problem(origin_m)
          return Core::Result.fail([problem]) if problem

          written = @guard.run(model, 'ARCHGEN : créer un ensemble') { write_new_root(model, computed.value, origin_m) }
          written.ok? ? Core::Result.ok(written.value, computed.diagnostics) : written
        end

        def load(model:, persistent_id:)
          record = @repository.read(model, persistent_id: persistent_id)
          record.ok? ? load_record(model, record.value) : record
        end

        def load_selection(model:)
          selection = model.selection
          return stale('selection_not_single') unless selection.length == 1

          record = @repository.read_instance(model, selection.first)
          record.ok? ? load_record(model, record.value) : record
        end

        # Régénère tout l'ensemble dans une définition fraîche ; une copie garde la sienne.
        # `changes` : champs à modifier, fusionnés sur les réglages enregistrés.
        def regenerate(model:, target:, changes: {})
          loaded = verify_target(model, target)
          return loaded unless loaded.ok?

          version = version_problem(loaded.value.record.metadata)
          return Core::Result.fail([version]) if version

          computed = preview(tree: Core::Merge.leaves(loaded.value.settings, changes))
          return computed unless computed.ok?

          record = loaded.value.record
          written = @guard.run(model, 'ARCHGEN : régénérer l’ensemble', instance: record.instance) { replace_definition(model, record, computed.value) }
          written.ok? ? Core::Result.ok(written.value, computed.diagnostics) : written
        end

        private

        def stale(reason, **params)
          Core::Result.fail([Core::Diagnostic.error('E_TARGET_STALE', '/target', reason: reason, **params)])
        end

        def compute(settings)
          plan = Core::EnsembleEngine.call(settings, registry: @registry, intake: @intake, materials: @materials, limits: @limits)
          return plan unless plan.ok?

          Core::Result.ok(EnsemblePreview.new(settings: settings, plan: plan.value, ensemble_digest: Core::EnsembleEngine.digest(plan.value)), plan.diagnostics)
        end

        def context_problem(model)
          return Core::Diagnostic.error('E_TARGET_STALE', '/model', reason: 'model_unavailable') unless model.valid?
          return nil unless model.active_path

          Core::Diagnostic.error('E_TARGET_STALE', '/model', reason: 'nested_edit_context')
        end

        def origin_problem(origin)
          return nil if origin.is_a?(Array) && origin.size == 3 && origin.all? { |c| c.is_a?(Numeric) && c.to_f.finite? }

          Core::Diagnostic.error('E_SCHEMA', '/origin_m', reason: 'invalid_origin')
        end

        def write_new_root(model, computed, origin)
          definition = write_definition(model, computed)
          instance = @roots.insert(model, definition: definition, transform: @host.transformation(translation(origin)))
          instance.name = ROOT_NAME
          finish(model, instance, computed, 1)
        end

        def replace_definition(model, record, computed)
          @roots.swap(record.instance, definition: write_definition(model, computed))
          finish(model, record.instance, computed, record.metadata['revision'] + 1)
        end

        def finish(model, instance, computed, revision)
          metadata = metadata_for(computed, revision)
          @repository.write(instance, metadata)
          raise WriteError, 'Relecture des métadonnées incohérente' unless @repository.read_metadata(instance) == metadata

          EnsembleSummary.new(persistent_id: instance.persistent_id, revision: revision, ensemble_digest: computed.ensemble_digest,
                              metrics: computed.plan['metrics'], target: target_for(model, instance, metadata))
        end

        def metadata_for(computed, revision)
          {
            'ensemble_version' => EnsembleRepository::VERSION,
            'revision' => revision,
            'ensemble_json' => Core::Canonical.dump(computed.settings),
            'ensemble_digest' => computed.ensemble_digest,
            'engine_version' => ENGINE_VERSION,
            'material_revision' => @material_revision
          }
        end

        # Un bâtiment par définition du plan, une instance par parcelle : le partage du plan
        # se retrouve dans le fichier. La barre d'état suit, car l'écriture peut durer.
        def write_definition(model, computed)
          plan = computed.plan
          resources = Resources.new(model, catalog: @materials, revision: @material_revision, host: @host)
          parcels = {}
          plan['definitions'].each_with_index do |(id, row_plan), index|
            parcels[id] = write_parcel_definition(model, row_plan, resources)
            @host.status("ARCHGEN : bâtiment #{index + 1} sur #{plan['definitions'].size}")
          end
          definition = model.definitions.add(DEFINITION_NAME)
          raise WriteError, 'Création de la définition refusée' unless definition

          plan['parcels'].each { |parcel| place_parcel(definition, parcel, parcels.fetch(parcel['definition_id'])) }
          definition
        end

        def write_parcel_definition(model, row_plan, resources)
          definition = model.definitions.add(PARCEL_DEFINITION_NAME)
          raise WriteError, 'Création de la définition refusée' unless definition

          @writer.write(row_plan, entities: definition.entities, resources: resources)
          @writer.mark_definition(definition, plan_digest: Core::GeometryEngine.plan_digest(row_plan), kind: 'parcel')
          definition
        end

        def place_parcel(definition, parcel, parcel_definition)
          instance = definition.entities.add_instance(parcel_definition, @host.transformation(inches(parcel['matrix'])))
          raise WriteError, "Parcelle refusée : #{parcel['id']}" unless instance

          instance.name = parcel['id']
        end

        def inches(matrix)
          matrix.each_with_index.map { |value, index| [12, 13, 14].include?(index) ? value / METERS_PER_INCH : value }
        end

        def translation(origin)
          inches([1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, origin[0].to_f, origin[1].to_f, origin[2].to_f, 1.0])
        end

        def load_record(model, record)
          settings = @ensemble_intake.settings(record.metadata['ensemble_json'])
          return settings unless settings.ok?

          Core::Result.ok(LoadedEnsemble.new(record: record, settings: settings.value, target: target_for(model, record.instance, record.metadata)))
        end

        def target_for(model, instance, metadata)
          EnsembleTarget.new(document_key: model.guid, persistent_id: instance.persistent_id, definition_id: instance.definition.persistent_id,
                             revision: metadata['revision'], ensemble_digest: metadata['ensemble_digest'])
        end

        # Relit l'entité avant chaque écriture : rien de ce que dit l'interface n'est cru.
        def verify_target(model, target)
          context = context_problem(model)
          return Core::Result.fail([context]) if context
          return stale('invalid_target') unless target.is_a?(EnsembleTarget)
          return stale('document_changed') unless target.document_key == model.guid

          loaded = load(model: model, persistent_id: target.persistent_id)
          return loaded unless loaded.ok?

          problem = target_problem(model, target, loaded.value)
          problem ? stale(problem) : loaded
        end

        def target_problem(model, target, loaded)
          instance = loaded.record.instance
          return 'selection_changed' unless model.selection.length == 1 && model.selection.first == instance
          return 'target_locked' if instance.locked?
          return 'non_rigid_transform' unless @roots.rigid_direct?(instance.transformation)
          return 'definition_changed' unless instance.definition.persistent_id == target.definition_id
          return 'revision_changed' unless loaded.target.revision == target.revision
          return 'config_changed' unless loaded.target.ensemble_digest == target.ensemble_digest

          nil
        end

        # Un moteur ou un catalogue plus récent : consultable, jamais écrasé par des règles anciennes.
        def version_problem(metadata)
          engine = Integer(metadata['engine_version'], exception: false)
          if engine.nil? || engine > Integer(ENGINE_VERSION)
            return Core::Diagnostic.error('E_VERSION', '/metadata/engine_version', reason: 'newer_engine', value: metadata['engine_version'], supported: ENGINE_VERSION)
          end
          return nil unless metadata['material_revision'] > @material_revision

          Core::Diagnostic.error('E_VERSION', '/metadata/material_revision', reason: 'newer_materials', value: metadata['material_revision'], supported: @material_revision)
        end
      end
    end
  end
end
