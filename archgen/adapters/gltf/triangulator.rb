# frozen_string_literal: true

module Archgen
  module Adapters
    module Gltf
      # Triangulation par oreilles d'un polygone plan à une boucle (docs/DECOR_JEU_CONTRACT.md §1).
      # Les triangles gardent le sens des indices, donc la normale de la face ; une face de
      # n sommets donne n − 2 triangles, un sommet aligné donnant un triangle d'aire nulle.
      module Triangulator
        module_function

        AREA_EPS = 1e-12
        ALIGN_EPS = 1e-9

        # Rend des triplets d'indices dans `points`, ou nil pour une face dégénérée.
        def call(points)
          return nil if points.size < 3

          normal = newell(points)
          length = Math.sqrt(normal.sum { |c| c * c })
          return nil if length < AREA_EPS

          flat = project(points, normal)
          ears(flat)
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

        # Plan de l'axe dominant, orienté pour que la boucle tourne dans le sens direct.
        def project(points, normal)
          axis = (0..2).max_by { |i| normal[i].abs }
          u, v = [[1, 2], [2, 0], [0, 1]][axis]
          flip = normal[axis].negative?
          points.map { |p| flip ? [p[v], p[u]] : [p[u], p[v]] }
        end

        def ears(flat)
          remaining = (0...flat.size).to_a
          triangles = []
          while remaining.size > 3
            index = find_ear(flat, remaining, strict: true) || find_ear(flat, remaining, strict: false)
            return nil unless index

            count = remaining.size
            triangles << [remaining[(index - 1) % count], remaining[index], remaining[(index + 1) % count]]
            remaining.delete_at(index)
          end
          triangles << remaining
        end

        # Une oreille stricte est convexe et vide ; à défaut, un sommet aligné se retire.
        def find_ear(flat, remaining, strict:)
          count = remaining.size
          count.times.find do |i|
            a = flat[remaining[(i - 1) % count]]
            b = flat[remaining[i]]
            c = flat[remaining[(i + 1) % count]]
            turn = cross(a, b, c)
            if strict
              turn > ALIGN_EPS && empty?(flat, remaining, i, a, b, c)
            else
              turn.abs <= ALIGN_EPS
            end
          end
        end

        def empty?(flat, remaining, index, a, b, c)
          count = remaining.size
          others = remaining.each_index.reject { |j| [(index - 1) % count, index, (index + 1) % count].include?(j) }
          others.none? do |j|
            p = flat[remaining[j]]
            next false if [a, b, c].any? { |q| same?(p, q) }

            cross(a, b, p) > ALIGN_EPS && cross(b, c, p) > ALIGN_EPS && cross(c, a, p) > ALIGN_EPS
          end
        end

        def cross(a, b, c)
          ((b[0] - a[0]) * (c[1] - a[1])) - ((b[1] - a[1]) * (c[0] - a[0]))
        end

        def same?(p, q)
          (p[0] - q[0]).abs <= ALIGN_EPS && (p[1] - q[1]).abs <= ALIGN_EPS
        end
      end
    end
  end
end
