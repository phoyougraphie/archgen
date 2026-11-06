# frozen_string_literal: true

module Archgen
  module Geometry
    # Toit d'un bâtiment de rangée : une section constante dans le plan (y, z), balayée entre
    # les deux murs latéraux. Aucun débord latéral : deux voisines se rejoignent exactement
    # (docs/ENSEMBLE_CONTRACT.md, Bâtiment de rangée). La croupe est refusée en amont.
    module RowRoofSolver
      module_function

      def call(footprint, wall_top_z, roof, materials:)
        problem = eave_problem(wall_top_z, roof)
        return Core::Result.fail([problem]) if problem

        section, ends = shapes(footprint.depth_m, wall_top_z, roof)
        faces = pans(section, footprint.width_m) + gables(ends, footprint.width_m)
        nodes = faces.map { |id, category, points| node(id, category, points, materials) }
        top = section.map { |_, z| Core::Quant.q(z) }.max
        Core::Result.ok(RoofPlan.new(nodes: [Node.group('roof', 'roof', nodes)], top_z_m: top))
      end

      def eave_problem(top, roof)
        pitch = roof['type'] == 'mansard' ? roof['lower_pitch_deg'] : roof['pitch_deg']
        return nil if top - (RoofSolver.slope(pitch) * roof['overhang_m']) >= -Core::Quant::EPSILON

        Core::Diagnostic.error('E_ROOF_GEOMETRY', '/roof/overhang_m', reason: 'eave_below_ground')
      end
      private_class_method :eave_problem

      # Section [[nom, y, z]...] de l'avant vers l'arrière, et polygones de pignon dans le plan (y, z).
      def shapes(depth, h, roof)
        case roof['type']
        when 'flat' then flat(depth, h, roof)
        when 'gable' then gable(depth, h, roof)
        when 'mansard' then mansard(depth, h, roof)
        else raise ArgumentError, "Toit de rangée inconnu : #{roof['type']}"
        end
      end
      private_class_method :shapes

      def flat(depth, h, roof)
        e = roof['overhang_m']
        [[[-e, h], [depth + e, h]], []]
      end
      private_class_method :flat

      def gable(depth, h, roof)
        e = roof['overhang_m']
        r = RoofSolver.slope(roof['pitch_deg'])
        ridge = depth / 2.0
        top = h + (r * ridge)
        eave = h - (r * e)
        [[[-e, eave], [ridge, top], [depth + e, eave]], [[[0.0, h], [depth, h], [ridge, top]]]]
      end
      private_class_method :gable

      def mansard(depth, h, roof)
        e = roof['overhang_m']
        inset = roof['inset_m']
        low = RoofSolver.slope(roof['lower_pitch_deg'])
        ring = h + (low * inset)
        ridge = depth / 2.0
        top = ring + (RoofSolver.slope(roof['pitch_deg']) * (ridge - inset))
        eave = h - (low * e)
        section = [[-e, eave], [inset, ring], [ridge, top], [depth - inset, ring], [depth + e, eave]]
        ends = [[[0.0, h], [depth, h], [depth - inset, ring], [inset, ring]], [[inset, ring], [depth - inset, ring], [ridge, top]]]
        [section, ends]
      end
      private_class_method :mansard

      # Sommets en sens antihoraire vu du dessus : y croît le long de la section, donc la
      # normale reste vers le haut sur les pans avant comme arrière.
      def pans(section, width)
        section.each_cons(2).with_index.map do |((y0, z0), (y1, z1)), index|
          ["roof/pan/#{index}", 'roof_face', [[0.0, y0, z0], [width, y0, z0], [width, y1, z1], [0.0, y1, z1]]]
        end
      end
      private_class_method :pans

      def gables(ends, width)
        ends.each_with_index.flat_map do |polygon, index|
          right = polygon.map { |y, z| [width, y, z] }
          left = polygon.reverse.map { |y, z| [0.0, y, z] }
          [["roof/gable/right/#{index}", 'gable_end', right], ["roof/gable/left/#{index}", 'gable_end', left]]
        end
      end
      private_class_method :gables

      def node(id, category, points, materials)
        material = category == 'gable_end' ? materials['wall'] : materials['roof']
        Node.leaf(id, category, MeshBuilder.new('surface').add_face(points, material).to_primitive)
      end
      private_class_method :node
    end
  end
end
