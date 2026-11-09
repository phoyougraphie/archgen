# frozen_string_literal: true

module Archgen
  module Geometry
    RoofPlan = Struct.new(:nodes, :top_z_m, keyword_init: true)

    # Couverture en peau, identique dans les deux modes. Toutes les faces sont
    # écrites dans le sens antihoraire vu de l'extérieur.
    module RoofSolver
      SQUARE_TOLERANCE = Core::Quant::EPSILON

      module_function

      # Retourne Result<RoofPlan> ; rejette une rive sous Z=0 et une arête trop courte.
      # `side_overhang` : faux pour un bâtiment de rangée à faîtage perpendiculaire (AG-079).
      def call(footprint, wall_top_z, roof, materials:, side_overhang: true)
        problems = check(footprint, wall_top_z, roof)
        return Core::Result.fail(problems) unless problems.empty?

        pans = case roof['type']
               when 'flat' then flat(footprint, wall_top_z, roof)
               when 'gable'
                 roof['ridge'] == 'perpendicular' ? cross_gable(footprint, wall_top_z, roof, side_overhang) : gable(footprint, wall_top_z, roof)
               when 'hip' then hip_roof(footprint, wall_top_z, roof)
               when 'mansard' then mansard(footprint, wall_top_z, roof)
               else raise ArgumentError, "Type de toit inconnu : #{roof['type']}"
               end
        nodes = pans.map { |id, category, points| face_node(id, category, points, materials) }
        top = pans.flat_map { |_, _, points| points.map { |p| Core::Quant.q(p[2]) } }.max
        Core::Result.ok(RoofPlan.new(nodes: [Node.group('roof', 'roof', nodes)], top_z_m: top))
      end

      def slope(degrees)
        Math.tan(degrees * Math::PI / 180.0)
      end

      def check(footprint, top, roof)
        problems = []
        pitch = roof['type'] == 'mansard' ? roof['lower_pitch_deg'] : roof['pitch_deg']
        if top - (slope(pitch) * roof['overhang_m']) < -Core::Quant::EPSILON
          problems << Core::Diagnostic.error('E_ROOF_GEOMETRY', '/roof/overhang_m', reason: 'eave_below_ground')
        end
        difference = (footprint.width_m - footprint.depth_m).abs
        if %w[hip mansard].include?(roof['type']) && difference > SQUARE_TOLERANCE && difference < Core::Quant::MIN_EDGE_M
          problems << Core::Diagnostic.error('E_ROOF_GEOMETRY', '/footprint/width_m', reason: 'ridge_too_short', length: difference)
        end
        problems
      end
      private_class_method :check

      def face_node(id, category, points, materials)
        material = category == 'gable_end' ? materials['wall'] : materials['roof']
        Node.leaf(id, category, MeshBuilder.new('surface').add_face(points, material).to_primitive)
      end
      private_class_method :face_node

      def flat(footprint, h, roof)
        e = roof['overhang_m']
        w = footprint.width_m
        d = footprint.depth_m
        [['roof/top', 'roof_face', [[-e, -e, h], [w + e, -e, h], [w + e, d + e, h], [-e, d + e, h]]]]
      end
      private_class_method :flat

      def gable(footprint, h, roof)
        e = roof['overhang_m']
        r = slope(roof['pitch_deg'])
        w = footprint.width_m
        d = footprint.depth_m
        ridge_y = d / 2.0
        ridge_z = h + (r * ridge_y)
        eave_z = h - (r * e)
        [
          ['roof/front', 'roof_face', [[-e, -e, eave_z], [w + e, -e, eave_z], [w + e, ridge_y, ridge_z], [-e, ridge_y, ridge_z]]],
          ['roof/rear', 'roof_face', [[w + e, d + e, eave_z], [-e, d + e, eave_z], [-e, ridge_y, ridge_z], [w + e, ridge_y, ridge_z]]],
          ['roof/gable/right', 'gable_end', [[w, 0.0, h], [w, d, h], [w, ridge_y, ridge_z]]],
          ['roof/gable/left', 'gable_end', [[0.0, d, h], [0.0, 0.0, h], [0.0, ridge_y, ridge_z]]]
        ]
      end
      private_class_method :gable

      # AG-079 : faîtage au milieu de la largeur, de l'avant à l'arrière ; pignons sur les façades
      # avant et arrière. En rangée, pas de débord sur les murs latéraux.
      def cross_gable(footprint, h, roof, side_overhang)
        e = roof['overhang_m']
        s = side_overhang ? e : 0.0
        r = slope(roof['pitch_deg'])
        w = footprint.width_m
        d = footprint.depth_m
        ridge_x = w / 2.0
        ridge_z = h + (r * ridge_x)
        eave_z = h - (r * s)
        [
          ['roof/left', 'roof_face', [[-s, d + e, eave_z], [-s, -e, eave_z], [ridge_x, -e, ridge_z], [ridge_x, d + e, ridge_z]]],
          ['roof/right', 'roof_face', [[w + s, -e, eave_z], [w + s, d + e, eave_z], [ridge_x, d + e, ridge_z], [ridge_x, -e, ridge_z]]],
          ['roof/gable/front', 'gable_end', [[0.0, 0.0, h], [w, 0.0, h], [ridge_x, 0.0, ridge_z]]],
          ['roof/gable/rear', 'gable_end', [[w, d, h], [0.0, d, h], [ridge_x, d, ridge_z]]]
        ]
      end
      private_class_method :cross_gable

      def hip_roof(footprint, h, roof)
        hip_faces('roof', 0.0, 0.0, footprint.width_m, footprint.depth_m, h, slope(roof['pitch_deg']), roof['overhang_m'])
      end
      private_class_method :hip_roof

      # Pans inférieurs raides entre rive et anneau, couronnés par une croupe sans débord.
      def mansard(footprint, h, roof)
        e = roof['overhang_m']
        inset = roof['inset_m']
        low = slope(roof['lower_pitch_deg'])
        w = footprint.width_m
        d = footprint.depth_m
        eave_z = h - (low * e)
        ring_z = h + (low * inset)
        o = [[-e, -e, eave_z], [w + e, -e, eave_z], [w + e, d + e, eave_z], [-e, d + e, eave_z]]
        i = [[inset, inset, ring_z], [w - inset, inset, ring_z], [w - inset, d - inset, ring_z], [inset, d - inset, ring_z]]
        lower = FACADE_ORDER.each_with_index.map do |side, n|
          m = (n + 1) % 4
          ["roof/lower/#{side}", 'roof_face', [o[n], o[m], i[m], i[n]]]
        end
        lower + hip_faces('roof/upper', inset, inset, w - inset, d - inset, ring_z, slope(roof['pitch_deg']), 0.0)
      end
      private_class_method :mansard

      # Pente constante : faîtage dans l'axe du côté long ; carré quantifié = un sommet.
      def hip_faces(prefix, x0, y0, x1, y1, h, r, e)
        width = x1 - x0
        depth = y1 - y0
        half = [width, depth].min / 2.0
        top = h + (r * half)
        z = h - (r * e)
        a = [x0 - e, y0 - e, z]
        b = [x1 + e, y0 - e, z]
        c = [x1 + e, y1 + e, z]
        d = [x0 - e, y1 + e, z]
        xc = (x0 + x1) / 2.0
        yc = (y0 + y1) / 2.0
        faces = if (width - depth).abs <= SQUARE_TOLERANCE
                  apex = [xc, yc, top]
                  { 'front' => [a, b, apex], 'right' => [b, c, apex], 'rear' => [c, d, apex], 'left' => [d, a, apex] }
                elsif width > depth
                  p = [x0 + half, yc, top]
                  q = [x1 - half, yc, top]
                  { 'front' => [a, b, q, p], 'right' => [b, c, q], 'rear' => [c, d, p, q], 'left' => [d, a, p] }
                else
                  p = [xc, y0 + half, top]
                  q = [xc, y1 - half, top]
                  { 'front' => [a, b, p], 'right' => [b, c, q, p], 'rear' => [c, d, q], 'left' => [d, a, p, q] }
                end
        FACADE_ORDER.map { |side| ["#{prefix}/#{side}", 'roof_face', faces.fetch(side)] }
      end
      private_class_method :hip_faces
    end
  end
end
