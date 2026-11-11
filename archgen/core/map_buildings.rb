# frozen_string_literal: true

module Archgen
  module Core
    # Bâtiments d'une carte → brouillons ARCHGEN placés (docs/CARTOGRAPHIE_CONTRACT.md §3, AG-127, D-41).
    # Chaque contour est remplacé par son rectangle orienté d'aire minimale s'il le remplit assez.
    # Repère d'un bâtiment : origine au coin gauche de la façade avant, X le long de la façade,
    # Y vers l'intérieur (la façade avant regarde −Y), comme le plan d'un bâtiment.
    module MapBuildings
      module_function

      MIN_FILL = 0.85
      MIN_SIDE_M = 4.0
      MAX_SIDE_M = Limits::MAX_FOOTPRINT_M
      LEVEL_HEIGHT_M = 3.0
      DEFAULT_LEVELS = 3
      MAX_BUILDINGS = 300
      FRONT_REACH_M = 30.0
      OVERLAP_RATIO = 0.01

      # map : MapReader ; roads : polylignes en mètres (voies importées) ; style : identifiant de profil.
      def call(map, style:, roads: [], mode: 'shell')
        skipped = Hash.new(0)
        placed = []
        # Au-delà de 300, on garde les plus proches du centre de la carte (ADR-58) ; le reste est compté.
        ordered = map['buildings'].sort_by { |b| [centre_distance(b['ring_m']), b['id']] }
        ordered.each do |building|
          if placed.size >= MAX_BUILDINGS
            skipped['too_many'] += 1
            next
          end

          rect = oriented_rectangle(building['ring_m'])
          next skipped['degenerate'] += 1 unless rect
          next skipped['not_rectangular'] += 1 if rect[:fill] < MIN_FILL

          sides = [rect[:width], rect[:height]]
          next skipped['size'] += 1 unless sides.all? { |s| s.between?(MIN_SIDE_M, MAX_SIDE_M) }

          levels = levels_of(building['tags'])
          next skipped['levels'] += 1 unless levels.between?(1, Limits::MAX_LEVELS)

          corners = rect[:corners]
          next skipped['overlap'] += 1 if placed.any? { |other| overlap?(corners, other[:corners]) }

          placed << { building: building, corners: corners, levels: levels }
        end
        out = placed.map { |p| entry(p, style, mode, roads) }
        Result.ok({ 'buildings' => out, 'skipped' => skipped.sort.to_h })
      end

      def centre_distance(ring)
        x = ring.sum(&:first) / ring.size
        y = ring.sum(&:last) / ring.size
        Math.hypot(x, y)
      end

      def levels_of(tags)
        levels = Integer(tags['building:levels'].to_s, exception: false)
        return levels if levels

        height = Float(tags['height'].to_s.sub(/\s*m\z/, ''), exception: false)
        height ? [(height / LEVEL_HEIGHT_M).round, 1].max : DEFAULT_LEVELS
      end

      # Rectangle d'aire minimale parmi les directions d'arête : coins en sens direct, côtés, remplissage.
      def oriented_rectangle(ring)
        area = polygon_area(ring).abs
        return nil if ring.size < 3 || area < 1e-6

        best = nil
        ring.each_with_index do |a, i|
          b = ring[(i + 1) % ring.size]
          len = Math.hypot(b[0] - a[0], b[1] - a[1])
          next if len < 1e-9

          u = [(b[0] - a[0]) / len, (b[1] - a[1]) / len]
          v = [-u[1], u[0]]
          us = ring.map { |p| (p[0] * u[0]) + (p[1] * u[1]) }
          vs = ring.map { |p| (p[0] * v[0]) + (p[1] * v[1]) }
          box = (us.max - us.min) * (vs.max - vs.min)
          next if best && box >= best[:box] - 1e-9

          best = { box: box, u: u, v: v, u0: us.min, u1: us.max, v0: vs.min, v1: vs.max }
        end
        corner = ->(s, t) { [(best[:u][0] * s) + (best[:v][0] * t), (best[:u][1] * s) + (best[:v][1] * t)] }
        corners = [corner[best[:u0], best[:v0]], corner[best[:u1], best[:v0]], corner[best[:u1], best[:v1]], corner[best[:u0], best[:v1]]]
        { corners: corners, width: best[:u1] - best[:u0], height: best[:v1] - best[:v0], fill: area / best[:box] }
      end

      def polygon_area(ring)
        ring.each_with_index.sum { |p, i| q = ring[(i + 1) % ring.size]; (p[0] * q[1]) - (q[0] * p[1]) } / 2.0
      end

      # Façade avant : le côté dont le milieu est le plus proche d'une voie (à 30 m au plus),
      # sinon le côté le plus long ; à égalité, le premier côté.
      def entry(placed, style, mode, roads)
        corners = placed[:corners]
        sides = (0...4).map { |i| [corners[i], corners[(i + 1) % 4]] }
        front = front_side(sides, roads)
        a, b = sides[front]
        width = Math.hypot(b[0] - a[0], b[1] - a[1])
        depth = Math.hypot(corners[(front + 2) % 4][0] - b[0], corners[(front + 2) % 4][1] - b[1])
        # Coins en sens direct : de a vers b, l'intérieur est à gauche, donc +Y local.
        x_axis = [(b[0] - a[0]) / width, (b[1] - a[1]) / width]
        building = placed[:building]
        seed = Canonical.digest(building['id'])[0, 8].to_i(16)
        draft = { 'schema_version' => 1, 'name' => name_of(building), 'profile' => { 'id' => style }, 'mode' => mode,
                  'seed' => seed, 'footprint' => { 'width_m' => Quant.q(width), 'depth_m' => Quant.q(depth) },
                  'levels' => { 'count' => placed[:levels] } }
        { 'id' => building['id'], 'draft' => draft, 'origin_m' => a.map { |c| Quant.q(c) },
          'x_axis' => x_axis.map { |c| Quant.q(c) }, 'front' => front }
      end

      def front_side(sides, roads)
        scored = sides.each_with_index.map do |(a, b), i|
          mid = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2]
          [road_distance(mid, roads), i]
        end
        near = scored.select { |d, _| d && d <= FRONT_REACH_M }.min
        return near[1] if near

        sides.each_with_index.max_by { |(a, b), i| [Quant.q(Math.hypot(b[0] - a[0], b[1] - a[1])), -i] }[1]
      end

      def road_distance(point, roads)
        roads.flat_map { |line| line.each_cons(2).map { |a, b| MapRoads.segment_distance(point, a, b) } }.min
      end

      def name_of(building)
        label = building['tags']['name'].to_s.strip
        (label.empty? ? "OSM #{building['id']}" : label)[0, 60]
      end

      # Deux rectangles se chevauchent si leur intersection dépasse 1 % du plus petit.
      def overlap?(a, b)
        inter = clip(a, b)
        return false if inter.size < 3

        polygon_area(inter).abs > OVERLAP_RATIO * [polygon_area(a).abs, polygon_area(b).abs].min
      end

      # Sutherland-Hodgman : polygone a découpé par le convexe b (sens direct).
      def clip(subject, clipper)
        output = subject
        clipper.each_with_index do |c1, i|
          c2 = clipper[(i + 1) % clipper.size]
          input = output
          output = []
          break if input.empty?

          input.each_with_index do |p, j|
            q = input[(j + 1) % input.size]
            pin = cross(c1, c2, p) >= 0
            qin = cross(c1, c2, q) >= 0
            output << p if pin
            output << intersection(p, q, c1, c2) if pin != qin
          end
        end
        output
      end

      def cross(a, b, p) = ((b[0] - a[0]) * (p[1] - a[1])) - ((b[1] - a[1]) * (p[0] - a[0]))

      def intersection(p, q, a, b)
        d1 = cross(a, b, p)
        d2 = cross(a, b, q)
        t = d1 / (d1 - d2)
        [p[0] + ((q[0] - p[0]) * t), p[1] + ((q[1] - p[1]) * t)]
      end
    end
  end
end
