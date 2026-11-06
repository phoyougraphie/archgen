# frozen_string_literal: true

module Archgen
  module Geometry
    # Plan d'assise : plancher et soubassement sous un bâtiment déjà calculé, sans y toucher.
    # Coordonnées locales au bâtiment, z = 0 à la plateforme (docs/TERRAIN_CONTRACT.md).
    module SitePlanner
      SCHEMA_VERSION = 1
      TOE_M = 0.05
      DOOR_BURIED_M = 0.02
      DOOR_GAP_M = 0.20
      HINT = 'increase_survey_step'

      module_function

      # plan : GeometryPlan validé ; config : configuration effective du bâtiment.
      # materials : le catalogue complet, terre comprise ; nil ne contrôle pas les identifiants.
      def call(plan:, config:, grid:, settings:, assise:, materials: nil)
        footprint = FootprintSolver.call(width_m: plan['metrics']['width_m'], depth_m: plan['metrics']['depth_m'])
        platform = assise['platform_z_m']
        height = ->(facade, u) { terrain_height(grid, facade, u, platform) }
        door = door_diagnostic(plan, footprint, height)
        return Core::Result.fail([door]) if door&.error?

        earthwork = earthwork_nodes(footprint, grid, settings, platform)
        return earthwork unless earthwork.ok?

        built = build(footprint, settings, config, assise, earthwork.value, door_gap(plan, footprint, height), buried_openings(plan, footprint, height))
        problems = budget_problems(built['metrics'], plan['metrics'])
        problems = Core::SitePlanValidator.call(built, materials: materials) if problems.empty?
        return Core::Result.fail(problems) unless problems.empty?

        Core::Result.ok(Core::Canonical.deep_freeze(built), warnings(door, assise, built['metrics']))
      end

      def digest(site_plan)
        Core::Canonical.digest(site_plan)
      end

      # Plafonds propres à l'assise, puis total avec le bâtiment.
      def budget_problems(metrics, building_metrics)
        faces = metrics['site_face_count']
        total = faces + building_metrics['expanded_face_count']
        unique = faces + building_metrics['unique_face_count']
        problems = []
        problems << budget('site_faces', Core::Limits::SITE_MAX_FACES, faces) if faces > Core::Limits::SITE_MAX_FACES
        problems << budget('total_faces', Core::Limits::MAX_EXPANDED_FACES, total) if total > Core::Limits::MAX_EXPANDED_FACES
        problems << budget('total_faces', Core::Limits::MAX_UNIQUE_FACES, unique) if unique > Core::Limits::MAX_UNIQUE_FACES
        problems
      end

      # Une cellule de bande entre deux stations, en (u, z) ; sens antihoraire vu de l'extérieur.
      # b0 et b1 sont les altitudes locales du bord bas ; b ≥ 0 signifie « pas de bande ».
      def strip_cell(u0, b0, u1, b1)
        low0 = snap(b0)
        low1 = snap(b1)
        return nil if low0 >= 0.0 && low1 >= 0.0
        return [[u0, low0], [u1, low1], [u1, 0.0], [u0, 0.0]] if low0.negative? && low1.negative?
        return triangle_after_crossing(u0, low0, u1, low1) if low0.negative?

        triangle_before_crossing(u0, low0, u1, low1)
      end

      def triangle_after_crossing(u0, low0, u1, low1)
        return [[u0, low0], [u1, 0.0], [u0, 0.0]] if low1.zero?

        crossing = u0 + ((u1 - u0) * low0 / (low0 - low1))
        return nil if crossing - u0 < Core::Quant::MIN_EDGE_M
        return [[u0, low0], [u1, 0.0], [u0, 0.0]] if u1 - crossing < Core::Quant::MIN_EDGE_M

        [[u0, low0], [crossing, 0.0], [u0, 0.0]]
      end
      private_class_method :triangle_after_crossing

      def triangle_before_crossing(u0, low0, u1, low1)
        return [[u0, 0.0], [u1, low1], [u1, 0.0]] if low0.zero?

        crossing = u0 + ((u1 - u0) * low0 / (low0 - low1))
        return nil if u1 - crossing < Core::Quant::MIN_EDGE_M
        return [[u0, 0.0], [u1, low1], [u1, 0.0]] if crossing - u0 < Core::Quant::MIN_EDGE_M

        [[crossing, 0.0], [u1, low1], [u1, 0.0]]
      end
      private_class_method :triangle_before_crossing

      # Un bord bas à moins de 2 mm de z = 0 donnerait une arête refusée par le validateur.
      def snap(value)
        value.abs < Core::Quant::MIN_EDGE_M ? 0.0 : value
      end
      private_class_method :snap

      def terrain_height(grid, facade, u, platform)
        point = facade.point(u, 0.0)
        grid.altitude_at(point[0], point[1]) - platform
      end
      private_class_method :terrain_height

      def door_opening(plan)
        plan['openings'].find { |opening| opening['kind'] == 'door' }
      end
      private_class_method :door_opening

      def door_diagnostic(plan, footprint, height)
        door = door_opening(plan)
        return nil unless door

        facade = footprint.facade(door['facade_id'])
        highest = [door['u_min_m'], (door['u_min_m'] + door['u_max_m']) / 2.0, door['u_max_m']].map { |u| height.call(facade, u) }.max
        if highest > DOOR_BURIED_M + Core::Quant::EPSILON
          return Core::Diagnostic.error('E_SITE_DOOR_BURIED', '/site/platform', reason: 'door_buried', id: door['id'], value: Core::Quant.q(highest))
        end

        gap = door_gap(plan, footprint, height)
        return nil unless gap > DOOR_GAP_M + Core::Quant::EPSILON

        Core::Diagnostic.warning('W_SITE_DOOR_GAP', '/site/platform', reason: 'door_gap', id: door['id'], value: gap)
      end
      private_class_method :door_diagnostic

      # Hauteur du seuil au-dessus du terrain, au milieu de la porte. nil sans porte.
      def door_gap(plan, footprint, height)
        door = door_opening(plan)
        return nil unless door

        Core::Quant.q(-height.call(footprint.facade(door['facade_id']), (door['u_min_m'] + door['u_max_m']) / 2.0))
      end
      private_class_method :door_gap

      def buried_openings(plan, footprint, height)
        plan['openings'].count do |opening|
          facade = footprint.facade(opening['facade_id'])
          [opening['u_min_m'], (opening['u_min_m'] + opening['u_max_m']) / 2.0, opening['u_max_m']].any? do |u|
            height.call(facade, u) > opening['z_min_m'] + Core::Quant::EPSILON
          end
        end
      end
      private_class_method :buried_openings

      def warnings(door, assise, metrics)
        out = [door].compact
        return out unless assise['cut_max_m'].positive?

        out << Core::Diagnostic.warning('W_SITE_BURIED', '/site/platform', reason: 'terrain_above_platform', value: assise['cut_max_m'], count: metrics['buried_opening_count'])
      end
      private_class_method :warnings

      # Result<{ nodes:, reach_m: }> : un groupe de soubassement ou de talus, absent s'il est vide.
      def earthwork_nodes(footprint, grid, settings, platform)
        if settings['earthwork'] == 'embankment'
          built = EmbankmentBuilder.call(footprint: footprint, grid: grid, settings: settings, platform: platform)
          return built unless built.ok?

          return Core::Result.ok(nodes: wrap('site/embankment', 'embankment', built.value[:nodes]), reach_m: built.value[:reach_m])
        end
        strips = FACADE_ORDER.filter_map { |id| plinth_strip(footprint.facade(id), grid, platform, settings['plinth_material']) }
        Core::Result.ok(nodes: wrap('site/plinth', 'plinth', strips), reach_m: 0.0)
      end
      private_class_method :earthwork_nodes

      def wrap(id, category, children)
        children.empty? ? [] : [Node.group(id, category, children)]
      end
      private_class_method :wrap

      def build(footprint, settings, config, assise, earthwork, gap, buried)
        material = settings['plinth_material']
        children = [Node.leaf('site/platform', 'platform', platform_primitive(footprint, config, material))] + earthwork[:nodes]
        nodes = [Node.group('site', 'site', children)]
        {
          'schema_version' => SCHEMA_VERSION, 'units' => 'm', 'nodes' => nodes,
          'metrics' => assise.merge('site_face_count' => count_faces(nodes), 'door_gap_m' => gap, 'buried_opening_count' => buried, 'embankment_reach_m' => earthwork[:reach_m])
        }
      end
      private_class_method :build

      def platform_primitive(footprint, config, material)
        inset = config['mode'] == 'structural' ? config['structure']['wall_m'] : 0.0
        low_x = inset
        low_y = inset
        high_x = footprint.width_m - inset
        high_y = footprint.depth_m - inset
        MeshBuilder.new('surface').add_face([[low_x, low_y, 0.0], [high_x, low_y, 0.0], [high_x, high_y, 0.0], [low_x, high_y, 0.0]], material).to_primitive
      end
      private_class_method :platform_primitive

      def plinth_strip(facade, grid, platform, material)
        mesh = MeshBuilder.new('surface')
        cells = 0
        stations(facade, grid).each_cons(2) do |u0, u1|
          cell = strip_cell(u0, bottom(grid, facade, u0, platform), u1, bottom(grid, facade, u1, platform))
          next unless cell

          mesh.add_face(cell.map { |u, z| facade.point(u, z) }, material)
          cells += 1
        end
        cells.zero? ? nil : Node.leaf("site/plinth/#{facade.id}", 'plinth', mesh.to_primitive)
      end
      private_class_method :plinth_strip

      def bottom(grid, facade, u, platform)
        Core::Quant.q(terrain_height(grid, facade, u, platform) - TOE_M)
      end
      private_class_method :bottom

      # Abscisses des nœuds de la grille sur cette façade, de 0 à sa longueur.
      def stations(facade, grid)
        axis = facade.tangent[0].zero? ? grid.ys : grid.xs
        axis.select { |value| value >= -Core::Quant::EPSILON && value <= facade.length_m + Core::Quant::EPSILON }
      end
      private_class_method :stations

      def count_faces(nodes)
        nodes.sum { |node| (node['primitive'] ? node['primitive']['faces'].size : 0) + count_faces(node['children']) }
      end
      private_class_method :count_faces

      def budget(reason, limit, value)
        Core::Diagnostic.error('E_SITE_BUDGET', '/site/survey/step_m', reason: reason, limit: limit, value: value, hint: HINT)
      end
      private_class_method :budget
    end
  end
end
