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
