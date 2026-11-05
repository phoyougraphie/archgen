# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      # Seul point de contact avec les classes natives de construction. Remplacé par
      # un double dans les tests Ruby ; les doubles ne valident pas le natif.
      module NativeHost
        module_function

        def point(x, y, z)
          ::Geom::Point3d.new(x, y, z)
        end

        def face?(entity)
          entity.is_a?(::Sketchup::Face)
        end

        def color(red, green, blue)
          ::Sketchup::Color.new(red, green, blue)
        end
      end
    end
  end
end
