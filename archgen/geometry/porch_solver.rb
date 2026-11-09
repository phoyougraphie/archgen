# frozen_string_literal: true

module Archgen
  module Geometry
    # Porche d'un bâtiment de rangée (docs/ENSEMBLE_CONTRACT.md, Accès à la cour) : un passage
    # au RDC, de la façade à l'arrière, sous les étages. Toujours sur une parcelle droite.
    module PorchSolver
      EPS = Core::Quant::EPSILON
      CLEARANCE = Core::Quant::CLEARANCE_M

      module_function

      # Retire les baies de RDC recouvertes et ajoute le passage en façade et à l'arrière.
      def call(openings, footprint:, levels:, config:, porch:)
        problems = room_problems(footprint, levels, config, porch)
        return Core::Result.fail(problems) unless problems.empty?

        low, high = span(footprint, porch)
        kept = openings.filter_map { |o| o.level_index.zero? && covered?(o, low, high) ? trimmed(o, low, high) : o }
        passages = %w[front rear].map { |side| opening(side, low, high, porch) }
        Core::Result.ok(OpeningSolver.sort(kept + passages))
      end

      # Deux parois et un plafond. En Structural, ils s'arrêtent aux faces intérieures des murs.
      def passage_node(footprint, porch, config)
        low, high = span(footprint, porch)
        wall = config['mode'] == 'structural' ? config['structure']['wall_m'] : 0.0
        y0 = wall
        y1 = footprint.depth_m - wall
        h = porch['height_m']
        material = config['materials']['wall']
        mesh = MeshBuilder.new('surface')
        mesh.add_face([[low, y0, 0.0], [low, y1, 0.0], [low, y1, h], [low, y0, h]], material)
        mesh.add_face([[high, y1, 0.0], [high, y0, 0.0], [high, y0, h], [high, y1, h]], material)
        mesh.add_face([[low, y0, h], [low, y1, h], [high, y1, h], [high, y0, h]], material)
        Node.leaf('wall/passage', 'wall', mesh.to_primitive)
      end

      def span(footprint, porch)
        middle = footprint.width_m / 2.0
        half = porch['width_m'] / 2.0
        [Core::Quant.q(middle - half), Core::Quant.q(middle + half)]
      end

      def room_problems(footprint, levels, config, porch)
        problems = []
        low, high = span(footprint, porch)
        end_clearance = config['structure']['wall_m'] + CLEARANCE
        if low < end_clearance - EPS || footprint.width_m - high < end_clearance - EPS
          problems << Core::Diagnostic.error('E_STREET_ACCESS', '/access/width_m', reason: 'porch_no_room', limit: end_clearance)
        end
        limit = height_limit(levels, config)
        problems << Core::Diagnostic.error('E_STREET_ACCESS', '/access/height_m', reason: 'porch_too_high', limit: limit, value: porch['height_m']) if porch['height_m'] > limit + EPS
        problems
      end
      private_class_method :room_problems

      # Sous le plafond du RDC : même règle qu'une baie du même niveau.
      def height_limit(levels, config)
        first = levels.first
        slab = levels.size > 1 ? config['structure']['slab_m'] : 0.0
        Core::Quant.q(first.top_z_m - slab - CLEARANCE)
      end
      private_class_method :height_limit

      # AG-065 : une vitrine s'arrête à CLEARANCE du passage, du côté de son milieu, si elle garde
      # sa largeur minimale ; sinon elle est retirée comme une baie. Une baie recouverte est retirée.
      def trimmed(opening, low, high)
        return nil unless opening.kind == 'shopfront' && opening.facade_id == 'front'

        middle = (opening.u_min_m + opening.u_max_m) / 2.0
        bounds = if middle < (low + high) / 2.0
                   [opening.u_min_m, [opening.u_max_m, Core::Quant.q(low - CLEARANCE)].min]
                 else
                   [[opening.u_min_m, Core::Quant.q(high + CLEARANCE)].max, opening.u_max_m]
                 end
        return nil if bounds[1] - bounds[0] < OpeningSolver::SHOPFRONT_MIN_WIDTH_M - EPS

        opening.dup.tap do |copy|
          copy.u_min_m = bounds[0]
          copy.u_max_m = bounds[1]
        end
      end
      private_class_method :trimmed

      def covered?(opening, low, high)
        opening.u_max_m > low - CLEARANCE + EPS && opening.u_min_m < high + CLEARANCE - EPS
      end
      private_class_method :covered?

      # La travée -1 trie le passage avant les baies du RDC : c'est une ouverture à part.
      def opening(side, low, high, porch)
        Opening.new(id: "opening/#{side}/0/porch", facade_id: side, level_index: 0, bay_index: -1, kind: 'porch',
                    u_min_m: low, u_max_m: high, z_min_m: 0.0, z_max_m: Core::Quant.q(porch['height_m']))
      end
      private_class_method :opening
    end
  end
end
