# frozen_string_literal: true

module Archgen
  module Geometry
    # Passage à niveau (AG-050 ; docs/VOIRIE_CONTRACT.md, Carrefours). Une route traverse une voie ferrée :
    # la voie ferrée reste entière ; la route monte par deux rampes droites jusqu'à un platelage 5 mm sous
    # le dessus des rails, avec murets sur les rampes, feux de passage et barrières. Plan pur, en mètres.
    module RoadCrossing
      DEFAULT_GRADE = 4.0
      BELOW_RAIL_M = 0.005
      DECK_MARGIN_M = 0.5
      RAIL_ZONE_MARGIN_M = 1.0
      MIN_ANGLE_RAD = 45.0 * Math::PI / 180.0
      LIGHT_BEFORE_M = 3.0
      GATE_BEFORE_M = 1.5
      LIGHT_HEIGHT_M = 3.2
      GATE_HEIGHT_M = 1.2
      J = RoadJunction
      N = RoadNetwork

      Crossing = Struct.new(:road, :rail, :s, :deck_half, :ramp, :height, :rail_s, :rail_half, keyword_init: true)

      module_function

      def railway?(road)
        road.section['bands'].any? { |b| b['role'] == 'rail' }
      end

      def plain_road?(road)
        bands = road.section['bands']
        bands.any? { |b| b['role'] == 'carriageway' } && bands.none? { |b| %w[rail tram].include?(b['role']) || b['type'] == 'tram_lane' }
      end

      # Contrôles, coupes (zones) des quatre branches et géométrie ; Result<{ faces:, instances:, crossing: }>.
      def build(node)
        arms = node.arms
        roads = arms.map(&:road).uniq(&:index)
        rail = roads.find { |r| railway?(r) }
        road = roads.find { |r| plain_road?(r) }
        return fail(node, 'crossing_roads') unless roads.size == 2 && rail && road
        return fail(node, 'crossing_through') unless arms.size == 4 && arms.count { |a| a.road.equal?(rail) } == 2

        on_road = arms.select { |a| a.road.equal?(road) }.sort_by(&:sign)
        on_rail = arms.select { |a| a.road.equal?(rail) }
        sin = J.dot(on_road.last.dir, on_rail.first.left).abs
        return fail(node, 'crossing_angle', min_deg: 45, value_deg: (Math.asin([sin, 1.0].min) * 180 / Math::PI).round(1)) if sin < Math.sin(MIN_ANGLE_RAD) - 1e-9

        cot = Math.sqrt([1 - (sin * sin), 0.0].max) / sin
        rail_half = [rail.ax, rail.width - rail.ax].max
        road_half = [road.ax, road.width - road.ax].max
        height = rail.section['rails'].map { |r| r['z_m'] }.max - BELOW_RAIL_M
        grade = node.options.fetch('ramp_grade_percent', DEFAULT_GRADE)
        deck_half = (rail_half / sin) + (road_half * cot) + DECK_MARGIN_M
        ramp = height / (grade / 100.0)
        on_road.each { |a| a.cut = deck_half + ramp }
        on_rail.each { |a| a.cut = (road_half / sin) + (rail_half * cot) + RAIL_ZONE_MARGIN_M }
        straight = arms.filter_map { |a| N.straight_problem(node, a) }.uniq(&:to_h)
        return Core::Result.fail(straight) unless straight.empty?

        crossing = Crossing.new(road: road, rail: rail, s: on_road.first.s, deck_half: deck_half, ramp: ramp, height: height,
                                rail_s: on_rail.first.s, rail_half: on_rail.first.cut)
        lights = signs(node, on_road, crossing)
        return lights unless lights.ok?

        Core::Result.ok({ faces: skirts(on_road, crossing), instances: lights.value, crossing: crossing })
      end

      def fail(node, reason, **params)
        Core::Result.fail([N.error(node.id, reason, **params)])
      end

      # Cote du profil de la route à la distance `along` du nœud.
      def rise(crossing, along)
        d = along.abs
        return crossing.height if d <= crossing.deck_half + 1e-9
        return 0.0 if d >= crossing.deck_half + crossing.ramp - 1e-9

        crossing.height * (crossing.deck_half + crossing.ramp - d) / crossing.ramp
      end

      # Points du profil en long d'une route, [[s, z]], tous ses passages à niveau compris.
      def profile(road, nodes)
        crossings = nodes.filter_map { |n| n.crossing if n.crossing && n.crossing.road.equal?(road) }
        return nil if crossings.empty?

        points = [[0.0, 0.0], [road.length, 0.0]]
        crossings.each do |c|
          points += [[c.s - c.deck_half - c.ramp, 0.0], [c.s - c.deck_half, c.height], [c.s + c.deck_half, c.height], [c.s + c.deck_half + c.ramp, 0.0]]
        end
        points.sort_by(&:first).uniq { |s, _| Core::Quant.q(s) }
      end

      # Intervalles de la voie ferrée où ses objets (hors rails et traverses) s'interrompent.
      def gaps(road, nodes)
        nodes.filter_map { |n| n.crossing if n.crossing && n.crossing.rail.equal?(road) }.map { |c| [c.rail_s - c.rail_half, c.rail_s + c.rail_half] }
      end

      # Stations d'un tronçon de route, plus une à chaque point du profil, avec leur cote.
      def lift(stations, from, to, profile)
        inner = profile.select { |s, _| s > from + 1e-6 && s < to - 1e-6 }
        local = ([[from, RoadGround.z_at(profile, from)]] + inner + [[to, RoadGround.z_at(profile, to)]]).map { |s, z| [s - from, z] }
        RoadGround.stations(stations, local).map(&:first)
      end

      # Murets le long des deux bords, sur chaque rampe, du bord jusqu'au sol.
      def skirts(on_road, crossing)
        faces = []
        on_road.each do |arm|
          line = arm.road.line
          [[arm.outer_l, edge_z(arm, arm.outer_l, line)], [arm.outer_r, edge_z(arm, arm.outer_r, line)]].each do |u, dz|
            foot = crossing.deck_half + crossing.ramp
            top = crossing.deck_half
            a = J.point(arm, nil, foot, u)
            b = J.point(arm, nil, top, u)
            quad = [[a[0], a[1], 0.0], [b[0], b[1], 0.0], [b[0], b[1], crossing.height + dz], [a[0], a[1], dz]]
            outward = u.positive? ? arm.left : [-arm.left[0], -arm.left[1]]
            n = RoadGround.normal(quad.first(3))
            faces << [(n[0] * outward[0]) + (n[1] * outward[1]) >= 0 ? quad : quad.reverse, 'road/curb']
          end
        end
        faces
      end

      # Cote de la coupe au bord u de la branche (bout de la ligne de coupe).
      def edge_z(arm, u, _line)
        RoadSignals.level_at(arm, u)
      end

      # Feu et barrière pour chaque sens, à droite de ceux qui arrivent, avant le platelage.
      def signs(node, on_road, crossing)
        out = []
        on_road.each_with_index do |arm, k|
          width = arm.outer_l - arm.kerb_l
          return fail(node, 'no_room_for_signal', road: arm.road.id) if width < RoadSignals::MIN_FOOTING_M

          u = arm.kerb_l + [RoadSignals::SIGNAL_SETBACK_M, width / 2].min
          [['crossing_light', LIGHT_BEFORE_M, LIGHT_HEIGHT_M], ['crossing_gate', GATE_BEFORE_M, GATE_HEIGHT_M]].each do |kind, before, h|
            along = crossing.deck_half + before
            z = rise(crossing, along) + RoadSignals.level_at(arm, u)
            id = RoadItems.definition_id(kind, 'standard', h)
            out << RoadItems.instance("signal/#{node.id}/#{kind}/#{k + 1}", id, J.point(arm, nil, along, u), arm.dir, z, 'right')
          end
        end
        Core::Result.ok(out)
      end

      def definitions
        [['crossing_light', LIGHT_HEIGHT_M], ['crossing_gate', GATE_HEIGHT_M]].to_h do |kind, h|
          [RoadItems.definition_id(kind, 'standard', h), RoadItemShapes.definition(kind, 'standard', h)]
        end
      end
    end
  end
end
