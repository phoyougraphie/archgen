# frozen_string_literal: true

module Archgen
  module Geometry
    # Giratoire (AG-045, docs/VOIRIE_CONTRACT.md, Carrefours). Centre au nœud. Anneau de chaussée
    # entre l'îlot central (rayon intérieur) et le bord extérieur ; chaque entrée se raccorde au bord
    # extérieur par un arrondi tangent de rayon corner_radius_m ; îlot séparateur en triangle sur
    # chaque branche assez large. La chaussée est découpée en secteurs entre branches voisines, le
    # long de la ligne médiane de chaque chaussée : aucun polygone à trou. Plan pur, en mètres.
    module RoadRoundabout
      DEFAULT_OUTER_M = 15.0
      DEFAULT_RING_M = 7.0
      ISLAND_BASE_M = 2.0
      ISLAND_LENGTH_M = 8.0
      ISLAND_GAP_M = 1.0
      ISLAND_MIN_LANE_M = 3.0
      ISLAND_LEVEL_M = 0.14
      MIN_WALK_M = 0.3
      J = RoadJunction
      N = RoadNetwork

      Entry = Struct.new(:arm, :mid, :inner, :inner_l, :inner_r, :island, :ca, :t1, :t2, :cb, :t3, :t4, keyword_init: true)

      module_function

      def error(node, reason, **params)
        N.error(node.id, reason, **params)
      end

      # Plus grande racine t de |p + d t - o| = r, ou nil.
      def line_circle(p, d, o, r)
        w = J.sub(p, o)
        b = J.dot(w, d)
        disc = (b * b) - (J.dot(w, w) - (r * r))
        disc.negative? ? nil : -b + Math.sqrt(disc)
      end

      def at(arm, t, u)
        J.point(arm, nil, t, u)
      end

      def arc_ccw(center, from, to, radius)
        a0 = J.angle(J.sub(from, center))
        span = ccw(a0, J.angle(J.sub(to, center)))
        count = [(span / (2 * Math.acos(1 - (J::CHORD_M / radius)))).ceil, 1].max
        (1...count).map do |i|
          t = a0 + (span * i / count)
          [center[0] + (radius * Math.cos(t)), center[1] + (radius * Math.sin(t))]
        end
      end

      def ccw(a0, a1)
        d = a1 - a0
        d += 2 * Math::PI while d <= 0
        d -= 2 * Math::PI while d > 2 * Math::PI
        d
      end

      def build(node)
        arms = node.arms
        o = node.point
        outer = node.options.fetch('outer_radius_m', DEFAULT_OUTER_M)
        inner = outer - node.options.fetch('ring_width_m', DEFAULT_RING_M)
        radius = node.radius
        return Core::Result.fail([error(node, 'roundabout_without_carriageway')]) unless arms.all?(&:carriageway)

        entries = []
        problems = []
        arms.each do |arm|
          entry = entry(arm, o, outer, inner, radius)
          entry.is_a?(Entry) ? entries << entry : problems << error(node, entry, road: arm.road.id)
        end
        return Core::Result.fail(problems.uniq(&:to_h)) unless problems.empty?

        corners = entries.each_index.map { |k| corner(node, entries[k], entries[(k + 1) % entries.size], o, outer, radius) }
        broken = corners.grep(String)
        return Core::Result.fail(broken.uniq.map { |r| error(node, r) }) unless broken.empty?

        entries.each { |e| e.arm.cut = cut(e, corners, o) }
        Core::Result.ok({ entries: entries, corners: corners, outer: outer, inner: inner })
      end

      # Une entrée : ligne médiane, point sur l'îlot central, îlot séparateur, arrondis de chaque bord.
      def entry(arm, o, outer, inner, radius)
        mid = (arm.kerb_l + arm.kerb_r) / 2
        return 'ring_too_small' if arm.kerb_l >= outer - 1e-9 || arm.kerb_r <= -outer + 1e-9 || mid.abs >= inner - 1e-9

        t_inner = line_circle(at(arm, 0, mid), arm.dir, o, inner)
        t_outer = line_circle(at(arm, 0, mid), arm.dir, o, outer)
        island = nil
        # La liaison d'un double giratoire n'a pas d'îlot séparateur.
        # Tram (AG-047) : le couloir des rails traverse l'îlot central ; ses bords coupent l'îlot.
        if arm.through
          return 'ring_too_small' if arm.kerb_l >= inner - 1e-9 || arm.kerb_r <= -inner + 1e-9

          edge_l = at(arm, line_circle(at(arm, 0, arm.kerb_l), arm.dir, o, inner), arm.kerb_l)
          edge_r = at(arm, line_circle(at(arm, 0, arm.kerb_r), arm.dir, o, inner), arm.kerb_r)
        end
        if !arm.link && !arm.through && arm.kerb_l - mid >= ISLAND_MIN_LANE_M + (ISLAND_BASE_M / 2) && mid - arm.kerb_r >= ISLAND_MIN_LANE_M + (ISLAND_BASE_M / 2)
          t1 = t_outer + ISLAND_GAP_M
          island = [t1, t1 + ISLAND_LENGTH_M]
        end
        ca, t1p, t2p = fillet(arm, o, outer, radius, arm.kerb_l + radius, arm.kerb_l)
        cb, t4p, t3p = fillet(arm, o, outer, radius, arm.kerb_r - radius, arm.kerb_r)
        return 'ring_too_small' unless ca && cb

        Entry.new(arm: arm, mid: mid, inner: at(arm, t_inner, mid), inner_l: edge_l, inner_r: edge_r, island: island, ca: ca, t1: t1p, t2: t2p, cb: cb, t3: t3p, t4: t4p)
      end

      # Arrondi tangent au bord u_kerb de la branche (côté trottoir) et, de l'extérieur, au bord de l'anneau.
      def fillet(arm, o, outer, radius, u_center, u_kerb)
        t = line_circle(at(arm, 0, u_center), arm.dir, o, outer + radius)
        return nil unless t

        c = at(arm, t, u_center)
        on_kerb = at(arm, t, u_kerb)
        k = outer / (outer + radius)
        [c, on_kerb, [o[0] + ((c[0] - o[0]) * k), o[1] + ((c[1] - o[1]) * k)]]
      end

      # Coin entre deux entrées voisines : bordure (bord de A, arrondi, anneau, arrondi, bord de B) et
      # bord extérieur du trottoir (angle vif sur chaque bord, arc concentrique à l'anneau).
      def corner(node, ea, eb, o, outer, radius)
        a = ea.arm
        b = eb.arm
        span = ccw(J.angle(J.sub(ea.t2, o)), J.angle(J.sub(eb.t3, o)))
        return 'roundabout_arms_too_close' if span >= J.ccw_delta(a.dir, b.dir) - 1e-9

        wa = a.outer_l - a.kerb_l
        wb = b.kerb_r - b.outer_r
        c = J::Corner.new(a: a, b: b, fillet: true)
        return c if wa < J::EPS && wb < J::EPS
        return 'junction_shape' if wa < J::EPS || wb < J::EPS

        w = [wa, wb].min
        ta = line_circle(at(a, 0, a.outer_l), a.dir, o, outer + w)
        tb = line_circle(at(b, 0, b.outer_r), b.dir, o, outer + w)
        return 'junction_shape' unless ta && tb

        xa = at(a, ta, a.outer_l)
        xb = at(b, tb, b.outer_r)
        ok = Math.hypot(xa[0] - ea.ca[0], xa[1] - ea.ca[1]) <= radius - MIN_WALK_M &&
             Math.hypot(xb[0] - eb.cb[0], xb[1] - eb.cb[1]) <= radius - MIN_WALK_M &&
             ccw(J.angle(J.sub(xa, o)), J.angle(J.sub(xb, o))) < J.ccw_delta(a.dir, b.dir)
        return 'junction_shape' unless ok

        c.outer = [xa] + arc_ccw(o, xa, xb, outer + w) + [xb]
        c
      end

      def along(arm, p)
        J.dot(J.sub(p, arm.origin), arm.dir)
      end

      # Coupe : arrondis, îlot, bord extérieur et recouvrement des emprises restent dans le giratoire.
      def cut(entry, corners, o)
        arm = entry.arm
        points = [entry.t1, entry.t4]
        corners.each do |c|
          next unless c.outer

          points << c.outer.first if c.a.equal?(arm)
          points << c.outer.last if c.b.equal?(arm)
        end
        # Recouvrement des emprises voisines : borné par l'intersection de leurs bords extérieurs.
        corners.each do |c|
          other, u_own, u_other = if c.a.equal?(arm) then [c.b, arm.outer_l, c.b.outer_r]
                                  elsif c.b.equal?(arm) then [c.a, arm.outer_r, c.a.outer_l]
                                  end
          next unless other

          q = J.intersect(at(arm, 0, u_own), arm.dir, at(other, 0, u_other), other.dir)
          points << q if q && along(arm, q).positive? && along(other, q).positive?
        end
        needs = points.map { |p| along(arm, p) }
        needs << (entry.island.last + ISLAND_GAP_M) if entry.island
        ([J::MIN_CUT_M] + needs).max
      end

      # Chemin de bordure d'un coin, de la coupe de A à celle de B.
      def kerb_path(ea, eb, o, outer, radius)
        a = ea.arm
        b = eb.arm
        path = [at(a, a.cut, a.kerb_l), ea.t1] + J.arc(ea.ca, ea.t1, ea.t2, radius) + [ea.t2] +
               arc_ccw(o, ea.t2, eb.t3, outer) + [eb.t3] + J.arc(eb.cb, eb.t3, eb.t4, radius) + [eb.t4, at(b, b.cut, b.kerb_r)]
        J.dedupe(path)
      end

      def inner_angle_points(ea, eb, o, inner)
        [ea.inner] + arc_ccw(o, ea.inner, eb.inner, inner)
      end

      # Ligne médiane de la branche, de l'îlot central à la coupe ; side +1 contourne l'îlot séparateur par
      # la gauche (secteur qui suit la branche), -1 par la droite (secteur qui la précède).
      def median(entry, side)
        arm = entry.arm
        pts = [entry.inner]
        if entry.island
          t1, t2 = entry.island
          pts += [at(arm, t1, entry.mid), at(arm, t1, entry.mid + (side * ISLAND_BASE_M / 2)), at(arm, t2, entry.mid)]
        end
        pts << at(arm, arm.cut, entry.mid)
        pts
      end

      # Points de la coupe de lo à hi, bornes comprises même si elles ne sont pas des points de la coupe.
      def cut_line(arm, lo, hi)
        inner = arm.points.map(&:first).uniq.select { |u| u > lo + 1e-9 && u < hi - 1e-9 }.sort
        ([lo] + inner + [hi]).map { |u| at(arm, arm.cut, u) }
      end

      # Faces : secteurs de chaussée, îlot central, îlots séparateurs, trottoirs de coin, contremarches.
      def faces(node, shape)
        entries = shape[:entries]
        o = node.point
        out = []
        problems = []
        island = []
        entries.each_with_index do |ea, k|
          eb = entries[(k + 1) % entries.size]
          a = ea.arm
          b = eb.arm
          corner = shape[:corners][k]
          path = kerb_path(ea, eb, o, shape[:outer], node.radius)
          # Le secteur longe la ligne médiane de chaque branche, ou le bord du couloir du tram.
          first = a.through ? ea.inner_l : ea.inner
          last = b.through ? eb.inner_r : eb.inner
          head = a.through ? [first, path.first] : median(ea, +1) + cut_line(a, ea.mid, a.kerb_l).drop(1)
          tail = b.through ? [last] : cut_line(b, b.kerb_r, eb.mid).drop(1) + median(eb, -1).reverse.drop(1)
          ring = [first] + arc_ccw(o, first, last, shape[:inner])
          sector = clean(head + path.drop(1) + tail + ring.drop(1).reverse)
          problems << N.error(node.id, 'junction_shape') unless N.add_polygon(out, sector, 0.0, 'road/lane')
          island << { start: a.through, points: ring + [last], stop: b.through }
          corner_faces(out, problems, node, corner, path)
        end
        island_pieces(island).each do |piece|
          problems << N.error(node.id, 'junction_shape') unless raised(out, clean(piece), 'road/plant')
        end
        out.concat(N.crossing_faces(node)) if entries.any? { |e| e.arm.through }
        entries.each do |e|
          next unless e.island

          t1, t2 = e.island
          tri = [at(e.arm, t1, e.mid - (ISLAND_BASE_M / 2)), at(e.arm, t2, e.mid), at(e.arm, t1, e.mid + (ISLAND_BASE_M / 2)), at(e.arm, t1, e.mid)]
          problems << N.error(node.id, 'junction_shape') unless raised(out, tri, 'road/median')
        end
        entries.each { |e| problems.concat(N.caps(out, e.arm, node, 0.0, shape[:corners])) }
        problems.empty? ? Core::Result.ok(out) : Core::Result.fail(problems.uniq(&:to_h))
      end

      # Îlot central : un disque, ou deux morceaux de part et d'autre du couloir du tram, chacun fermé
      # par la corde qui longe le couloir.
      def island_pieces(chains)
        return [chains.flat_map { |c| c[:points] }] if chains.none? { |c| c[:start] }

        k = chains.index { |c| c[:start] }
        ordered = chains.rotate(k)
        pieces = []
        ordered.each do |c|
          pieces << [] if c[:start]
          pieces.last.concat(c[:points])
        end
        pieces
      end

      def clean(poly)
        poly = J.dedupe(poly)
        poly.pop if poly.size > 1 && Math.hypot(poly[0][0] - poly[-1][0], poly[0][1] - poly[-1][1]) < 1e-7
        poly
      end

      # Plateau surélevé (îlot) et contremarche tout autour, tournée vers la chaussée.
      def raised(out, poly, material)
        return false unless N.add_polygon(out, poly, ISLAND_LEVEL_M, material)

        poly.each_index do |i|
          p = poly[i]
          q = poly[(i + 1) % poly.size]
          out << [[[p[0], p[1], 0.0], [q[0], q[1], 0.0], [q[0], q[1], ISLAND_LEVEL_M], [p[0], p[1], ISLAND_LEVEL_M]], 'road/curb']
        end
        true
      end

      def corner_faces(out, problems, node, corner, path)
        a = corner.a
        b = corner.b
        unless corner.outer
          corner.level = 0.0
          return
        end
        corner.level = [a.side_l, b.side_r].compact.min
        poly = path.reverse + J.cut_points(a, nil, [a.kerb_l, a.outer_l]).drop(1) + corner.outer +
               J.cut_points(b, nil, [b.outer_r, b.kerb_r]).reverse.drop(1).reverse
        poly = clean(poly)
        material = N.corner_material(a, :left) || N.corner_material(b, :right) || 'road/verge'
        return problems << N.error(node.id, 'junction_shape') unless N.add_polygon(out, poly, corner.level, material)
        return if corner.level.abs < 1e-9

        path.each_cons(2) do |p, q|
          quad = [[q[0], q[1], 0.0], [p[0], p[1], 0.0], [p[0], p[1], corner.level], [q[0], q[1], corner.level]]
          out << [corner.level.positive? ? quad : quad.reverse, 'road/curb']
        end
      end
    end
  end
end
