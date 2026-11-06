# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      EnsembleSummary = Struct.new(:persistent_id, :revision, :ensemble_digest, :metrics, :target, keyword_init: true)
      EnsemblePreview = Struct.new(:settings, :plan, :ensemble_digest, keyword_init: true)
      LoadedEnsemble = Struct.new(:record, :settings, :target, keyword_init: true)
      EnsembleSiteWrite = Struct.new(:settings, :site_plan, :site_digest, :survey_digest, :terrain_pid, keyword_init: true)

      # Écrit et relit une racine d'ensemble (docs/ENSEMBLE_CONTRACT.md, Écriture et
      # persistance). Une validation = une opération, quel que soit le nombre de bâtiments.
      class EnsembleService
        DEFINITION_NAME = 'ARCHGEN ensemble'
        PARCEL_DEFINITION_NAME = 'ARCHGEN parcelle'
        SITE_DEFINITION_NAME = 'ARCHGEN assise'
        ROOT_NAME = 'Ensemble ARCHGEN'
        METERS_PER_INCH = 0.0254

        def self.default(writer: nil)
          registry = Composition.registry
          raise ArgumentError, registry.errors.map(&:to_h).inspect unless registry.ok?

          materials = Composition.materials
          new(registry: registry.value, intake: Composition.intake, ensemble_intake: Composition.ensemble_intake,
              materials: materials.fetch('materials'), material_revision: materials.fetch('schema_version'), writer: writer)
        end

        def initialize(registry:, intake:, ensemble_intake:, materials:, material_revision:, host: NativeHost, writer: nil, repository: nil, surveyor: nil, limits: Core::EnsembleEngine::DEFAULT_LIMITS)
          @registry = registry
          @intake = intake
          @ensemble_intake = ensemble_intake
          @materials = materials
          @material_revision = material_revision
          @host = host
          @writer = writer || GeometryWriter.new(host: host)
          @repository = repository || EnsembleRepository.new(host: host)
          @roots = ComponentRepository.new(host: host)
          @surveyor = surveyor || TerrainSurveyor.new(host: host)
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
          return stale('ensemble_selection_not_single') unless selection.length == 1

          record = @repository.read_instance(model, selection.first)
          record.ok? ? load_record(model, record.value) : record
        end

        # Régénère tout l'ensemble dans une définition fraîche ; une copie garde la sienne.
        # `changes` : champs à modifier, fusionnés sur les réglages enregistrés ; `replace` : réglages complets.
        def regenerate(model:, target:, changes: {}, replace: nil)
          loaded = verify_target(model, target)
          return loaded unless loaded.ok?

          version = version_problem(loaded.value.record.metadata)
          return Core::Result.fail([version]) if version

          computed = preview(tree: replace || Core::Merge.leaves(loaded.value.settings, changes))
          return computed unless computed.ok?

          record = loaded.value.record
          site = kept_site(model, record, computed.value)
          return site unless site.ok?

          written = @guard.run(model, 'ARCHGEN : régénérer l’ensemble', instance: record.instance) { replace_definition(model, record, computed.value, site: site.value) }
          written.ok? ? Core::Result.ok(written.value, computed.diagnostics + site.diagnostics) : written
        end

        # --- Étagement (docs/TERRAIN_CONTRACT.md).

        # La sélection courante devient le terrain retenu. Aucune écriture.
        def retain_terrain(model:)
          context = context_problem(model)
          context ? Core::Result.fail([context]) : @surveyor.retain(model)
        end

        # Relève le terrain sous chaque parcelle et calcule l'étagement. Aucune écriture, aucune opération.
        def preview_site(model:, target:, terrain:, site:)
          loaded = writable_root(model, target)
          return loaded unless loaded.ok?

          settings = site_intake.settings(site)
          return settings unless settings.ok?

          computed = compute(loaded.value.settings)
          computed.ok? ? compute_site(model, loaded.value.record.instance, computed.value, settings.value, terrain) : computed
        end

        # Le relevé est refait avant d'écrire : un résultat différent de l'aperçu est refusé sans rien toucher.
        def adapt_to_site(model:, target:, terrain:, site:, site_digest: nil)
          computed = preview_site(model: model, target: target, terrain: terrain, site: site)
          return computed unless computed.ok?
          return stale('terrain_changed') if site_digest && computed.value.site_digest != site_digest

          loaded = verify_target(model, target).value
          ensemble = compute(loaded.settings).value
          written = @guard.run(model, 'ARCHGEN : adapter au terrain', instance: loaded.record.instance) { replace_definition(model, loaded.record, ensemble, site: computed.value) }
          written.ok? ? Core::Result.ok(written.value, computed.diagnostics) : written
        end

        # Parcelles ramenées à z = 0, dictionnaire retiré, racine immobile.
        def remove_site(model:, target:)
          loaded = writable_root(model, target)
          return loaded unless loaded.ok?

          record = loaded.value.record
          return stale('site_absent') unless @roots.read_site(record.instance)

          ensemble = compute(loaded.value.settings)
          return ensemble unless ensemble.ok?

          @guard.run(model, 'ARCHGEN : retirer l’assise', instance: record.instance) { replace_definition(model, record, ensemble.value, site: nil) }
        end

        # Lecture seule pour le panneau : réglages, terrain et placement enregistrés. nil sans assise.
        def site_status(model:, target:)
          loaded = verify_target(model, target)
          return loaded unless loaded.ok?

          instance = loaded.value.record.instance
          stored = @roots.read_site(instance)
          return Core::Result.ok(nil) unless stored

          problem = @roots.site_problem(stored)
          return Core::Result.fail([problem]) if problem

          settings = site_intake.stored_settings(stored['site_json'])
          return settings unless settings.ok?

          moved = Core::StrictJson.parse(stored['placement_json']).value != placement(instance)
          Core::Result.ok('settings' => settings.value, 'terrain_pid' => stored['terrain_pid'], 'site_digest' => stored['site_digest'], 'moved' => moved)
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

        def site_intake
          @site_intake ||= Composition.site_intake
        end

        def site_catalog
          @site_catalog ||= @materials.merge(Composition.site_materials)
        end

        def writable_root(model, target)
          loaded = verify_target(model, target)
          return loaded unless loaded.ok?

          version = version_problem(loaded.value.record.metadata)
          return Core::Result.fail([version]) if version

          problem = @roots.site_problem(@roots.read_site(loaded.value.record.instance))
          problem ? Core::Result.fail([problem]) : loaded
        end

        # Une racine qui a une assise la garde : son terrain est relevé de nouveau. Jamais de retrait silencieux.
        def kept_site(model, record, computed)
          stored = @roots.read_site(record.instance)
          return Core::Result.ok(nil) unless stored

          problem = @roots.site_problem(stored)
          return Core::Result.fail([problem]) if problem

          settings = site_intake.stored_settings(stored['site_json'])
          return settings unless settings.ok?

          compute_site(model, record.instance, computed, settings.value, TerrainRef.new(document_key: model.guid, persistent_id: stored['terrain_pid']))
        end

        def compute_site(model, instance, computed, settings, terrain)
          layout = Core::EnsembleEngine.layout_for(computed.settings, registry: @registry)
          return layout unless layout.ok?

          requests = Core::EnsembleSite.requests(computed.plan, layout.value, settings)
          return requests unless requests.ok?

          grids = survey_parcels(model, terrain, instance, requests.value)
          return grids unless grids.ok?

          root_z = instance.transformation.to_a[14] * METERS_PER_INCH
          planned = Core::EnsembleSite.call(settings: computed.settings, site: settings, plan: computed.plan, layout: layout.value, grids: grids.value,
                                            root_z_m: root_z, registry: @registry, intake: @intake, materials: site_catalog, limits: @limits)
          return planned unless planned.ok?

          survey_digest = Core::Canonical.digest(grids.value.transform_values(&:digest))
          Core::Result.ok(EnsembleSiteWrite.new(settings: settings, site_plan: planned.value, site_digest: Core::EnsembleSite.digest(planned.value),
                                                survey_digest: survey_digest, terrain_pid: terrain.persistent_id), planned.diagnostics)
        end

        def survey_parcels(model, terrain, instance, requests)
          root = instance.transformation.to_a
          grids = {}
          requests.each_with_index do |request, index|
            @host.status("ARCHGEN : relevé de la parcelle #{index + 1} sur #{requests.size}")
            tree = @surveyor.survey_matrix(model, terrain, in_root(root, request['matrix']), request['axes'])
            return located(tree, request['id']) unless tree.ok?

            grid = site_intake.parcel_grid(tree.value, request['axes'])
            return located(grid, request['id']) unless grid.ok?

            grids[request['id']] = grid.value
          end
          @host.status('')
          Core::Result.ok(grids)
        end

        def located(result, id)
          Core::Result.fail(result.errors.map { |d| Core::ParcelBuilding.relocate(d, 'id' => id) })
        end

        # Du repère de la parcelle au modèle, translation en pouces ; le Z vertical reste celui de la racine.
        def in_root(root, parcel)
          x = parcel[12] / METERS_PER_INCH
          y = parcel[13] / METERS_PER_INCH
          out = root.dup
          out[0] = (root[0] * parcel[0]) + (root[4] * parcel[1])
          out[1] = (root[1] * parcel[0]) + (root[5] * parcel[1])
          out[4] = (root[0] * parcel[4]) + (root[4] * parcel[5])
          out[5] = (root[1] * parcel[4]) + (root[5] * parcel[5])
          out[12] = (root[0] * x) + (root[4] * y) + root[12]
          out[13] = (root[1] * x) + (root[5] * y) + root[13]
          out
        end

        # X, Y et axe de la racine, plus le Z : il décide de l'étagement.
        def placement(instance)
          @roots.placement(instance) + [Core::Quant.q(instance.transformation.to_a[14] * METERS_PER_INCH)]
        end

        def store_site(instance, site)
          return @roots.clear_site(instance) unless site

          stored = { 'site_version' => ComponentRepository::SITE_VERSION, 'site_json' => Core::Canonical.dump(site.settings),
                     'survey_digest' => site.survey_digest, 'site_digest' => site.site_digest, 'terrain_pid' => site.terrain_pid,
                     'placement_json' => Core::Canonical.dump(placement(instance)) }
          @roots.write_site(instance, stored)
          raise WriteError, 'Relecture de l’assise incohérente' unless @roots.read_site(instance) == stored
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

        def replace_definition(model, record, computed, site: nil)
          @roots.swap(record.instance, definition: write_definition(model, computed, site))
          store_site(record.instance, site)
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
        def write_definition(model, computed, site = nil)
          plan = computed.plan
          resources = Resources.new(model, catalog: site ? site_catalog : @materials, revision: @material_revision, host: @host)
          parcels = {}
          plan['definitions'].each_with_index do |(id, row_plan), index|
            parcels[id] = write_parcel_definition(model, row_plan, resources)
            @host.status("ARCHGEN : bâtiment #{index + 1} sur #{plan['definitions'].size}")
          end
          definition = model.definitions.add(DEFINITION_NAME)
          raise WriteError, 'Création de la définition refusée' unless definition

          levels = site ? site.site_plan['parcels'].to_h { |entry| [entry['id'], entry] } : {}
          site_definitions = site ? write_site_definitions(model, site.site_plan, resources) : {}
          plan['parcels'].each do |parcel|
            entry = levels[parcel['id']]
            place_parcel(definition, parcel, parcels.fetch(parcel['definition_id']), entry ? entry['level_m'] : 0.0)
            place_site(definition, parcel, site_definitions.fetch(entry['site_definition_id']), entry) if entry
          end
          @host.status('')
          definition
        end

        def write_parcel_definition(model, row_plan, resources)
          definition = model.definitions.add(PARCEL_DEFINITION_NAME)
          raise WriteError, 'Création de la définition refusée' unless definition

          @writer.write(row_plan, entities: definition.entities, resources: resources)
          @writer.mark_definition(definition, plan_digest: Core::GeometryEngine.plan_digest(row_plan), kind: 'parcel')
          definition
        end

        def place_parcel(definition, parcel, parcel_definition, level_m = 0.0)
          instance = definition.entities.add_instance(parcel_definition, @host.transformation(inches(at_level(parcel['matrix'], level_m))))
          raise WriteError, "Parcelle refusée : #{parcel['id']}" unless instance

          instance.name = parcel['id']
        end

        def write_site_definitions(model, site_plan, resources)
          site_plan['definitions'].to_h do |id, site_definition|
            definition = model.definitions.add(SITE_DEFINITION_NAME)
            raise WriteError, 'Création de la définition refusée' unless definition

            @writer.write_site(site_definition, entities: definition.entities, resources: resources)
            [id, definition]
          end
        end

        def place_site(definition, parcel, site_definition, entry)
          instance = definition.entities.add_instance(site_definition, @host.transformation(inches(at_level(parcel['matrix'], entry['level_m']))))
          raise WriteError, "Assise refusée : #{parcel['id']}" unless instance

          instance.name = "#{parcel['id']}/assise"
        end

        def at_level(matrix, level_m)
          out = matrix.dup
          out[14] = level_m
          out
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
