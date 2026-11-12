# frozen_string_literal: true

module Archgen
  module Geometry
    # Voie sur un terrain, étape 1 (AG-049, ADR-38 ; docs/VOIRIE_CONTRACT.md, Terrain) : relevé du
    # couloir en repère de la voie, profil en long à pente bornée, stations ajoutées aux points de
    # pente, talus jusqu'au terrain. Plan pur, en mètres ; le terrain arrive en grille relevée.
    module RoadGround
      RELIEF_MAX_M = 6.0
      OVERLAP_M = 0.05
      LEVEL_TOL_M = 0.01
      MAX_POINTS = 6000
      RAIL_GRADE = 2.5
      TRAM_GRADE = 6.0
      DEFAULTS = { 'survey_step_m' => 4.0, 'grade_step_m' => 20.0, 'max_grade_percent' => 8.0, 'slope_ratio' => 1.5 }.freeze

      module_function

      def settings(ground)
        DEFAULTS.merge(ground || {})
      end

      def error(code, path, reason, **params)
        Core::Diagnostic.error(code, path, reason: reason, **params)
      end

      def q(value)
        Core::Quant.q(value)
      end

      def margin(ground)
        (RELIEF_MAX_M * ground['slope_ratio']) + ground['survey_step_m']
      end

      # Axes du relevé : s de 0 à L en intervalles égaux ; u de −(droite + marge) à gauche + marge,
      # 0 et les bords de l'emprise compris (u positif à gauche).
      def axes(length, left_m, right_m, ground)
        step = ground['survey_step_m']
        n = [(length / step).ceil, 1].max
        s = (0..n).map { |i| q(length * i / n) }
        lo = -(right_m + margin(ground))
        hi = left_m + margin(ground)
        count = ((hi - lo) / step).ceil
        u = (0..count).map { |k| q(lo + ((hi - lo) * k / count)) }
        u = (u + [0.0, q(left_m), q(-right_m)]).uniq.sort
        Core::Result.ok({ 's_m' => s, 'u_m' => u }).then do |r|
          points = s.size * u.size
          next r if points <= MAX_POINTS

          Core::Result.fail([error('E_ROAD_BUDGET', '/ground/survey_step_m', 'ground_points', limit: MAX_POINTS, value: points)])
        end
      end

      # Point et normale de l'axe à l'abscisse s, interpolés entre stations.
      def frame_at(stations, s)
        walked = 0.0
        stations.each_cons(2) do |a, b|
          len = Math.hypot(b.point[0] - a.point[0], b.point[1] - a.point[1])
          if s <= walked + len + 1e-9 || b.equal?(stations.last)
            t = len.zero? ? 0.0 : [[(s - walked) / len, 0.0].max, 1.0].min
            n = [a.normal[0] + ((b.normal[0] - a.normal[0]) * t), a.normal[1] + ((b.normal[1] - a.normal[1]) * t)]
            l = Math.hypot(*n)
            return [[a.point[0] + ((b.point[0] - a.point[0]) * t), a.point[1] + ((b.point[1] - a.point[1]) * t)], [n[0] / l, n[1] / l]]
          end
          walked += len
        end
      end

      # Points du relevé, ligne par ligne (s puis u), en repère du tracé (premier point à l'origine).
      def corridor_points(stations, axes)
        axes['s_m'].flat_map do |s|
          point, normal = frame_at(stations, s)
          axes['u_m'].map { |u| [point[0] + (normal[0] * u), point[1] + (normal[1] * u)] }
        end
      end

      # Altitude du terrain en (s, u), bilinéaire ; nil hors de la grille ou sur un trou.
      def terrain(grid, s, u)
        i = bracket(grid['s_m'], s)
        j = bracket(grid['u_m'], u)
        return nil unless i && j

        s0, s1 = grid['s_m'].values_at(i, i + 1)
        u0, u1 = grid['u_m'].values_at(j, j + 1)
        z = grid['z_m']
        corners = [z[i][j], z[i][j + 1], z[i + 1][j], z[i + 1][j + 1]]
        return nil if corners.any?(&:nil?)

        ts = s1 == s0 ? 0.0 : (s - s0) / (s1 - s0)
        tu = u1 == u0 ? 0.0 : (u - u0) / (u1 - u0)
        a = corners[0] + ((corners[1] - corners[0]) * tu)
        b = corners[2] + ((corners[3] - corners[2]) * tu)
        a + ((b - a) * ts)
      end

      def bracket(values, v)
        return nil if v < values.first - 1e-6 || v > values.last + 1e-6

        k = values.each_cons(2).find_index { |a, b| v >= a - 1e-6 && v <= b + 1e-6 }
        k || (values.size - 2)
      end

      # Points de pente [[s, z]] : moyenne du terrain sur l'emprise roulante à chaque abscisse.
      def profile(grid, length, span, ground, section, water: nil)
        step = ground['grade_step_m']
        ss = (0..(length / step).floor).map { |k| q(k * step) }
        ss << q(length) if length - ss.last > 1e-6
        lo, hi = span
        us = grid['u_m'].select { |u| u >= lo - 1e-9 && u <= hi + 1e-9 } | [lo, hi]
        samples = []
        ss.each do |s|
          zs = us.map { |u| terrain(grid, s, u) }
          return Core::Result.fail([error('E_ROAD_GROUND', '/ground', 'ground_missing', s_m: q(s))]) if zs.any?(&:nil?)

          samples << [s, q(zs.sum / zs.size)]
        end
        river = water && water['mode'] == 'river'
        # Canal : la pente n'a pas de sens, les biefs sont plats et les écluses placées ensuite (RoadLocks).
        return Core::Result.ok(samples) if water && water['mode'] == 'canal'
        # Un seul niveau (AG-055) : le niveau saisi, sinon le plus bas des points de pente.
        if water && water['mode'] == 'flat'
          level = water.key?('level_m') ? water['level_m'] : samples.map(&:last).min
          return Core::Result.ok(samples.map { |s, _| [s, q(level)] })
        end
        if river
          samples = river_envelope(samples)
          return samples unless samples.ok?

          samples = samples.value
        end
        limit = river ? water['max_grade_percent'] : grade_limit(ground, section)
        path = river ? '/water/max_grade_percent' : '/ground/max_grade_percent'
        problems = samples.each_cons(2).filter_map do |(s0, z0), (s1, z1)|
          grade = ((z1 - z0) / (s1 - s0)).abs * 100
          next if grade <= limit + 1e-9

          error('E_ROAD_GRADE', path, 'grade_too_steep', s_m: q(s0), value: grade.round(2), limit: limit)
        end
        problems.empty? ? Core::Result.ok(samples) : Core::Result.fail(problems)
      end

      # Rivière (EAU_CONTRACT, AG-053) : le tracé va de l'amont vers l'aval, et l'eau ne remonte jamais.
      # À chaque point de pente, le niveau est le plus bas entre le terrain moyen en ce point et le niveau
      # du point précédent : là où le terrain remonte, la rivière creuse.
      UPSTREAM_TOL_M = 1.0

      def river_envelope(samples)
        rise = samples.last[1] - samples.first[1]
        if rise >= UPSTREAM_TOL_M - 1e-9
          return Core::Result.fail([error('E_ROAD_WATER', '/trace', 'river_upstream', value: q(rise), limit: UPSTREAM_TOL_M)])
        end

        level = nil
        Core::Result.ok(samples.map do |s, z|
          level = level.nil? ? z : [level, z].min
          [s, level]
        end)
      end

      def grade_limit(ground, section)
        roles = section['bands'].map { |b| b['role'] }
        limit = ground['max_grade_percent']
        limit = [limit, RAIL_GRADE].min if roles.include?('rail')
        limit = [limit, TRAM_GRADE].min if roles.include?('tram') || section['bands'].any? { |b| b['type'] == 'tram_lane' }
        limit
      end

      def z_at(samples, s)
        k = samples.each_cons(2).find_index { |(a, _), (b, _)| s >= a - 1e-9 && s <= b + 1e-9 } || (samples.size - 2)
        (s0, z0), (s1, z1) = samples[k], samples[k + 1]
        return z0 if s1 == s0

        z0 + ((z1 - z0) * (s - s0) / (s1 - s0))
      end

      # Stations du tracé, plus une à chaque point de pente tombant dans un segment droit ; chacune
      # reçoit sa cote (repère du modèle) et son abscisse.
      def stations(stations, samples)
        chain = [0.0]
        stations.each_cons(2) { |a, b| chain << (chain.last + Math.hypot(b.point[0] - a.point[0], b.point[1] - a.point[1])) }
        out = [[stations.first, 0.0]]
        stations.each_cons(2).with_index do |(a, b), i|
          straight = (a.normal[0] - b.normal[0]).abs < 1e-9 && (a.normal[1] - b.normal[1]).abs < 1e-9
          if straight
            samples.map(&:first).select { |s| s > chain[i] + 1e-6 && s < chain[i + 1] - 1e-6 }.each do |s|
              t = (s - chain[i]) / (chain[i + 1] - chain[i])
              point = [a.point[0] + ((b.point[0] - a.point[0]) * t), a.point[1] + ((b.point[1] - a.point[1]) * t)]
              out << [RoadAxis::Station.new(point: point, normal: a.normal, vertex: -1), s]
            end
          end
          out << [b, chain[i + 1]]
        end
        out.map { |st, s| [RoadAxis::Station.new(point: st.point, normal: st.normal, vertex: st.vertex, z: z_at(samples, s)), s] }
      end

      # Déblai ou remblai sous l'emprise, à chaque station : au plus RELIEF_MAX_M.
      def earthwork(grid, placed, line, ax)
        worst = { cut: 0.0, fill: 0.0 }
        placed.each do |station, s|
          line.each do |(xa, za), (xb, zb), _|
            [[xa, za], [xb, zb]].each do |x, z|
              ground = terrain(grid, s, ax - x)
              next unless ground

              diff = ground - (station.z + z)
              worst[:cut] = [worst[:cut], diff].max
              worst[:fill] = [worst[:fill], -diff].max
              next if diff.abs <= RELIEF_MAX_M + 1e-9

              return Core::Result.fail([error('E_ROAD_EARTHWORK', '/ground', 'earthwork_too_high', s_m: q(s), value: q(diff.abs), limit: RELIEF_MAX_M)])
            end
          end
        end
        Core::Result.ok(worst)
      end

      # Talus d'un bord : du bord (u, z) vers l'extérieur (side = +1 à gauche, -1 à droite) jusqu'au terrain.
      def toe(grid, s, u, z, side, ground)
        ratio = ground['slope_ratio']
        here = terrain(grid, s, u)
        return nil if here.nil?
        return [u, z] if (here - z).abs <= LEVEL_TOL_M

        up = here > z ? 1 : -1
        height = ->(d) { z + (up * d / ratio) }
        gap = ->(d) { g = terrain(grid, s, u + (side * d)); g && ((height.call(d) - g) * up) }
        step = ground['survey_step_m'] / 4.0
        reach = margin(ground)
        d = 0.0
        while d < reach
          nxt = [d + step, reach].min
          g = gap.call(nxt)
          return :hole if g.nil?
          if g >= 0
            lo = d
            hi = nxt
            30.times do
              mid = (lo + hi) / 2
              gap.call(mid) >= 0 ? hi = mid : lo = mid
            end
            return [u + (side * hi), height.call(hi) + (up * OVERLAP_M)]
          end
          d = nxt
        end
        :none
      end

      # Faces des talus des deux bords, entre stations voisines ; repère de la racine (z − z0).
      # open : côté sans talus ('left' ou 'right'), celui de la mer : le bord de la voie y est le bord de l'entaille.
      def slopes(grid, placed, line, ax, ground, z0, open: nil)
        width_left = ax
        width_right = ax - (line.last[1][0])
        sides = [[+1, width_left, line.first[0][1]], [-1, width_right, line.last[1][1]]]
        rows = sides.map do |side, u, dz|
          bare = open == (side.positive? ? 'left' : 'right')
          placed.map do |station, s|
            edge_z = station.z + dz
            foot = bare ? [u, edge_z] : toe(grid, s, u, edge_z, side, ground)
            if foot.nil? || foot == :hole || foot == :none
              return Core::Result.fail([error('E_ROAD_TOE', '/ground/slope_ratio', 'road_toe_not_found', s_m: q(s), side: side.positive? ? 'left' : 'right')])
            end

            [station, u, edge_z, foot]
          end
        end
        faces = []
        reach = 0.0
        rows.each_with_index do |row, k|
          side = sides[k][0]
          row.each_cons(2) do |(sa, ua, za, fa), (sb, ub, zb, fb)|
            pa = place(sa, ua, za - z0)
            pb = place(sb, ub, zb - z0)
            qa = place(sa, fa[0], fa[1] - z0)
            qb = place(sb, fb[0], fb[1] - z0)
            reach = [reach, (fa[0] - ua).abs, (fb[0] - ub).abs].max
            quad = side.positive? ? [pa, qa, qb, pb] : [pa, pb, qb, qa]
            [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]].each do |tri|
              next if area(tri) < 1e-8

              faces << (normal(tri)[2] >= 0 ? tri : tri.reverse)
            end
          end
        end
        # Contour de l'entaille : pieds gauches dans l'ordre, pieds droits à rebours (repère de la racine).
        outline = rows[0].map { |st, _u, _z, f| place(st, f[0], 0)[0, 2] } + rows[1].reverse.map { |st, _u, _z, f| place(st, f[0], 0)[0, 2] }
        Core::Result.ok({ faces: faces, reach: reach, outline: outline })
      end

      def place(station, u, z)
        [station.point[0] + (station.normal[0] * u), station.point[1] + (station.normal[1] * u), z]
      end

      def normal(tri)
        a, b, c = tri
        ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]]
        ac = [c[0] - a[0], c[1] - a[1], c[2] - a[2]]
        [(ab[1] * ac[2]) - (ab[2] * ac[1]), (ab[2] * ac[0]) - (ab[0] * ac[2]), (ab[0] * ac[1]) - (ab[1] * ac[0])]
      end

      def area(tri)
        n = normal(tri)
        Math.sqrt(n.sum { |c| c * c }) / 2
      end
    end
  end
end
