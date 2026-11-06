# frozen_string_literal: true

module Archgen
  module Geometry
    # Anneau CCW (0,0), (W,0), (W,D), (0,D) et repères des quatre façades.
    module FootprintSolver
      module_function

      def call(width_m:, depth_m:)
        w = Core::Quant.q(width_m)
        d = Core::Quant.q(depth_m)
        ring = [[0.0, 0.0], [w, 0.0], [w, d], [0.0, d]]
        Footprint.new(width_m: w, depth_m: d, ring: ring, facades: facades(ring, w, d))
      end

      # Parcelle d'angle : façade et arrière parallèles, murs latéraux suivant les onglets.
      def trapezoid(width_m:, depth_m:, delta_left_m:, delta_right_m:)
        w = Core::Quant.q(width_m)
        d = Core::Quant.q(depth_m)
        left = Core::Quant.q(delta_left_m)
        right = Core::Quant.q(delta_right_m)
        ring = [[0.0, 0.0], [w, 0.0], [Core::Quant.q(w - right), d], [left, d]]
        Footprint.new(width_m: w, depth_m: d, ring: ring, facades: mitred_facades(ring), delta_left_m: left, delta_right_m: right)
      end

      # Un mur dont les deux joints intérieurs se rejoindraient n'a plus de face intérieure.
      def inner_problems(footprint, thickness)
        footprint.facades.filter_map do |facade|
          length = facade.inner_end(thickness) - facade.inner_start(thickness)
          next if length >= Core::Quant::MIN_EDGE_M

          Core::Diagnostic.error('E_STREET_CORNER', '/structure/wall_m', reason: 'wall_too_short', id: facade.id, value: length.round(3))
        end
      end

      def mitred_facades(ring)
        sides = FACADE_ORDER.each_with_index.map do |id, i|
          a = ring[i]
          b = ring[(i + 1) % 4]
          length = Core::Quant.q(Math.hypot(b[0] - a[0], b[1] - a[1]))
          [id, a, [(b[0] - a[0]) / length, (b[1] - a[1]) / length], length]
        end
        sides.each_with_index.map do |(id, a, tangent, length), i|
          Facade.new(id: id, a: a, tangent: tangent, normal: [zero(tangent[1]), zero(-tangent[0])], length_m: length,
                     start_factor: turn_factor(sides[i - 1][2], tangent), end_factor: turn_factor(tangent, sides[(i + 1) % 4][2]))
        end
      end
      private_class_method :mitred_facades

      # Le joint suit la bissectrice : le recul vaut t × tan(virage / 2).
      def turn_factor(before, after)
        Math.tan(Math.atan2((before[0] * after[1]) - (before[1] * after[0]), (before[0] * after[0]) + (before[1] * after[1])) / 2.0)
      end
      private_class_method :turn_factor

      def facades(ring, width, depth)
        lengths = [width, depth, width, depth]
        FACADE_ORDER.each_with_index.map do |id, i|
          a = ring[i]
          b = ring[(i + 1) % 4]
          length = lengths[i]
          tangent = [(b[0] - a[0]) / length, (b[1] - a[1]) / length]
          # N = T × K, avec K = (0,0,1) : (Ty, −Tx).
          normal = [zero(tangent[1]), zero(-tangent[0])]
          Facade.new(id: id, a: a, tangent: tangent, normal: normal, length_m: length)
        end
      end
      private_class_method :facades

      def zero(value)
        value.zero? ? 0.0 : value
      end
      private_class_method :zero
    end
  end
end
