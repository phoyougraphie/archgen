# frozen_string_literal: true

module Archgen
  module Geometry
    # Positions candidates à pas constant : P = (L−2M)/N, u = M + (i+0,5)P.
    module FacadeSolver
      module_function

      def call(footprint, levels, facade)
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
          pitch = (side.length_m - (2 * margin)) / bays
          levels.flat_map do |level|
            (0...bays).map do |bay|
              Candidate.new(facade_id: side.id, level_index: level.index, bay_index: bay,
                            center_u_m: margin + ((bay + 0.5) * pitch))
            end
          end
        end
        problems.empty? ? Core::Result.ok(candidates) : Core::Result.fail(problems)
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
