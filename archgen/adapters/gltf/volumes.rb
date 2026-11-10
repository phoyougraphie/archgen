# frozen_string_literal: true

module Archgen
  module Adapters
    module Gltf
      # Enveloppe convexe 3D incrémentale : rend des triangles orientés vers l'extérieur.
      module ConvexHull
        module_function

        EPS = 1e-7

        # `points` : sommets en mètres. Rend des triplets de points, ou nil si tout est plan.
        def call(points)
          pts = points.map { |p| p.map { |c| c.round(4) + 0.0 } }.uniq.sort
          simplex = initial(pts)
          return nil unless simplex

          faces = tetrahedron(pts, simplex)
          # Les plus lointains d'abord : un point posé sur une face déjà tracée n'ajoute pas de sommet.
          center = simplex.map { |i| pts[i] }.transpose.map { |c| c.sum / 4.0 }
          rest = (pts.each_index.to_a - simplex).sort_by { |i| [-dist2(pts[i], center), i] }
          rest.each { |i| add_point(pts, faces, i) }
          faces.map { |face| face.map { |i| pts[i] } }
        end

        def initial(pts)
          return nil if pts.size < 4

          a = 0
          b = pts.each_index.max_by { |i| dist2(pts[i], pts[a]) }
          c = pts.each_index.max_by { |i| norm2(cross(sub(pts[b], pts[a]), sub(pts[i], pts[a]))) }
          normal = cross(sub(pts[b], pts[a]), sub(pts[c], pts[a]))
          return nil if norm2(normal) < EPS

          d = pts.each_index.max_by { |i| dot(normal, sub(pts[i], pts[a])).abs }
          return nil if dot(normal, sub(pts[d], pts[a])).abs / Math.sqrt(norm2(normal)) < EPS

          [a, b, c, d]
        end

        def tetrahedron(pts, simplex)
          center = simplex.map { |i| pts[i] }.transpose.map { |c| c.sum / 4.0 }
          simplex.combination(3).map do |face|
            facing?(pts, face, center) ? face.reverse : face
          end
        end

        def facing?(pts, face, point)
          height(pts, face, point) > 0
        end

        def height(pts, face, point)
          a, b, c = face.map { |i| pts[i] }
          normal = cross(sub(b, a), sub(c, a))
          length = Math.sqrt(norm2(normal))
          return 0.0 if length < EPS * EPS

          dot(normal, sub(point, a)) / length
        end

        def add_point(pts, faces, index)
          visible = faces.select { |face| height(pts, face, pts[index]) > EPS }
          return if visible.empty?

          edges = visible.flat_map { |f| [[f[0], f[1]], [f[1], f[2]], [f[2], f[0]]] }
          lookup = edges.to_h { |e| [e, true] }
          horizon = edges.reject { |(u, v)| lookup[[v, u]] }
          faces.reject! { |face| visible.include?(face) }
          horizon.each { |(u, v)| faces << [u, v, index] }
        end

        def sub(a, b) = [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
        def dot(a, b) = (a[0] * b[0]) + (a[1] * b[1]) + (a[2] * b[2])
        def norm2(a) = dot(a, a)
        def dist2(a, b) = norm2(sub(a, b))

        def cross(a, b)
          [(a[1] * b[2]) - (a[2] * b[1]), (a[2] * b[0]) - (a[0] * b[2]), (a[0] * b[1]) - (a[1] * b[0])]
        end
      end

      # Volume simple d'un bâtiment (LOD2 et collision, docs/DECOR_JEU_CONTRACT.md §3) :
      # l'enveloppe convexe des murs et du toit ; détails, balcons et cheminées exclus.
      module Volumes
        module_function

        SOURCES = %w[walls roof].freeze

        # Rend { 'triangles' => [[p, p, p], ...], 'wall' => matière, 'roof' => matière, 'wall_top' => z } ou nil.
        def call(plan)
          root = plan['nodes'].first
          parts = (root['children'] || []).select { |node| SOURCES.include?(node['category']) }
          points = []
          materials = {}
          parts.each { |part| collect(part, points, materials) }
          triangles = ConvexHull.call(points)
          return nil unless triangles

          { 'triangles' => triangles, 'wall' => materials['walls'], 'roof' => materials['roof'] || materials['walls'],
            'wall_top' => plan.dig('metrics', 'wall_top_z_m') }
        end

        def collect(node, points, materials, source = node['category'])
          primitive = node['primitive']
          if primitive && primitive['type'] != 'instance'
            points.concat(primitive['vertices'])
            materials[source] ||= primitive['faces'].first&.fetch('material', nil)
          end
          (node['children'] || []).each { |child| collect(child, points, materials, source) }
        end
      end
    end
  end
end
