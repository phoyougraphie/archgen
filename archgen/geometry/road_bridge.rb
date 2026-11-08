# frozen_string_literal: true

module Archgen
  module Geometry
    # Pont (AG-057 ; docs/PONT_CONTRACT.md). Un nœud de réseau où une voie passe sur une autre : la voie
    # franchie reste entière ; la voie portée monte par deux rampes droites jusqu'au tablier, à la cote
    # H = point le plus haut de la voie franchie + hauteur libre + épaisseur. Murs sur les rampes, tablier,
    # culées et garde-corps en solides fermés. Même profil en long que le passage à niveau (RoadCrossing).
    module RoadBridge
      KINDS = %w[beam arch vault].freeze
      THICKNESS = { 'beam' => 1.2, 'arch' => 0.6, 'vault' => 0.8 }.freeze
      MAX_SPAN = { 'beam' => 40.0, 'arch' => 120.0, 'vault' => Float::INFINITY }.freeze
      DEFAULT_GRADE = 5.0
      CLEARANCE = { 'water' => 4.0, 'rail' => 5.5, 'road' => 4.75 }.freeze
      SPAN_MARGIN_M = 1.0
      ZONE_MARGIN_M = 1.0
      ABUTMENT_M = 1.5
      SLAB_GAP_M = 0.02
      # Le tablier entre de 0,2 m dans chaque culée, sans dépasser la rampe (8 % au plus : 1,6 cm < 2 cm).
      SLAB_BEARING_M = 0.2
      PARAPET_H = 1.1
      PARAPET_T = { 'beam' => 0.05, 'arch' => 0.05, 'vault' => 0.3 }.freeze
      MIN_ANGLE_RAD = 45.0 * Math::PI / 180.0
      SETTINGS = %w[bridge_kind over clearance_m].freeze
      J = RoadJunction
      N = RoadNetwork
      C = RoadCrossing

      module_function

      def wet?(road)
        road.section['bands'].any? { |b| %w[water sea].include?(b['type']) }
      end

      def railway?(road)
        road.section['bands'].any? { |b| b['role'] == 'rail' }
      end

      def fail(node, reason, **params)
        Core::Result.fail([N.error(node.id, reason, **params)])
      end

      # Voie portée et voie franchie ; Result<[portée, franchie]>.
      def roles(node, roads)
        a, b = roads
        return fail(node, 'water_confluence') if wet?(a) && wet?(b)
        over = node.options['over']
        return fail(node, 'bridge_over_unknown', over: over.to_s) if over && roads.any? { |r| r.id == over && wet?(r) }
        return Core::Result.ok([b, a]) if wet?(a)
        return Core::Result.ok([a, b]) if wet?(b)

        named = roads.find { |r| r.id == over }
        return fail(node, 'bridge_over_unknown', over: over.to_s) if over && named.nil?
        return Core::Result.ok([named, roads.find { |r| !r.equal?(named) }]) if named
        return Core::Result.ok([b, a]) if railway?(a) && !railway?(b)
        return Core::Result.ok([a, b]) if railway?(b) && !railway?(a)

        fail(node, 'bridge_over_missing', roads: roads.map(&:id).join(', '))
      end

      # Point le plus haut de la voie franchie : surfaces, dessus des rails, surface de l'eau.
      def top(road)
        zs = road.section['bands'].flat_map { |b| b['surface'].map(&:last) }
        zs += road.section['rails'].map { |r| r['z_m'] }
        zs += road.section.fetch('water', []).map { |w| w['z_m'] }
        zs.max
      end

      def default_clearance(road)
        return CLEARANCE['water'] if wet?(road)
        return CLEARANCE['rail'] if railway?(road)

        CLEARANCE['road']
      end

      # Contrôles, zones et géométrie ; Result<{ faces:, instances: [], solids:, crossing: }>.
      def build(node)
        arms = node.arms
        roads = arms.map(&:road).uniq(&:index)
        return fail(node, 'bridge_roads', value: roads.size) unless roads.size == 2
        return fail(node, 'water_confluence') if arms.size != 4 && roads.any? { |r| wet?(r) }
        return fail(node, 'bridge_through') unless arms.size == 4 && roads.all? { |r| arms.count { |a| a.road.equal?(r) } == 2 }

        picked = roles(node, roads)
        return picked unless picked.ok?

        over, under = picked.value
        kind = node.options.fetch('bridge_kind', 'beam')
        on_over = arms.select { |a| a.road.equal?(over) }.sort_by(&:sign)
        on_under = arms.select { |a| a.road.equal?(under) }
        sin = J.dot(on_over.last.dir, on_under.first.left).abs
        return fail(node, 'bridge_angle', min_deg: 45, value_deg: (Math.asin([sin, 1.0].min) * 180 / Math::PI).round(1)) if sin < Math.sin(MIN_ANGLE_RAD) - 1e-9

        cot = Math.sqrt([1 - (sin * sin), 0.0].max) / sin
        under_half = [under.ax, under.width - under.ax].max
        over_half = [over.ax, over.width - over.ax].max
        span_half = (under_half / sin) + (over_half * cot) + SPAN_MARGIN_M
        if 2 * span_half > MAX_SPAN.fetch(kind) + 1e-9
          return fail(node, 'bridge_span_too_long', value: Core::Quant.q(2 * span_half), limit: MAX_SPAN.fetch(kind), kind: kind)
        end

        clearance = node.options.fetch('clearance_m', default_clearance(under))
        thickness = THICKNESS.fetch(kind)
        height = top(under) + clearance + thickness
        grade = node.options.fetch('ramp_grade_percent', DEFAULT_GRADE)
        ramp = height / (grade / 100.0)
        on_over.each { |a| a.cut = span_half + ramp }
        on_under.each { |a| a.cut = (over_half / sin) + (under_half * cot) + ZONE_MARGIN_M }
        straight = arms.filter_map { |a| N.straight_problem(node, a) }.uniq(&:to_h)
        return Core::Result.fail(straight) unless straight.empty?

        crossing = C::Crossing.new(road: over, rail: under, s: on_over.first.s, deck_half: span_half, ramp: ramp, height: height,
                                   rail_s: on_under.first.s, rail_half: on_under.first.cut)
        info = { kind: kind, span: 2 * span_half, thickness: thickness, clearance: clearance }
        Core::Result.ok({ faces: C.skirts(on_over, crossing, material: 'road/bridge'), instances: [],
                          solids: solids(node, on_over.last, crossing, info), crossing: crossing, bridge: info })
      end

      # --- Solides

      # Point (x, y, z) de la branche portée, à `along` du nœud (négatif : de l'autre côté), en travers u.
      def at(arm, along, u, z)
        x, y = J.point(arm, nil, along, u)
        [x, y, z]
      end

      # Solide fermé balayé : sections = anneaux de points (même nombre), dans l'ordre.
      def prism(sections, material)
        builder = MeshBuilder.new('solid')
        faces = []
        sections.each_cons(2) do |a, b|
          a.each_index do |j|
            n = (j + 1) % a.size
            faces << [a[j], a[n], b[n], b[j]]
          end
        end
        faces << sections.first.reverse
        faces << sections.last
        faces = faces.map(&:reverse) if RoadItems.signed_volume(faces).negative?
        faces.each { |f| builder.add_face(f, material) }
        builder.to_primitive
      end

      def box(arm, a0, a1, u0, u1, z0, z1, material)
        ring = ->(a) { [at(arm, a, u0, z0), at(arm, a, u1, z0), at(arm, a, u1, z1), at(arm, a, u0, z1)] }
        prism([ring.call(a0), ring.call(a1)], material)
      end

      # Tablier, culées et garde-corps, dans le repère du réseau ; arm : branche portée de signe +.
      def solids(node, arm, crossing, info)
        h = crossing.height
        dh = crossing.deck_half
        ramp = crossing.ramp
        right = arm.outer_r
        left = arm.outer_l
        bottom = h - info[:thickness]
        material = info[:kind] == 'vault' ? 'road/bridge_stone' : 'road/bridge'
        out = []
        # Tablier : sous la coupe portée, sur la portée et un peu dans les culées.
        out << ['slab', box(arm, -dh - SLAB_BEARING_M, dh + SLAB_BEARING_M, right, left, bottom, h - SLAB_GAP_M, material)]
        # Culées : du sol au tablier, sous le haut de chaque rampe.
        [-1, 1].each_with_index do |side, k|
          a0 = side * dh
          a1 = side * (dh + ABUTMENT_M)
          top = C.rise(crossing, dh + ABUTMENT_M) - SLAB_GAP_M
          out << ["abutment/#{k + 1}", box(arm, [a0, a1].min, [a0, a1].max, right, left, 0.0, top, material)]
        end
        out.concat(parapets(arm, crossing, info, left, right, bottom))
        out.map do |name, primitive|
          { 'id' => "bridge/#{node.id}/#{name}", 'category' => 'linear', 'children' => [], 'primitive' => primitive }
        end
      end

      # Garde-corps des deux bords, à l'extérieur de la coupe : sur la portée, de la sous-face du tablier à
      # 1,1 m au-dessus du bord ; sur chaque rampe, du bord à 1,1 m au-dessus.
      def parapets(arm, crossing, info, left, right, bottom)
        t = PARAPET_T.fetch(info[:kind])
        material = info[:kind] == 'vault' ? 'road/bridge_stone' : 'road/item/steel'
        dh = crossing.deck_half
        foot = dh + crossing.ramp
        out = []
        [[left, 1, 'left'], [right, -1, 'right']].each do |u, outward, name|
          edge = RoadSignals.level_at(arm, u)
          u0, u1 = [u, u + (outward * t)].minmax
          ring = lambda do |a, z0, z1|
            [at(arm, a, u0, z0), at(arm, a, u1, z0), at(arm, a, u1, z1), at(arm, a, u0, z1)]
          end
          deck_top = crossing.height + edge + PARAPET_H
          out << ["parapet/#{name}/deck", prism([ring.call(-dh, bottom, deck_top), ring.call(dh, bottom, deck_top)], material)]
          [[-foot, -dh, 1], [dh, foot, 2]].each do |a0, a1, k|
            z0 = C.rise(crossing, a0) + edge
            z1 = C.rise(crossing, a1) + edge
            out << ["parapet/#{name}/ramp#{k}", prism([ring.call(a0, z0, z0 + PARAPET_H), ring.call(a1, z1, z1 + PARAPET_H)], material)]
          end
        end
        out
      end
    end
  end
end
