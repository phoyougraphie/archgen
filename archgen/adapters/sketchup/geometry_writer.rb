# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      # Toute anomalie remonte au service, qui abandonne l'opération.
      WriteError = Class.new(StandardError)

      WriteStats = Struct.new(:face_count, :group_count, :hidden_edge_count, keyword_init: true)

      # Traduit un plan validé en géométrie native dans une collection vide. Ne crée ni
      # transaction ni racine. Les mètres ne sont convertis qu'ici, une seule fois.
      class GeometryWriter
        METERS_PER_INCH = 0.0254
        NORMAL_MIN_DOT = 0.0
        # Cosinus minimal entre normales pour traiter deux faces voisines comme coplanaires.
        COPLANAR_MIN_COS = 1.0 - 1e-9

        def initialize(host: NativeHost)
          @host = host
        end

        def write(plan, entities:, resources:)
          check_preconditions(plan, entities)
          stats = WriteStats.new(face_count: 0, group_count: 0, hidden_edge_count: 0)
          plan['nodes'].first['children'].each { |node| write_node(node, entities, resources, stats) }
          expected = plan['metrics']['expanded_face_count']
          raise WriteError, "Faces écrites #{stats.face_count}, attendues #{expected}" unless stats.face_count == expected

          stats
        end

        private

        def check_preconditions(plan, entities)
          raise WriteError, 'Unité de plan non prise en charge' unless plan['units'] == 'm'
          raise WriteError, 'Destination non vide' unless entities.length.zero?
          # Les définitions partagées arrivent avec les cadres, en AG-015.
          raise WriteError, 'Définitions de détail non prises en charge' unless plan['definitions'].empty?
        end

        # Une collection d'entités par pièce : les jonctions ne fusionnent pas.
        def write_node(node, parent, resources, stats)
          group = parent.add_group
          raise WriteError, "Groupe refusé : #{node['id']}" unless group

          stats.group_count += 1
          group.name = node['id']
          tag = resources.tag(node['category'])
          group.layer = tag if tag
          if node['primitive']
            stats.face_count += write_primitive(node, group.entities, resources)
            stats.hidden_edge_count += hide_grid_edges(group.entities)
          else
            node['children'].each { |child| write_node(child, group.entities, resources, stats) }
          end
        end

        def write_primitive(node, entities, resources)
          primitive = node['primitive']
          unless %w[surface solid].include?(primitive['type'])
            raise WriteError, "Primitive non prise en charge : #{primitive['type']}"
          end

          vertices = primitive['vertices']
          points = vertices.map { |v| to_point(v) }
          faces = build_faces(node, entities, primitive, points)
          faces.each_with_index { |face, i| finish_face(node, face, primitive['faces'][i], vertices, resources) }
          check_count(node, entities, primitive['faces'].size)
          faces.size
        end

        def to_point(vertex)
          @host.point(vertex[0] / METERS_PER_INCH, vertex[1] / METERS_PER_INCH, vertex[2] / METERS_PER_INCH)
        end

        # Rien d'autre ne touche la collection pendant le bloc : orientation et matériau après.
        def build_faces(node, entities, primitive, points)
          faces = []
          entities.build do |builder|
            primitive['faces'].each do |spec|
              face = builder.add_face(spec['indices'].map { |i| points[i] })
              raise WriteError, "Face refusée : #{node['id']}" unless face

              faces << face
            end
          end
          faces
        end

        def finish_face(node, face, spec, vertices, resources)
          expected = newell(spec['indices'].map { |i| vertices[i] })
          face.reverse! unless agrees?(face, expected)
          raise WriteError, "Orientation impossible : #{node['id']}" unless agrees?(face, expected)

          face.material = resources.material(spec['material'])
        end

        def agrees?(face, expected)
          normal = face.normal
          (normal.x * expected[0]) + (normal.y * expected[1]) + (normal.z * expected[2]) > NORMAL_MIN_DOT
        end

        # La grille de découpe reste dans la topologie mais ne se dessine pas (ADR-15) :
        # seules les arêtes entre deux faces coplanaires de même matériau sont masquées.
        def hide_grid_edges(entities)
          edges = entities.select { |entity| @host.edge?(entity) && grid_edge?(entity) }
          edges.each { |edge| edge.hidden = true }
          edges.size
        end

        def grid_edge?(edge)
          faces = edge.faces
          return false unless faces.size == 2

          faces[0].material == faces[1].material && same_direction?(faces[0].normal, faces[1].normal)
        end

        def same_direction?(a, b)
          dot = (a.x * b.x) + (a.y * b.y) + (a.z * b.z)
          lengths = Math.sqrt(((a.x * a.x) + (a.y * a.y) + (a.z * a.z)) * ((b.x * b.x) + (b.y * b.y) + (b.z * b.z)))
          dot / lengths >= COPLANAR_MIN_COS
        end

        def check_count(node, entities, expected)
          actual = entities.count { |entity| @host.face?(entity) }
          raise WriteError, "#{node['id']} : #{actual} faces, #{expected} attendues" unless actual == expected
        end

        def newell(points)
          total = [0.0, 0.0, 0.0]
          points.each_with_index do |p, i|
            q = points[(i + 1) % points.size]
            total[0] += (p[1] - q[1]) * (p[2] + q[2])
            total[1] += (p[2] - q[2]) * (p[0] + q[0])
            total[2] += (p[0] - q[0]) * (p[1] + q[1])
          end
          total
        end
      end
    end
  end
end
