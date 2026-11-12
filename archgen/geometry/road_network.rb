# frozen_string_literal: true

module Archgen
  module Geometry
    # Réseau de voies (ADR-36) : nœuds trouvés tout seuls, branches, carrefours simples et
    # tronçons entre eux. Plan pur, en mètres, repère du réseau (premier point de la première voie).
    module RoadNetwork
      SNAP_M = 1.0
      MERGE_M = 2.0
      MIN_ARM_RAD = 30.0 * Math::PI / 180.0
      MAX_ARMS = 6
      DEFAULT_RADIUS_M = 6.0
      # AG-132 : une branche dont la zone touche un virage est redressée jusqu'à sa coupe, puis raccordée
      # à la courbe ; le raccord tourne d'au plus BEND_MAX_RAD et chaque bord du ruban avance d'au moins BEND_MIN_M.
      BEND_MAX_RAD = 45.0 * Math::PI / 180.0
      BEND_MIN_M = 0.05
      RAIL_ROLES = %w[rail tram].freeze
      J = RoadJunction

      # Une voie du réseau : ses stations en repère du réseau et sa ligne de coupe.
      Road = Struct.new(:index, :id, :settings, :section, :width, :ax, :stations, :chain, :line, :joints, keyword_init: true) do
        def length
          chain.last
        end
      end
      Node = Struct.new(:id, :point, :hits, :arms, :radius, :type, :options, :crossing, :bridge, keyword_init: true)

      module_function

      def road(index, id, settings, offset, stations, section)
        ax = RoadRibbons.axis_x(section['width_m'], settings['axis'])
        moved = stations.map { |s| RoadAxis::Station.new(point: [s.point[0] + offset[0], s.point[1] + offset[1]], normal: s.normal, vertex: s.vertex) }
        chain = [0.0]
        moved.each_cons(2) { |a, b| chain << (chain.last + Math.hypot(b.point[0] - a.point[0], b.point[1] - a.point[1])) }
        Road.new(index: index, id: id, settings: settings, section: section, width: section['width_m'], ax: ax,
                 stations: moved, chain: chain, line: RoadRibbons.cross_line(section), joints: [])
      end

      def error(id, reason, **params)
        Core::Diagnostic.error('E_ROAD_JUNCTION', "/junctions/#{id}", reason: reason, **params)
      end

      # --- Détection

      # Croisements d'axes, bouts posés sur une autre voie, bouts qui se rejoignent ; regroupés à 2 m.
      def detect(roads)
        hits = []
        roads.combination(2) do |a, b|
          # AG-101 : un croisement à moins de la demi-largeur de l'autre voie (+ 1 m) d'un bout est ce
          # bout : une voie qui dépasse un peu fait un T, pas une croix à moignon.
          crossings(a, b).each { |p, sa, sb| hits << [p, [[a.index, end_snap(a, sa, b)], [b.index, end_snap(b, sb, a)]]] }
        end
        roads.each do |r|
          [0.0, r.length].each do |s|
            end_point = at(r, s)
            roads.each do |o|
              next if o.index == r.index

              p, so = closest(o, end_point)
              # AG-101 : un bout posé sur la chaussée de l'autre voie fait un T, au point de son axe.
              hits << [p, [[r.index, s], [o.index, so]]] if Math.hypot(p[0] - end_point[0], p[1] - end_point[1]) <= reach(o)
            end
          end
        end
        merge(hits, roads)
      end

      # Portée d'un raccord sur une voie : sa demi-largeur et SNAP_M.
      def reach(road)
        (road.width / 2.0) + SNAP_M
      end

      def end_snap(road, s, other)
        return 0.0 if s <= reach(other)
        return road.length if road.length - s <= reach(other)

        s
      end

      def crossings(a, b)
        out = []
        a.stations.each_cons(2).with_index do |(p1, p2), i|
          b.stations.each_cons(2).with_index do |(q1, q2), j|
            hit = segment_hit(p1.point, p2.point, q1.point, q2.point)
            next unless hit

            t, u = hit
            point = [p1.point[0] + ((p2.point[0] - p1.point[0]) * t), p1.point[1] + ((p2.point[1] - p1.point[1]) * t)]
            out << [point, a.chain[i] + ((a.chain[i + 1] - a.chain[i]) * t), b.chain[j] + ((b.chain[j + 1] - b.chain[j]) * u)]
          end
        end
        out
      end

      def segment_hit(p1, p2, q1, q2)
        d = J.sub(p2, p1)
        e = J.sub(q2, q1)
        den = (d[0] * e[1]) - (d[1] * e[0])
        return nil if den.abs < 1e-12

        w = J.sub(q1, p1)
        t = ((w[0] * e[1]) - (w[1] * e[0])) / den
        u = ((w[0] * d[1]) - (w[1] * d[0])) / den
        t.between?(0, 1) && u.between?(0, 1) ? [t, u] : nil
      end

      def at(road, s)
        point_and_dir(road, s).first
      end

      # Point de l'axe et direction de la voie à l'abscisse s ; `before` choisit le segment amont aux sommets.
      def point_and_dir(road, s, before: false)
        st = road.stations
        k = (0...(st.size - 1)).find { |i| before ? s > road.chain[i] && s <= road.chain[i + 1] + 1e-9 : s >= road.chain[i] - 1e-9 && s < road.chain[i + 1] }
        k ||= before ? 0 : st.size - 2
        a = st[k].point
        b = st[k + 1].point
        len = road.chain[k + 1] - road.chain[k]
        t = len.zero? ? 0 : (s - road.chain[k]) / len
        dir = [(b[0] - a[0]) / len, (b[1] - a[1]) / len]
        [[a[0] + ((b[0] - a[0]) * t), a[1] + ((b[1] - a[1]) * t)], dir, k]
      end

      def closest(road, p)
        best = nil
        road.stations.each_cons(2).with_index do |(a, b), i|
          d = J.sub(b.point, a.point)
          len2 = J.dot(d, d)
          t = len2.zero? ? 0 : [[J.dot(J.sub(p, a.point), d) / len2, 0].max, 1].min
          q = [a.point[0] + (d[0] * t), a.point[1] + (d[1] * t)]
          dist = Math.hypot(q[0] - p[0], q[1] - p[1])
          best = [q, road.chain[i] + ((road.chain[i + 1] - road.chain[i]) * t), dist] if best.nil? || dist < best[2]
        end
        best.first(2)
      end

      def merge(hits, roads)
        groups = []
        hits.each do |point, raw|
          pairs = raw.map { |r, s| [r, snap_end(roads[r], s)] }
          group = groups.find { |g| Math.hypot(g[:point][0] - point[0], g[:point][1] - point[1]) <= MERGE_M }
          group ? group[:pairs].concat(pairs) : groups << { point: point, pairs: pairs.dup }
        end
        groups.map do |g|
          pairs = g[:pairs].sort.each_with_object([]) do |(r, s), out|
            out << [r, s] unless out.any? { |r2, s2| r2 == r && (s2 - s).abs <= MERGE_M }
          end
          id = pairs.map { |r, s| "#{roads[r].id}@#{format('%.1f', s)}" }.sort.join('+')
          Node.new(id: id, point: g[:point], hits: pairs)
        end.sort_by(&:id)
      end

      # Une abscisse à moins de 2 m d'un bout est ce bout : la voie finit au carrefour.
      def snap_end(road, s)
        return 0.0 if s <= MERGE_M
        return road.length if s >= road.length - MERGE_M

        s
      end

      # --- Branches et refus

      def arms_for(node, roads)
        node.hits.flat_map do |r, s|
          road = roads[r]
          out = []
          if s < road.length - 1e-6
            origin, dir, = point_and_dir(road, s)
            out << J.arm(road, s, +1, dir, origin)
          end
          if s > 1e-6
            origin, dir, = point_and_dir(road, s, before: true)
            out << J.arm(road, s, -1, [-dir[0], -dir[1]], origin)
          end
          out
        end.sort_by { |a| J.angle(a.dir) }
      end

      def node_problems(node)
        arms = node.arms
        return [error(node.id, 'too_many_arms', limit: MAX_ARMS, value: arms.size)] if arms.size > MAX_ARMS
        return [error(node.id, 'motorway_at_grade')] if arms.any? { |a| a.road.section['bands'].any? { |b| b['type'] == 'hard' } }
        return [error(node.id, 'rails_at_junction')] if arms.any? { |a| a.road.section['bands'].any? { |b| b['role'] == 'rail' } }

        tram = tram_problem(node)
        return [tram] if tram

        tight = arms.each_index.map { |k| J.ccw_delta(arms[k].dir, arms[(k + 1) % arms.size].dir) }.min
        return [error(node.id, 'arms_too_close', min_deg: 30, value_deg: (tight * 180 / Math::PI).round(1))] if arms.size > 1 && tight < MIN_ARM_RAD

        []
      end

      def tram?(arm)
        arm.road.section['bands'].any? { |b| b['role'] == 'tram' || b['type'] == 'tram_lane' }
      end

      # Tram (AG-047) : une seule voie à rails, qui traverse le nœud tout droit ; ses rails dans la chaussée.
      def tram_problem(node)
        trams = node.arms.select { |a| tram?(a) }
        return nil if trams.empty?

        through = trams.size == 2 && trams[0].road.equal?(trams[1].road) && trams.map(&:sign).sort == [-1, 1]
        return error(node.id, 'tram_not_through') unless through

        arm = trams.first
        rails = arm.road.section['rails'].map { |r| arm.sign.positive? ? arm.road.ax - r['x_m'] : r['x_m'] - arm.road.ax }
        return error(node.id, 'tram_outside_carriageway', road: arm.road.id) unless rails.all? { |u| u > arm.kerb_r && u < arm.kerb_l }

        trams.each { |a| a.through = true }
        nil
      end

      # Couloir du tram, d'une coupe à l'autre : la chaussée de la voie à rails, mise à niveau 0
      # (une plateforme s'abaisse à la coupe), rails au ras. Ligne de coupe en x de la voie.
      def crossing_line(arm)
        bands = arm.road.section['bands']
        lanes = bands.select { |b| b['role'] == 'carriageway' }
        x0 = lanes.map { |b| b['x0_m'] }.min
        x1 = lanes.map { |b| b['x1_m'] }.max
        rails = arm.road.section['rails'].map { |r| r['x_m'] }
        half = RoadRibbons::RAIL_HEAD_M / 2
        breaks = (bands.flat_map { |b| [b['x0_m'], b['x1_m']] } + rails.flat_map { |x| [x - half, x + half] } + [x0, x1])
                 .select { |x| x >= x0 - 1e-9 && x <= x1 + 1e-9 }.map { |x| Core::Quant.q(x) }.uniq.sort
        breaks.each_cons(2).map do |a, b|
          mid = (a + b) / 2
          band = bands.find { |row| mid > row['x0_m'] && mid < row['x1_m'] }
          rail = rails.any? { |x| mid > x - half && mid < x + half }
          [[a, 0.0], [b, 0.0], rail ? RoadRibbons::RAIL_MATERIAL : "road/#{band['type']}"]
        end
      end

      def crossing_faces(node)
        plus = node.arms.find { |a| a.through && a.sign.positive? }
        minus = node.arms.find { |a| a.through && a.sign.negative? }
        RoadSignals.sweep(plus, -minus.cut, plus.cut, crossing_line(plus))
      end

      # Cœur coupé par le couloir du tram : de la coupe de x (bord gauche) à celle de y (bord droit).
      def chain(corners, from, to, node)
        k = corners.index { |c| c.a.equal?(from) }
        out = [J.point(from, nil, from.cut, from.kerb_l)]
        loop do
          c = corners[k]
          out.concat(J.kerb_path(c, node.point, node.radius).drop(1))
          break if c.b.equal?(to)

          out.concat(J.cut_points(c.b, node.point, [c.b.kerb_r, c.b.kerb_l]).drop(1))
          k = (k + 1) % corners.size
        end
        J.dedupe(out)
      end

      # La zone coupée d'une branche doit tenir dans un seul segment droit de sa voie. Avec bend (carrefour
      # simple, à feux, giratoire ; AG-132), une zone qui touche un virage est redressée : la branche reste
      # droite jusqu'à sa coupe et le tronçon suivant part de cette coupe (raccord vérifié par pieces).
      def straight_problem(node, arm, bend: false)
        road = arm.road
        from, to = arm.sign.positive? ? [arm.s, arm.s + arm.reach] : [arm.s - arm.reach, arm.s]
        return error(node.id, 'arm_too_short', road: road.id) if from < -1e-6 || to > road.length + 1e-6

        _, _, k = point_and_dir(road, (from + to) / 2)
        a = road.stations[k]
        b = road.stations[k + 1]
        d = J.sub(b.point, a.point)
        len = Math.hypot(*d)
        n = [-d[1] / len, d[0] / len]
        straight = [a, b].all? { |st| (st.normal[0] - n[0]).abs < 1e-6 && (st.normal[1] - n[1]).abs < 1e-6 }
        inside = from >= road.chain[k] - 1e-6 && to <= road.chain[k + 1] + 1e-6
        return nil if straight && inside
        return error(node.id, 'junction_on_curve', road: road.id) unless bend

        road.joints << { at: arm.sign.positive? ? to : from, start: arm.sign.positive?, node: node.id,
                         origin: arm.origin, dir: arm.dir, reach: arm.reach }
        nil
      end

      # Coupe, coins et géométrie d'un nœud ; Result<{ faces: [[points, matériau]], cuts: }>.
      def build(node, roads)
        node.arms = arms_for(node, roads)
        return bridge(node) if node.type == 'bridge'
        # Sur l'eau, seul un pont se construit (docs/PONT_CONTRACT.md).
        return Core::Result.fail([error(node.id, 'water_crossing')]) if node.arms.any? { |a| RoadBridge.wet?(a.road) }
        return crossing(node) if node.type == 'level_crossing'

        problems = node_problems(node)
        return Core::Result.fail(problems) unless problems.empty?
        mark_link(node)
        return roundabout(node) if %w[roundabout double_roundabout].include?(node.type)

        corners = J.corners(node.arms, node.point, node.radius)
        return Core::Result.fail([error(node.id, 'junction_shape')]) if corners.any?(&:broken)

        cuts = Hash.new(J::MIN_CUT_M).compare_by_identity
        corners.each do |c|
          need_a, need_b = J.needs(c, node.point)
          cuts[c.a] = [cuts[c.a], need_a].max
          cuts[c.b] = [cuts[c.b], need_b].max
        end
        return Core::Result.fail([error(node.id, 'junction_shape')]) if cuts.values.any? { |v| !v.finite? || v > 200 }

        node.arms.each { |a| a.cut = cuts[a] }
        signals = node.type == 'signals'
        if signals
          return Core::Result.fail([error(node.id, 'signals_without_carriageway')]) unless node.arms.any?(&:carriageway)

          node.arms.each { |a| a.ext = RoadSignals.extension(a) }
        end
        straight = node.arms.filter_map { |a| straight_problem(node, a, bend: true) }.uniq(&:to_h)
        return Core::Result.fail(straight) unless straight.empty?

        built = faces(node, corners)
        return built unless built.ok?
        return Core::Result.ok({ faces: built.value, instances: [] }) unless signals

        dressed(node, built.value)
      end

      # Double giratoire : la branche qui part vers l'autre anneau est la liaison.
      def mark_link(node)
        road, toward = node.options && node.options['link']
        return unless road

        node.arms.each { |a| a.link = a.road.index == road && a.sign == ((toward > a.s) ? 1 : -1) }
      end

      # Passage à niveau : les deux voies traversent ; RoadCrossing donne murets, feux et le profil.
      def crossing(node)
        built = RoadCrossing.build(node)
        return built unless built.ok?

        node.crossing = built.value[:crossing]
        Core::Result.ok({ faces: built.value[:faces], instances: built.value[:instances] })
      end

      # Pont : comme un passage à niveau, plus le tablier, les culées et les garde-corps (RoadBridge).
      def bridge(node)
        built = RoadBridge.build(node)
        return built unless built.ok?

        node.crossing = built.value[:crossing]
        node.bridge = built.value[:bridge]
        Core::Result.ok({ faces: built.value[:faces], instances: [], solids: built.value[:solids] })
      end

      # Giratoire : anneau, îlots et coins de RoadRoundabout, mêmes contrôles de virage et de murets.
      def roundabout(node)
        shape = RoadRoundabout.build(node)
        return shape unless shape.ok?

        straight = node.arms.filter_map { |a| straight_problem(node, a, bend: true) }.uniq(&:to_h)
        return Core::Result.fail(straight) unless straight.empty?

        built = RoadRoundabout.faces(node, shape.value)
        built.ok? ? Core::Result.ok({ faces: built.value, instances: [] }) : built
      end

      # Carrefour à feux : bandes de marquage au-delà des coupes et un feu par branche à chaussée.
      def dressed(node, faces)
        lights = []
        problems = []
        node.arms.each_with_index do |arm, k|
          next unless arm.carriageway

          faces += RoadSignals.faces(arm)
          lights.concat(RoadSignals.studs(arm, "crossing_stud/#{node.id}/#{k + 1}")) if node.options && node.options['crossing_studs']
          light = RoadSignals.light(arm, "signal/#{node.id}/#{k + 1}")
          light ? lights << light : problems << error(node.id, 'no_room_for_signal', road: arm.road.id)
        end
        problems.empty? ? Core::Result.ok({ faces: faces, instances: lights }) : Core::Result.fail(problems)
      end

      def core_level(arms)
        return 0.0 if arms.any?(&:carriageway)

        arms.map { |a| a.points.select { |u, _| u.between?(a.kerb_r - 1e-9, a.kerb_l + 1e-9) }.map(&:last).min }.min
      end

      def faces(node, corners)
        arms = node.arms
        zc = core_level(arms)
        out = []
        problems = []
        core = []
        corners.each do |c|
          path = J.kerb_path(c, node.point, node.radius)
          poly = corner_polygon(c, node, path)
          # Un coin vide (un chemin prend la place du trottoir) reste au niveau du cœur.
          c.poly = poly && poly.size >= 3 && J.signed_area(poly) > 1e-9 ? poly : nil
          c.level = c.poly ? [c.a.side_l, c.b.side_r].compact.min || zc : zc
          core.concat(J.cut_points(c.a, node.point, [c.a.kerb_r, c.a.kerb_l])) if core.empty?
          core.concat(path.drop(1))
          core.concat(J.cut_points(c.b, node.point, [c.b.kerb_r, c.b.kerb_l]).drop(1)) unless c.b.equal?(arms.first)
        end
        core = J.dedupe(core)
        core.pop if core.size > 1 && Math.hypot(core[0][0] - core[-1][0], core[0][1] - core[-1][1]) < 1e-7
        if arms.any?(&:through)
          plus = arms.find { |a| a.through && a.sign.positive? }
          minus = arms.find { |a| a.through && a.sign.negative? }
          [chain(corners, plus, minus, node), chain(corners, minus, plus, node)].each do |piece|
            next if piece.size < 3 || J.signed_area(piece) <= 1e-9

            problems << error(node.id, 'junction_shape') unless add_polygon(out, piece, zc, 'road/lane')
          end
          out.concat(crossing_faces(node))
        else
          problems << error(node.id, 'junction_shape') unless add_polygon(out, core, zc, arms.any?(&:carriageway) ? 'road/lane' : 'road/path')
        end
        corners.each { |c| problems.concat(corner_faces(out, c, node, zc)) }
        arms.each { |a| problems.concat(caps(out, a, node, zc, corners)) }
        problems.empty? ? Core::Result.ok(out) : Core::Result.fail(problems.uniq)
      end

      def add_polygon(out, poly, z, material)
        return false if poly.size < 3 || J.signed_area(poly) <= 1e-9

        tris = J.triangulate(poly)
        return false unless tris

        tris.each { |t| out << [t.map { |i| [poly[i][0], poly[i][1], z] }, material] }
        true
      end

      # Coin : trottoir (ou accotement) entre la bordure et les bords extérieurs, et contremarche le
      # long de la bordure là où ce trottoir la borde.
      def corner_faces(out, corner, node, zc)
        a = corner.a
        b = corner.b
        path = J.kerb_path(corner, node.point, node.radius)
        level = corner.level
        poly = corner.poly
        edges = poly ? poly.each_index.map { |i| [poly[i], poly[(i + 1) % poly.size]] } : []
        if (level - zc).abs > 1e-9
          path.each_cons(2) do |p, q|
            next unless edges.any? { |e| e.any? { |v| same?(v, p) } && e.any? { |v| same?(v, q) } }

            quad = [[q[0], q[1], zc], [p[0], p[1], zc], [p[0], p[1], level], [q[0], q[1], level]]
            out << [level > zc ? quad : quad.reverse, 'road/curb']
          end
        end
        return [] unless poly

        material = corner_material(a, :left) || corner_material(b, :right) || 'road/verge'
        add_polygon(out, poly, level, material) ? [] : [error(node.id, 'junction_shape')]
      end

      def same?(p, q)
        Math.hypot(p[0] - q[0], p[1] - q[1]) < 1e-7
      end

      # Contour du trottoir de coin, dans le sens direct ; nil sans rien au-delà des bordures.
      # Un côté sans bord (chemin) : le contour quitte la bordure de ce côté à l'onglet K.
      def corner_polygon(corner, node, path)
        a = corner.a
        b = corner.b
        wa = a.outer_l > a.kerb_l + 1e-9
        wb = b.outer_r < b.kerb_r - 1e-9
        return nil unless wa || wb

        on = ->(arm, u, p) { (J.dot(J.sub(p, arm.origin), arm.left) - u).abs < 1e-6 }
        poly = path.reverse
        poly.shift while !wb && poly.size > 1 && on.call(b, b.kerb_r, poly[0]) && on.call(b, b.kerb_r, poly[1])
        poly.pop while !wa && poly.size > 1 && on.call(a, a.kerb_l, poly[-1]) && on.call(a, a.kerb_l, poly[-2])
        poly.concat(J.cut_points(a, node.point, [a.kerb_l, a.outer_l]).drop(1))
        poly.concat(corner.outer || [corner.q].compact.select { !wa || !wb })
        poly.concat(J.cut_points(b, node.point, [b.outer_r, b.kerb_r]).reverse.drop(1).reverse)
        poly = J.dedupe(poly)
        poly.pop if poly.size > 1 && Math.hypot(poly[0][0] - poly[-1][0], poly[0][1] - poly[-1][1]) < 1e-7
        poly
      end

      def corner_material(arm, side)
        bands = arm.road.section['bands']
        outside = bands.select do |band|
          u0, u1 = [band['x0_m'], band['x1_m']].map { |x| arm.sign.positive? ? arm.road.ax - x : x - arm.road.ax }.minmax
          side == :left ? u0 >= arm.kerb_l - 1e-9 : u1 <= arm.kerb_r + 1e-9
        end
        return 'road/sidewalk' if outside.any? { |band| band['role'] == 'pedestrian' }

        nearest = outside.min_by { |band| side == :left ? band['x1_m'] : -band['x0_m'] }
        nearest && "road/#{nearest['type']}"
      end

      # Murets à la coupe : chaque segment de coupe qui n'est pas au niveau de la face voisine.
      def caps(out, arm, node, zc, corners)
        left_level = corners.find { |c| c.a.equal?(arm) }&.level || zc
        right_level = corners.find { |c| c.b.equal?(arm) }&.level || zc
        problems = []
        arm.points.each_cons(2) do |(ua, za), (ub, zb)|
          next if (ua - ub).abs < 1e-9

          mid = (ua + ub) / 2
          ref = if mid > arm.kerb_l then left_level
                elsif mid < arm.kerb_r then right_level
                else zc
                end
          next if (za - ref).abs < 1e-9 && (zb - ref).abs < 1e-9

          if (za - ref) * (zb - ref) < -1e-12
            problems << error(node.id, 'junction_levels', road: arm.road.id)
            next
          end
          p = J.point(arm, node.point, arm.cut, ua)
          q = J.point(arm, node.point, arm.cut, ub)
          poly = [[p[0], p[1], za], [q[0], q[1], zb], [q[0], q[1], ref], [p[0], p[1], ref]]
          poly = poly.each_with_object([]) { |v, acc| acc << v unless acc.any? { |w| w == v } }
          next if poly.size < 3

          above = [za, zb].max > ref + 1e-9
          normal = cap_normal(poly)
          toward = above ? [-arm.dir[0], -arm.dir[1]] : arm.dir
          poly = poly.reverse if (normal[0] * toward[0]) + (normal[1] * toward[1]) < 0
          out << [poly, 'road/curb']
        end
        problems
      end

      def cap_normal(poly)
        n = [0.0, 0.0, 0.0]
        poly.each_with_index do |p, i|
          q = poly[(i + 1) % poly.size]
          n[0] += (p[1] - q[1]) * (p[2] + q[2])
          n[1] += (p[2] - q[2]) * (p[0] + q[0])
          n[2] += (p[0] - q[0]) * (p[1] + q[1])
        end
        n
      end

      # --- Soudure

      # Sommets en T : un sommet du carrefour posé au milieu d'une arête (cœur contre muret, contremarche
      # d'un tronçon contre deux faces de niveaux différents) est inséré dans cette arête. Seules les faces
      # du carrefour et les bouts de tronçon qui le touchent sont repris ; chaque face reste plane.
      def heal(surface, from)
        vertices = surface['vertices']
        faces = surface['faces']
        points = faces[from..].flat_map { |f| f['indices'] }.uniq
        touched = points.to_h { |i| [i, true] }
        grid = points.group_by { |i| cell(vertices[i]) }
        healed = faces.each_with_index.flat_map do |face, k|
          next [face] unless k >= from || face['indices'].any? { |i| touched[i] }

          ring = split_edges(face['indices'], grid, vertices)
          next [face] if ring.size == face['indices'].size

          tris = retriangulate(ring, vertices)
          return nil unless tris

          tris.map { |t| { 'indices' => t, 'material' => face['material'] } }
        end
        surface.merge('faces' => healed)
      end

      # Triangule une face plane dans son plan (axe dominant de la normale ôté), sens conservé.
      def retriangulate(ring, vertices)
        pts = ring.map { |i| vertices[i] }
        n = [0.0, 0.0, 0.0]
        pts.each_with_index do |p, i|
          q = pts[(i + 1) % pts.size]
          n[0] += (p[1] - q[1]) * (p[2] + q[2])
          n[1] += (p[2] - q[2]) * (p[0] + q[0])
          n[2] += (p[0] - q[0]) * (p[1] + q[1])
        end
        drop = n.each_index.max_by { |c| n[c].abs }
        keep = [0, 1, 2] - [drop]
        flat = pts.map { |p| keep.map { |c| p[c] } }
        flip = J.signed_area(flat).negative?
        flat = flat.reverse if flip
        order = flip ? ring.reverse : ring
        tris = J.triangulate(flat)
        tris&.map { |t| t.map { |i| order[i] } }&.map { |t| flip ? t.reverse : t }
      end

      HEAL_CELL_M = 2.0

      def cell(point)
        [(point[0] / HEAL_CELL_M).floor, (point[1] / HEAL_CELL_M).floor]
      end

      # Sommets du carrefour dans les cases que couvre l'arête (index par cases de 2 m).
      def near(grid, pa, pb)
        x0, x1 = [cell(pa)[0], cell(pb)[0]].minmax
        y0, y1 = [cell(pa)[1], cell(pb)[1]].minmax
        (x0..x1).flat_map { |x| (y0..y1).flat_map { |y| grid.fetch([x, y], []) } }
      end

      def split_edges(indices, grid, vertices)
        indices.each_with_index.flat_map do |a, i|
          b = indices[(i + 1) % indices.size]
          pa = vertices[a]
          d = (0..2).map { |c| vertices[b][c] - pa[c] }
          len2 = d.sum { |c| c * c }
          inner = near(grid, pa, vertices[b]).filter_map do |m|
            next if m == a || m == b || len2.zero?

            w = (0..2).map { |c| vertices[m][c] - pa[c] }
            t = w.each_index.sum { |c| w[c] * d[c] } / len2
            next unless t > 1e-9 && t < 1 - 1e-9

            off = (0..2).map { |c| w[c] - (d[c] * t) }
            off.sum { |c| c * c } < 1e-12 ? [t, m] : nil
          end
          [a] + inner.sort.map(&:last)
        end
      end

      # --- Tronçons entre carrefours

      # Intervalles d'abscisse à garder sur chaque voie, hors des zones coupées.
      def pieces(road, nodes)
        # Un passage à niveau ne coupe pas ses voies : sa zone compte seulement pour les nœuds trop proches.
        cuts = nodes.flat_map do |n|
          n.arms.select { |a| a.road.equal?(road) }.map do |a|
            (a.sign.positive? ? [a.s, a.s + a.reach] : [a.s - a.reach, a.s]) + [n.id, !n.crossing.nil?]
          end
        end.sort_by(&:first)
        problems = cuts.each_cons(2).filter_map do |(_, e1, id1, _), (s2, _, id2, _)|
          next if id1 == id2 || s2 >= e1 - 1e-6

          error(id1, 'junctions_too_close', other: id2, road: road.id)
        end
        return Core::Result.fail(problems) unless problems.empty?

        out = []
        start = 0.0
        cuts.reject(&:last).each do |s0, s1, _|
          out << [start, s0] if s0 - start > 1e-6
          start = [start, s1].max
        end
        out << [start, road.length] if road.length - start > 1e-6
        bad = road.joints.reject { |j| out.any? { |from, to| joint_fits?(road, j, from, to) } }
        return Core::Result.fail(bad.map { |j| error(j[:node], 'junction_on_curve', road: road.id) }.uniq(&:to_h)) unless bad.empty?

        Core::Result.ok(out)
      end

      # Raccord d'une branche redressée au tronçon qui part de sa coupe : il tourne d'au plus BEND_MAX_RAD
      # et chaque bord du ruban avance (aucune face retournée).
      def joint_fits?(road, joint, from, to)
        ends = joint[:start] ? (joint[:at] - from).abs < 1e-6 : (joint[:at] - to).abs < 1e-6
        return false unless ends

        st = piece_stations(road, from, to)
        st = st.reverse unless joint[:start]
        return false if st.size < 2

        p = st[0]
        q = st[1]
        d = J.sub(q.point, p.point)
        len = Math.hypot(*d)
        return false if len < 1e-6 || J.dot(d, joint[:dir]) < len * Math.cos(BEND_MAX_RAD)

        offsets = road.line.flat_map { |(xa, _), (xb, _), _| [road.ax - xa, road.ax - xb] }.minmax
        offsets.all? do |u|
          a = [p.point[0] + (p.normal[0] * u), p.point[1] + (p.normal[1] * u)]
          b = [q.point[0] + (q.normal[0] * u), q.point[1] + (q.normal[1] * u)]
          J.dot(J.sub(b, a), d) / len >= BEND_MIN_M
        end
      end

      # Stations d'un tronçon : celles de la voie, plus ses deux bouts interpolés sur un segment droit.
      # Au bout d'une branche redressée (AG-132), le tronçon part de la coupe de la branche, sur sa droite,
      # et laisse les stations de la courbe restées en deçà.
      def piece_stations(road, from, to)
        inner = road.stations.each_index.select { |i| road.chain[i] > from + 1e-6 && road.chain[i] < to - 1e-6 }.map { |i| road.stations[i] }
        first = station_at(road, from, after: true)
        last = station_at(road, to, after: false)
        head = joint_at(road, from, true)
        tail = joint_at(road, to, false)
        if head
          first = joint_station(head)
          inner = inner.drop_while { |st| !ahead?(st, head) }
        end
        if tail
          last = joint_station(tail)
          inner = inner.reverse.drop_while { |st| !ahead?(st, tail) }.reverse
        end
        [first] + inner + [last]
      end

      def joint_at(road, s, start)
        (road.joints || []).find { |j| j[:start] == start && (j[:at] - s).abs < 1e-6 }
      end

      # Station de la coupe : sur l'axe redressé, normale à gauche dans le sens de la voie.
      def joint_station(joint)
        o = joint[:origin]
        d = joint[:dir]
        point = [o[0] + (d[0] * joint[:reach]), o[1] + (d[1] * joint[:reach])]
        normal = joint[:start] ? [-d[1], d[0]] : [d[1], -d[0]]
        RoadAxis::Station.new(point: point, normal: normal, vertex: -1)
      end

      # Une station de la courbe au-delà de la coupe, en avançant le long de la branche.
      def ahead?(station, joint)
        J.dot(J.sub(station.point, joint[:origin]), joint[:dir]) > joint[:reach] + BEND_MIN_M
      end

      def station_at(road, s, after:)
        exact = road.chain.index { |c| (c - s).abs < 1e-9 }
        return road.stations[exact] if exact

        point, dir, = point_and_dir(road, s, before: !after)
        RoadAxis::Station.new(point: point, normal: [-dir[1], dir[0]], vertex: -1)
      end
    end
  end
end
