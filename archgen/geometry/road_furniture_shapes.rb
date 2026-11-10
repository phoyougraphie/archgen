# frozen_string_literal: true

module Archgen
  module Geometry
    # Formes du mobilier urbain (docs/MOBILIER_CONTRACT.md §1, AG-120, D-35 à D-37) : solides fermés,
    # couleurs unies. Même repère que RoadItemShapes : pied à l'origine, X le long de la voie,
    # Y vers la chaussée la plus proche, Z vers le haut.
    module RoadFurnitureShapes
      module_function

      S = RoadItemShapes
      HOOP_PITCH_M = 0.8
      HOOP_HALF_M = 0.4
      BAR_M = 0.05
      PLATE_M = 0.7
      PLATE_BORDER_M = 0.05
      PLATE_THICK_M = 0.02
      MAST_RADIUS_M = 0.03
      SHELTER_LENGTH_M = 3.0
      SHELTER_DEPTH_M = 1.4
      STOP_MAST_M = 2.6

      # Banc de 1,8 m : il tourne le dos à la chaussée, dossier côté +Y.
      def bench(h)
        [S.box(-0.9, 0.9, -0.2, 0.2, 0.42, 0.47, 'wood'), S.box(-0.9, 0.9, 0.16, 0.2, 0.5, h, 'wood'),
         S.box(-0.83, -0.77, -0.2, 0.2, 0, 0.42, 'steel'), S.box(0.77, 0.83, -0.2, 0.2, 0, 0.42, 'steel')]
      end

      def bin(h)
        [S.lathe([[0, 0], [0.25, 0], [0.25, h], [0, h]], 'steel')]
      end

      # Arceaux en U renversé dans le plan YZ, espacés de 0,80 m le long de la voie, groupe centré.
      def bike_rack(h, count)
        (0...count).flat_map do |k|
          x = (k - ((count - 1) / 2.0)) * HOOP_PITCH_M
          a = x - (BAR_M / 2)
          b = x + (BAR_M / 2)
          [S.box(a, b, -HOOP_HALF_M, -HOOP_HALF_M + BAR_M, 0, h, 'steel'),
           S.box(a, b, HOOP_HALF_M - BAR_M, HOOP_HALF_M, 0, h, 'steel'),
           S.box(a, b, -HOOP_HALF_M + BAR_M, HOOP_HALF_M - BAR_M, h - BAR_M, h, 'steel')]
        end
      end

      # Abri (D-35) ouvert vers +Y : fond et joues vitrés, toit, poteaux, banc ; mât et plaque à côté.
      def bus_stop(variant, h)
        return stop_mast(0.0, 0.0) if variant == 'pole'

        x = SHELTER_LENGTH_M / 2
        y = SHELTER_DEPTH_M / 2
        posts = [-x, x].product([-y, y]).map { |px, py| S.box(px - 0.03, px + 0.03, py - 0.03, py + 0.03, 0, h - 0.1, 'steel') }
        glass = [S.box(-x + 0.03, x - 0.03, -y - 0.01, -y + 0.01, 0.1, h - 0.15, 'glass'),
                 S.box(-x - 0.01, -x + 0.01, -y + 0.03, 0.3, 0.1, h - 0.15, 'glass'),
                 S.box(x - 0.01, x + 0.01, -y + 0.03, 0.3, 0.1, h - 0.15, 'glass')]
        roof = [S.box(-x - 0.05, x + 0.05, -y - 0.05, y + 0.05, h - 0.1, h, 'steel')]
        seat = [S.box(-1.0, 1.0, -y + 0.05, -y + 0.35, 0.42, 0.47, 'wood')]
        posts + glass + roof + seat + stop_mast(x + 0.3, y - 0.1)
      end

      def stop_mast(x, y)
        [S.lathe([[0, 0], [0.04, 0], [0.04, STOP_MAST_M], [0, STOP_MAST_M]], 'steel', sides: 6).then { |p| shift(p, x, y) },
         S.box(x - 0.06, x - 0.04, y - 0.2, y + 0.2, STOP_MAST_M - 0.4, STOP_MAST_M, 'blue')]
      end

      # Plaques sans texte (D-36) : [côtés, rotation en degrés, rayon, fond, liseré, symbole].
      SIGNS = {
        'stop' => [8, 22.5, 0.35 / Math.cos(Math::PI / 8), 'red', 'white', nil],
        'give_way' => [3, -90, 0.8 / Math.sqrt(3), 'white', 'red', nil],
        'prohibition' => [16, 0, 0.35, 'red', 'red', :bar],
        'limit' => [16, 0, 0.35, 'white', 'red', nil],
        'mandatory' => [16, 0, 0.35, 'blue', 'white', nil],
        'information' => [4, 45, 0.35 * Math.sqrt(2), 'blue', 'white', nil],
        'danger' => [3, 90, 0.8 / Math.sqrt(3), 'white', 'red', nil],
        'crossing' => [4, 45, 0.35 * Math.sqrt(2), 'blue', 'white', :triangle]
      }.freeze

      # Mât de rayon 0,03 m ; plaque face à −X (ceux qui arrivent), son haut à `h`.
      def sign(variant, h)
        sides, turn, radius, fill, border, symbol = SIGNS.fetch(variant)
        outer = polygon(sides, turn, radius)
        top = outer.map(&:last).max
        lift = ->(points) { points.map { |y, z| [y, z + h - top] } }
        inner = polygon(sides, turn, radius - (PLATE_BORDER_M / Math.cos(Math::PI / sides)))
        front = -MAST_RADIUS_M
        solids = [S.lathe([[0, 0], [MAST_RADIUS_M, 0], [MAST_RADIUS_M, h - 0.05], [0, h - 0.05]], 'steel', sides: 6),
                  prism(lift.call(outer), front - PLATE_THICK_M, front, border),
                  prism(lift.call(inner), front - PLATE_THICK_M - 0.005, front - PLATE_THICK_M, fill)]
        centre = h - top
        case symbol
        when :bar then solids << prism([[-0.22, centre - 0.06], [0.22, centre - 0.06], [0.22, centre + 0.06], [-0.22, centre + 0.06]], front - 0.03, front - 0.025, 'white')
        when :triangle then solids << prism(polygon(3, 90, 0.2).map { |y, z| [y, z + centre] }, front - 0.03, front - 0.025, 'white')
        end
        solids
      end

      # Polygone régulier (y, z) centré à l'origine, sens direct vu depuis −X.
      def polygon(sides, turn_deg, radius)
        (0...sides).map do |k|
          a = ((turn_deg * Math::PI) / 180) + (2 * Math::PI * k / sides)
          [-radius * Math.cos(a), radius * Math.sin(a)]
        end
      end

      # Prisme d'un polygone (y, z) entre x0 et x1, fermé et orienté vers l'extérieur.
      def prism(points, x0, x1, part)
        builder = MeshBuilder.new('solid')
        near = points.map { |y, z| [x0.to_f, y.to_f, z.to_f] }
        far = points.map { |y, z| [x1.to_f, y.to_f, z.to_f] }
        builder.add_face(near, S.material(part))
        builder.add_face(far.reverse, S.material(part))
        points.size.times do |i|
          j = (i + 1) % points.size
          builder.add_face([near[j], near[i], far[i], far[j]], S.material(part))
        end
        primitive = builder.to_primitive
        S.normal_out?(primitive) ? primitive : S.flip(primitive)
      end

      def shift(primitive, x, y)
        primitive.merge('vertices' => primitive['vertices'].map { |v| [v[0] + x, v[1] + y, v[2]] })
      end
    end
  end
end
