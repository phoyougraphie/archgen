# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      RoadSummary = Struct.new(:persistent_id, :revision, :road_digest, :metrics, :target, keyword_init: true)
      RoadPreview = Struct.new(:settings, :plan, :road_digest, keyword_init: true)
      LoadedRoad = Struct.new(:record, :settings, :target, keyword_init: true)

      # Écrit et relit une racine de voie (docs/VOIRIE_CONTRACT.md, Écriture et persistance).
      # Une validation = une opération, quel que soit le nombre d'objets ; un refus ne touche à rien.
      class RoadService
        DEFINITION_NAME = 'ARCHGEN voie'
        ROOT_NAME = 'Voie ARCHGEN'
        METERS_PER_INCH = 0.0254

        def self.default(writer: nil)
          materials = Composition.road_catalog
          new(intake: Composition.road_intake, bands: Composition.road_bands, items: Composition.road_items,
              materials: materials, material_revision: Composition.road_materials.fetch('schema_version'), writer: writer)
        end

        def initialize(intake:, bands:, items:, materials:, material_revision:, host: NativeHost, writer: nil, repository: nil, limits: {})
          @intake = intake
          @bands = bands
          @items = items
          @materials = materials
          @material_revision = material_revision
          @host = host
          @writer = writer || GeometryWriter.new(host: host)
          @repository = repository || RoadRepository.new(host: host)
          @roots = ComponentRepository.new(host: host)
          @limits = limits
          @guard = TransactionGuard.new
        end

        # Aucune écriture, aucune trace dans l'Undo.
        def preview(tree:)
          settings = @intake.settings(tree)
          return settings unless settings.ok?

          plan = Core::RoadEngine.call(settings.value, bands: @bands, items: @items, limits: @limits)
          return plan unless plan.ok?

          Core::Result.ok(RoadPreview.new(settings: settings.value, plan: plan.value, road_digest: Core::RoadEngine.digest(plan.value)),
                          settings.diagnostics + plan.diagnostics)
        end

        # origin_m : le premier point du tracé, dans le repère du modèle.
        def create(model:, tree:, origin_m:)
          computed = preview(tree: tree)
          return computed unless computed.ok?

          problem = context_problem(model) || origin_problem(origin_m)
          return Core::Result.fail([problem]) if problem

          written = @guard.run(model, labels[:create]) { write_new_root(model, computed.value, origin_m) }
          written.ok? ? Core::Result.ok(written.value, computed.diagnostics) : written
        end

        def load(model:, persistent_id:)
          record = @repository.read(model, persistent_id: persistent_id)
          record.ok? ? load_record(model, record.value) : record
        end

        def load_selection(model:)
          selection = model.selection
          return stale('road_selection_not_single') unless selection.length == 1

          record = @repository.read_instance(model, selection.first)
          record.ok? ? load_record(model, record.value) : record
        end

        # La voie entière est réécrite dans une définition fraîche ; une copie garde la sienne.
        # `changes` : champs fusionnés sur les réglages enregistrés (la coupe se remplace en entier).
        def regenerate(model:, target:, changes: {})
          loaded = verify_target(model, target)
          return loaded unless loaded.ok?

          version = version_problem(loaded.value.record.metadata)
          return Core::Result.fail([version]) if version

          computed = preview(tree: merged(loaded.value.settings, changes))
          return computed unless computed.ok?

          record = loaded.value.record
          written = @guard.run(model, labels[:regenerate], instance: record.instance) do
            @roots.swap(record.instance, definition: write_definition(model, computed.value))
            finish(model, record.instance, computed.value, record.metadata['revision'] + 1)
          end
          written.ok? ? Core::Result.ok(written.value, computed.diagnostics) : written
        end

        private

        # Libellés d'Annuler, matière d'écriture : un réseau (NetworkService) remplace ceux-ci.
        def labels
          { create: 'ARCHGEN : créer une voie', regenerate: 'ARCHGEN : régénérer la voie', kind: 'road', writing: 'de la voie',
            definition: self.class::DEFINITION_NAME, root: self.class::ROOT_NAME }
        end

        def merged(settings, changes)
          base = settings.reject { |k, _| changes.key?(k) }
          trace = changes['trace'] ? settings['trace'].merge(changes['trace']) : settings['trace']
          base.merge(changes).merge('trace' => trace)
        end

        def stale(reason, **params)
          Core::Result.fail([Core::Diagnostic.error('E_TARGET_STALE', '/target', reason: reason, **params)])
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
          instance.name = labels[:root]
          finish(model, instance, computed, 1)
        end

        # Le writer écrit chaque famille sous sa balise ; les objets répétés sont des instances partagées.
        def write_definition(model, computed)
          definition = model.definitions.add(labels[:definition])
          raise WriteError, 'Création de la définition refusée' unless definition

          @host.status("ARCHGEN : écriture #{labels[:writing]}, #{computed.plan['metrics']['item_count']} objets")
          resources = Resources.new(model, catalog: @materials, revision: @material_revision, host: @host)
          @writer.write(computed.plan, entities: definition.entities, resources: resources)
          @writer.mark_definition(definition, plan_digest: computed.road_digest, kind: labels[:kind])
          @host.status('')
          definition
        end

        def finish(model, instance, computed, revision)
          metadata = metadata_for(computed, revision)
          @repository.write(instance, metadata)
          raise WriteError, 'Relecture des métadonnées incohérente' unless @repository.read_metadata(instance) == metadata

          RoadSummary.new(persistent_id: instance.persistent_id, revision: revision, road_digest: computed.road_digest,
                          metrics: computed.plan['metrics'], target: target_for(model, instance, metadata))
        end

        def metadata_for(computed, revision)
          {
            'road_version' => RoadRepository::VERSION, 'revision' => revision,
            'road_json' => Core::Canonical.dump(computed.settings), 'road_digest' => computed.road_digest,
            'road_engine_version' => ROAD_ENGINE_VERSION, 'material_revision' => @material_revision
          }
        end

        def translation(origin)
          [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0,
           origin[0].to_f / METERS_PER_INCH, origin[1].to_f / METERS_PER_INCH, origin[2].to_f / METERS_PER_INCH, 1.0]
        end

        def load_record(model, record)
          settings = @intake.settings(record.metadata['road_json'])
          return settings unless settings.ok?

          Core::Result.ok(LoadedRoad.new(record: record, settings: settings.value, target: target_for(model, record.instance, record.metadata)))
        end

        def target_for(model, instance, metadata)
          RoadTarget.new(document_key: model.guid, persistent_id: instance.persistent_id, definition_id: instance.definition.persistent_id,
                         revision: metadata['revision'], road_digest: metadata['road_digest'])
        end

        # Relit l'entité avant chaque écriture : rien de ce que dit l'interface n'est cru.
        def verify_target(model, target)
          context = context_problem(model)
          return Core::Result.fail([context]) if context
          return stale('invalid_target') unless target.is_a?(RoadTarget)
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
          return 'config_changed' unless loaded.target.road_digest == target.road_digest

          nil
        end

        # Un moteur ou un catalogue plus récent : consultable, jamais écrasé par des règles anciennes.
        def version_problem(metadata)
          engine = Integer(metadata['road_engine_version'], exception: false)
          if engine.nil? || engine > Integer(ROAD_ENGINE_VERSION)
            return Core::Diagnostic.error('E_VERSION', '/metadata/road_engine_version', reason: 'newer_engine',
                                                                                         value: metadata['road_engine_version'], supported: ROAD_ENGINE_VERSION)
          end
          return nil unless metadata['material_revision'] > @material_revision

          Core::Diagnostic.error('E_VERSION', '/metadata/material_revision', reason: 'newer_materials', value: metadata['material_revision'], supported: @material_revision)
        end
      end
    end
  end
end
