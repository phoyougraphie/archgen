# frozen_string_literal: true

module Archgen
  module Geometry
    # Axe d'une voie (docs/VOIRIE_CONTRACT.md, Tronçon) : polyligne dont chaque sommet intérieur
    # porte un rayon. Un rayon nul garde un angle vif à onglet ; sinon un arc tangent, découpé pour
    # que l'écart à la corde reste sous la tolérance au bord le plus éloigné.
    # Une station = point de l'axe, normale gauche (allongée à l'onglet), sommet d'origine.
    module RoadAxis
      MAX_TURN_RAD = 179.0 * Math::PI / 180.0
      TOL = 1e-9

      Station = Struct.new(:point, :normal, :vertex, :z, keyword_init: true)

      module_function

      # left_m : plus grand décalage à gauche de l'axe (>= 0) ; right_m : à droite (>= 0).
      def call(points, radii, left_m:, right_m:)
        segments = points.each_cons(2).map { |a, b| segment(a, b) }
        problems = segment_problems(segments)
        return Core::Result.fail(problems) unless problems.empty?

        turns = (1...(points.size - 1)).map { |i| turn(segments[i - 1][:dir], segments[i][:dir]) }
        problems = turn_problems(turns, radii, segments, left_m, right_m)
        return Core::Result.fail(problems) unless problems.empty?

        stations = build(points, radii, segments, turns, [left_m, right_m].max)
        problems = fold_problems(stations, left_m, right_m) + overlap_problems(stations, left_m, right_m)
        return Core::Result.fail(problems.uniq.sort_by(&:sort_key)) unless problems.empty?

        Core::Result.ok(stations.freeze)
      end

      def segment(a, b)
        d = [b[0] - a[0], b[1] - a[1]]
        len = Math.hypot(*d)
        { a: a, b: b, length: len, dir: len.zero? ? [0.0, 0.0] : [d[0] / len, d[1] / len] }
      end

      def left(dir)
        [-dir[1], dir[0]]
      end

      def turn(din, dout)
        Math.atan2((din[0] * dout[1]) - (din[1] * dout[0]), (din[0] * dout[0]) + (din[1] * dout[1]))
      end

      def error(path, reason, **params)
        Core::Diagnostic.error('E_ROAD_TRACE', path, reason: reason, **params)
      end

      def segment_problems(segments)
        segments.each_with_index.filter_map do |s, k|
          next if s[:length] >= Core::Limits::ROAD_MIN_SEGMENT_M - TOL

          error("/trace/segments/#{k}", 'segment_too_short', min: Core::Limits::ROAD_MIN_SEGMENT_M, value: Core::Quant.q(s[:length]))
        end
      end

      def tangent_length(radius, phi)
        radius * Math.tan(phi.abs / 2)
      end

      def turn_problems(turns, radii, segments, left_m, right_m)
        out = []
        turns.each_with_index do |phi, j|
          vertex = j + 1
          out << error("/trace/points_m/#{vertex}", 'reversal', max_deg: 179) if phi.abs > MAX_TURN_RAD
          next if radii[j].zero? || phi.abs < TOL

          # Le bord intérieur de l'arc garde au moins 1 m de rayon.
          inner = phi.positive? ? left_m : right_m
          min = inner + Core::Limits::ROAD_MIN_INNER_RADIUS_M
          out << error("/trace/radii_m/#{j}", 'radius_too_small', min: Core::Quant.q(min), value: radii[j]) if radii[j] < min - TOL
        end
        segments.each_with_index do |s, k|
          need = (k.positive? ? tangent_length(radii[k - 1], turns[k - 1]) : 0.0) +
                 (k < segments.size - 1 ? tangent_length(radii[k], turns[k]) : 0.0)
          out << error("/trace/segments/#{k}", 'arcs_too_long', value: Core::Quant.q(need), length: Core::Quant.q(s[:length])) if need > s[:length] + TOL
        end
        out
      end

      def build(points, radii, segments, turns, reach)
        out = [Station.new(point: points[0], normal: left(segments[0][:dir]), vertex: 0)]
        turns.each_with_index do |phi, j|
          vertex = j + 1
          next if phi.abs < TOL

          din = segments[j][:dir]
          dout = segments[j + 1][:dir]
          if radii[j].zero?
            out << mitre(points[vertex], din, dout, phi, vertex)
          else
            arc(points[vertex], din, phi, radii[j], reach, vertex).each { |st| out << st }
          end
        end
        out << Station.new(point: points[-1], normal: left(segments[-1][:dir]), vertex: points.size - 1)
        dedupe(out)
      end

      # Onglet : la normale suit la bissectrice, allongée de 1 / cos(φ/2) pour garder chaque largeur.
      def mitre(point, din, dout, phi, vertex)
        a = left(din)
        b = left(dout)
        sum = [a[0] + b[0], a[1] + b[1]]
        len = Math.hypot(*sum)
        scale = 1.0 / (Math.cos(phi / 2) * len)
        Station.new(point: point, normal: [sum[0] * scale, sum[1] * scale], vertex: vertex)
      end

      def arc(vertex_point, din, phi, radius, reach, vertex)
        t = tangent_length(radius, phi)
        start = [vertex_point[0] - (din[0] * t), vertex_point[1] - (din[1] * t)]
        sign = phi.positive? ? 1.0 : -1.0
        n0 = left(din)
        center = [start[0] + (n0[0] * radius * sign), start[1] + (n0[1] * radius * sign)]
        step = 2 * Math.acos(1 - (Core::Limits::ROAD_CHORD_TOLERANCE_M / (radius + reach)))
        count = [(phi.abs / step).ceil, 1].max
        (0..count).map do |m|
          angle = sign * phi.abs * m / count
          dir = rotate(din, angle)
          normal = left(dir)
          point = [center[0] - (normal[0] * radius * sign), center[1] - (normal[1] * radius * sign)]
          Station.new(point: point, normal: normal, vertex: vertex)
        end
      end

      def rotate(v, angle)
        c = Math.cos(angle)
        s = Math.sin(angle)
        [(v[0] * c) - (v[1] * s), (v[0] * s) + (v[1] * c)]
      end

      def dedupe(stations)
        # Deux stations confondues (fin d'arc et début du suivant) ont la même normale : on n'en garde qu'une.
        stations.each_with_object([]) do |st, out|
          next if out.any? && Math.hypot(st.point[0] - out[-1].point[0], st.point[1] - out[-1].point[1]) < 1e-7

          out << st
        end
      end

      def offset(st, d)
        [st.point[0] + (st.normal[0] * d), st.point[1] + (st.normal[1] * d)]
      end

      # Un bord intérieur qui recule plus que la longueur disponible se replie : refus.
      def fold_problems(stations, left_m, right_m)
        stations.each_cons(2).flat_map do |a, b|
          chord = [b.point[0] - a.point[0], b.point[1] - a.point[1]]
          [left_m, -right_m].filter_map do |d|
            pa = offset(a, d)
            pb = offset(b, d)
            along = ((pb[0] - pa[0]) * chord[0]) + ((pb[1] - pa[1]) * chord[1])
            next if along > Core::Quant::MIN_EDGE_M * Math.hypot(*chord)

            error("/trace/points_m/#{[a.vertex, b.vertex].max}", 'inner_edge_folds')
          end
        end
      end

      # Contour de l'emprise : bord gauche à l'aller, bord droit au retour. Il doit rester simple.
      def overlap_problems(stations, left_m, right_m)
        ring = stations.map { |s| offset(s, left_m) } + stations.reverse.map { |s| offset(s, -right_m) }
        owners = stations.map(&:vertex) + stations.reverse.map(&:vertex)
        edges = ring.each_index.map { |i| [ring[i], ring[(i + 1) % ring.size]] }
        hit = first_crossing(edges)
        return [] unless hit

        [error("/trace/points_m/#{[owners[hit[0]], owners[hit[1]]].max}", 'self_overlap')]
      end

      # Grille : seules les arêtes d'une même case sont comparées.
      def first_crossing(edges)
        cell = 10.0
        grid = Hash.new { |h, k| h[k] = [] }
        edges.each_with_index do |(p, q), i|
          xs = [p[0], q[0]].minmax.map { |v| (v / cell).floor }
          ys = [p[1], q[1]].minmax.map { |v| (v / cell).floor }
          (xs[0]..xs[1]).each { |x| (ys[0]..ys[1]).each { |y| grid[[x, y]] << i } }
        end
        n = edges.size
        grid.each_value do |list|
          list.combination(2) do |i, j|
            next if (i - j).abs <= 1 || (i - j).abs == n - 1

            return [i, j] if crossing?(edges[i], edges[j])
          end
        end
        nil
      end

      def crossing?((p1, p2), (q1, q2))
        d1 = orient(q1, q2, p1)
        d2 = orient(q1, q2, p2)
        d3 = orient(p1, p2, q1)
        d4 = orient(p1, p2, q2)
        ((d1.positive? && d2.negative?) || (d1.negative? && d2.positive?)) &&
          ((d3.positive? && d4.negative?) || (d3.negative? && d4.positive?))
      end

      def orient(a, b, c)
        ((b[0] - a[0]) * (c[1] - a[1])) - ((b[1] - a[1]) * (c[0] - a[0]))
      end
    end
  end
end
