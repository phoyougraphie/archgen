# frozen_string_literal: true

module Archgen
  module Geometry
    # Formes 3D simples des objets de voirie (ADR-35) : volumes fermés à facettes, couleurs unies,
    # mêmes proportions que la coupe de l'éditeur. Repère local : origine au pied, X le long de la
    # voie, Y vers la chaussée la plus proche (côté d'une crosse), Z vers le haut.
    module RoadItemShapes
      SIDES = 8
      PARTS = %w[trunk crown steel lamp hedge wood concrete].freeze

      module_function

      def material(part)
        "road/item/#{part}"
      end

      # Une définition : liste de nœuds « part », chacun un solide fermé.
      def definition(kind, variant, height, crown: nil)
        solids = case kind
                 when 'tree' then tree(variant, height, crown)
                 when 'lamp' then lamp(variant, height)
                 when 'bollard' then [lathe([[0, 0], [0.05, 0], [0.05, height], [0, height]], 'steel')]
                 when 'pole' then catenary_pole(height)
                 when 'post' then [box(-crown / 2, crown / 2, -crown / 2, crown / 2, 0, height, variant)]
                 # Traverse : 2,60 m en travers, 0,25 m le long, 0,15 m d'épaisseur dont 2 cm hors du ballast.
                 when 'sleeper' then [box(-0.125, 0.125, -1.3, 1.3, -height + 0.02, 0.02, variant)]
                 else raise ArgumentError, "Objet sans forme : #{kind}"
                 end
        solids.each_with_index.map do |primitive, i|
          { 'id' => "part/#{i}", 'category' => 'part', 'children' => [], 'primitive' => primitive }
        end
      end

      # crown : { 'radius' => r, 'base' => hauteur du bas de la couronne }.
      def tree(variant, h, crown)
        r = crown.fetch('radius')
        base = crown.fetch('base')
        trunk_r = [0.012 * h, 0.06].max
        trunk_top = base + (0.3 * (h - base))
        trunk = lathe([[0, 0], [trunk_r, 0], [trunk_r, trunk_top], [0, trunk_top]], 'trunk', sides: 6)
        crown_solid = if variant == 'conifer'
                        lathe([[0, base], [r, base], [0, h]], 'crown')
                      else
                        center = (base + h) / 2
                        half = (h - base) / 2
                        ring = [-90, -45, 0, 45, 90].map { |deg| [r * Math.cos(deg * Math::PI / 180), center + (half * Math.sin(deg * Math::PI / 180))] }
                        ring[0][0] = 0
                        ring[-1][0] = 0
                        lathe(ring, 'crown')
                      end
        [trunk, crown_solid]
      end

      def lamp(variant, h)
        case variant
        when 'single', 'double'
          arms = variant == 'double' ? [1, -1] : [1]
          [pole(0.06, h)] + arms.flat_map do |s|
            [box(-0.04, 0.04, *[0.0, 1.5 * s].minmax, h - 0.08, h, 'steel'),
             box(-0.15, 0.15, *[1.25 * s, 1.75 * s].minmax, h - 0.2, h - 0.08, 'lamp')]
          end
        when 'ped'
          sphere = [-90, -45, 0, 45, 90].map { |deg| [0.18 * Math.cos(deg * Math::PI / 180), h - 0.18 + (0.18 * Math.sin(deg * Math::PI / 180))] }
          sphere[0][0] = 0
          sphere[-1][0] = 0
          [pole(0.05, h - 0.34), lathe(sphere, 'lamp')]
        when 'heritage'
          [pole(0.06, h - 0.55), lathe([[0, h - 0.55], [0.22, h - 0.55], [0.3, h], [0, h]], 'lamp', sides: 4)]
        else
          [pole(0.15, h - 0.25), box(-0.9, 0.9, -0.9, 0.9, h - 0.25, h, 'lamp')]
        end
      end

      def catenary_pole(h)
        [pole(0.1, h), box(-0.05, 0.05, 0.0, 2.6, h - 0.45, h - 0.35, 'steel')]
      end

      def pole(radius, top)
        lathe([[0, 0], [radius, 0], [radius, top], [0, top]], 'steel', sides: 6)
      end

      # Solide de révolution autour de Z : profil [[rayon, z], …] du bas vers le haut, rayon nul aux pôles.
      def lathe(profile, part, sides: SIDES)
        builder = MeshBuilder.new('solid')
        rings = profile.map do |r, z|
          (0...sides).map { |k| a = 2 * Math::PI * (k + 0.5) / sides; [r * Math.cos(a), r * Math.sin(a), z.to_f] }
        end
        profile.each_cons(2).with_index do |((ra, _), (rb, _)), i|
          (0...sides).each do |k|
            n = (k + 1) % sides
            a0, a1, b1, b0 = rings[i][k], rings[i][n], rings[i + 1][n], rings[i + 1][k]
            face = if ra.zero? then [a0, b1, b0]
                   elsif rb.zero? then [a0, a1, b0]
                   else [a0, a1, b1, b0]
                   end
            builder.add_face(face, material(part))
          end
        end
        builder.to_primitive
      end

      def box(x0, x1, y0, y1, z0, z1, part)
        c = ->(x, y, z) { [x.to_f, y.to_f, z.to_f] }
        faces = [
          [c[x0, y0, z0], c[x0, y1, z0], c[x1, y1, z0], c[x1, y0, z0]],
          [c[x0, y0, z1], c[x1, y0, z1], c[x1, y1, z1], c[x0, y1, z1]],
          [c[x0, y0, z0], c[x1, y0, z0], c[x1, y0, z1], c[x0, y0, z1]],
          [c[x1, y1, z0], c[x0, y1, z0], c[x0, y1, z1], c[x1, y1, z1]],
          [c[x0, y1, z0], c[x0, y0, z0], c[x0, y0, z1], c[x0, y1, z1]],
          [c[x1, y0, z0], c[x1, y1, z0], c[x1, y1, z1], c[x1, y0, z1]]
        ]
        builder = MeshBuilder.new('solid')
        faces.each { |f| builder.add_face(f, material(part)) }
        builder.to_primitive
      end
    end
  end
end
