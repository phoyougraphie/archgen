# frozen_string_literal: true

module Archgen
  module Geometry
    DetailPlan = Struct.new(:nodes, :definitions, keyword_init: true)

    # Boîte axis-alignée en solide fermé, faces orientées vers l'extérieur.
    module Boxes
      module_function

      def solid(x0, x1, y0, y1, z0, z1, material)
        a = [x0, y0, z0]
        b = [x1, y0, z0]
        c = [x1, y1, z0]
        d = [x0, y1, z0]
        e = [x0, y0, z1]
        f = [x1, y0, z1]
        g = [x1, y1, z1]
        h = [x0, y1, z1]
        mesh = MeshBuilder.new('solid')
        [[a, d, c, b], [e, f, g, h], [a, b, f, e], [b, c, g, f], [c, d, h, g], [d, a, e, h]].each { |q| mesh.add_face(q, material) }
        mesh.to_primitive
      end

      # Prisme vertical sur un contour antihoraire de 4 sommets.
      def prism(ring, z0, z1, material)
        low = ring.map { |x, y| [x, y, z0] }
        high = ring.map { |x, y| [x, y, z1] }
        mesh = MeshBuilder.new('solid')
        mesh.add_face(low.reverse, material)
        mesh.add_face(high, material)
        ring.each_index do |i|
          j = (i + 1) % ring.size
          mesh.add_face([low[i], low[j], high[j], high[i]], material)
        end
        mesh.to_primitive
      end

      # Boîte donnée en coordonnées de façade (u, z, d), quel que soit le côté.
      def on_facade(facade, u0, u1, z0, z1, d0, d1, material)
        p = facade.point(u0, z0, d0)
        q = facade.point(u1, z1, d1)
        solid(*[p[0], q[0]].minmax, *[p[1], q[1]].minmax, *[p[2], q[2]].minmax, material)
      end
    end

    # Détails LOD 1. Ils ne déplacent aucun percement et ne modifient aucun mur :
    # le volume de référence, les baies et le toit restent ceux du LOD 0.
    module DetailSolver
      FRAME_BAR_M = 0.04
      FRAME_MAX_RECESS_M = 0.16
      PANE_Y_M = [0.015, 0.025].freeze
      LEAF_Y_M = [0.005, 0.035].freeze
      TRANSOM_FROM_M = 2.40
      TRANSOM_Z_M = 2.20
      CORNICE_DEPTH_M = 0.15
      CORNICE_HEIGHT_M = 0.08
      BALCONY_DEPTH_M = 0.90
      BALCONY_THICKNESS_M = 0.12
      BALCONY_LEVELS = [2, 5].freeze
      SURROUND_BAR_M = 0.04
      SURROUND_DEPTH_M = 0.03
      HEAD_MARGIN_M = 0.10
      FASCIA_DEPTH_M = 0.10
      FASCIA_Z_M = [0.50, 0.10].freeze # sous le plancher du premier étage
      SHOP_DOOR_M = 0.90
      # AG-066 : souche de cheminée (départ).
      CHIMNEY_X_M = 0.60
      CHIMNEY_Y_M = 0.45
      CHIMNEY_GAP_M = 0.10
      CHIMNEY_ABOVE_RIDGE_M = 0.60
      CHIMNEY_ABOVE_FLAT_M = 1.00
      CHIMNEY_CAP_M = 0.05
      EPS = Core::Quant::EPSILON

      module_function

      # `roof_top_z_m` et `row` ne servent qu'aux cheminées : haut du toit, bâtiment de rangée.
      def call(footprint:, levels:, openings:, config:, roof_top_z_m: nil, row: false)
        return Core::Result.ok(DetailPlan.new(nodes: [], definitions: {})) unless config['lod'] == 1

        features = config['features']
        problems = []
        problems.concat(cornice_problems(config, levels, openings)) if features['cornice']
        balcony_levels = features['balcony'] ? levels.select { |l| BALCONY_LEVELS.include?(l.index) } : []
        problems.concat(balcony_problems(config, balcony_levels, openings))
        problems.concat(fascia_problems(levels, openings)) if shop?(config)
        return Core::Result.fail(problems) unless problems.empty?

        definitions = {}
        nodes = frames(footprint, openings, config, definitions)
        nodes += surrounds(footprint, openings, config) if features['surrounds']
        nodes << cornice(footprint, levels, config) if features['cornice']
        fascia_node = shop?(config) ? fascia(footprint, levels, config) : nil
        nodes << fascia_node if fascia_node
        nodes += chimneys(footprint, levels, config, roof_top_z_m, row) if features['chimneys'] && roof_top_z_m
        built_balconies = features['balcony'] ? balconies(footprint, balcony_levels, config) : []
        nodes += built_balconies
        warnings = features['balcony'] && built_balconies.empty? ? [balcony_warning(balcony_levels)] : []
        Core::Result.ok(DetailPlan.new(nodes: nodes, definitions: definitions), warnings)
      end

      def shop?(config)
        config['ground_floor'] == 'shop'
      end
      private_class_method :shop?

      def fascia_span(levels)
        top = levels.first.top_z_m
        [Core::Quant.q(top - FASCIA_Z_M[0]), Core::Quant.q(top - FASCIA_Z_M[1])]
      end
      private_class_method :fascia_span

      # AG-065 : le bandeau passerait devant la porte de l'immeuble ou le passage du porche.
      def fascia_problems(levels, openings)
        bottom = fascia_span(levels)[0]
        front(openings).filter_map do |opening|
          next unless opening.level_index.zero? && opening.kind != 'shopfront' && opening.z_max_m > bottom + EPS

          Core::Diagnostic.error('E_OPENING_CLEARANCE', '/shop/height_m', reason: 'fascia_over_entrance', id: opening.id, limit: bottom)
        end
      end
      private_class_method :fascia_problems

      def balcony_warning(balcony_levels)
        reason = balcony_levels.empty? ? 'no_balcony_level' : 'balcony_no_room'
        Core::Diagnostic.warning('W_DETAIL', '/features/balcony', reason: reason, levels: BALCONY_LEVELS)
      end
      private_class_method :balcony_warning

      def front(openings)
        openings.select { |o| o.facade_id == 'front' }
      end
      private_class_method :front

      # La tête des fenêtres garde sa marge sous la corniche ; un toit plat débordant
      # poserait une face coplanaire superposée au dessus de la corniche.
      def cornice_problems(config, levels, openings)
        problems = []
        limit = levels.last.top_z_m - CORNICE_HEIGHT_M - HEAD_MARGIN_M
        front(openings).each do |opening|
          next unless opening.z_max_m > limit + EPS

          problems << Core::Diagnostic.error('E_OPENING_CLEARANCE', '/features/cornice', reason: 'cornice_head_margin', id: opening.id, limit: limit)
        end
        roof = config['roof']
        if roof['type'] == 'flat' && roof['overhang_m'].positive?
          problems << Core::Diagnostic.error('E_ROOF_GEOMETRY', '/features/cornice', reason: 'cornice_coplanar_with_roof')
        end
        problems
      end
      private_class_method :cornice_problems

      # Une dalle de balcon passerait devant la baie ou l'encadrement du dessous.
      def balcony_problems(config, balcony_levels, openings)
        head = config['features']['surrounds'] ? SURROUND_BAR_M : 0.0
        balcony_levels.flat_map do |level|
          bottom = level.base_z_m - BALCONY_THICKNESS_M
          front(openings).filter_map do |opening|
            next unless opening.z_max_m + head > bottom + EPS && opening.z_min_m < level.base_z_m - EPS

            Core::Diagnostic.error('E_OPENING_CLEARANCE', '/features/balcony', reason: 'balcony_over_opening', id: opening.id, level: level.index)
          end
        end
      end
      private_class_method :balcony_problems

      def frames(footprint, openings, config, definitions)
        material = config['materials']['frames']
        glass = config['features']['glazing'] ? config['materials']['glass'] : nil
        wall = config['structure']['wall_m']
        recess = config['mode'] == 'structural' ? [FRAME_MAX_RECESS_M, wall - FRAME_BAR_M].min : 0.0
        entrance = entrance_u(openings)
        openings.reject { |opening| opening.kind == 'porch' }.map do |opening|
          definition_id = frame_definition(opening, material, glass, definitions, door_side(opening, entrance))
          facade = footprint.facade(opening.facade_id)
          Node.leaf("frame/#{opening.facade_id}/#{opening.level_index}/#{opening.bay_index}", 'frame',
                    { 'type' => 'instance', 'definition_id' => definition_id, 'matrix' => frame_matrix(facade, opening, recess) })
        end
      end
      private_class_method :frames

      # Milieu de l'entrée de l'immeuble (porte ou passage) sur la façade avant.
      def entrance_u(openings)
        entry = front(openings).find { |o| o.level_index.zero? && %w[door porch].include?(o.kind) }
        entry && ((entry.u_min_m + entry.u_max_m) / 2.0)
      end
      private_class_method :entrance_u

      # La porte vitrée d'une vitrine prend son bord le plus proche de l'entrée de l'immeuble.
      def door_side(opening, entrance)
        return nil unless opening.kind == 'shopfront'

        entrance && entrance < (opening.u_min_m + opening.u_max_m) / 2.0 ? 'left' : 'right'
      end
      private_class_method :door_side

      # Une définition par type, largeur, hauteur et matériau : le recul vit dans la matrice.
      # Sans vitrage, l'identifiant et le contenu restent ceux d'avant AG-064.
      def frame_definition(opening, material, glass, definitions, side = nil)
        width = Core::Quant.q(opening.u_max_m - opening.u_min_m)
        height = Core::Quant.q(opening.z_max_m - opening.z_min_m)
        id = "frame/#{opening.kind}/#{micrometres(width)}x#{micrometres(height)}/#{material}"
        id += "/glazed/#{glass}" if glass
        id += "/door-#{side}" if glass && side
        definitions[id] ||= frame_bars(opening.kind, width, height, material) + (glass ? joinery(opening.kind, width, height, material, glass, side) : [])
        id
      end
      private_class_method :frame_definition

      def micrometres(value)
        (value * Core::Quant::SCALE).round
      end
      private_class_method :micrometres

      # Montants sur toute la hauteur, traverses entre les montants, pas de seuil de porte.
      def frame_bars(kind, width, height, material)
        bar = FRAME_BAR_M
        bars = {
          'left' => [0.0, bar, 0.0, height],
          'right' => [width - bar, width, 0.0, height],
          'top' => [bar, width - bar, height - bar, height]
        }
        bars['bottom'] = [bar, width - bar, 0.0, bar] unless kind == 'door'
        bars.map do |name, (x0, x1, z0, z1)|
          Node.leaf("bar/#{name}", 'frame', Boxes.solid(x0, x1, 0.0, bar, z0, z1, material))
        end
      end
      private_class_method :frame_bars

      # AG-064 : vitre dans le jour d'une fenêtre ; vantail plein d'une porte, imposte vitrée
      # au-dessus de TRANSOM_FROM_M pour une porte haute. Tout reste dans la profondeur du cadre.
      def joinery(kind, width, height, material, glass, side = nil)
        bar = FRAME_BAR_M
        x0 = bar
        x1 = width - bar
        return [pane(x0, x1, bar, height - bar, glass)] if kind == 'window'
        return shop_joinery(x0, x1, height, material, glass, side) if kind == 'shopfront'

        top = height - bar
        return [leaf(x0, x1, 0.0, top, material)] unless height > TRANSOM_FROM_M + EPS

        [leaf(x0, x1, 0.0, TRANSOM_Z_M, material),
         Node.leaf('bar/transom', 'frame', Boxes.solid(x0, x1, 0.0, bar, TRANSOM_Z_M, TRANSOM_Z_M + bar, material)),
         pane(x0, x1, TRANSOM_Z_M + bar, top, glass)]
      end
      private_class_method :joinery

      # AG-065 : vitre fixe et porte vitrée de SHOP_DOOR_M, séparées par un montant.
      def shop_joinery(x0, x1, height, material, glass, side)
        bar = FRAME_BAR_M
        z0 = bar
        z1 = height - bar
        if side == 'left'
          door = [x0, x0 + SHOP_DOOR_M]
          mullion = [door[1], door[1] + bar]
          fixed = [mullion[1], x1]
        else
          door = [x1 - SHOP_DOOR_M, x1]
          mullion = [door[0] - bar, door[0]]
          fixed = [x0, mullion[0]]
        end
        [Node.leaf('bar/mullion', 'frame', Boxes.solid(*mullion, 0.0, bar, z0, z1, material)),
         Node.leaf('pane/door', 'frame', Boxes.solid(*door, PANE_Y_M[0], PANE_Y_M[1], z0, z1, glass)),
         pane(*fixed, z0, z1, glass)]
      end
      private_class_method :shop_joinery

      def pane(x0, x1, z0, z1, glass)
        Node.leaf('pane', 'frame', Boxes.solid(x0, x1, PANE_Y_M[0], PANE_Y_M[1], z0, z1, glass))
      end
      private_class_method :pane

      def leaf(x0, x1, z0, z1, material)
        Node.leaf('leaf', 'frame', Boxes.solid(x0, x1, LEAF_Y_M[0], LEAF_Y_M[1], z0, z1, material))
      end
      private_class_method :leaf

      # Colonnes (T, −N, K), rigide et directe : x = u relatif, y = d relatif, z = hauteur.
      def frame_matrix(facade, opening, recess)
        t = facade.tangent
        n = facade.normal
        origin = facade.point(opening.u_min_m, opening.z_min_m, recess)
        [t[0], t[1], 0.0, 0.0, -n[0], -n[1], 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, origin[0], origin[1], origin[2], 1.0].map { |c| Core::Quant.q(c) }
      end
      private_class_method :frame_matrix

      def surrounds(footprint, openings, config)
        material = config['materials']['wall']
        bar = SURROUND_BAR_M
        openings.select { |o| o.kind == 'window' }.flat_map do |o|
          facade = footprint.facade(o.facade_id)
          base = "surround/#{o.facade_id}/#{o.level_index}/#{o.bay_index}"
          {
            'left' => [o.u_min_m - bar, o.u_min_m, o.z_min_m, o.z_max_m],
            'right' => [o.u_max_m, o.u_max_m + bar, o.z_min_m, o.z_max_m],
            'top' => [o.u_min_m - bar, o.u_max_m + bar, o.z_max_m, o.z_max_m + bar]
          }.map do |name, (u0, u1, z0, z1)|
            Node.leaf("#{base}/#{name}", 'surround', Boxes.on_facade(facade, u0, u1, z0, z1, -SURROUND_DEPTH_M, 0.0, material))
          end
        end
      end
      private_class_method :surrounds

      def cornice(footprint, levels, config)
        facade = footprint.facade('front')
        top = levels.last.top_z_m
        return mitred_cornice(footprint, top, config) if footprint.trapezoid?

        Node.leaf('cornice', 'cornice',
                  Boxes.on_facade(facade, 0.0, facade.length_m, top - CORNICE_HEIGHT_M, top, -CORNICE_DEPTH_M, 0.0, config['materials']['wall']))
      end
      private_class_method :cornice

      # Coupée par les plans d'onglet : deux voisines se rejoignent sans se recouvrir.
      def mitred_cornice(footprint, top, config)
        y = -CORNICE_DEPTH_M
        ring = [[footprint.left_x(y), y], [footprint.right_x(y), y], [footprint.width_m, 0.0], [0.0, 0.0]]
        Node.leaf('cornice', 'cornice', Boxes.prism(ring, top - CORNICE_HEIGHT_M, top, config['materials']['wall']))
      end
      private_class_method :mitred_cornice

      # Du premier au dernier axe de travée plus un demi-pas : de la marge à la marge.
      def balconies(footprint, balcony_levels, config)
        facade = footprint.facade('front')
        margin = config['facade']['margin_m']
        return mitred_balconies(footprint, balcony_levels, margin, config) if footprint.trapezoid?

        balcony_levels.map do |level|
          Node.leaf("balcony/#{level.index}", 'balcony',
                    Boxes.on_facade(facade, margin, facade.length_m - margin, level.base_z_m - BALCONY_THICKNESS_M, level.base_z_m,
                                    -BALCONY_DEPTH_M, 0.0, config['materials']['wall']))
        end
      end
      private_class_method :balconies

      def mitred_balconies(footprint, balcony_levels, margin, config)
        ring = mitred_ring(footprint, margin, BALCONY_DEPTH_M)
        return [] unless ring

        balcony_levels.map do |level|
          Node.leaf("balcony/#{level.index}", 'balcony', Boxes.prism(ring, level.base_z_m - BALCONY_THICKNESS_M, level.base_z_m, config['materials']['wall']))
        end
      end
      private_class_method :mitred_balconies

      # De marge à marge, comme ailleurs, mais sans franchir l'onglet d'un angle rentrant.
      def mitred_ring(footprint, margin, depth)
        y = -depth
        near = [margin, footprint.width_m - margin]
        far = [[margin, footprint.left_x(y)].max, [footprint.width_m - margin, footprint.right_x(y)].min]
        return nil if far[1] - far[0] < Core::Quant::MIN_EDGE_M

        [[far[0], y], [far[1], y], [near[1], 0.0], [near[0], 0.0]]
      end
      private_class_method :mitred_ring

      # AG-065 : bandeau d'enseigne de marge à marge, entre les vitrines et le premier plancher.
      def fascia(footprint, levels, config)
        z0, z1 = fascia_span(levels)
        margin = config['facade']['margin_m']
        material = config['materials']['frames']
        unless footprint.trapezoid?
          facade = footprint.facade('front')
          return Node.leaf('fascia', 'fascia', Boxes.on_facade(facade, margin, facade.length_m - margin, z0, z1, -FASCIA_DEPTH_M, 0.0, material))
        end

        ring = mitred_ring(footprint, margin, FASCIA_DEPTH_M)
        ring && Node.leaf('fascia', 'fascia', Boxes.prism(ring, z0, z1, material))
      end
      private_class_method :fascia

      # AG-066 : une ou deux souches. Contre les murs latéraux, centrées sur le faîtage (deux pans,
      # toit plat, toute rangée) ; au bout du faîtage d'une croupe ou d'une mansarde seule.
      def chimneys(footprint, levels, config, roof_top, row)
        seed = config['seed']
        count = Core::DeterministicRandom.unit(seed, 'chimneys') < 0.5 ? 1 : 2
        spots = chimney_spots(footprint, config, row)
        spots = [spots[Core::DeterministicRandom.unit(seed, 'chimneys/side') < 0.5 ? 0 : -1]] if count == 1 || spots.size == 1
        flat = config['roof']['type'] == 'flat'
        top = Core::Quant.q(roof_top + (flat ? CHIMNEY_ABOVE_FLAT_M : CHIMNEY_ABOVE_RIDGE_M))
        base = levels.last.top_z_m
        material = config['materials']['wall']
        spots.uniq.each_with_index.flat_map do |(x, y), index|
          x0 = Core::Quant.q(x - (CHIMNEY_X_M / 2.0))
          x1 = Core::Quant.q(x + (CHIMNEY_X_M / 2.0))
          y0 = Core::Quant.q(y - (CHIMNEY_Y_M / 2.0))
          y1 = Core::Quant.q(y + (CHIMNEY_Y_M / 2.0))
          cap = CHIMNEY_CAP_M
          [Node.leaf("chimney/#{index}", 'chimney', Boxes.solid(x0, x1, y0, y1, base, Core::Quant.q(top - cap), material)),
           Node.leaf("chimney/#{index}/cap", 'chimney', Boxes.solid(x0 - cap, x1 + cap, y0 - cap, y1 + cap, Core::Quant.q(top - cap), top, material))]
        end
      end
      private_class_method :chimneys

      # Milieux des souches, de gauche à droite (ou de l'avant vers l'arrière).
      def chimney_spots(footprint, config, row)
        roof = config['roof']
        return ridge_ends(footprint, roof) if !row && %w[hip mansard].include?(roof['type'])

        y = footprint.depth_m / 2.0
        ys = [y - (CHIMNEY_Y_M / 2.0), y + (CHIMNEY_Y_M / 2.0)]
        inner = config['structure']['wall_m'] + CHIMNEY_GAP_M + (CHIMNEY_X_M / 2.0)
        left = ys.map { |v| footprint.left_x(v) }.max + inner
        right = ys.map { |v| footprint.right_x(v) }.min - inner
        [[left, y], [right, y]]
      end
      private_class_method :chimney_spots

      # Même faîtage que RoofSolver.hip_faces ; un carré n'a qu'un sommet.
      def ridge_ends(footprint, roof)
        inset = roof['type'] == 'mansard' ? roof['inset_m'] : 0.0
        x0 = inset
        y0 = inset
        x1 = footprint.width_m - inset
        y1 = footprint.depth_m - inset
        width = x1 - x0
        depth = y1 - y0
        half = [width, depth].min / 2.0
        xc = (x0 + x1) / 2.0
        yc = (y0 + y1) / 2.0
        return [[xc, yc]] if (width - depth).abs <= RoofSolver::SQUARE_TOLERANCE
        return [[x0 + half, yc], [x1 - half, yc]] if width > depth

        [[xc, y0 + half], [xc, y1 - half]]
      end
      private_class_method :ridge_ends
    end
  end
end
