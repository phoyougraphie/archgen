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
      # AG-105 : perron ou rampe devant une porte au-dessus du terrain (docs/TEINTES_ABORDS_CONTRACT.md).
      STEP_FROM_M = 0.05
      RISER_M = 0.17
      TREAD_M = 0.28
      STEP_SIDE_M = 0.15
      RAMP_SLOPE = 0.05
      RAMP_WIDTH_M = 1.20
      HINT = 'increase_survey_step'

      module_function

      # plan : GeometryPlan validé ; config : configuration effective du bâtiment.
      # materials : le catalogue complet, terre comprise ; nil ne contrôle pas les identifiants.
      # footprint : le trapèze d'une parcelle, rectangle du bâtiment seul sinon. passage : le porche d'une parcelle.
      # party : en rangée à talus, { sloped: façades en talus, right_dz: écart avec la voisine de droite } (AG-109).
      def call(plan:, config:, grid:, settings:, assise:, materials: nil, footprint: nil, passage: nil, party: nil)
        footprint ||= FootprintSolver.call(width_m: plan['metrics']['width_m'], depth_m: plan['metrics']['depth_m'])
        platform = assise['platform_z_m']
        height = ->(facade, u) { terrain_height(grid, facade, u, platform) }
        door = passage ? passage_diagnostic(passage, footprint, grid, platform) : door_diagnostic(plan, footprint, height)
        return Core::Result.fail([door]) if door&.error?

        earthwork = earthwork_nodes(footprint, grid, settings, platform, party)
        return earthwork unless earthwork.ok?

        gap = passage ? passage_gap(passage, footprint, grid, platform) : door_gap(plan, footprint, height)
        entrance = passage ? Core::Result.ok([]) : entrance_nodes(plan, footprint, settings, gap)
        return entrance unless entrance.ok?

        door = nil if door && !entrance.value.empty? # le seuil haut est résolu
        built = build(footprint, settings, config, assise, earthwork.value, gap, buried_openings(plan, footprint, height), passage, entrance.value)
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

      def passage_span(passage, footprint)
        low = (footprint.width_m - passage['width_m']) / 2.0
        [low, footprint.width_m / 2.0, low + passage['width_m']]
      end
      private_class_method :passage_span

      # Un passage s'emprunte par ses deux bouts : la règle de la porte vaut en façade et à l'arrière.
      def passage_diagnostic(passage, footprint, grid, platform)
        span = passage_span(passage, footprint)
        highest = [0.0, footprint.depth_m].product(span).map { |y, x| grid.altitude_at(x, y) - platform }.max
        if highest > DOOR_BURIED_M + Core::Quant::EPSILON
          return Core::Diagnostic.error('E_SITE_DOOR_BURIED', '/site/platform', reason: 'passage_buried', value: Core::Quant.q(highest))
        end

        middle = span[1]
        gap = Core::Quant.q([0.0, footprint.depth_m].map { |y| platform - grid.altitude_at(middle, y) }.max)
        gap > DOOR_GAP_M + Core::Quant::EPSILON ? Core::Diagnostic.warning('W_SITE_DOOR_GAP', '/site/platform', reason: 'passage_gap', value: gap) : nil
      end
      private_class_method :passage_diagnostic

      def passage_gap(passage, footprint, grid, platform)
        Core::Quant.q(platform - grid.altitude_at(passage_span(passage, footprint)[1], 0.0))
      end
      private_class_method :passage_gap

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
      def earthwork_nodes(footprint, grid, settings, platform, party = nil)
        if settings['earthwork'] == 'embankment'
          sloped = party ? party[:sloped] : FACADE_ORDER
          built = EmbankmentBuilder.call(footprint: footprint, grid: grid, settings: settings, platform: platform, sloped: sloped, right_dz: party && party[:right_dz])
          return built unless built.ok?

          strips = (FACADE_ORDER - sloped).filter_map { |id| plinth_strip(footprint.facade(id), grid, platform, settings['plinth_material'], nil) }
          nodes = wrap('site/embankment', 'embankment', built.value[:nodes]) + wrap('site/retaining', 'plinth', built.value[:walls]) + wrap('site/plinth', 'plinth', strips)
          return Core::Result.ok(nodes: nodes, reach_m: built.value[:reach_m])
        end
        even = footprint.trapezoid? ? settings.dig('survey', 'step_m') : nil
        strips = FACADE_ORDER.filter_map { |id| plinth_strip(footprint.facade(id), grid, platform, settings['plinth_material'], even) }
        Core::Result.ok(nodes: wrap('site/plinth', 'plinth', strips), reach_m: 0.0)
      end
      private_class_method :earthwork_nodes

      def wrap(id, category, children)
        children.empty? ? [] : [Node.group(id, category, children)]
      end
      private_class_method :wrap

      # Marches de RISER_M au plus, la dernière au niveau du seuil ; ou palier et rampe le long de la
      # façade, du côté le plus long. Matière du soubassement.
      def entrance_nodes(plan, footprint, settings, gap)
        kind = settings['entrance']
        door = door_opening(plan)
        return Core::Result.ok([]) unless door && %w[steps ramp].include?(kind) && gap && gap > STEP_FROM_M + Core::Quant::EPSILON

        facade = footprint.facade(door['facade_id'])
        u0 = Core::Quant.q([door['u_min_m'] - STEP_SIDE_M, 0.0].max)
        u1 = Core::Quant.q([door['u_max_m'] + STEP_SIDE_M, facade.length_m].min)
        bottom = Core::Quant.q(-gap - TOE_M)
        material = settings['plinth_material']
        return Core::Result.ok(steps(facade, u0, u1, gap, bottom, material)) if kind == 'steps'

        ramp(facade, u0, u1, gap, bottom, material)
      end
      private_class_method :entrance_nodes

      def steps(facade, u0, u1, gap, bottom, material)
        count = (gap / RISER_M).ceil
        (1..count).map do |j|
          top = Core::Quant.q(-gap + (gap * j / count))
          d0 = Core::Quant.q(-(count - j + 1) * TREAD_M)
          d1 = Core::Quant.q(-(count - j) * TREAD_M)
          Node.leaf("site/entrance/step/#{j}", 'plinth', Boxes.on_facade(facade, u0, u1, bottom, top, d0, d1, material))
        end
      end
      private_class_method :steps

      def ramp(facade, u0, u1, gap, bottom, material)
        length = Core::Quant.q(gap / RAMP_SLOPE)
        middle = (u0 + u1) / 2.0
        l0 = Core::Quant.q([[middle - (RAMP_WIDTH_M / 2.0), 0.0].max, u0].min)
        l1 = Core::Quant.q([[middle + (RAMP_WIDTH_M / 2.0), facade.length_m].min, u1].max)
        right = facade.length_m - l1
        room = [right, l0].max
        if room + Core::Quant::EPSILON < length
          return Core::Result.fail([Core::Diagnostic.error('E_SITE_ENTRANCE', '/site/entrance', reason: 'ramp_too_long', value: length, limit: Core::Quant.q(room))])
        end

        near, far = right >= l0 ? [l1, l1 + length] : [l0, l0 - length]
        landing = Node.leaf('site/entrance/landing', 'plinth', Boxes.on_facade(facade, l0, l1, bottom, 0.0, -RAMP_WIDTH_M, 0.0, material))
        slope = Node.leaf('site/entrance/ramp', 'plinth', sloped(facade, near, Core::Quant.q(far), gap, bottom, material))
        Core::Result.ok([landing, slope])
      end
      private_class_method :ramp

      # Solide à dessus incliné : de z = 0 en `near` à z = -gap en `far`, sur RAMP_WIDTH_M devant la façade.
      def sloped(facade, near, far, gap, bottom, material)
        corners = [[near, 0.0], [far, 0.0], [far, -RAMP_WIDTH_M], [near, -RAMP_WIDTH_M]]
        ring = corners.map { |u, d| facade.point(u, 0.0, d)[0, 2] }
        tops = corners.map { |u, _| u == near ? 0.0 : Core::Quant.q(-gap) }
        area = ring.each_index.sum { |i| (ring[i][0] * ring[(i + 1) % 4][1]) - (ring[(i + 1) % 4][0] * ring[i][1]) }
        if area.negative?
          ring.reverse!
          tops.reverse!
        end
        low = ring.map { |x, y| [x, y, bottom] }
        high = ring.each_with_index.map { |(x, y), i| [x, y, tops[i]] }
        mesh = MeshBuilder.new('solid')
        mesh.add_face(low.reverse, material)
        mesh.add_face(high, material)
        4.times { |i| mesh.add_face([low[i], low[(i + 1) % 4], high[(i + 1) % 4], high[i]], material) }
        mesh.to_primitive
      end
      private_class_method :sloped

      def build(footprint, settings, config, assise, earthwork, gap, buried, passage = nil, entrance = [])
        material = settings['plinth_material']
        children = [Node.leaf('site/platform', 'platform', platform_primitive(footprint, config, material, passage))] + earthwork[:nodes]
        children << Node.group('site/entrance', 'plinth', entrance) unless entrance.empty?
        nodes = [Node.group('site', 'site', children)]
        {
          'schema_version' => SCHEMA_VERSION, 'units' => 'm', 'nodes' => nodes,
          'metrics' => assise.merge('site_face_count' => count_faces(nodes), 'door_gap_m' => gap, 'buried_opening_count' => buried, 'embankment_reach_m' => earthwork[:reach_m])
        }
      end
      private_class_method :build

      def platform_primitive(footprint, config, material, passage = nil)
        inset = config['mode'] == 'structural' ? config['structure']['wall_m'] : 0.0
        return trapezoid_platform(footprint, inset, material, passage) if footprint.trapezoid?

        low_x = inset
        low_y = inset
        high_x = footprint.width_m - inset
        high_y = footprint.depth_m - inset
        MeshBuilder.new('surface').add_face([[low_x, low_y, 0.0], [high_x, low_y, 0.0], [high_x, high_y, 0.0], [low_x, high_y, 0.0]], material).to_primitive
      end
      private_class_method :platform_primitive

      # Plancher sur le trapèze intérieur. Les murs d'un passage de porche s'arrêtent à ses bords :
      # leur épaisseur, en façade et à l'arrière, reçoit aussi un plancher.
      def trapezoid_platform(footprint, inset, material, passage)
        ring = footprint.facades.map { |facade| facade.point(facade.inner_start(inset), 0.0, inset) }
        mesh = MeshBuilder.new('surface').add_face(ring, material)
        return mesh.to_primitive unless passage && inset.positive?

        low, _, high = passage_span(passage, footprint)
        [[0.0, inset], [footprint.depth_m - inset, footprint.depth_m]].each do |y0, y1|
          mesh.add_face([[low, y0, 0.0], [high, y0, 0.0], [high, y1, 0.0], [low, y1, 0.0]].map { |p| p.map { |c| Core::Quant.q(c) } }, material)
        end
        mesh.to_primitive
      end
      private_class_method :trapezoid_platform

      def plinth_strip(facade, grid, platform, material, even = nil)
        mesh = MeshBuilder.new('surface')
        cells = 0
        (even ? Core::SurveyGrid.even_stations(facade.length_m, even) : stations(facade, grid)).each_cons(2) do |u0, u1|
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
