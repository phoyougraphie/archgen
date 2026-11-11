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
      # AG-070 : petits bois, devant la vitre.
      MULLION_M = 0.03
      MUNTIN_M = 0.02
      MUNTIN_Y_M = [0.004, 0.014].freeze
      TWO_LEAVES_FROM_M = 0.80
      # AG-090 : montants d'une baie en bandeau.
      RIBBON_MULLION_M = 0.05
      RIBBON_MODULE_MIN_M = 0.80
      # AG-071 : battants de volet ouverts, plaqués au mur.
      SHUTTER_THICKNESS_M = 0.03
      SHUTTER_GAP_M = 0.01
      # AG-074 : génoise, rangs du haut vers le bas (hauteur, saillie).
      GENOISE_ROWS = [[0.10, 0.16], [0.10, 0.08]].freeze
      GENOISE_HEAD_M = 0.10
      GENOISE_ROOFS = %w[gable hip].freeze
      # AG-080 : pignon à redents (départ).
      STEPS = 5
      STEP_ABOVE_M = 0.30
      PINNACLE_M = [0.50, 0.40].freeze
      STEP_DEPTH_M = [-0.05, 0.25].freeze
      TRANSOM_Z_M = 2.20
      CORNICE_DEPTH_M = 0.15
      CORNICE_HEIGHT_M = 0.08
      BALCONY_DEPTH_M = 0.90
      BALCONY_THICKNESS_M = 0.12
      BALCONY_LEVELS = [2, 5].freeze
      # AG-137 : bow-window, avancée vitrée d'un étage à l'autre devant une baie.
      BOW_DEPTH_M = 0.70
      BOW_SIDE_M = 0.30
      BOW_SLAB_M = 0.15
      BOW_POST_M = 0.06
      BOW_PANE_M = 0.02
      # AG-143 : bandeaux, tourelle d'angle, balconnets.
      BAND_HALF_M = 0.10
      BAND_DEPTH_M = 0.04
      TURRET_SIDE_M = 2.0
      TURRET_SPIRE = 1.4
      TURRET_EAVE_M = 0.15
      TURRET_CLEAR_M = 0.10
      BALCONETTE_DEPTH_M = 0.35
      BALCONETTE_SLAB_M = 0.08
      BALCONETTE_RAIL_M = 0.75
      BALCONETTE_BAR_M = 0.02
      BALCONETTE_SPACING_M = 0.12
      # AG-133 : balcons filants à chaque étage au-dessus du rez-de-chaussée (immeuble balnéaire).
      # AG-106 : garde-corps de balcon (docs/TEINTES_ABORDS_CONTRACT.md).
      RAIL_HEIGHT_M = 1.00
      RAIL_TOP_M = 0.05
      RAIL_SOLID_M = 0.10
      # AG-135 : vitrage du garde-corps vitré, sous la main courante.
      RAIL_GLASS_M = 0.02
      RAIL_GLASS_FOOT_M = 0.05
      BAR_M = 0.02
      BAR_SPACING_M = 0.12
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
      # `ridge` : faîtage effectivement posé (AG-079), 'parallel' ou 'perpendicular'.
      def call(footprint:, levels:, openings:, config:, roof_top_z_m: nil, row: false, ridge: 'parallel')
        return Core::Result.ok(DetailPlan.new(nodes: [], definitions: {})) unless config['lod'] == 1

        features = config['features']
        problems = []
        problems.concat(cornice_problems(config, levels, openings)) if features['cornice']
        balcony_levels = features['balcony'] ? levels.select { |l| balcony_level?(l, features) } : []
        # AG-137 : balcons qui tournent l'angle, sur un bâtiment seul et rectangulaire seulement.
        wrap = features['balcony_wrap'] && !row && !footprint.trapezoid?
        problems.concat(balcony_problems(config, balcony_levels, openings, wrap))
        bows = features['bow_window'] ? bow_openings(openings, config) : []
        problems.concat(bow_problems(config, bows, balcony_levels, features))
        problems.concat(band_problems(footprint, levels, openings, config, row, balcony_levels, bows)) if features['string_courses']
        turret = features['turret'] && !row && !footprint.trapezoid?
        problems.concat(turret_problems(footprint, openings)) if turret
        problems.concat(balconette_problems(balcony_levels)) if features['balconettes']
        problems.concat(fascia_problems(levels, openings)) if shop?(config)
        clashes = features['shutters'] ? shutter_clashes(footprint, openings, config) : {}
        problems.concat(shutter_problems(clashes))
        cross = ridge == 'perpendicular'
        problems.concat(OrnamentSolver.arch_problems(openings, config)) if config['facade']['arch']
        problems.concat(OrnamentSolver.classical_problems(footprint, openings, config, levels)) if features['classical']
        problems.concat(genoise_problems(levels, openings, config)) if genoise?(config) && !cross
        dormers = features['dormers'] && !cross ? DormerSolver.call(footprint: footprint, levels: levels, config: config, row: row, blocked: chimney_boxes(footprint, config, row)) : nil
        problems.concat(dormers.errors) if dormers && !dormers.ok?
        return Core::Result.fail(problems) unless problems.empty?

        definitions = {}
        nodes = frames(footprint, openings, config, definitions)
        nodes += surrounds(footprint, openings, config) if features['surrounds']
        skipped = clashes.select { |_, why| why == :porch }.keys
        nodes += shutters(footprint, openings.reject { |o| skipped.include?(o.id) }, config, definitions) if features['shutters']
        nodes << cornice(footprint, levels, config) if features['cornice']
        nodes += genoise(footprint, levels, config) if genoise?(config) && !cross
        nodes += stepped_gable(footprint, levels, config) if features['stepped_gable'] && cross
        nodes += TimberSolver.call(footprint: footprint, levels: levels, openings: openings, config: config, row: row) if features['timber_frame']
        nodes += OrnamentSolver.arches(footprint, openings, config) if config['facade']['arch']
        nodes += OrnamentSolver.classical(footprint, openings, config, levels.last.top_z_m) if features['classical']
        nodes += ModernSolver.structural_grid(footprint, levels, openings, config) if features['structural_grid']
        nodes += ModernSolver.sun_shades(footprint, openings, config) if features['sun_shades']
        nodes += ModernSolver.shop_front(footprint, levels, openings, config) if features['shop_front'] && shop?(config)
        fascia_node = shop?(config) ? fascia(footprint, levels, config) : nil
        nodes << fascia_node if fascia_node
        nodes += chimneys(footprint, levels, config, roof_top_z_m, row, cross) if features['chimneys'] && roof_top_z_m
        nodes += dormer_nodes(footprint, levels, config, dormers.value, definitions) if dormers
        built_balconies = features['balcony'] ? balconies(footprint, balcony_levels, config, wrap) : []
        nodes += built_balconies
        nodes += balcony_rails(footprint, balcony_levels, config, definitions, wrap) if features['balcony_rail'] && !built_balconies.empty?
        nodes += bow_windows(footprint, bows, levels, config)
        nodes += string_courses(footprint, levels, config, row, balcony_levels, bows) if features['string_courses']
        nodes += turret_nodes(levels, config) if turret
        nodes += balconettes(footprint, openings, config, bows) if features['balconettes']
        warnings = features['balcony'] && built_balconies.empty? ? [balcony_warning(balcony_levels)] : []
        warnings << Core::Diagnostic.warning('W_DETAIL', '/features/balcony_wrap', reason: 'balcony_wrap_in_row') if features['balcony'] && features['balcony_wrap'] && !wrap
        warnings << Core::Diagnostic.warning('W_DETAIL', '/features/bow_window', reason: 'no_bow_window') if features['bow_window'] && bows.empty?
        warnings << Core::Diagnostic.warning('W_DETAIL', '/features/turret', reason: 'turret_in_row') if features['turret'] && !turret
        warnings += dormers.warnings if dormers
        porch_warning = features['classical'] ? OrnamentSolver.porch_warning(footprint, openings, config) : nil
        warnings << porch_warning if porch_warning
        warnings << Core::Diagnostic.warning('W_DETAIL', '/features/genoise', reason: 'genoise_roof') if features['genoise'] && (!genoise?(config) || cross)
        warnings << Core::Diagnostic.warning('W_DETAIL', '/features/dormers', reason: 'dormer_ridge') if features['dormers'] && cross
        warnings << Core::Diagnostic.warning('W_DETAIL', '/features/stepped_gable', reason: 'stepped_gable_corner') if features['stepped_gable'] && !cross
        warnings << Core::Diagnostic.warning('W_DETAIL', '/features/shutters', reason: 'shutters_skipped', ids: skipped.sort) unless skipped.empty?
        Core::Result.ok(DetailPlan.new(nodes: nodes, definitions: definitions), warnings)
      end

      # AG-080 : marches empilées sur le pignon avant, chacune 0,30 m au-dessus de la pente au droit
      # de son bout intérieur ; un pinacle au faîte. Posées devant le nu, elles couvrent le pignon du toit.
      def stepped_gable(footprint, levels, config)
        facade = footprint.facade('front')
        width = facade.length_m
        r = RoofSolver.slope(config['roof']['pitch_deg'])
        step = (width / 2.0) / STEPS
        material = config['materials']['wall']
        d0, d1 = STEP_DEPTH_M
        bottom = levels.last.top_z_m
        nodes = (0...STEPS).map do |k|
          top = Core::Quant.q(levels.last.top_z_m + (r * (k + 1) * step) + STEP_ABOVE_M)
          u0 = Core::Quant.q(k * step)
          u1 = Core::Quant.q(width - (k * step))
          node = Node.leaf("stepped_gable/#{k}", 'stepped_gable', Boxes.on_facade(facade, u0, u1, bottom, top, d0, d1, material))
          bottom = top
          node
        end
        half = PINNACLE_M[0] / 2.0
        middle = width / 2.0
        nodes << Node.leaf('stepped_gable/pinnacle', 'stepped_gable',
                           Boxes.on_facade(facade, Core::Quant.q(middle - half), Core::Quant.q(middle + half), bottom, Core::Quant.q(bottom + PINNACLE_M[1]), d0, d1, material))
      end
      private_class_method :stepped_gable

      # AG-081 : balcons de bois avec le bardage.
      def balcony_material(config)
        config['materials']['cladding'] || config['materials']['wall']
      end
      private_class_method :balcony_material

      def genoise?(config)
        config['features']['genoise'] && GENOISE_ROOFS.include?(config['roof']['type'])
      end
      private_class_method :genoise?

      # Le rang du haut s'arrête sous la peau du toit prolongée : rien ne la traverse.
      def genoise_top(levels, config)
        Core::Quant.q(levels.last.top_z_m - (RoofSolver.slope(config['roof']['pitch_deg']) * GENOISE_ROWS.first[1]))
      end
      private_class_method :genoise_top

      def genoise_problems(levels, openings, config)
        problems = []
        problems << Core::Diagnostic.error('E_OPENING_CLEARANCE', '/features/genoise', reason: 'genoise_with_cornice') if config['features']['cornice']
        limit = Core::Quant.q(genoise_top(levels, config) - GENOISE_ROWS.sum(&:first) - GENOISE_HEAD_M)
        openings.select { |o| %w[front rear].include?(o.facade_id) && o.z_max_m > limit + EPS }.each do |o|
          problems << Core::Diagnostic.error('E_OPENING_CLEARANCE', '/features/genoise', reason: 'genoise_head_margin', id: o.id, limit: limit)
        end
        problems
      end
      private_class_method :genoise_problems

      # AG-074 : rangs de tuiles en encorbellement sous l'égout, avant et arrière.
      def genoise(footprint, levels, config)
        material = config['materials']['roof']
        top = genoise_top(levels, config)
        nodes = []
        GENOISE_ROWS.each_with_index do |(height, depth), row|
          z1 = Core::Quant.q(top - GENOISE_ROWS.first(row).sum(&:first))
          z0 = Core::Quant.q(z1 - height)
          front = footprint.facade('front')
          if footprint.trapezoid?
            ring = mitred_ring(footprint, 0.0, depth)
            nodes << Node.leaf("genoise/front/#{row}", 'genoise', Boxes.prism(ring, z0, z1, material)) if ring
          else
            nodes << Node.leaf("genoise/front/#{row}", 'genoise', Boxes.on_facade(front, 0.0, front.length_m, z0, z1, -depth, 0.0, material))
          end
          rear = footprint.facade('rear')
          trim = footprint.trapezoid? ? depth : 0.0
          nodes << Node.leaf("genoise/rear/#{row}", 'genoise', Boxes.on_facade(rear, trim, rear.length_m - trim, z0, z1, -depth, 0.0, material))
        end
        nodes
      end
      private_class_method :genoise

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

      # AG-134 : profondeur réglable (features.balcony_depth_m), 0,90 m par défaut.
      def balcony_depth(config)
        config['features']['balcony_depth_m'] || BALCONY_DEPTH_M
      end
      private_class_method :balcony_depth

      def balcony_level?(level, features)
        features['balcony_levels'] == 'all' ? level.index >= 1 : BALCONY_LEVELS.include?(level.index)
      end
      private_class_method :balcony_level?

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
      def balcony_problems(config, balcony_levels, openings, wrap = false)
        head = config['features']['surrounds'] ? SURROUND_BAR_M : 0.0
        faced = wrap ? openings.select { |o| %w[front left right].include?(o.facade_id) } : front(openings)
        balcony_levels.flat_map do |level|
          bottom = level.base_z_m - BALCONY_THICKNESS_M
          faced.filter_map do |opening|
            next unless opening.z_max_m + head > bottom + EPS && opening.z_min_m < level.base_z_m - EPS

            Core::Diagnostic.error('E_OPENING_CLEARANCE', '/features/balcony', reason: 'balcony_over_opening', id: opening.id, level: level.index)
          end
        end
      end
      private_class_method :balcony_problems

      def frames(footprint, openings, config, definitions)
        material = config['materials']['frames']
        glass = config['features']['glazing'] ? config['materials']['glass'] : nil
        rows = glass && config['features']['muntins'] ? config['facade']['muntin_rows'] : nil
        wall = config['structure']['wall_m']
        recess = config['mode'] == 'structural' ? [FRAME_MAX_RECESS_M, wall - FRAME_BAR_M].min : 0.0
        entrance = entrance_u(openings)
        openings.reject { |opening| opening.kind == 'porch' }.map do |opening|
          own = opening.kind == 'door' ? config['materials']['door'] || material : material # AG-104 : porte teinte à part
          definition_id = frame_definition(opening, own, glass, definitions, door_side(opening, entrance), rows)
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
      def frame_definition(opening, material, glass, definitions, side = nil, rows = nil)
        width = Core::Quant.q(opening.u_max_m - opening.u_min_m)
        height = Core::Quant.q(opening.z_max_m - opening.z_min_m)
        id = "frame/#{opening.kind}/#{micrometres(width)}x#{micrometres(height)}/#{material}"
        id += "/glazed/#{glass}" if glass
        id += "/door-#{side}" if glass && side
        rows = nil unless opening.kind == 'window'
        id += "/muntins/#{rows}" if rows
        module_width = opening.kind == 'ribbon' ? ribbon_module(width) : nil
        id += "/modules/#{micrometres(module_width)}" if module_width
        definitions[id] ||= frame_bars(opening.kind, width, height, material) +
                            (module_width ? ribbon_joinery(width, height, module_width, material, glass) : []) +
                            (glass && !module_width ? joinery(opening.kind, width, height, material, glass, side) : []) +
                            (rows ? muntins(width, height, rows, material) : [])
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

      # AG-070 : montant central (deux vantaux dès TWO_LEAVES_FROM_M) et rows − 1 traverses par vantail.
      def muntins(width, height, rows, material)
        bar = FRAME_BAR_M
        z0 = bar
        z1 = height - bar
        y0, y1 = MUNTIN_Y_M
        middle = width / 2.0
        two = width >= TWO_LEAVES_FROM_M - EPS
        spans = two ? [[bar, middle - (MULLION_M / 2.0)], [middle + (MULLION_M / 2.0), width - bar]] : [[bar, width - bar]]
        out = []
        out << Node.leaf('muntin/mullion', 'frame', Boxes.solid(middle - (MULLION_M / 2.0), middle + (MULLION_M / 2.0), y0, y1, z0, z1, material)) if two
        spans.each_with_index do |(x0, x1), leaf|
          (1...rows).each do |k|
            z = z0 + ((z1 - z0) * k / rows)
            out << Node.leaf("muntin/#{leaf}/#{k}", 'frame', Boxes.solid(x0, x1, y0, y1, z - (MUNTIN_M / 2.0), z + (MUNTIN_M / 2.0), material))
          end
        end
        out
      end
      private_class_method :muntins

      # Modules égaux d'au moins RIBBON_MODULE_MIN_M, séparés par des montants ; une vitre par module.
      def ribbon_module(width)
        clear = width - (2 * FRAME_BAR_M)
        count = [(clear / RIBBON_MODULE_MIN_M).floor, 1].max
        Core::Quant.q(clear / count)
      end
      private_class_method :ribbon_module

      def ribbon_joinery(width, height, module_width, material, glass)
        bar = FRAME_BAR_M
        count = ((width - (2 * bar)) / module_width).round
        half = RIBBON_MULLION_M / 2.0
        nodes = (1...count).map do |k|
          x = bar + (k * module_width)
          Node.leaf("bar/mullion/#{k}", 'frame', Boxes.solid(x - half, x + half, 0.0, bar, bar, height - bar, material))
        end
        return nodes unless glass

        nodes + (0...count).map do |k|
          x0 = bar + (k * module_width) + (k.zero? ? 0.0 : half)
          x1 = bar + ((k + 1) * module_width) - (k == count - 1 ? 0.0 : half)
          Node.leaf("pane/#{k}", 'frame', Boxes.solid(x0, x1, PANE_Y_M[0], PANE_Y_M[1], bar, height - bar, glass))
        end
      end
      private_class_method :ribbon_joinery

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

      # AG-071 : deux battants par fenêtre, chacun la moitié de sa largeur, à l'extérieur de l'encadrement.
      def shutter_spans(opening, config)
        off = config['features']['surrounds'] ? SURROUND_BAR_M : 0.0
        half = (opening.u_max_m - opening.u_min_m) / 2.0
        [[opening.u_min_m - off - half, opening.u_min_m - off], [opening.u_max_m + off, opening.u_max_m + off + half]]
      end
      private_class_method :shutter_spans

      # Jamais rétréci ni omis : un battant qui sort de la façade ou touche une autre baie (ou son
      # battant) du même niveau est refusé, avec l'id de la fenêtre.
      # { id de fenêtre => :porch | :other } pour chaque fenêtre dont un battant ne tient pas.
      # :porch : seul le passage d'un porche le gêne (AG-073) ; ses volets sont omis et dits.
      def shutter_clashes(footprint, openings, config)
        off = config['features']['surrounds'] ? SURROUND_BAR_M : 0.0
        openings.select { |o| o.kind == 'window' }.each_with_object({}) do |window, out|
          length = footprint.facade(window.facade_id).length_m
          spans = shutter_spans(window, config)
          others = openings.reject { |o| o.equal?(window) || o.facade_id != window.facade_id }
                           .select { |o| o.z_min_m < window.z_max_m - EPS && o.z_max_m > window.z_min_m + EPS }
          clash = lambda do |list|
            taken = list.flat_map { |o| [[o.u_min_m - off, o.u_max_m + off]] + (o.kind == 'window' ? shutter_spans(o, config) : []) }
            spans.any? { |a, b| a < -EPS || b > length + EPS || taken.any? { |c, d| a < d - EPS && b > c + EPS } }
          end
          next unless clash.call(others)

          out[window.id] = clash.call(others.reject { |o| o.kind == 'porch' }) ? :other : :porch
        end
      end
      private_class_method :shutter_clashes

      def shutter_problems(clashes)
        clashes.select { |_, why| why == :other }.keys.map do |id|
          Core::Diagnostic.error('E_OPENING_CLEARANCE', '/features/shutters', reason: 'shutters_no_room', id: id)
        end
      end
      private_class_method :shutter_problems

      # Une définition par largeur, hauteur et matière ; la matrice pose chaque battant.
      def shutters(footprint, openings, config, definitions)
        material = config['materials']['shutters']
        openings.select { |o| o.kind == 'window' }.flat_map do |window|
          facade = footprint.facade(window.facade_id)
          height = Core::Quant.q(window.z_max_m - window.z_min_m)
          shutter_spans(window, config).each_with_index.map do |(u0, u1), side|
            width = Core::Quant.q(u1 - u0)
            id = "shutter/#{micrometres(width)}x#{micrometres(height)}/#{material}"
            definitions[id] ||= [Node.leaf('leaf', 'shutter', Boxes.solid(0.0, width, 0.0, SHUTTER_THICKNESS_M, 0.0, height, material))]
            depth = -(SHUTTER_GAP_M + SHUTTER_THICKNESS_M)
            Node.leaf("shutter/#{window.facade_id}/#{window.level_index}/#{window.bay_index}/#{side}", 'shutter',
                      { 'type' => 'instance', 'definition_id' => id, 'matrix' => placement_matrix(facade, Core::Quant.q(u0), window.z_min_m, depth) })
          end
        end
      end
      private_class_method :shutters

      def placement_matrix(facade, u, z, depth)
        t = facade.tangent
        n = facade.normal
        origin = facade.point(u, z, depth)
        [t[0], t[1], 0.0, 0.0, -n[0], -n[1], 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, origin[0], origin[1], origin[2], 1.0].map { |c| Core::Quant.q(c) }
      end
      private_class_method :placement_matrix

      def surrounds(footprint, openings, config)
        material = config['materials']['surrounds'] || config['materials']['wall'] # AG-141 : brique sur enduit
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
      def balconies(footprint, balcony_levels, config, wrap = false)
        facade = footprint.facade('front')
        margin = config['facade']['margin_m']
        return mitred_balconies(footprint, balcony_levels, margin, config) if footprint.trapezoid?

        if wrap
          ring = wrap_ring(footprint, balcony_depth(config), margin)
          return balcony_levels.map do |level|
            Node.leaf("balcony/#{level.index}", 'balcony', wrap_slab(ring, level.base_z_m - BALCONY_THICKNESS_M, level.base_z_m, balcony_material(config)))
          end
        end

        balcony_levels.map do |level|
          Node.leaf("balcony/#{level.index}", 'balcony',
                    Boxes.on_facade(facade, margin, facade.length_m - margin, level.base_z_m - BALCONY_THICKNESS_M, level.base_z_m,
                                    -balcony_depth(config), 0.0, balcony_material(config)))
        end
      end
      private_class_method :balconies

      def mitred_balconies(footprint, balcony_levels, margin, config)
        ring = mitred_ring(footprint, margin, balcony_depth(config))
        return [] unless ring

        balcony_levels.map do |level|
          Node.leaf("balcony/#{level.index}", 'balcony', Boxes.prism(ring, level.base_z_m - BALCONY_THICKNESS_M, level.base_z_m, balcony_material(config)))
        end
      end
      private_class_method :mitred_balconies

      # Main courante et barreaux (une définition partagée), ou muret plein, sur les trois côtés
      # libres du balcon ; le côté du mur reste ouvert.
      def balcony_rails(footprint, balcony_levels, config, definitions, wrap = false)
        margin = config['facade']['margin_m']
        ring = footprint.trapezoid? ? mitred_ring(footprint, margin, balcony_depth(config)) : rect_ring(footprint, margin, balcony_depth(config))
        return [] unless ring

        segments = [[ring[3], ring[0]], [ring[0], ring[1]], [ring[1], ring[2]]]
        if wrap
          u = wrap_ring(footprint, balcony_depth(config), margin)
          # Bord extérieur du U, avec ses deux retours contre les murs latéraux.
          segments = [[u[6], u[7]], [u[7], u[0]], [u[0], u[1]], [u[1], u[2]], [u[2], u[3]]]
        end
        solid = config['features']['balcony_rail'] == 'solid'
        glass = config['features']['balcony_rail'] == 'glass'
        rails_on(segments, balcony_levels.map(&:base_z_m), config, definitions, solid, glass, ->(z) { balcony_levels.find { |l| l.base_z_m == z }.index })
      end
      private_class_method :balcony_rails

      # Garde-corps au bord de la terrasse d'un attique (AG-135), en repère de l'attique : bande de
      # `depth` devant sa façade, à z = 0. Barreaux si le style n'en dit pas autrement.
      def terrace_rails(footprint, depth, config, definitions)
        ring = rect_ring(footprint, 0.0, depth)
        segments = [[ring[3], ring[0]], [ring[0], ring[1]], [ring[1], ring[2]]]
        kind = config['features']['balcony_rail']
        rails_on(segments, [0.0], config, definitions, kind == 'solid', kind == 'glass', ->(_) { 'terrace' })
      end

      def rails_on(segments, zs, config, definitions, solid, glass, name)
        zs.flat_map do |z|
          label = name.call(z)
          segments.each_with_index.flat_map do |(p, q), i|
            id = "balcony/#{label}/rail/#{i}"
            next [Node.leaf(id, 'balcony', Boxes.prism(band(p, q, RAIL_SOLID_M), z, z + RAIL_HEIGHT_M, config['materials']['wall']))] if solid

            material = config['materials']['frames']
            top = Node.leaf(id, 'balcony', Boxes.prism(band(p, q, RAIL_TOP_M), z + RAIL_HEIGHT_M - RAIL_TOP_M, z + RAIL_HEIGHT_M, material))
            if glass
              pane = Boxes.prism(band(p, q, RAIL_GLASS_M), z + RAIL_GLASS_FOOT_M, z + RAIL_HEIGHT_M - RAIL_TOP_M, config['materials']['glass'] || 'glass')
              next [top, Node.leaf("#{id}/glass", 'balcony', pane)]
            end
            [top] + bars(p, q, z, material, definitions).each_with_index.map { |matrix, k| Node.leaf("#{id}/bar/#{k}", 'balcony', matrix) }
          end
        end
      end
      private_class_method :rails_on

      # Balcon en U (AG-137) : devant la façade, d'un bout à l'autre plus la profondeur, et le long des
      # deux murs latéraux jusqu'à `margin` du fond. Anneau direct, de 8 sommets.
      def wrap_ring(footprint, depth, margin)
        w = footprint.width_m
        back = Core::Quant.q(footprint.depth_m - margin)
        d = Core::Quant.q(depth)
        [[-d, -d], [Core::Quant.q(w + d), -d], [Core::Quant.q(w + d), back], [w, back], [w, 0.0], [0.0, 0.0], [0.0, back], [-d, back]]
      end
      private_class_method :wrap_ring

      # Dalle en U fermée : dessus et dessous en cinq quadrilatères (trois devant, un par côté), sans
      # sommet en T ; contour extérieur et intérieur en faces verticales.
      def wrap_slab(ring, z0, z1, material)
        d0, w0 = ring[0]
        wd = ring[1][0]
        back = ring[2][1]
        w = ring[3][0]
        p = { o0: [d0, w0], o1: [0.0, w0], o2: [w, w0], o3: [wd, w0], a: [d0, 0.0], f0: [0.0, 0.0], f1: [w, 0.0], c: [wd, 0.0],
              lb: [d0, back], li: [0.0, back], rb: [wd, back], ri: [w, back] }
        quads = [%i[o0 o1 f0 a], %i[o1 o2 f1 f0], %i[o2 o3 c f1], %i[a f0 li lb], %i[f1 c rb ri]]
        outline = %i[o0 o1 o2 o3 c rb ri f1 f0 li lb a]
        mesh = MeshBuilder.new('solid')
        quads.each do |quad|
          mesh.add_face(quad.map { |k| p[k] + [z1] }, material)
          mesh.add_face(quad.reverse.map { |k| p[k] + [z0] }, material)
        end
        outline.each_index do |n|
          a = p[outline[n]]
          b = p[outline[(n + 1) % outline.size]]
          mesh.add_face([a + [z0], b + [z0], b + [z1], a + [z1]], material)
        end
        mesh.to_primitive
      end
      private_class_method :wrap_slab

      # --- Bow-windows (AG-137, ADR-65)

      # Fenêtres de façade, aux étages, des travées choisies : centre, ou les deux bouts.
      def bow_openings(openings, config)
        ground = config['features']['bow_window'] == 'ground'
        windows = front(openings).select { |o| o.kind == 'window' && (ground ? o.level_index.zero? : o.level_index >= 1) }
        bays = windows.map(&:bay_index).uniq.sort
        return [] if bays.empty?

        chosen = config['features']['bow_window'] == 'ends' ? [bays.first, bays.last].uniq : [bays[bays.size / 2]]
        # Au rez-de-chaussée, la fenêtre la plus proche du milieu (la porte n'en est pas une).
        chosen = [bays.min_by { |b| (b - ((config['facade']['front_bays'] - 1) / 2.0)).abs }] if ground
        windows.select { |o| chosen.include?(o.bay_index) }
      end
      private_class_method :bow_openings

      def bow_problems(config, bows, balcony_levels, features)
        return [] if bows.empty?

        out = []
        clash = bows.map(&:level_index) & balcony_levels.map(&:index)
        clash |= bows.map { |o| o.level_index + 1 } & balcony_levels.map(&:index)
        out << Core::Diagnostic.error('E_OPENING_CLEARANCE', '/features/bow_window', reason: 'bow_window_with_balcony', levels: clash.sort) unless clash.empty?
        out << Core::Diagnostic.error('E_OPENING_CLEARANCE', '/features/bow_window', reason: 'bow_window_with_shutters') if features['shutters']
        margin = config['facade']['margin_m']
        bows.each do |o|
          next if o.u_min_m - BOW_SIDE_M >= margin - EPS

          out << Core::Diagnostic.error('E_OPENING_CLEARANCE', '/features/bow_window', reason: 'bow_window_facade_end', id: o.id)
        end
        out.uniq(&:to_h)
      end
      private_class_method :bow_problems

      # Une avancée par travée : dalle basse à chaque étage, vitrage jusqu'à la dalle suivante,
      # montants aux angles, dalle haute sur le dernier étage de la colonne.
      def bow_windows(footprint, bows, levels, config)
        return [] if bows.empty?

        facade = footprint.facade('front')
        wall = config['materials']['wall']
        frames = config['materials']['frames']
        glass = config['materials']['glass'] || 'glass'
        by_level = levels.to_h { |l| [l.index, l] }
        bows.group_by(&:bay_index).flat_map do |bay, column|
          column = column.sort_by(&:level_index)
          u0 = Core::Quant.q(column.map(&:u_min_m).min - BOW_SIDE_M)
          u1 = Core::Quant.q(column.map(&:u_max_m).max + BOW_SIDE_M)
          d = -BOW_DEPTH_M
          column.each_with_index.flat_map do |o, k|
            level = by_level.fetch(o.level_index)
            above = column[k + 1] && by_level[column[k + 1].level_index]
            # Au rez-de-chaussée, la dalle basse est posée sur le sol au lieu de passer dessous (AG-143).
            ground = level.base_z_m.abs < EPS
            z0 = ground ? Core::Quant.q(level.base_z_m + BOW_SLAB_M) : level.base_z_m
            top = above ? above.base_z_m - BOW_SLAB_M : level.top_z_m
            id = "bow/#{bay}/#{o.level_index}"
            parts = [
              Node.leaf("#{id}/floor", 'balcony', Boxes.on_facade(facade, u0, u1, z0 - BOW_SLAB_M, z0, d, 0.0, wall)),
              Node.leaf("#{id}/front", 'balcony', Boxes.on_facade(facade, u0 + BOW_POST_M, u1 - BOW_POST_M, z0, top, d, d + BOW_PANE_M, glass)),
              Node.leaf("#{id}/left", 'balcony', Boxes.on_facade(facade, u0, u0 + BOW_PANE_M, z0, top, d + BOW_POST_M, 0.0, glass)),
              Node.leaf("#{id}/right", 'balcony', Boxes.on_facade(facade, u1 - BOW_PANE_M, u1, z0, top, d + BOW_POST_M, 0.0, glass)),
              Node.leaf("#{id}/post/0", 'balcony', Boxes.on_facade(facade, u0, u0 + BOW_POST_M, z0, top, d, d + BOW_POST_M, frames)),
              Node.leaf("#{id}/post/1", 'balcony', Boxes.on_facade(facade, u1 - BOW_POST_M, u1, z0, top, d, d + BOW_POST_M, frames))
            ]
            parts << Node.leaf("#{id}/roof", 'balcony', Boxes.on_facade(facade, u0, u1, top, top + BOW_SLAB_M, d, 0.0, wall)) unless above
            parts
          end
        end
      end
      private_class_method :bow_windows

      # --- Bandeaux, tourelle, balconnets (AG-143, ADR-68)

      # Façades qui reçoivent un bandeau : en rangée, les murs latéraux sont mitoyens.
      def band_facades(footprint, row)
        row ? %w[front rear] : %w[front right rear left]
      end
      private_class_method :band_facades

      # Cotes des bandeaux : chaque plancher d'étage (sauf sous un balcon) et l'égout (sauf corniche, génoise).
      def band_zs(levels, config, balcony_levels)
        floors = levels.drop(1).reject { |l| balcony_levels.include?(l) }.map(&:base_z_m)
        top = config['features']['cornice'] || config['features']['genoise'] ? [] : [Core::Quant.q(levels.last.top_z_m - BAND_HALF_M)]
        floors + top
      end
      private_class_method :band_zs

      def band_problems(footprint, levels, openings, config, row, balcony_levels, bows)
        out = []
        out << Core::Diagnostic.error('E_OPENING_CLEARANCE', '/features/string_courses', reason: 'string_courses_with_timber') if config['features']['timber_frame']
        zs = band_zs(levels, config, balcony_levels)
        facades = band_facades(footprint, row)
        openings.each do |o|
          next unless facades.include?(o.facade_id)
          next unless zs.any? { |z| o.z_max_m > z - BAND_HALF_M + EPS && o.z_min_m < z + BAND_HALF_M - EPS }

          out << Core::Diagnostic.error('E_OPENING_CLEARANCE', '/features/string_courses', reason: 'string_course_over_opening', id: o.id)
        end
        out
      end
      private_class_method :band_problems

      # Cordon de 20 cm, en saillie de 4 cm ; devant et derrière, il couvre l'angle des murs libres.
      # Le bandeau s'interrompt au droit d'un bow-window qu'il croiserait (dalles comprises).
      def string_courses(footprint, levels, config, row, balcony_levels, bows = [])
        material = config['materials']['surrounds'] || config['materials']['wall']
        by_level = levels.to_h { |l| [l.index, l] }
        gaps = bows.group_by(&:bay_index).map do |_, column|
          low = column.map { |o| by_level[o.level_index].base_z_m }.min - BOW_SLAB_M
          high = column.map { |o| by_level[o.level_index].top_z_m }.max + BOW_SLAB_M
          [column.map(&:u_min_m).min - BOW_SIDE_M, column.map(&:u_max_m).max + BOW_SIDE_M, low, high]
        end
        band_facades(footprint, row).flat_map do |id|
          facade = footprint.facade(id)
          over = !row && %w[front rear].include?(id) ? BAND_DEPTH_M : 0.0
          band_zs(levels, config, balcony_levels).each_with_index.flat_map do |z, k|
            cuts = id == 'front' ? gaps.select { |_, _, lo, hi| z + BAND_HALF_M > lo && z - BAND_HALF_M < hi }.map { |u0, u1, _, _| [u0, u1] }.sort : []
            spans = [[-over, facade.length_m + over]]
            cuts.each { |c0, c1| spans = spans.flat_map { |a, b| [[a, [b, c0].min], [[a, c1].max, b]].select { |s0, s1| s1 - s0 > Core::Quant::MIN_EDGE_M } } }
            spans.each_with_index.map do |(a, b), n|
              Node.leaf(n.zero? ? "band/#{id}/#{k}" : "band/#{id}/#{k}/#{n}", 'cornice',
                        Boxes.on_facade(facade, a, b, z - BAND_HALF_M, z + BAND_HALF_M, -BAND_DEPTH_M, 0.0, material))
            end
          end
        end
      end
      private_class_method :string_courses

      # Tour carrée centrée sur l'angle avant gauche, un étage plus haute que l'égout, flèche d'ardoise.
      def turret_box
        half = TURRET_SIDE_M / 2.0
        [-half, half, -half, half]
      end
      private_class_method :turret_box

      def turret_problems(footprint, openings)
        x0, x1, y0, y1 = turret_box
        openings.filter_map do |o|
          next unless %w[front left].include?(o.facade_id)

          facade = footprint.facade(o.facade_id)
          p = facade.point(o.u_min_m, 0.0)
          q = facade.point(o.u_max_m, 0.0)
          xs = [p[0], q[0]].minmax
          ys = [p[1], q[1]].minmax
          next unless xs[1] > x0 - TURRET_CLEAR_M && xs[0] < x1 + TURRET_CLEAR_M && ys[1] > y0 - TURRET_CLEAR_M && ys[0] < y1 + TURRET_CLEAR_M

          Core::Diagnostic.error('E_OPENING_CLEARANCE', '/features/turret', reason: 'turret_over_opening', id: o.id)
        end
      end
      private_class_method :turret_problems

      def turret_nodes(levels, config)
        x0, x1, y0, y1 = turret_box
        last = levels.last
        storey = last.top_z_m - last.base_z_m
        top = Core::Quant.q(last.top_z_m + storey)
        wall = config['materials']['wall']
        roof = config['materials']['roof']
        glass = config['materials']['glass'] || 'glass'
        frames = config['materials']['frames']
        e = TURRET_EAVE_M
        apex = [0.0, 0.0, Core::Quant.q(top + (TURRET_SIDE_M * TURRET_SPIRE))]
        base = [[x0 - e, y0 - e], [x1 + e, y0 - e], [x1 + e, y1 + e], [x0 - e, y1 + e]].map { |x, y| [Core::Quant.q(x), Core::Quant.q(y), top] }
        spire = MeshBuilder.new('solid')
        spire.add_face(base.reverse, roof)
        base.each_index { |i| spire.add_face([base[i], base[(i + 1) % 4], apex], roof) }
        nodes = [Node.leaf('turret/body', 'structure', Boxes.solid(x0, x1, y0, y1, 0.0, top, wall)),
                 Node.leaf('turret/spire', 'roof_face', spire.to_primitive)]
        bases = levels.map(&:base_z_m) + [last.top_z_m]
        bases.each_with_index do |z, k|
          sill = Core::Quant.q(z + 0.9)
          head = Core::Quant.q(sill + 1.2)
          next if head > top - 0.2

          nodes << Node.leaf("turret/frame/front/#{k}", 'frame', Boxes.solid(-0.4, 0.4, y0 - 0.03, y0, sill - 0.05, head + 0.05, frames))
          nodes << Node.leaf("turret/glass/front/#{k}", 'frame', Boxes.solid(-0.33, 0.33, y0 - 0.04, y0 - 0.03, sill, head, glass))
          nodes << Node.leaf("turret/frame/left/#{k}", 'frame', Boxes.solid(x0 - 0.03, x0, -0.4, 0.4, sill - 0.05, head + 0.05, frames))
          nodes << Node.leaf("turret/glass/left/#{k}", 'frame', Boxes.solid(x0 - 0.04, x0 - 0.03, -0.33, 0.33, sill, head, glass))
        end
        nodes
      end
      private_class_method :turret_nodes

      def balconette_problems(balcony_levels)
        return [] if balcony_levels.empty?

        [Core::Diagnostic.error('E_OPENING_CLEARANCE', '/features/balconettes', reason: 'balconettes_with_balcony')]
      end
      private_class_method :balconette_problems

      # Devant chaque fenêtre d'étage en façade (hors bow-window) : dalle de pierre et ferronnerie noire.
      def balconettes(footprint, openings, config, bows)
        facade = footprint.facade('front')
        stone = config['materials']['surrounds'] || config['materials']['wall']
        iron = 'dark_metal'
        skip = bows.map(&:id)
        d = -BALCONETTE_DEPTH_M
        b = BALCONETTE_BAR_M
        front(openings).select { |o| o.kind == 'window' && o.level_index >= 1 && !skip.include?(o.id) }.flat_map do |o|
          id = "balconette/#{o.level_index}/#{o.bay_index}"
          z = o.z_min_m
          rail = Core::Quant.q(z + BALCONETTE_RAIL_M)
          u0 = o.u_min_m
          u1 = o.u_max_m
          parts = [
            Node.leaf("#{id}/slab", 'balcony', Boxes.on_facade(facade, u0, u1, z - BALCONETTE_SLAB_M, z, d, 0.0, stone)),
            Node.leaf("#{id}/rail/front", 'balcony', Boxes.on_facade(facade, u0, u1, rail - b, rail, d, d + b, iron)),
            Node.leaf("#{id}/rail/left", 'balcony', Boxes.on_facade(facade, u0, u0 + b, rail - b, rail, d + b, 0.0, iron)),
            Node.leaf("#{id}/rail/right", 'balcony', Boxes.on_facade(facade, u1 - b, u1, rail - b, rail, d + b, 0.0, iron))
          ]
          count = ((u1 - u0) / BALCONETTE_SPACING_M).floor
          (0..count).each do |k|
            u = Core::Quant.q([u0 + (k * BALCONETTE_SPACING_M), u1 - b].min)
            parts << Node.leaf("#{id}/bar/#{k}", 'balcony', Boxes.on_facade(facade, u, u + b, z, rail - b, d, d + b, iron))
          end
          parts
        end
      end
      private_class_method :balconettes

      def rect_ring(footprint, margin, depth)
        x0 = margin
        x1 = footprint.width_m - margin
        [[x0, -depth], [x1, -depth], [x1, 0.0], [x0, 0.0]]
      end
      private_class_method :rect_ring

      # Bande de largeur `width` à gauche du segment p→q (vers l'intérieur d'un contour antihoraire).
      def band(p, q, width)
        length = Math.hypot(q[0] - p[0], q[1] - p[1])
        n = [-(q[1] - p[1]) / length * width, (q[0] - p[0]) / length * width]
        [p, q, [q[0] + n[0], q[1] + n[1]], [p[0] + n[0], p[1] + n[1]]].map { |x, y| [Core::Quant.q(x), Core::Quant.q(y)] }
      end
      private_class_method :band

      # Instances d'un barreau carré, centrées dans la bande de la main courante.
      def bars(p, q, z, material, definitions)
        height = Core::Quant.q(RAIL_HEIGHT_M - RAIL_TOP_M)
        id = "balcony/bar/#{micrometres(height)}/#{material}"
        half = BAR_M / 2.0
        definitions[id] ||= [Node.leaf('bar', 'balcony', Boxes.solid(-half, half, -half, half, 0.0, height, material))]
        length = Math.hypot(q[0] - p[0], q[1] - p[1])
        count = (length / BAR_SPACING_M).floor
        return [] if count < 1

        inward = [-(q[1] - p[1]) / length * (RAIL_TOP_M / 2.0), (q[0] - p[0]) / length * (RAIL_TOP_M / 2.0)]
        step = length / count
        (0...count).map do |k|
          t = ((k + 0.5) * step) / length
          x = p[0] + ((q[0] - p[0]) * t) + inward[0]
          y = p[1] + ((q[1] - p[1]) * t) + inward[1]
          { 'type' => 'instance', 'definition_id' => id, 'matrix' => [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, x, y, z, 1.0].map { |c| Core::Quant.q(c) } }
        end
      end
      private_class_method :bars

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
      # Souches réellement posées (nombre et côté tirés par la seed).
      def drawn_spots(footprint, config, row, cross = false)
        seed = config['seed']
        count = Core::DeterministicRandom.unit(seed, 'chimneys') < 0.5 ? 1 : 2
        spots = cross ? cross_spots(footprint, config) : chimney_spots(footprint, config, row)
        spots = [spots[Core::DeterministicRandom.unit(seed, 'chimneys/side') < 0.5 ? 0 : -1]] if count == 1 || spots.size == 1
        spots.uniq
      end
      private_class_method :drawn_spots

      # Emprises au sol des souches, couronnement compris, pour les lucarnes (AG-072).
      def chimney_boxes(footprint, config, row)
        return [] unless config['features']['chimneys']

        reach = [CHIMNEY_X_M / 2.0, CHIMNEY_Y_M / 2.0].map { |half| half + CHIMNEY_CAP_M }
        drawn_spots(footprint, config, row).map { |x, y| [[x - reach[0], x + reach[0]], [y - reach[1], y + reach[1]]] }
      end
      private_class_method :chimney_boxes

      # AG-079 : au faîtage perpendiculaire, contre les murs avant et arrière.
      def cross_spots(footprint, config)
        inner = config['structure']['wall_m'] + CHIMNEY_GAP_M + (CHIMNEY_Y_M / 2.0)
        x = footprint.width_m / 2.0
        [[x, inner], [x, footprint.depth_m - inner]]
      end
      private_class_method :cross_spots

      def chimneys(footprint, levels, config, roof_top, row, cross = false)
        spots = drawn_spots(footprint, config, row, cross)
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

      # AG-072 : volume de chaque lucarne et sa fenêtre, même définition partagée qu'une fenêtre.
      def dormer_nodes(footprint, levels, config, dormers, definitions)
        material = config['materials']['frames']
        glass = config['features']['glazing'] ? config['materials']['glass'] : nil
        rows = glass && config['features']['muntins'] ? config['facade']['muntin_rows'] : nil
        width = config['facade']['window_width_m']
        facade = footprint.facade('front')
        top = levels.last.top_z_m
        dormers.flat_map do |dormer|
          u0 = Core::Quant.q(((dormer.x0 + dormer.x1) / 2.0) - (width / 2.0))
          window = Opening.new(id: dormer.id, facade_id: 'front', level_index: levels.size, bay_index: 0, kind: 'window',
                               u_min_m: u0, u_max_m: Core::Quant.q(u0 + width), z_min_m: dormer.sill_z, z_max_m: Core::Quant.q(dormer.sill_z + dormer.window_height))
          definition_id = frame_definition(window, material, glass, definitions, nil, rows)
          [DormerSolver.body(dormer, top, width, config),
           Node.leaf("frame/#{dormer.id}", 'frame', { 'type' => 'instance', 'definition_id' => definition_id, 'matrix' => placement_matrix(facade, u0, dormer.sill_z, dormer.y_front) })]
        end
      end
      private_class_method :dormer_nodes

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
