# frozen_string_literal: true

module Archgen
  module Geometry
    # Canal à écluses sur un terrain (docs/EAU_CONTRACT.md, AG-054). Le canal avance par biefs
    # horizontaux ; une écluse est placée par une règle fixe dès que le terrain s'écarte du bief de plus
    # de la chute. Dans la chambre, les bandes de terre passent en rampe d'un bief à l'autre ; le lit et
    # l'eau restent au niveau bas ; un mur de chute ferme le lit côté haut ; une porte à chaque bout.
    # Plan pur, en mètres.
    module RoadLocks
      APPROACH_M = 10.0
      GATE_THICKNESS_M = 0.4
      GATE_RISE_M = 0.2
      TOL = 1e-6

      Lock = Struct.new(:c0, :c1, :from, :to, keyword_init: true) do
        def low
          [from, to].min
        end

        def drop
          to - from
        end
      end

      module_function

      def error(path, reason, **params)
        Core::Diagnostic.error('E_ROAD_WATER', path, reason: reason, **params)
      end

      def q(value)
        Core::Quant.q(value)
      end

      # samples : [[s, moyenne du terrain sous l'eau]] aux points de pente ; stations : axe en plan.
      # Retourne { samples: profil des biefs et des rampes, locks: [Lock] }.
      def plan(samples, water, stations, length)
        drop = water['lock_drop_m']
        chamber = water['lock_length_m']
        level = samples.first[1]
        locks = []
        profile = [[samples.first[0], level]]
        samples.each_with_index.drop(1).each do |(s, z), k|
          while (z - level).abs > drop + TOL
            c1 = samples[k - 1][0]
            lock = Lock.new(c0: q(c1 - chamber), c1: q(c1), from: level, to: q(level + (z > level ? drop : -drop)))
            problem = placement_problem(lock, locks.last, stations, length)
            return Core::Result.fail([problem]) if problem

            locks << lock
            level = lock.to
          end
          profile << [s, level]
        end
        Core::Result.ok({ samples: with_ramps(profile, locks), locks: locks })
      end

      def placement_problem(lock, previous, stations, length)
        lo = lock.c0 - APPROACH_M
        hi = lock.c1 + APPROACH_M
        return error('/trace', 'lock_outside_trace', s_m: lock.c0, limit: APPROACH_M) if lo < -TOL || hi > length + TOL
        return error('/trace', 'locks_too_close', s_m: lock.c0) if previous && lo < previous.c1 + APPROACH_M - TOL
        return error('/trace', 'lock_on_curve', s_m: lock.c0) unless straight?(stations, lo, hi)

        nil
      end

      # Points du profil : biefs plats, rampe droite d'un bief à l'autre le long de chaque chambre.
      def with_ramps(profile, locks)
        points = profile.dup
        locks.each do |lock|
          points.reject! { |s, _| s > lock.c0 + TOL && s < lock.c1 - TOL }
          points.reject! { |s, _| (s - lock.c0).abs < TOL || (s - lock.c1).abs < TOL }
          points << [lock.c0, lock.from] << [lock.c1, lock.to]
        end
        points.sort_by(&:first).map { |s, z| [q(s), q(z)] }
      end

      # Le tracé est-il droit, sans sommet ni arc, de lo à hi ?
      def straight?(stations, lo, hi)
        s = 0.0
        normal = nil
        stations.each_cons(2) do |a, b|
          s_b = s + Math.hypot(b.point[0] - a.point[0], b.point[1] - a.point[1])
          if s_b > lo + TOL && s < hi - TOL
            return false unless (a.normal[0] - b.normal[0]).abs < 1e-9 && (a.normal[1] - b.normal[1]).abs < 1e-9

            normal ||= a.normal
            return false unless (normal[0] - a.normal[0]).abs < 1e-9 && (normal[1] - a.normal[1]).abs < 1e-9
          end
          s = s_b
        end
        true
      end

      # --- Plan

      # Décalage du lit et de l'eau à une station (repère de la racine) : dans la chambre, on les ramène
      # au niveau bas ; ailleurs, rien.
      def shift(lock, s, z, z0)
        return 0.0 unless lock

        (lock.low - z0) - z
      end

      def lock_of_pair(locks, s_a, s_b)
        locks.find { |l| s_a > l.c0 - TOL && s_b < l.c1 + TOL }
      end

      # Points du lit des plans d'eau (x dans un plan d'eau, au niveau du lit) décalés de d.
      def shifted(line, beds, d)
        return line if d.zero?

        move = lambda do |(x, z)|
          bed = beds.find { |x0, x1, zb| x > x0 - TOL && x < x1 + TOL && z < zb + TOL }
          bed ? [x, z + d] : [x, z]
        end
        line.map { |a, b, mat| [move.call(a), move.call(b), mat] }
      end

      def beds(section)
        section['bands'].select { |b| b['type'] == 'water' }.map { |b| [b['x0_m'], b['x1_m'], -(b['freeboard_m'] + b['depth_m'])] }
      end

      # Balayage d'une ligne de coupe dont le lit est décalé dans les chambres.
      def sweep(builder, stations, ss, line, ax, locks, z0, beds, all: false)
        stations.each_cons(2).with_index do |(a, b), j|
          lock = lock_of_pair(locks, ss[j], ss[j + 1])
          la = lock ? shifted_all_or_beds(line, beds, shift(lock, ss[j], a.z, z0), all) : line
          lb = lock ? shifted_all_or_beds(line, beds, shift(lock, ss[j + 1], b.z, z0), all) : line
          la.each_index do |k|
            (xa, za), (xb, zb), mat = la[k]
            (xc, zc), (xd, zd), = lb[k]
            quad = [RoadRibbons.place(a, ax - xa, za), RoadRibbons.place(a, ax - xb, zb), RoadRibbons.place(b, ax - xd, zd), RoadRibbons.place(b, ax - xc, zc)]
            if RoadRibbons.planar?(quad)
              builder.add_face(quad, mat)
            else
              builder.add_face([quad[0], quad[1], quad[2]], mat)
              builder.add_face([quad[0], quad[2], quad[3]], mat)
            end
          end
        end
        builder
      end

      def shifted_all_or_beds(line, beds, d, all)
        all ? line.map { |(xa, za), (xb, zb), mat| [[xa, za + d], [xb, zb + d], mat] } : shifted(line, beds, d)
      end

      # Mur de chute : au bout haut de chaque chambre, du lit du bief haut au lit de la chambre.
      def chute_walls(builder, stations, ss, ax, locks, z0, beds)
        locks.each do |lock|
          s_high = lock.drop.negative? ? lock.c0 : lock.c1
          j = ss.index { |s| (s - s_high).abs < TOL }
          st = stations[j]
          d = shift(lock, s_high, st.z, z0)
          tangent = [st.normal[1], -st.normal[0]]
          toward = lock.drop.negative? ? 1.0 : -1.0
          beds.each do |x0, x1, zb|
            quad = [RoadRibbons.place(st, ax - x0, zb), RoadRibbons.place(st, ax - x1, zb), RoadRibbons.place(st, ax - x1, zb + d), RoadRibbons.place(st, ax - x0, zb + d)]
            n = RoadRibbons.cross(RoadRibbons.sub(quad[1], quad[0]), RoadRibbons.sub(quad[3], quad[0]))
            quad.reverse! if ((n[0] * tangent[0]) + (n[1] * tangent[1])) * toward < 0
            builder.add_face(quad, 'road/quay')
          end
        end
      end

      # Une porte à chaque bout de chambre : un battant droit (ADR-35) sur toute la largeur de l'eau, du lit
      # de la chambre au haut du quai plus 0,2 m.
      def gates(stations, ss, ax, locks, z0, section)
        waters = section['bands'].select { |b| b['type'] == 'water' }
        locks.each_with_index.flat_map do |lock, i|
          [lock.c0, lock.c1].each_with_index.flat_map do |s, k|
            st = stations[ss.index { |x| (x - s).abs < TOL }]
            tangent = [st.normal[1], -st.normal[0]]
            half = GATE_THICKNESS_M / 2
            ends = [-half, half].map do |t|
              RoadAxis::Station.new(point: [st.point[0] + (tangent[0] * t), st.point[1] + (tangent[1] * t)], normal: st.normal, vertex: -1, z: st.z)
            end
            waters.map do |w|
              bottom = (lock.low - z0) - st.z - (w['freeboard_m'] + w['depth_m'])
              u = (w['x1_m'] - w['x0_m']) / 2
              polygon = RoadItems.rect(-u, u, bottom, GATE_RISE_M)
              { 'id' => "gate/#{i}/#{k}/#{w['index']}", 'category' => 'linear', 'children' => [],
                'primitive' => RoadItems.extrude(ends, ax - ((w['x0_m'] + w['x1_m']) / 2), 0.0, polygon, 'road/item/wood') }
            end
          end
        end
      end
    end
  end
end
