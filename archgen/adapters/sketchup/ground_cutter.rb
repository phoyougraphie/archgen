# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      # Copie entaillée du terrain sous une voie (AG-049, ADR-38 ; docs/VOIRIE_CONTRACT.md, Terrain).
      # L'original est masqué, jamais modifié ; la copie, unique, est coupée le long du contour de
      # l'entaille et perd ses faces intérieures. À appeler dans une opération : une panne l'annule.
      class GroundCutter
        NAME = 'Terrain entaillé ARCHGEN'
        DICTIONARY = 'archgen.ground_copy'
        MARGIN_IN = 39.37

        # terrain : groupe ou composant de niveau racine ; outline_m : [[x, y]] en mètres du modèle.
        # Retourne la copie.
        def entaille(model, terrain, outline_m)
          copy = duplicate(model, terrain)
          terrain.hidden = true
          cut(model, copy, outline_m)
          copy
        end

        # Efface une copie précédente, retrouvée par son PID ; rien si elle n'existe plus.
        def remove(model, persistent_id)
          entity = persistent_id && model.find_entity_by_persistent_id(persistent_id)
          entity.erase! if entity&.valid? && entity.get_attribute(DICTIONARY, 'terrain_pid')
        end

        private

        def duplicate(model, terrain)
          copy = if terrain.is_a?(Sketchup::Group)
                   terrain.copy
                 else
                   model.entities.add_instance(terrain.definition, terrain.transformation)
                 end
          copy.make_unique
          copy.hidden = false
          copy.layer = terrain.layer
          copy.name = NAME
          copy.set_attribute(DICTIONARY, 'terrain_pid', terrain.persistent_id)
          copy
        end

        def entities_of(entity)
          entity.is_a?(Sketchup::Group) ? entity.entities : entity.definition.entities
        end

        # Faces verticales temporaires le long du contour, intersection, faces intérieures effacées.
        def cut(model, copy, outline_m)
          bounds = copy.bounds
          low = bounds.min.z - MARGIN_IN
          high = bounds.max.z + MARGIN_IN
          ring = outline_m.map { |x, y| [x.m, y.m] }
          temp = model.entities.add_group
          ring.each_index do |i|
            a = ring[i]
            b = ring[(i + 1) % ring.size]
            next if (a[0] - b[0]).abs + (a[1] - b[1]).abs < 0.01

            temp.entities.add_face([a[0], a[1], low], [b[0], b[1], low], [b[0], b[1], high], [a[0], a[1], high])
          end
          entities = entities_of(copy)
          transform = copy.transformation
          entities.intersect_with(false, transform, entities, transform, true, [temp])
          temp.erase!
          inside = entities.grep(Sketchup::Face).select do |face|
            vertices = face.outer_loop.vertices.map { |v| transform * v.position }
            x = vertices.sum(&:x) / vertices.size
            y = vertices.sum(&:y) / vertices.size
            inside?(x, y, ring)
          end
          entities.erase_entities(inside) unless inside.empty?
          loose = entities.grep(Sketchup::Edge).select { |edge| edge.faces.empty? }
          entities.erase_entities(loose) unless loose.empty?
        end

        def inside?(x, y, ring)
          inside = false
          j = ring.size - 1
          ring.each_with_index do |p, i|
            q = ring[j]
            inside = !inside if ((p[1] > y) != (q[1] > y)) && (x < (((q[0] - p[0]) * (y - p[1])) / (q[1] - p[1])) + p[0])
            j = i
          end
          inside
        end
      end
    end
  end
end
