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
      CORNICE_DEPTH_M = 0.15
      CORNICE_HEIGHT_M = 0.08
      BALCONY_DEPTH_M = 0.90
      BALCONY_THICKNESS_M = 0.12
      BALCONY_LEVELS = [2, 5].freeze
      SURROUND_BAR_M = 0.04
      SURROUND_DEPTH_M = 0.03
      HEAD_MARGIN_M = 0.10
      EPS = Core::Quant::EPSILON

      module_function

      def call(footprint:, levels:, openings:, config:)
        return Core::Result.ok(DetailPlan.new(nodes: [], definitions: {})) unless config['lod'] == 1

        features = config['features']
        problems = []
        problems.concat(cornice_problems(config, levels, openings)) if features['cornice']
        balcony_levels = features['balcony'] ? levels.select { |l| BALCONY_LEVELS.include?(l.index) } : []
        problems.concat(balcony_problems(config, balcony_levels, openings))
        return Core::Result.fail(problems) unless problems.empty?

        definitions = {}
        nodes = frames(footprint, openings, config, definitions)
        nodes += surrounds(footprint, openings, config) if features['surrounds']
        nodes << cornice(footprint, levels, config) if features['cornice']
        built_balconies = features['balcony'] ? balconies(footprint, balcony_levels, config) : []
        nodes += built_balconies
        warnings = features['balcony'] && built_balconies.empty? ? [balcony_warning(balcony_levels)] : []
        Core::Result.ok(DetailPlan.new(nodes: nodes, definitions: definitions), warnings)
      end

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
        wall = config['structure']['wall_m']
        recess = config['mode'] == 'structural' ? [FRAME_MAX_RECESS_M, wall - FRAME_BAR_M].min : 0.0
        openings.map do |opening|
          definition_id = frame_definition(opening, material, definitions)
          facade = footprint.facade(opening.facade_id)
          Node.leaf("frame/#{opening.facade_id}/#{opening.level_index}/#{opening.bay_index}", 'frame',
                    { 'type' => 'instance', 'definition_id' => definition_id, 'matrix' => frame_matrix(facade, opening, recess) })
        end
      end
      private_class_method :frames

      # Une définition par type, largeur, hauteur et matériau : le recul vit dans la matrice.
      def frame_definition(opening, material, definitions)
        width = Core::Quant.q(opening.u_max_m - opening.u_min_m)
        height = Core::Quant.q(opening.z_max_m - opening.z_min_m)
        id = "frame/#{opening.kind}/#{micrometres(width)}x#{micrometres(height)}/#{material}"
        definitions[id] ||= frame_bars(opening.kind, width, height, material)
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
        bars['bottom'] = [bar, width - bar, 0.0, bar] if kind == 'window'
        bars.map do |name, (x0, x1, z0, z1)|
          Node.leaf("bar/#{name}", 'frame', Boxes.solid(x0, x1, 0.0, bar, z0, z1, material))
        end
      end
      private_class_method :frame_bars

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

      # De marge à marge, comme ailleurs, mais sans franchir l'onglet d'un angle rentrant.
      def mitred_balconies(footprint, balcony_levels, margin, config)
        y = -BALCONY_DEPTH_M
        near = [margin, footprint.width_m - margin]
        far = [[margin, footprint.left_x(y)].max, [footprint.width_m - margin, footprint.right_x(y)].min]
        return [] if far[1] - far[0] < Core::Quant::MIN_EDGE_M

        ring = [[far[0], y], [far[1], y], [near[1], 0.0], [near[0], 0.0]]
        balcony_levels.map do |level|
          Node.leaf("balcony/#{level.index}", 'balcony', Boxes.prism(ring, level.base_z_m - BALCONY_THICKNESS_M, level.base_z_m, config['materials']['wall']))
        end
      end
      private_class_method :mitred_balconies
    end
  end
end
