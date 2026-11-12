# frozen_string_literal: true

require 'securerandom'

module Archgen
  module Adapters
    module SketchUp
      BuildingSummary = Struct.new(:persistent_id, :building_uuid, :revision, :name, :plan_digest, :metrics, :target, :site_metrics, keyword_init: true)
      LoadedBuilding = Struct.new(:record, :config, :target, keyword_init: true)
      Preview = Struct.new(:config, :plan, :projection, :plan_digest, :base, keyword_init: true)
      SiteSurvey = Struct.new(:settings, :grid, :assise, :survey_digest, keyword_init: true)
      # Une assise calculée, prête à être écrite ; rien n'a encore touché au modèle.
      SiteWrite = Struct.new(:settings, :survey, :site_plan, :site_digest, :terrain_pid, keyword_init: true)

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

        # Export glTF (AG-118) : relit l'unique racine sélectionnée et recalcule ses plans,
        # assise comprise si elle est enregistrée. Lecture seule : ni opération, ni écriture.
        def export_source(model:)
          loaded = load_selection(model: model)
          return loaded unless loaded.ok?

          config = loaded.value.config
          plan = Core::GeometryEngine.generate(config, materials: @materials)
          return plan unless plan.ok?

          site = kept_site(model, loaded.value.record, config, plan.value)
          return site unless site.ok?

          Core::Result.ok({ 'name' => loaded.value.record.instance.name.to_s, 'config' => config, 'plan' => plan.value,
                            'site_plan' => site.value&.site_plan }, loaded.diagnostics + plan.diagnostics + site.diagnostics)
        end

        # Import de carte (AG-129) : brouillon résolu et plan, sans écriture.
        def prepare_import(draft)
          prepare(draft)
        end

        # Écrit une racine préparée et placée ; l'appelant tient l'opération (une seule pour tout l'import).
        def write_imported(model, config, plan, transform)
          write_new_root(model, config, plan, transform: transform)
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
          site = kept_site(model, record, config, plan)
          return site unless site.ok?

          written = @guard.run(model, 'ARCHGEN : régénérer', instance: record.instance) { replace_definition(model, record, config, plan, site: site.value) }
          return written unless written.ok?

          Core::Result.ok(written.value, prepared.diagnostics + site.diagnostics)
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

        # Assise calculée avant confirmation : aucune écriture, aucune opération.
        def preview_site(model:, target:, terrain:, site:)
          loaded = writable_root(model, target)
          return loaded unless loaded.ok?

          settings = site_intake.settings(site)
          return settings unless settings.ok?

          config = loaded.value.config
          plan = Core::GeometryEngine.generate(config, materials: @materials)
          return plan unless plan.ok?

          compute_site(model, loaded.value.record.instance, config, plan.value, settings.value, terrain)
        end

        # Pose la racine sur son assise. Le relevé est refait avant d'écrire : un terrain changé
        # depuis l'aperçu (survey_digest) est refusé sans rien toucher.
        def adapt_to_site(model:, target:, terrain:, site:, survey_digest: nil)
          computed = preview_site(model: model, target: target, terrain: terrain, site: site)
          return computed unless computed.ok?
          return stale('terrain_changed') if survey_digest && computed.value.survey.survey_digest != survey_digest

          loaded = verify_target(model, target).value
          record = loaded.record
          config = loaded.config
          plan = Core::GeometryEngine.generate(config, materials: @materials).value
          written = @guard.run(model, 'ARCHGEN : adapter au terrain', instance: record.instance) do
            replace_definition(model, record, config, plan, site: computed.value)
          end
          written.ok? ? Core::Result.ok(written.value, computed.diagnostics) : written
        end

        # Retire l'assise : nouvelle définition sans elle, dictionnaire retiré, altitude inchangée.
        def remove_site(model:, target:)
          loaded = writable_root(model, target)
          return loaded unless loaded.ok?

          record = loaded.value.record
          return stale('site_absent') unless @repository.read_site(record.instance)

          config = loaded.value.config
          plan = Core::GeometryEngine.generate(config, materials: @materials)
          return plan unless plan.ok?

          @guard.run(model, 'ARCHGEN : retirer l’assise', instance: record.instance) { replace_definition(model, record, config, plan.value, site: nil) }
        end

        # Lecture seule pour le panneau : réglages, terrain et placement enregistrés. nil sans assise.
        def site_status(model:, target:)
          loaded = verify_target(model, target)
          return loaded unless loaded.ok?

          instance = loaded.value.record.instance
          site = @repository.read_site(instance)
          return Core::Result.ok(nil) unless site

          problem = @repository.site_problem(site)
          return Core::Result.fail([problem]) if problem

          settings = site_intake.stored_settings(site['site_json'])
          return settings unless settings.ok?

          moved = Core::StrictJson.parse(site['placement_json']).value != @repository.placement(instance)
          Core::Result.ok('settings' => settings.value, 'terrain_pid' => site['terrain_pid'], 'survey_digest' => site['survey_digest'],
                          'site_digest' => site['site_digest'], 'moved' => moved)
        end

        private

        def stale(reason, **params)
          Core::Result.fail([Core::Diagnostic.error('E_TARGET_STALE', '/target', reason: reason, **params)])
        end

        def site_intake
          @site_intake ||= Composition.site_intake
        end

        def site_catalog
          @site_catalog ||= @materials.merge(Composition.site_materials)
        end

        # Cible vérifiée, versions du bâtiment et de son assise lisibles : on peut y écrire.
        def writable_root(model, target)
          loaded = verify_target(model, target)
          return loaded unless loaded.ok?

          version = version_problem(loaded.value.record.metadata)
          return Core::Result.fail([version]) if version

          problem = @repository.site_problem(@repository.read_site(loaded.value.record.instance))
          problem ? Core::Result.fail([problem]) : loaded
        end

        # Une racine qui a une assise la garde : son terrain est relevé de nouveau pour la
        # nouvelle emprise. Terrain disparu : refus, jamais de retrait silencieux.
        def kept_site(model, record, config, plan)
          stored = @repository.read_site(record.instance)
          return Core::Result.ok(nil) unless stored

          problem = @repository.site_problem(stored)
          return Core::Result.fail([problem]) if problem

          settings = site_intake.stored_settings(stored['site_json'])
          return settings unless settings.ok?

          compute_site(model, record.instance, config, plan, settings.value, TerrainRef.new(document_key: model.guid, persistent_id: stored['terrain_pid']))
        end

        def compute_site(model, instance, config, plan, settings, terrain)
          footprint = config.to_h['footprint']
          axes = Core::SurveyGrid.plan(width_m: footprint['width_m'], depth_m: footprint['depth_m'], settings: settings)
          return axes unless axes.ok?

          surveyed = @surveyor.survey(model, terrain, instance, axes.value)
          return surveyed unless surveyed.ok?

          survey = site_survey(surveyed.value, settings, footprint)
          return survey unless survey.ok?

          planned = Geometry::SitePlanner.call(plan: plan, config: config.to_h, grid: survey.value.grid, settings: settings, assise: survey.value.assise, materials: site_catalog)
          return planned unless planned.ok?

          Core::Result.ok(SiteWrite.new(settings: settings, survey: survey.value, site_plan: planned.value, site_digest: Geometry::SitePlanner.digest(planned.value),
                                        terrain_pid: terrain.persistent_id), planned.diagnostics)
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

        def replace_definition(model, record, config, plan, site: nil)
          definition, digest = write_definition(model, plan, site)
          @repository.swap(record.instance, definition: definition)
          @repository.place_at_altitude(record.instance, site.survey.assise['platform_z_m']) if site
          previous = record.metadata
          uuid = @repository.uuid_shared?(model, previous['building_uuid'], except: record.instance) ? @uuid.call : previous['building_uuid']
          metadata = metadata_for(config, digest, uuid: uuid, revision: previous['revision'] + 1)
          store_metadata(record.instance, metadata)
          store_site(record.instance, site)
          summary_for(model, record.instance, config, plan, metadata, site)
        end

        def store_site(instance, site)
          return @repository.clear_site(instance) unless site

          stored = { 'site_version' => ComponentRepository::SITE_VERSION, 'site_json' => Core::Canonical.dump(site.settings),
                     'survey_digest' => site.survey.survey_digest, 'site_digest' => site.site_digest, 'terrain_pid' => site.terrain_pid,
                     'placement_json' => Core::Canonical.dump(@repository.placement(instance)) }
          @repository.write_site(instance, stored)
          return if @repository.read_site(instance) == stored

          raise WriteError, 'Relecture de l’assise incohérente'
        end

        def write_definition(model, plan, site = nil)
          resources = Resources.new(model, catalog: site ? site_catalog : @materials, revision: @material_revision, host: @host)
          definition = model.definitions.add(DEFINITION_NAME)
          raise WriteError, 'Création de la définition refusée' unless definition

          @writer.write(plan, entities: definition.entities, resources: resources)
          @writer.write_site(site.site_plan, entities: definition.entities, resources: resources) if site
          digest = Core::GeometryEngine.plan_digest(plan)
          @writer.mark_definition(definition, plan_digest: digest)
          [definition, digest]
        end

        def store_metadata(instance, metadata)
          @repository.write_metadata(instance, metadata)
          return if @repository.read_metadata(instance) == metadata

          raise WriteError, 'Relecture des métadonnées incohérente'
        end

        def summary_for(model, instance, config, plan, metadata, site = nil)
          BuildingSummary.new(persistent_id: instance.persistent_id, building_uuid: metadata['building_uuid'], revision: metadata['revision'],
                              name: config.to_h['name'], plan_digest: metadata['plan_digest'], metrics: plan['metrics'],
                              target: target_for(model, instance, metadata), site_metrics: site&.site_plan&.fetch('metrics'))
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

        def write_new_root(model, config, plan, transform: nil)
          definition, digest = write_definition(model, plan)
          instance = transform ? @repository.insert(model, definition: definition, transform: transform) : @repository.insert(model, definition: definition)
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
