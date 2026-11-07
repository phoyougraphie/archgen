# frozen_string_literal: true

module Archgen
  module Geometry
    # Carrefour à feux (AG-044, docs/VOIRIE_CONTRACT.md, Carrefours) : sur chaque branche à chaussée,
    # au-delà de la coupe du carrefour simple, un passage piéton s'il y a un trottoir ou un chemin,
    # une ligne d'arrêt sur les voies qui entrent, et un feu à droite de ceux qui arrivent.
    # Circulation à droite. Le marquage est taillé dans la surface : aucune face superposée.
    module RoadSignals
      CROSSING_M = 4.0
      GAP_M = 1.0
      STOP_M = 0.5
      STRIPE_M = 0.5
      STRIPE_STEP_M = 1.0
      STRIPE_EDGE_M = 0.25
      SIGNAL_HEIGHT_M = 3.0
      SIGNAL_SETBACK_M = 0.5
      MIN_FOOTING_M = 0.3
      MARKING = 'road/marking'
      J = RoadJunction

      module_function

      def carriageway?(arm)
        arm.carriageway
      end

      def crossing?(arm)
        arm.road.section['bands'].any? { |b| b['role'] == 'pedestrian' }
      end

      # Longueur ajoutée à la coupe d'une branche : passage, garde, ligne d'arrêt.
      def extension(arm)
        return 0.0 unless carriageway?(arm)

        (crossing?(arm) ? CROSSING_M : 0.0) + GAP_M + STOP_M
      end

      # Intervalles x de chaussée roulante (stationnement exclu), de gauche à droite.
      def lanes(arm)
        arm.road.section['bands'].select { |b| b['role'] == 'carriageway' && b['type'] != 'parking' }.map { |b| [b['x0_m'], b['x1_m']] }
      end

      def stripes(arm)
        lanes(arm).flat_map do |x0, x1|
          out = []
          x = x0 + STRIPE_EDGE_M
          while x + STRIPE_M <= x1 - STRIPE_EDGE_M + 1e-9
            out << [x, x + STRIPE_M]
            x += STRIPE_STEP_M
          end
          out
        end
      end

      # Voies de circulation qui entrent dans le carrefour : à gauche de la branche, au-delà du milieu
      # des voies de circulation (bandes dérasées, arrêt d'urgence et stationnement exclus).
      def incoming(arm)
        all = arm.road.section['bands'].select { |b| b['type'] == 'lane' }.map { |b| [b['x0_m'], b['x1_m']] }
        return [] if all.empty?

        mid = (all.map(&:first).min + all.map(&:last).max) / 2.0
        all.filter_map do |x0, x1|
          lo, hi = arm.sign.positive? ? [x0, [x1, mid].min] : [[x0, mid].max, x1]
          hi - lo > 1e-9 ? [lo, hi] : nil
        end
      end

      # Ligne de coupe dont les segments compris dans les intervalles prennent la matière du marquage.
      def marked(line, intervals)
        line.flat_map do |(xa, za), (xb, zb), mat|
          next [[[xa, za], [xb, zb], mat]] if (xa - xb).abs < 1e-12 || mat == 'road/curb'

          cuts = intervals.flatten.select { |x| x > xa + 1e-9 && x < xb - 1e-9 }.sort
          xs = [xa] + cuts + [xb]
          xs.each_cons(2).map do |p, q|
            zp = za + ((zb - za) * (p - xa) / (xb - xa))
            zq = za + ((zb - za) * (q - xa) / (xb - xa))
            mid = (p + q) / 2
            [[p, zp], [q, zq], intervals.any? { |lo, hi| mid > lo && mid < hi } ? MARKING : mat]
          end
        end
      end

      # Bandes balayées de la coupe à la coupe prolongée : [[points, matériau]].
      def faces(arm)
        return [] unless carriageway?(arm)

        line = arm.road.line
        start = arm.cut
        out = []
        if crossing?(arm)
          out.concat(sweep(arm, start, start + CROSSING_M, marked(line, stripes(arm))))
          start += CROSSING_M
        end
        out.concat(sweep(arm, start, start + GAP_M, line))
        out.concat(sweep(arm, start + GAP_M, start + GAP_M + STOP_M, marked(line, incoming(arm))))
        out
      end

      def sweep(arm, from, to, line)
        normal = arm.sign.positive? ? arm.left : [-arm.left[0], -arm.left[1]]
        at = ->(along) { RoadAxis::Station.new(point: J.point(arm, nil, along, 0), normal: normal, vertex: -1) }
        stations = arm.sign.positive? ? [at.call(from), at.call(to)] : [at.call(to), at.call(from)]
        builder = MeshBuilder.new('surface')
        RoadRibbons.sweep(builder, stations, line, arm.road.ax)
        prim = builder.to_primitive
        prim['faces'].map { |f| [f['indices'].map { |i| prim['vertices'][i] }, f['material']] }
      end

      # Feu à droite de la circulation qui arrive, sur la bande au-delà de la bordure, au droit de la
      # ligne d'arrêt, optiques tournées vers elle. nil si rien ne le porte.
      def light(arm, id)
        width = arm.outer_l - arm.kerb_l
        return nil if width < MIN_FOOTING_M

        u = arm.kerb_l + [SIGNAL_SETBACK_M, width / 2].min
        along = arm.cut + extension(arm) - (STOP_M / 2)
        point = J.point(arm, nil, along, u)
        definition = RoadItems.definition_id('signal', 'tricolor', SIGNAL_HEIGHT_M)
        RoadItems.instance(id, definition, point, arm.dir, level_at(arm, u), 'right')
      end

      def definition
        [RoadItems.definition_id('signal', 'tricolor', SIGNAL_HEIGHT_M), RoadItemShapes.definition('signal', 'tricolor', SIGNAL_HEIGHT_M)]
      end

      # Cote de la surface de la branche en u (plus haute si u tombe sur une contremarche).
      def level_at(arm, u)
        arm.points.each_cons(2).filter_map do |(ua, za), (ub, zb)|
          next unless u.between?([ua, ub].min - 1e-9, [ua, ub].max + 1e-9)

          (ua - ub).abs < 1e-12 ? [za, zb].max : za + ((zb - za) * (u - ua) / (ub - ua))
        end.max
      end
    end
  end
end
