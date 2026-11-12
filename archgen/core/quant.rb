# frozen_string_literal: true

module Archgen
  module Core
    # Quantification canonique des coordonnées (contrat géométrique, Repères).
    module Quant
      EPSILON = 1e-6
      SCALE = 1_000_000
      MIN_EDGE_M = 0.002
      CLEARANCE_M = 0.10

      module_function

      # Float#round arrondit le demi loin de zéro ; l'entier 0 élimine -0.
      def q(value)
        (value * SCALE).round / SCALE.to_f
      end

      def q3(point)
        point.map { |c| q(c) }
      end
    end
  end
end
