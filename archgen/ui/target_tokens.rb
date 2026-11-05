# frozen_string_literal: true

require 'securerandom'

module Archgen
  module UI
    # Jetons de cible opaques, limités à la session et au modèle. L'interface ne voit
    # jamais le PID. Le service revalide toujours la référence avant d'écrire.
    class TargetTokens
      MAX_ENTRIES = 64

      def initialize(generator: -> { SecureRandom.hex(16) })
        @generator = generator
        @entries = {}
      end

      def issue(target, model:)
        token = @generator.call
        @entries.shift while @entries.size >= MAX_ENTRIES
        @entries[token] = { target: target, model: model }
        token
      end

      # Retourne Result<TargetRef> : jeton inconnu ou lié à un autre modèle = cible périmée.
      def resolve(token, model:)
        entry = token.is_a?(String) ? @entries[token] : nil
        return stale('unknown_token') unless entry
        return stale('other_model') unless entry[:model] == model

        Core::Result.ok(entry[:target])
      end

      # Fermeture de session, changement de document, Undo ou Redo.
      def clear
        @entries.clear
      end

      private

      def stale(reason)
        Core::Result.fail([Core::Diagnostic.error('E_TARGET_STALE', '/target_token', reason: reason)])
      end
    end
  end
end
