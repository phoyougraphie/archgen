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
        balcony_levels = features['balcony'] ? levels.select { |l| BALCONY_LEVELS.include?(l.index) } : []
        problems.concat(balcony_problems(config, balcony_levels, openings))
        problems.concat(fascia_problems(levels, openings)) if shop?(config)
        clashes = features['shutters'] ? shutter_clashes(footprint, openings, config) : {}
        problems.concat(shutter_problems(clashes))
        cross = ridge == 'perpendicular'
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
        fascia_node = shop?(config) ? fascia(footprint, levels, config) : nil
        nodes << fascia_node if fascia_node
        nodes += chimneys(footprint, levels, config, roof_top_z_m, row, cross) if features['chimneys'] && roof_top_z_m
        nodes += dormer_nodes(footprint, levels, config, dormers.value, definitions) if dormers
        built_balconies = features['balcony'] ? balconies(footprint, balcony_levels, config) : []
        nodes += built_balconies
        warnings = features['balcony'] && built_balconies.empty? ? [balcony_warning(balcony_levels)] : []
        warnings += dormers.warnings if dormers
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
        rows = glass && config['features']['muntins'] ? config['facade']['muntin_rows'] : nil
        wall = config['structure']['wall_m']
        recess = config['mode'] == 'structural' ? [FRAME_MAX_RECESS_M, wall - FRAME_BAR_M].min : 0.0
        entrance = entrance_u(openings)
        openings.reject { |opening| opening.kind == 'porch' }.map do |opening|
          definition_id = frame_definition(opening, material, glass, definitions, door_side(opening, entrance), rows)
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
        definitions[id] ||= frame_bars(opening.kind, width, height, material) + (glass ? joinery(opening.kind, width, height, material, glass, side) : []) +
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
                                    -BALCONY_DEPTH_M, 0.0, balcony_material(config)))
        end
      end
      private_class_method :balconies

      def mitred_balconies(footprint, balcony_levels, margin, config)
        ring = mitred_ring(footprint, margin, BALCONY_DEPTH_M)
        return [] unless ring

        balcony_levels.map do |level|
          Node.leaf("balcony/#{level.index}", 'balcony', Boxes.prism(ring, level.base_z_m - BALCONY_THICKNESS_M, level.base_z_m, balcony_material(config)))
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
