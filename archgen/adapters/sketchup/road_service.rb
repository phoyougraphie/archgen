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
        GROUND_DICTIONARY = 'archgen.road_ground'
        GROUND_KEYS = %w[terrain_pid copy_pid survey_digest].freeze

        def self.default(writer: nil)
          materials = Composition.road_catalog
          new(intake: Composition.road_intake, bands: Composition.road_bands, items: Composition.road_items,
              materials: materials, material_revision: Composition.road_materials.fetch('schema_version'), writer: writer)
        end

        def initialize(intake:, bands:, items:, materials:, material_revision:, host: NativeHost, writer: nil, repository: nil, limits: {},
                       surveyor: nil, cutter: nil)
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
          @surveyor = surveyor || TerrainSurveyor.new(host: host)
          @cutter = cutter || GroundCutter.new
        end

        # Aucune écriture, aucune trace dans l'Undo.
        # survey : grille du couloir (voie à `ground`), relevée par #survey.
        def preview(tree:, survey: nil)
          settings = @intake.settings(tree)
          return settings unless settings.ok?

          plan = Core::RoadEngine.call(settings.value, bands: @bands, items: @items, limits: @limits, survey: survey)
          return plan unless plan.ok?

          Core::Result.ok(RoadPreview.new(settings: settings.value, plan: plan.value, road_digest: Core::RoadEngine.digest(plan.value)),
                          settings.diagnostics + plan.diagnostics)
        end

        # Relevé du couloir d'une voie à `ground` (AG-049) : grille { s_m, u_m, z_m } en mètres du modèle.
        # origin_m : premier point du tracé dans le modèle ; allow_hidden : l'original masqué par ARCHGEN.
        def survey(model:, tree:, origin_m:, terrain:, allow_hidden: false)
          settings = @intake.settings(tree)
          return settings unless settings.ok?
          return Core::Result.fail([Core::Diagnostic.error('E_ROAD_GROUND', '/ground', reason: 'not_on_ground')]) unless settings.value['ground']

          axes = Core::RoadEngine.ground_axes(settings.value, bands: @bands, items: @items)
          return axes unless axes.ok?

          points = axes.value['points_m'].map { |x, y| [x + origin_m[0], y + origin_m[1]] }
          values = @surveyor.survey_points(model, terrain, points, allow_hidden: allow_hidden)
          return values unless values.ok?

          rows = values.value.map { |z| z && Core::Quant.q(z) }.each_slice(axes.value['u_m'].size).to_a
          Core::Result.ok({ 's_m' => axes.value['s_m'], 'u_m' => axes.value['u_m'], 'z_m' => rows })
        end

        # origin_m : le premier point du tracé, dans le repère du modèle. Voie à `ground` : terrain retenu,
        # relevé refait ici ; survey_digest, celui de l'aperçu, doit concorder.
        def create(model:, tree:, origin_m:, terrain: nil, survey_digest: nil)
          ground = nil
          if ground_tree?(tree)
            return terrain_missing unless terrain

            ground = survey(model: model, tree: tree, origin_m: origin_m, terrain: terrain)
            return ground unless ground.ok?
            return stale('terrain_changed') if survey_digest && Core::Canonical.digest(ground.value) != survey_digest
          end
          computed = preview(tree: tree, survey: ground&.value)
          return computed unless computed.ok?

          problem = context_problem(model) || origin_problem(origin_m)
          return Core::Result.fail([problem]) if problem

          written = @guard.run(model, labels[:create]) do
            write_new_root(model, computed.value, origin_m, ground && { terrain: terrain, grid: ground.value })
          end
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

          tree = merged(loaded.value.settings, changes)
          record = loaded.value.record
          ground = regenerate_survey(model, record.instance, tree)
          return ground if ground.is_a?(Core::Result) && !ground.ok?

          computed = preview(tree: tree, survey: ground&.value)
          return computed unless computed.ok?

          written = @guard.run(model, labels[:regenerate], instance: record.instance) do
            @roots.swap(record.instance, definition: write_definition(model, computed.value))
            if ground
              reground(model, record.instance, computed.value, ground.value)
            end
            finish(model, record.instance, computed.value, record.metadata['revision'] + 1)
          end
          written.ok? ? Core::Result.ok(written.value, computed.diagnostics) : written
        end

        # Relevé d'une voie déjà posée sur un terrain, à la place actuelle de sa racine (panneau, modification).
        def survey_existing(model:, instance:, tree:)
          regenerate_survey(model, instance, tree)
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
          # Une clé changée à nil est retirée (régime de l'eau ôté avec la dernière bande d'eau).
          base.merge(changes).merge('trace' => trace).reject { |_, v| v.nil? }
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

        def write_new_root(model, computed, origin, ground = nil)
          if ground
            origin = [origin[0], origin[1], computed.plan['metrics']['origin_z_m']]
            copy = entaille(model, computed, origin, ground[:terrain].persistent_id)
          end
          definition = write_definition(model, computed)
          instance = @roots.insert(model, definition: definition, transform: @host.transformation(translation(origin)))
          instance.name = labels[:root]
          write_ground(instance, ground[:terrain].persistent_id, copy.persistent_id, ground[:grid]) if ground
          finish(model, instance, computed, 1)
        end

        def ground_tree?(tree)
          parsed = tree.is_a?(String) ? Core::StrictJson.parse(tree) : Core::Result.ok(tree)
          parsed.ok? && parsed.value.is_a?(Hash) && parsed.value.key?('ground')
        end

        def terrain_missing
          Core::Result.fail([Core::Diagnostic.error('E_SITE_TERRAIN', '/site/terrain', reason: 'terrain_missing')])
        end

        # Copie entaillée le long du contour du plan, ramené dans le modèle.
        def entaille(model, computed, origin, terrain_pid)
          terrain = model.find_entity_by_persistent_id(terrain_pid)
          raise WriteError, 'Terrain d’origine introuvable' unless terrain

          outline = computed.plan['ground']['outline_m'].map { |x, y| [x + origin[0], y + origin[1]] }
          @cutter.entaille(model, terrain, outline)
        end

        def write_ground(instance, terrain_pid, copy_pid, grid)
          values = { 'terrain_pid' => terrain_pid, 'copy_pid' => copy_pid, 'survey_digest' => Core::Canonical.digest(grid) }
          GROUND_KEYS.each { |k| instance.set_attribute(GROUND_DICTIONARY, k, values.fetch(k)) }
        end

        # Régénérer une voie posée sur un terrain : l'original masqué est relevé de nouveau, à la place
        # actuelle de la racine. nil pour une voie horizontale.
        def regenerate_survey(model, instance, tree)
          return nil unless ground_tree?(tree)

          matrix = instance.transformation.to_a
          return stale('ground_road_rotated') unless (matrix[0] - 1).abs < 1e-9 && matrix[1].abs < 1e-9 && (matrix[10] - 1).abs < 1e-9

          pid = instance.get_attribute(GROUND_DICTIONARY, 'terrain_pid')
          return terrain_missing unless pid

          origin = [matrix[12] * METERS_PER_INCH, matrix[13] * METERS_PER_INCH]
          reference = TerrainRef.new(document_key: model.guid, persistent_id: pid)
          survey(model: model, tree: tree, origin_m: origin, terrain: reference, allow_hidden: true)
        end

        def reground(model, instance, computed, grid)
          @cutter.remove(model, instance.get_attribute(GROUND_DICTIONARY, 'copy_pid'))
          matrix = instance.transformation.to_a
          origin = [matrix[12] * METERS_PER_INCH, matrix[13] * METERS_PER_INCH, computed.plan['metrics']['origin_z_m']]
          pid = instance.get_attribute(GROUND_DICTIONARY, 'terrain_pid')
          copy = entaille(model, computed, origin, pid)
          instance.transformation = @host.transformation(translation(origin))
          write_ground(instance, pid, copy.persistent_id, grid)
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
