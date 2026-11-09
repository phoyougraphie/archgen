# frozen_string_literal: true

module Archgen
  module Geometry
    # Positions candidates à pas constant : P = (L−2M)/N, u = M + (i+0,5)P.
    module FacadeSolver
      module_function

      # `wall_m` : épaisseur des murs, nécessaire aux seules parcelles d'angle.
      def call(footprint, levels, facade, wall_m: nil)
        problems = []
        candidates = footprint.facades.flat_map do |side|
          bays = bay_count(side.id, facade)
          next [] if bays.zero?

          margin = facade['margin_m']
          unless side.length_m > (2 * margin) + Core::Quant::EPSILON
            problems << Core::Diagnostic.error('E_OPENING_CLEARANCE', '/facade/margin_m', reason: 'margin_exceeds_half_length',
                                               id: side.id, length: side.length_m, margin: margin)
            next []
          end
          start, pitch = frame(side, margin, bays, wall_m)
          levels.flat_map do |level|
            (0...bays).map do |bay|
              Candidate.new(facade_id: side.id, level_index: level.index, bay_index: bay,
                            center_u_m: start + ((bay + 0.5) * pitch))
            end
          end
        end
        problems.empty? ? Core::Result.ok(candidates) : Core::Result.fail(problems)
      end

      # Sur une parcelle d'angle, la trame se resserre entre les joints intérieurs : une baie ne
      # tombe pas dans un angle fermé. À angle droit, le calcul reste celui du contrat V1.
      def frame(side, margin, bays, wall_m)
        return [margin, (side.length_m - (2 * margin)) / bays] unless side.start_factor

        low = [margin, side.inner_start(wall_m)].max
        high = [side.length_m - margin, side.inner_end(wall_m)].min
        [low, (high - low) / bays]
      end

      # `rear_bays` n'existe que pour un bâtiment de rangée, dont l'arrière a sa propre longueur.
      def bay_count(side_id, facade)
        return facade.fetch('rear_bays', facade['front_bays']) if side_id == 'rear'

        side_id == 'front' ? facade['front_bays'] : facade['side_bays']
      end
      private_class_method :bay_count
    end
  end
end
