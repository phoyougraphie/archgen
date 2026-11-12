# frozen_string_literal: true

module Archgen
  module Geometry
    # Calculs plans sur des points [x, y], sans état.
    module Planar
      module_function

      def sub(a, b)
        [a[0] - b[0], a[1] - b[1]]
      end

      def add(a, b)
        [a[0] + b[0], a[1] + b[1]]
      end

      def scale(a, factor)
        [a[0] * factor, a[1] * factor]
      end

      def dot(a, b)
        (a[0] * b[0]) + (a[1] * b[1])
      end

      def cross(a, b)
        (a[0] * b[1]) - (a[1] * b[0])
      end

      def length(a)
        Math.hypot(a[0], a[1])
      end

      def unit(a)
        scale(a, 1.0 / length(a))
      end

      # Normale à gauche d'une direction.
      def left(a)
        [-a[1], a[0]]
      end

      def signed_area(ring)
        ring.each_index.sum { |i| cross(ring[i], ring[(i + 1) % ring.size]) } / 2.0
      end

      def segment_point_distance(a, b, p)
        ab = sub(b, a)
        span = dot(ab, ab)
        return length(sub(p, a)) if span.zero?

        ratio = (dot(sub(p, a), ab) / span).clamp(0.0, 1.0)
        length(sub(p, add(a, scale(ab, ratio))))
      end

      def crossing?(a, b, c, d)
        first = [cross(sub(b, a), sub(c, a)), cross(sub(b, a), sub(d, a))]
        second = [cross(sub(d, c), sub(a, c)), cross(sub(d, c), sub(b, c))]
        first.min.negative? && first.max.positive? && second.min.negative? && second.max.positive?
      end

      def segment_distance(a, b, c, d)
        return 0.0 if crossing?(a, b, c, d)

        [segment_point_distance(a, b, c), segment_point_distance(a, b, d),
         segment_point_distance(c, d, a), segment_point_distance(c, d, b)].min
      end

      # Contour convexe antihoraire, bord compris.
      def inside_convex?(ring, point)
        ring.each_index.all? { |i| cross(sub(ring[(i + 1) % ring.size], ring[i]), sub(point, ring[i])) >= 0.0 }
      end

      # Distance entre deux contours convexes antihoraires : 0 s'ils se recouvrent.
      def convex_distance(first, second)
        return 0.0 if first.any? { |p| inside_convex?(second, p) } || second.any? { |p| inside_convex?(first, p) }

        edges(first).flat_map { |a, b| edges(second).map { |c, d| segment_distance(a, b, c, d) } }.min
      end

      def edges(ring)
        ring.each_index.map { |i| [ring[i], ring[(i + 1) % ring.size]] }
      end
    end
  end
end
