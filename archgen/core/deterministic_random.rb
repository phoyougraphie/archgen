# frozen_string_literal: true

require 'digest/sha2'

module Archgen
  module Core
    # Tirages stables par clé sémantique : indépendants de l'ordre de parcours,
    # sans état et sans aléatoire global (contrat géométrique, Placement, point 3).
    module DeterministicRandom
      PREFIX = 'archgen-rng-v1'
      HEX_CHARS = 13
      DIVISOR = (2**52).to_f

      module_function

      def hex(seed, key)
        raise ArgumentError, 'Graine hors plage' unless seed.is_a?(Integer) && seed.between?(0, 0xFFFF_FFFF)
        raise ArgumentError, 'Clé non ASCII' unless key.is_a?(String) && key.ascii_only?

        Digest::SHA256.hexdigest("#{PREFIX}:#{seed}:#{key}")[0, HEX_CHARS]
      end

      # Float dans [0, 1[.
      def unit(seed, key)
        hex(seed, key).to_i(16) / DIVISOR
      end

      def opening_key(side, level, bay)
        "opening/#{side}/#{level}/#{bay}/u"
      end

      def feature_key(feature)
        "feature/#{feature}"
      end
    end
  end
end
