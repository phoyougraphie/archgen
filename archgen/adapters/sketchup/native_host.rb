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

        def vector(x, y, z)
          ::Geom::Vector3d.new(x, y, z)
        end

        def face?(entity)
          entity.is_a?(::Sketchup::Face)
        end

        def edge?(entity)
          entity.is_a?(::Sketchup::Edge)
        end

        def component_instance?(entity)
          entity.is_a?(::Sketchup::ComponentInstance)
        end

        def group?(entity)
          entity.is_a?(::Sketchup::Group)
        end

        def identity
          ::Geom::Transformation.new
        end

        def transformation(matrix)
          ::Geom::Transformation.new(matrix)
        end

        def input_point
          ::Sketchup::InputPoint.new
        end

        def active_view
          ::Sketchup.active_model&.active_view
        end

        # Le point visé sur le plan horizontal d'altitude z, en pouces ; nil si le rayon ne le coupe pas.
        def plane_hit(view, x, y, z)
          ::Geom.intersect_line_plane(view.pickray(x, y), [::Geom::Point3d.new(0, 0, z), ::Geom::Vector3d.new(0, 0, 1)])
        end

        def bounding_box(points)
          ::Geom::BoundingBox.new.tap { |box| points.each { |point| box.add(point) } }
        end

        # Selon les unités du modèle, en mètres ; nil si le texte n'est pas une longueur.
        def parse_length_m(text)
          [text, text.tr(',', '.'), text.tr('.', ',')].uniq.each do |candidate|
            return candidate.to_l.to_f * 0.0254
          rescue ArgumentError
            next
          end
          nil
        end

        def format_length(inches)
          ::Sketchup.format_length(inches)
        end

        def vcb(label, value)
          ::Sketchup.vcb_label = label
          ::Sketchup.vcb_value = value
        end

        def beep
          ::UI.beep
        end

        def gl_line_loop
          ::GL_LINE_LOOP
        end

        def gl_line_strip
          ::GL_LINE_STRIP
        end

        def gl_lines
          ::GL_LINES
        end

        def status(text)
          ::Sketchup.status_text = text
        end

        def color(red, green, blue)
          ::Sketchup::Color.new(red, green, blue)
        end
      end
    end
  end
end
