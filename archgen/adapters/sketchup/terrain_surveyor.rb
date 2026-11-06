# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      # Référence Ruby d'un terrain retenu : reconnue au document et au PID, relue à chaque relevé.
      TerrainRef = Struct.new(:document_key, :persistent_id, keyword_init: true)

      # Retient un terrain désigné et lance les rayons verticaux. Lecture seule : aucune
      # opération, aucune écriture, aucune trace dans l'Annuler (docs/TERRAIN_CONTRACT.md).
      class TerrainSurveyor
        MAX_PASSES = 64
        METERS_PER_INCH = 0.0254
        ABOVE_M = 1.0
        # Écart de chaque rayon au nœud, dans le repère de la racine. Les nœuds du périmètre sont dans
        # le plan des murs et sur les arêtes verticales du soubassement : mesuré en H13, un rayon qui
        # file le long d'une arête ne renvoie plus rien. Assez grand pour la tolérance de SketchUp.
        RAY_OFFSET_M = 0.0002
        # Une face posée à l'altitude exacte du terrain arrête le rayon, qui repart alors sous le terrain
        # et ne le voit plus (H18). Un autre point, à quelques millimètres, n'a pas cette coïncidence.
        RETRY_OFFSETS_M = [0.001, 0.005].freeze
        HORIZONTAL_TOLERANCE = 1e-6
        BUILDING_DICTIONARY = 'archgen.building'
        REASONS = %w[terrain_selection terrain_kind terrain_nested terrain_is_building terrain_hidden terrain_missing terrain_other_document].freeze

        def initialize(host: NativeHost)
          @host = host
        end

        # La sélection courante devient le terrain retenu. Rien n'est marqué sur l'entité.
        def retain(model)
          selection = model.selection
          return terrain_failure('terrain_selection') unless selection.length == 1

          entity = selection.first
          problem = terrain_problem(model, entity)
          return terrain_failure(problem) if problem

          Core::Result.ok(TerrainRef.new(document_key: model.guid, persistent_id: entity.persistent_id))
        end

        # axes : { 'xs_m', 'ys_m' } dans le repère de la racine. Retourne un Result<arbre de grille>.
        def survey(model, reference, instance, axes)
          survey_matrix(model, reference, instance.transformation.to_a, axes)
        end

        # matrix : du repère relevé vers le modèle, translation en pouces : la racine, ou une parcelle dans sa racine.
        def survey_matrix(model, reference, matrix, axes)
          terrain = read_terrain(model, reference)
          return terrain unless terrain.ok?

          return Core::Result.fail([Core::Diagnostic.error('E_SITE_TRANSFORM', '/site/placement', reason: 'not_horizontal')]) unless horizontal?(matrix)

          top = terrain.value.bounds.max.z.to_f + (ABOVE_M / METERS_PER_INCH)
          overflow = []
          rows = axes['ys_m'].map do |y|
            axes['xs_m'].map { |x| altitude(model, terrain.value, matrix, x, y, top, overflow) }
          end
          return too_many_obstacles(overflow) unless overflow.empty?

          Core::Result.ok('schema_version' => 1, 'xs_m' => axes['xs_m'], 'ys_m' => axes['ys_m'], 'z_m' => rows)
        end

        private

        def read_terrain(model, reference)
          return terrain_failure('terrain_missing') unless reference.is_a?(TerrainRef)
          return terrain_failure('terrain_other_document') unless reference.document_key == model.guid

          entity = model.find_entity_by_persistent_id(reference.persistent_id)
          return terrain_failure('terrain_missing') unless entity

          problem = terrain_problem(model, entity)
          problem ? terrain_failure(problem) : Core::Result.ok(entity)
        end

        def terrain_problem(model, entity)
          return 'terrain_kind' unless @host.group?(entity) || @host.component_instance?(entity)
          return 'terrain_missing' unless entity.valid?
          return 'terrain_nested' unless entity.parent == model
          return 'terrain_is_building' if entity.get_attribute(BUILDING_DICTIONARY, 'metadata_version')
          return 'terrain_is_building' if entity.get_attribute(EnsembleRepository::DICTIONARY, 'ensemble_version')
          return 'terrain_hidden' if entity.hidden? || !entity.layer.visible?

          nil
        end

        # L'axe Z de la racine doit rester vertical : sinon la grille ne décrit plus le sol.
        def horizontal?(matrix)
          (matrix[10] - 1.0).abs < HORIZONTAL_TOLERANCE && matrix[8].abs < HORIZONTAL_TOLERANCE && matrix[9].abs < HORIZONTAL_TOLERANCE
        end

        # Altitude du terrain à ce nœud, en mètres. Un obstacle est traversé en relançant
        # le rayon depuis son point d'impact ; nil si le rayon sort sans toucher le terrain.
        def altitude(model, terrain, matrix, x_m, y_m, top, overflow)
          value, crossed = cast(model, terrain, matrix, x_m, y_m, RAY_OFFSET_M, top, overflow)
          # Sans obstacle traversé, un rayon sans terrain est un vrai trou.
          return value if value || !crossed || overflow.last == [x_m, y_m]

          RETRY_OFFSETS_M.each do |offset|
            value, = cast(model, terrain, matrix, x_m, y_m, offset, top, overflow)
            return value if value
          end
          nil
        end

        # [altitude ou nil, obstacle traversé ?]
        def cast(model, terrain, matrix, x_m, y_m, offset, top, overflow)
          origin_x, origin_y = world_xy(matrix, x_m, y_m, offset)
          ray = [@host.point(origin_x, origin_y, top), @host.vector(0.0, 0.0, -1.0)]
          crossed = false
          MAX_PASSES.times do
            hit = model.raytest(ray, true)
            return [nil, crossed] unless hit
            return [hit[0].z.to_f * METERS_PER_INCH, crossed] if hit[1].first == terrain

            crossed = true
            ray = [hit[0], ray[1]]
          end
          overflow << [x_m, y_m]
          [nil, crossed]
        end

        def world_xy(matrix, x_m, y_m, offset = RAY_OFFSET_M)
          x = (x_m + offset) / METERS_PER_INCH
          y = (y_m + offset) / METERS_PER_INCH
          [(matrix[0] * x) + (matrix[4] * y) + matrix[12], (matrix[1] * x) + (matrix[5] * y) + matrix[13]]
        end

        def too_many_obstacles(points)
          Core::Result.fail([Core::Diagnostic.error('E_SITE_SURVEY', '/site/survey', reason: 'too_many_obstacles', count: points.size,
                                                                                    points: points.first(Core::SiteAssise::MAX_LISTED_POINTS))])
        end

        def terrain_failure(reason)
          Core::Result.fail([Core::Diagnostic.error('E_SITE_TERRAIN', '/site/terrain', reason: reason)])
        end
      end
    end
  end
end
