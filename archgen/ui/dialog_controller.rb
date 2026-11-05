# frozen_string_literal: true

module Archgen
  module UI
    # Liaison entre le panneau et le service. Toute entrée vient du pont JS, donc n'est
    # jamais crue : enveloppe, action et champs sont contrôlés ici, indépendamment du JS.
    class DialogController
      PROTOCOL = 1
      ACTIONS = %w[init load_selection preview].freeze
      PAYLOAD_KEYS = { 'init' => [], 'load_selection' => [], 'preview' => %w[draft target_token] }.freeze
      MAX_REQUEST_ID = 64

      attr_accessor :mode

      def initialize(service:, registry:, materials:, model_provider:, tokens: TargetTokens.new, mode: 'new')
        @service = service
        @registry = registry
        @materials = materials
        @model_provider = model_provider
        @tokens = tokens
        @mode = mode
      end

      # Reçoit toujours une chaîne JSON, retourne toujours une réponse sérialisable.
      def dispatch(raw)
        parsed = Core::StrictJson.parse(raw)
        return respond(nil, parsed) unless parsed.ok?

        envelope = parsed.value
        request_id = safe_request_id(envelope)
        problem = envelope_problem(envelope)
        return respond(request_id, invalid(problem)) if problem

        respond(request_id, perform(envelope['action'], envelope['payload']))
      rescue StandardError => e
        respond(request_id, failure('E_WRITE', '/model', 'internal_error', error: e.class.name))
      end

      private

      def safe_request_id(envelope)
        return nil unless envelope.is_a?(Hash)

        id = envelope['request_id']
        id.is_a?(String) && id.length <= MAX_REQUEST_ID ? id : nil
      end

      def envelope_problem(envelope)
        return 'invalid_envelope' unless envelope.is_a?(Hash) && (envelope.keys - %w[v request_id action payload]).empty?
        return 'unsupported_protocol' unless envelope['v'] == PROTOCOL
        return 'invalid_envelope' unless safe_request_id(envelope)
        return 'unknown_action' unless ACTIONS.include?(envelope['action'])
        return 'invalid_envelope' unless envelope['payload'].is_a?(Hash)
        return 'invalid_envelope' unless (envelope['payload'].keys - PAYLOAD_KEYS.fetch(envelope['action'])).empty?

        nil
      end

      def invalid(reason)
        failure('E_SCHEMA', '/request', reason)
      end

      def failure(code, path, reason, **params)
        Core::Result.fail([Core::Diagnostic.error(code, path, reason: reason, **params)])
      end

      def perform(action, payload)
        case action
        when 'init' then init
        when 'load_selection' then load_selection
        when 'preview' then preview(payload)
        end
      end

      def model
        @model_provider.call
      end

      def init
        Core::Result.ok(
          'mode' => @mode,
          'version' => VERSION,
          'profiles' => profiles,
          'materials' => @materials.map { |id, entry| { 'id' => id, 'label' => entry['label'], 'srgb' => entry['srgb'] } },
          'limits' => {
            'max_width_m' => Core::Limits::MAX_FOOTPRINT_M, 'max_levels' => Core::Limits::MAX_LEVELS,
            'max_wall_top_m' => Core::Limits::MAX_WALL_TOP_M, 'max_roof_top_m' => Core::Limits::MAX_ROOF_TOP_M
          }
        )
      end

      def profiles
        order = Messages::SIGNATURES.keys
        @registry.active_profiles.sort_by { |p| order.index(p.id) || order.size }.map do |profile|
          { 'id' => profile.id, 'revision' => profile.revision, 'label' => profile.label, 'signature' => Messages::SIGNATURES[profile.id].to_s }
        end
      end

      def load_selection
        current = model
        loaded = @service.load_selection(model: current)
        return loaded unless loaded.ok?

        value = loaded.value
        Core::Result.ok(
          { 'config' => value.config.to_h, 'revision' => value.record.metadata['revision'],
            'target_token' => @tokens.issue(value.target, model: current) },
          loaded.diagnostics
        )
      end

      def preview(payload)
        current = model
        target = resolve_target(payload['target_token'], current)
        return target unless target.ok?

        result = @service.preview(draft: payload['draft'], model: current, target: target.value)
        return result unless result.ok?

        value = result.value
        Core::Result.ok(
          { 'config' => value.config.to_h, 'projection' => value.projection, 'metrics' => value.plan['metrics'], 'plan_digest' => value.plan_digest },
          result.diagnostics
        )
      end

      def resolve_target(token, current)
        return Core::Result.ok(nil) if token.nil?

        @tokens.resolve(token, model: current)
      end

      def respond(request_id, result)
        {
          'v' => PROTOCOL,
          'request_id' => request_id,
          'ok' => result.ok?,
          'result' => result.value,
          'diagnostics' => result.diagnostics.map { |d| Messages.to_h(d) }
        }
      end
    end
  end
end
