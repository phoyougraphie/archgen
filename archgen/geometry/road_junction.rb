# frozen_string_literal: true

module Archgen
  module Geometry
    # Carrefour simple d'un réseau de voies (docs/VOIRIE_CONTRACT.md, Carrefours ; ADR-36).
    # Chaque branche est coupée net à une distance qui laisse la place aux arrondis de bordure ;
    # un plateau de chaussée remplit le cœur, les trottoirs tournent les angles, des contremarches
    # et des murets ferment chaque différence de niveau. Plan pur, en mètres, repère du réseau.
    module RoadJunction
      MIN_CUT_M = 1.0
      STRAIGHT_RAD = 175.0 * Math::PI / 180.0
      CHORD_M = 0.05
      EPS = 1e-9
      # Largeur de trottoir gardée au plus étroit d'un coin, entre la bordure et l'angle extérieur.
      MIN_WALK_M = 0.3

      # road : index, section, ax ; s : abscisse du nœud sur la voie ; sign : +1 branche vers l'aval ;
      # origin : point de l'axe de la voie au nœud.
      Arm = Struct.new(:road, :s, :sign, :dir, :left, :points, :kerb_l, :kerb_r, :outer_l, :outer_r,
                       :carriageway, :side_l, :side_r, :origin, :cut, :ext, :link, :through, keyword_init: true) do
        # Bout de la zone du carrefour sur la branche : coupe, plus le marquage d'un carrefour à feux.
        def reach
          cut + (ext || 0.0)
        end

        # Ordre de grandeur de l'emprise, pour juger qu'un onglet part trop loin.
        def width_hint
          outer_l - outer_r
        end
      end
      Corner = Struct.new(:a, :b, :fillet, :center, :ta, :tb, :k, :q, :outer, :broken, :poly, :level, keyword_init: true)

      module_function

      # Profil de coupe d'une branche, dans son repère : u positif à gauche en regardant vers l'extérieur.
      def arm(road, s, sign, dir, origin)
        left = [-dir[1], dir[0]]
        line = road.line
        pts = []
        line.each do |a, b, _|
          pts << [a[0], a[1]] if pts.empty?
          pts << [b[0], b[1]]
        end
        to_u = ->(x) { sign.positive? ? road.ax - x : x - road.ax }
        points = pts.map { |x, z| [to_u.call(x), z] }
        points.reverse! if sign.positive? # de droite (u petit) à gauche (u grand)
        carriage = road.section['bands'].select { |b| b['role'] == 'carriageway' }
        us = points.map(&:first)
        if carriage.empty?
          kerb_l = us.max
          kerb_r = us.min
        else
          xs = [carriage.map { |b| b['x0_m'] }.min, carriage.map { |b| b['x1_m'] }.max].map { |x| to_u.call(x) }
          kerb_r, kerb_l = xs.minmax
        end
        Arm.new(road: road, s: s, sign: sign, dir: dir, left: left, origin: origin, points: points, kerb_l: kerb_l, kerb_r: kerb_r,
                outer_l: us.max, outer_r: us.min, carriageway: !carriage.empty?,
                side_l: side_level(points, kerb_l, +1), side_r: side_level(points, kerb_r, -1))
      end

      # Niveau de la surface juste au-delà de la bordure, côté extérieur ; nil sans rien au-delà.
      # Les points vont de droite à gauche ; une contremarche donne deux points de même u.
      def side_level(points, kerb, way)
        at = points.each_index.select { |i| (points[i][0] - kerb).abs < EPS }
        return nil if at.empty?

        if way.positive?
          return nil unless points.any? { |u, _| u > kerb + EPS }

          points[at.max][1]
        else
          return nil unless points.any? { |u, _| u < kerb - EPS }

          points[at.min][1]
        end
      end

      # Point de la branche à la distance along de son origine (l'axe de sa voie au nœud), décalé de u.
      def point(arm, _node, along, u)
        o = arm.origin
        [o[0] + (arm.dir[0] * along) + (arm.left[0] * u), o[1] + (arm.dir[1] * along) + (arm.left[1] * u)]
      end

      def angle(v)
        Math.atan2(v[1], v[0])
      end

      def ccw_delta(a, b)
        d = angle(b) - angle(a)
        d += 2 * Math::PI while d <= 0
        d -= 2 * Math::PI while d > 2 * Math::PI
        d
      end

      def intersect(p, d, q, e)
        den = (d[0] * e[1]) - (d[1] * e[0])
        return nil if den.abs < 1e-12

        t = (((q[0] - p[0]) * e[1]) - ((q[1] - p[1]) * e[0])) / den
        [p[0] + (d[0] * t), p[1] + (d[1] * t)]
      end

      def dot(a, b)
        (a[0] * b[0]) + (a[1] * b[1])
      end

      def sub(a, b)
        [a[0] - b[0], a[1] - b[1]]
      end

      # Coins entre branches consécutives (sens direct). Trois formes :
      # - arrondi de bordure (angle < 175°, les deux côtés bordés ou aucun) ;
      # - angle vif en onglet K (angle >= 175°, ou un seul côté bordé : un chemin rejoint une rue) ;
      # - corde droite, quand l'onglet partirait trop loin (bords presque parallèles et décalés).
      def corners(arms, node, radius)
        arms.each_index.map do |k|
          a = arms[k]
          b = arms[(k + 1) % arms.size]
          theta = ccw_delta(a.dir, b.dir)
          wa = a.outer_l - a.kerb_l
          wb = b.kerb_r - b.outer_r
          one_sided = (wa < EPS) != (wb < EPS)
          corner = Corner.new(a: a, b: b, fillet: theta < STRAIGHT_RAD && !one_sided)
          if corner.fillet
            fillet(corner, node, radius)
            outside(corner, node, radius, wa, wb)
          else
            mitre(corner, node, [a.width_hint, b.width_hint].max)
          end
          corner
        end
      end

      def fillet(corner, node, radius)
        a = corner.a
        b = corner.b
        kerb_a = point(a, node, 0, a.kerb_l)
        kerb_b = point(b, node, 0, b.kerb_r)
        shifted_a = [kerb_a[0] + (a.left[0] * radius), kerb_a[1] + (a.left[1] * radius)]
        shifted_b = [kerb_b[0] - (b.left[0] * radius), kerb_b[1] - (b.left[1] * radius)]
        c = intersect(shifted_a, a.dir, shifted_b, b.dir)
        corner.center = c
        corner.ta = [c[0] - (a.left[0] * radius), c[1] - (a.left[1] * radius)]
        corner.tb = [c[0] + (b.left[0] * radius), c[1] + (b.left[1] * radius)]
      end

      # Onglet : K croise les bordures, q les bords extérieurs. Corde si l'un d'eux part trop loin.
      def mitre(corner, node, reach)
        a = corner.a
        b = corner.b
        k = intersect(point(a, node, 0, a.kerb_l), a.dir, point(b, node, 0, b.kerb_r), b.dir)
        q = intersect(point(a, node, 0, a.outer_l), a.dir, point(b, node, 0, b.outer_r), b.dir)
        near = ->(p) { p && Math.hypot(p[0] - a.origin[0], p[1] - a.origin[1]) <= 2 * reach }
        return unless near.call(k) && near.call(q)

        corner.k = k
        corner.q = q
        corner.outer = [q] if a.outer_l - a.kerb_l > EPS && b.kerb_r - b.outer_r > EPS
      end

      # Bord extérieur du trottoir d'un coin arrondi : l'angle vif q quand il reste derrière la bordure,
      # sinon le plus grand arrondi tangent aux deux bords extérieurs, par pas de 0,5 m, qui reste dans
      # le cercle de bordure (donc derrière les deux bordures) à MIN_WALK_M au moins. Bords de même
      # largeur : le premier essai, R - w, est concentrique à la bordure. Sinon, refus junction_shape.
      def outside(corner, node, radius, wa, wb)
        return if wa < EPS && wb < EPS

        a = corner.a
        b = corner.b
        corner.q = intersect(point(a, node, 0, a.outer_l), a.dir, point(b, node, 0, b.outer_r), b.dir)
        return corner.broken = true if corner.q.nil?

        c = corner.center
        if radius - Math.hypot(corner.q[0] - c[0], corner.q[1] - c[1]) >= MIN_WALK_M
          corner.outer = [corner.q]
          return
        end
        corner.outer = outer_candidates(radius - [wa, wb].min).lazy.filter_map do |r|
          co = intersect(point(a, node, 0, a.outer_l + r), a.dir, point(b, node, 0, b.outer_r - r), b.dir)
          next unless co

          oa = [co[0] - (a.left[0] * r), co[1] - (a.left[1] * r)]
          ob = [co[0] + (b.left[0] * r), co[1] + (b.left[1] * r)]
          path = [oa] + arc(co, oa, ob, r) + [ob]
          path if path.all? { |p| Math.hypot(p[0] - c[0], p[1] - c[1]) <= radius - MIN_WALK_M + 1e-9 }
        end.first
        corner.broken = true unless corner.outer
      end

      def outer_candidates(top)
        first = Core::Quant.q(top)
        steps = ((top - 0.5) / 0.5).floor
        ([first] + (0..steps).map { |k| Core::Quant.q(top - 0.5 - (0.5 * k)) }).select { |r| r >= 0.5 - 1e-9 }.uniq
      end

      # Distance de coupe : arrondis, onglet et coin extérieur restent dans le carrefour.
      # q borne le recouvrement des deux emprises ; l'arrondi extérieur part de oa sur A et finit en ob sur B.
      def needs(corner, _node)
        a = corner.a
        b = corner.b
        along_a = ->(p) { dot(sub(p, a.origin), a.dir) }
        along_b = ->(p) { dot(sub(p, b.origin), b.dir) }
        need_a = ([MIN_CUT_M] + [corner.ta, corner.k, corner.q, corner.outer&.first].compact.map(&along_a)).max
        need_b = ([MIN_CUT_M] + [corner.tb, corner.k, corner.q, corner.outer&.last].compact.map(&along_b)).max
        [need_a, need_b]
      end

      def arc(center, from, to, radius)
        a0 = angle(sub(from, center))
        delta = angle(sub(to, center)) - a0
        delta -= 2 * Math::PI while delta > Math::PI
        delta += 2 * Math::PI while delta <= -Math::PI
        step = 2 * Math.acos(1 - (CHORD_M / radius))
        count = [(delta.abs / step).ceil, 1].max
        (1...count).map do |i|
          t = a0 + (delta * i / count)
          [center[0] + (radius * Math.cos(t)), center[1] + (radius * Math.sin(t))]
        end
      end

      # Chemin de bordure du coin, de la coupe de A à celle de B, dans le plan. Un côté sans bord
      # (chemin) passe par q quand q tombe entre l'onglet et la coupe, pour que les faces se touchent.
      def kerb_path(corner, node, radius)
        a = corner.a
        b = corner.b
        start = point(a, node, a.cut, a.kerb_l)
        finish = point(b, node, b.cut, b.kerb_r)
        if corner.fillet
          path = [start]
          path << corner.ta if a.cut > dot(sub(corner.ta, a.origin), a.dir) + 1e-6
          path.concat(arc(corner.center, corner.ta, corner.tb, radius))
          path << corner.tb if b.cut > dot(sub(corner.tb, b.origin), b.dir) + 1e-6
          path << finish
          return dedupe(path)
        end
        return [start, finish] unless corner.k

        k = corner.k
        q = corner.q
        path = [start]
        path << q if corner.outer.nil? && between?(a, q, k, a.cut)
        path << k
        path << q if corner.outer.nil? && between?(b, q, k, b.cut)
        path << finish
        dedupe(path)
      end

      # p est-il sur l'axe de la branche, plus loin que k et avant la coupe ?
      def between?(arm, p, k, cut)
        return false unless p

        along = dot(sub(p, arm.origin), arm.dir)
        on_line = [arm.kerb_l, arm.kerb_r].any? { |u| (dot(sub(p, arm.origin), arm.left) - u).abs < 1e-6 }
        on_line && along > dot(sub(k, arm.origin), arm.dir) + 1e-6 && along < cut - 1e-6
      end

      def dedupe(points)
        points.each_with_object([]) { |p, out| out << p unless out.any? && Math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) < 1e-7 }
      end

      def cut_points(arm, node, range)
        lo, hi = range
        arm.points.map(&:first).uniq.select { |u| u >= lo - EPS && u <= hi + EPS }.sort.map { |u| point(arm, node, arm.cut, u) }
      end

      # Triangulation par oreilles d'un polygone simple orienté dans le sens direct (plan xy).
      def triangulate(poly)
        idx = (0...poly.size).to_a
        out = []
        guard = poly.size * poly.size + 10
        while idx.size > 3
          guard -= 1
          return nil if guard.negative?

          k = idx.each_index.find { |i| ear?(poly, idx, i) }
          return nil unless k

          out << [idx[k - 1], idx[k], idx[(k + 1) % idx.size]]
          idx.delete_at(k)
        end
        out << idx if cross(poly[idx[0]], poly[idx[1]], poly[idx[2]]) > 1e-10
        out
      end

      def ear?(poly, idx, i)
        a = idx[i - 1]
        b = idx[i]
        c = idx[(i + 1) % idx.size]
        return false unless cross(poly[a], poly[b], poly[c]) > 1e-10

        idx.none? { |m| ![a, b, c].include?(m) && inside?(poly[m], poly[a], poly[b], poly[c]) }
      end

      def cross(a, b, c)
        ((b[0] - a[0]) * (c[1] - a[1])) - ((b[1] - a[1]) * (c[0] - a[0]))
      end

      def inside?(p, a, b, c)
        cross(a, b, p) >= -1e-10 && cross(b, c, p) >= -1e-10 && cross(c, a, p) >= -1e-10
      end

      def signed_area(poly)
        poly.each_index.sum { |i| (poly[i][0] * poly[(i + 1) % poly.size][1]) - (poly[(i + 1) % poly.size][0] * poly[i][1]) } / 2.0
      end
    end
  end
end
