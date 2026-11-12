# frozen_string_literal: true

require 'securerandom'

module Archgen
  module UI
    # Confirmation de remplacement : une seule active, valable 120 s, à usage unique,
    # liée à la cible et au brouillon exact. Elle est consommée avant toute écriture.
    class ConfirmationTokens
      TTL_S = 120

      attr_writer :clock

      def initialize(generator: -> { SecureRandom.hex(16) }, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @generator = generator
        @clock = clock
        @active = nil
      end

      # Une nouvelle prévisualisation valide remplace la confirmation précédente.
      def issue(target_token:, draft_digest:)
        token = @generator.call
        @active = { token: token, target_token: target_token, draft_digest: draft_digest, expires_at: @clock.call + TTL_S }
        token
      end

      # Un jeton inconnu ne brûle pas la confirmation active : seul le bon jeton la consomme.
      def consume(token, target_token:, draft_digest:)
        active = @active
        return stale('confirmation_unknown') unless active && token.is_a?(String) && token == active[:token]

        @active = nil
        return stale('confirmation_expired') if @clock.call > active[:expires_at]
        return stale('confirmation_mismatch') unless active[:target_token] == target_token && active[:draft_digest] == draft_digest

        Core::Result.ok(true)
      end

      def clear
        @active = nil
      end

      private

      def stale(reason)
        Core::Result.fail([Core::Diagnostic.error('E_CONFIRMATION_STALE', '/confirmation_token', reason: reason)])
      end
    end
  end
end
