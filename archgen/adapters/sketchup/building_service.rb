# frozen_string_literal: true

require 'securerandom'

module Archgen
  module Adapters
    module SketchUp
      BuildingSummary = Struct.new(:persistent_id, :building_uuid, :revision, :name, :plan_digest, :metrics, :target, keyword_init: true)
      LoadedBuilding = Struct.new(:record, :config, :target, keyword_init: true)
      Preview = Struct.new(:config, :plan, :projection, :plan_digest, :base, keyword_init: true)
      SiteSurvey = Struct.new(:settings, :grid, :assise, :survey_digest, keyword_init: true)

      # Résout, calcule, vérifie le contexte et tient la transaction. Seul propriétaire
      # de l'opération : writer, ressources et dépôt n'en démarrent jamais.
      class BuildingService
        DEFINITION_NAME = 'ARCHGEN bâtiment'

        def self.default(allow_internal: false, writer: nil, repository: nil)
          registry = Composition.registry
          raise ArgumentError, registry.errors.map(&:to_h).inspect unless registry.ok?

          materials = Composition.materials
          new(registry: registry.value, intake: Composition.intake, materials: materials.fetch('materials'),
              material_revision: materials.fetch('schema_version'), allow_internal: allow_internal,
              writer: writer, repository: repository)
        end

        def initialize(registry:, intake:, materials:, material_revision:, allow_internal: false, host: NativeHost,
                       writer: nil, repository: nil, surveyor: nil, uuid: -> { SecureRandom.uuid })
          @registry = registry
          @intake = intake
          @materials = materials
          @material_revision = material_revision
          @allow_internal = allow_internal
          @host = host
          @writer = writer || GeometryWriter.new(host: host)
          @repository = repository || ComponentRepository.new(host: host)
          @surveyor = surveyor || TerrainSurveyor.new(host: host)
          @uuid = uuid
          @guard = TransactionGuard.new
        end

        # Aucune écriture, aucune trace dans l'Undo. Avec une cible, l'aperçu part de la
        # configuration enregistrée, relue et revérifiée comme avant une écriture.
        def preview(draft:, model: nil, target: nil)
          base = nil
          if target
            loaded = verify_target(model, target)
            return loaded unless loaded.ok?

            base = loaded.value.config
          end
          prepared = prepare(draft, base: base)
          return prepared unless prepared.ok?

          config, plan = prepared.value
          Core::Result.ok(
            Preview.new(config: config, plan: plan, projection: Core::PlanProjection.call(plan),
                        plan_digest: Core::GeometryEngine.plan_digest(plan), base: base),
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
          written = @guard.run(model, 'ARCHGEN : créer') { write_new_root(model, config, plan) }
          return written unless written.ok?

          Core::Result.ok(written.value, prepared.diagnostics)
        end

        # Lit une racine sans la modifier : aucun défaut réappliqué, aucune migration.
        def load_building(model:, persistent_id:)
          record = @repository.read(model, persistent_id: persistent_id)
          return record unless record.ok?

          load_record(model, record.value)
        end

        # Lit l'unique racine sélectionnée. Lecture seule, aucun UUID n'est réécrit ici.
        def load_selection(model:)
          selection = model.selection
          return stale('selection_not_single') unless selection.length == 1

          record = @repository.read_instance(model, selection.first)
          return record unless record.ok?

          load_record(model, record.value)
        end

        # Remplace la géométrie d'une seule instance : racine, placement, nom, tag et
        # attributs tiers sont conservés ; l'ancienne définition n'est jamais touchée.
        def regenerate(model:, target:, draft:)
          loaded = verify_target(model, target)
          return loaded unless loaded.ok?

          version = version_problem(loaded.value.record.metadata)
          return Core::Result.fail([version]) if version

          prepared = prepare(draft, base: loaded.value.config)
          return prepared unless prepared.ok?

          config, plan = prepared.value
          record = loaded.value.record
          written = @guard.run(model, 'ARCHGEN : régénérer', instance: record.instance) { replace_definition(model, record, config, plan) }
          return written unless written.ok?

          Core::Result.ok(written.value, prepared.diagnostics)
        end

        # La sélection courante devient le terrain retenu. Aucune écriture.
        def retain_terrain(model:)
          context = context_problem(model)
          context ? Core::Result.fail([context]) : @surveyor.retain(model)
        end

        # Relève le terrain sous la racine ciblée et calcule l'assise. Aucune écriture, aucune
        # opération : le relevé peut être refait autant que nécessaire avant de confirmer.
        def survey_site(model:, target:, terrain:, site:)
          loaded = verify_target(model, target)
          return loaded unless loaded.ok?

          settings = site_intake.settings(site)
          return settings unless settings.ok?

          footprint = loaded.value.config.to_h['footprint']
          axes = Core::SurveyGrid.plan(width_m: footprint['width_m'], depth_m: footprint['depth_m'], settings: settings.value)
          return axes unless axes.ok?

          surveyed = @surveyor.survey(model, terrain, loaded.value.record.instance, axes.value)
          return surveyed unless surveyed.ok?

          site_survey(surveyed.value, settings.value, footprint)
        end

        private

        def stale(reason, **params)
          Core::Result.fail([Core::Diagnostic.error('E_TARGET_STALE', '/target', reason: reason, **params)])
        end

        def site_intake
          @site_intake ||= Composition.site_intake
        end

        def site_survey(tree, settings, footprint)
          size = { width_m: footprint['width_m'], depth_m: footprint['depth_m'] }
          grid = site_intake.grid(tree, settings: settings, **size)
          return grid unless grid.ok?

          assise = Core::SiteAssise.call(grid.value, settings, **size)
          return assise unless assise.ok?

          Core::Result.ok(SiteSurvey.new(settings: settings, grid: grid.value, assise: assise.value, survey_digest: grid.value.digest))
        end

        def load_record(model, record)
          config = Core::ConfigResolver.load_effective(
            record.metadata['config_json'], registry: @registry, intake: @intake, allow_internal: @allow_internal
          )
          return config unless config.ok?

          Core::Result.ok(LoadedBuilding.new(record: record, config: config.value, target: target_for(model, record.instance, record.metadata)),
                          config.diagnostics)
        end

        def target_for(model, instance, metadata)
          TargetRef.new(document_key: model.guid, persistent_id: instance.persistent_id, definition_id: instance.definition.persistent_id,
                        revision: metadata['revision'], config_digest: Core::Canonical.digest(Core::StrictJson.parse(metadata['config_json']).value))
        end

        # Relit l'entité avant chaque écriture : rien de ce que dit l'interface n'est cru.
        def verify_target(model, target)
          context = context_problem(model)
          return Core::Result.fail([context]) if context
          return stale('invalid_target') unless target.is_a?(TargetRef)
          # Avant toute lecture : un même PID peut exister dans un autre document.
          return stale('document_changed') unless target.document_key == model.guid

          loaded = load_building(model: model, persistent_id: target.persistent_id)
          return loaded unless loaded.ok?

          problem = target_problem(model, target, loaded.value)
          problem ? stale(problem) : loaded
        end

        def target_problem(model, target, loaded)
          instance = loaded.record.instance
          return 'selection_changed' unless model.selection.length == 1 && model.selection.first == instance
          return 'target_locked' if instance.locked?
          return 'non_rigid_transform' unless @repository.rigid_direct?(instance.transformation)
          return 'definition_changed' unless instance.definition.persistent_id == target.definition_id
          return 'revision_changed' unless loaded.target.revision == target.revision
          return 'config_changed' unless loaded.target.config_digest == target.config_digest

          nil
        end

        def replace_definition(model, record, config, plan)
          definition, digest = write_definition(model, plan)
          @repository.swap(record.instance, definition: definition)
          previous = record.metadata
          uuid = @repository.uuid_shared?(model, previous['building_uuid'], except: record.instance) ? @uuid.call : previous['building_uuid']
          metadata = metadata_for(config, digest, uuid: uuid, revision: previous['revision'] + 1)
          store_metadata(record.instance, metadata)
          summary_for(model, record.instance, config, plan, metadata)
        end

        def write_definition(model, plan)
          resources = Resources.new(model, catalog: @materials, revision: @material_revision, host: @host)
          definition = model.definitions.add(DEFINITION_NAME)
          raise WriteError, 'Création de la définition refusée' unless definition

          @writer.write(plan, entities: definition.entities, resources: resources)
          digest = Core::GeometryEngine.plan_digest(plan)
          @writer.mark_definition(definition, plan_digest: digest)
          [definition, digest]
        end

        def store_metadata(instance, metadata)
          @repository.write_metadata(instance, metadata)
          return if @repository.read_metadata(instance) == metadata

          raise WriteError, 'Relecture des métadonnées incohérente'
        end

        def summary_for(model, instance, config, plan, metadata)
          BuildingSummary.new(persistent_id: instance.persistent_id, building_uuid: metadata['building_uuid'], revision: metadata['revision'],
                              name: config.to_h['name'], plan_digest: metadata['plan_digest'], metrics: plan['metrics'],
                              target: target_for(model, instance, metadata))
        end

        def prepare(draft, base: nil)
          resolved = Core::ConfigResolver.resolve(draft, registry: @registry, intake: @intake, base: base, allow_internal: @allow_internal)
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
          definition, digest = write_definition(model, plan)
          instance = @repository.insert(model, definition: definition)
          instance.name = config.to_h['name']
          metadata = metadata_for(config, digest, uuid: @uuid.call, revision: 1)
          store_metadata(instance, metadata)
          summary_for(model, instance, config, plan, metadata)
        end

        def metadata_for(config, digest, uuid:, revision:)
          {
            'metadata_version' => ComponentRepository::METADATA_VERSION,
            'building_uuid' => uuid,
            'revision' => revision,
            'config_json' => Core::Canonical.dump(config.to_h),
            'plan_digest' => digest,
            'engine_version' => ENGINE_VERSION,
            'material_revision' => @material_revision
          }
        end

        # Un moteur ou un catalogue plus récent a produit ce bâtiment : consultable, non
        # régénérable, pour ne jamais l'écraser avec des règles plus anciennes.
        def version_problem(metadata)
          engine = Integer(metadata['engine_version'], exception: false)
          if engine.nil? || engine > Integer(ENGINE_VERSION)
            return Core::Diagnostic.error('E_VERSION', '/metadata/engine_version', reason: 'newer_engine',
                                          value: metadata['engine_version'], supported: ENGINE_VERSION)
          end
          return nil unless metadata['material_revision'] > @material_revision

          Core::Diagnostic.error('E_VERSION', '/metadata/material_revision', reason: 'newer_materials',
                                 value: metadata['material_revision'], supported: @material_revision)
        end
      end
    end
  end
end
