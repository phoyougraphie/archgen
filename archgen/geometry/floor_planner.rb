# frozen_string_literal: true

module Archgen
  module Geometry
    # Altitudes quantifiées des niveaux et bandes de dalle. Pas de dalle au RDC :
    # cette convention laisse l'entrée ouverte jusqu'à Z=0.
    module FloorPlanner
      module_function

      def call(levels, slab_m:)
        heights = levels['heights_m'].empty? ? Array.new(levels['count'], levels['height_m']) : levels['heights_m']
        base = 0.0
        heights.each_with_index.map do |height, index|
          bottom = Core::Quant.q(base)
          top = Core::Quant.q(base + height)
          base += height
          Level.new(index: index, base_z_m: bottom, top_z_m: top,
                    slab_bottom_z_m: index.zero? ? nil : Core::Quant.q(bottom - slab_m))
        end
      end
    end
  end
end
