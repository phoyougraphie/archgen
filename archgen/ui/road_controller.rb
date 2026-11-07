# frozen_string_literal: true

module Archgen
  module UI
    # Liaison entre l'éditeur de coupe et le noyau (AG-038). L'éditeur n'écrit rien dans le
    # modèle : il compose une coupe, Ruby la juge et en calcule le dessin. Le panneau ne
    # reproduit aucune règle de plage ni de catalogue.
    class RoadController
      PROTOCOL = 1
      ACTIONS = %w[init preview].freeze
      PAYLOAD_KEYS = { 'init' => [], 'preview' => %w[profile] }.freeze
      MAX_REQUEST_ID = 64
      START_PRESET = 'ville'

      def initialize(intake:, bands:, items:, presets:)
        @intake = intake
        @bands = bands
        @items = items
        @presets = presets.fetch('presets')
        @profile = @presets.find { |p| p['id'] == START_PRESET }.fetch('profile')
      end

      def dispatch(raw)
        parsed = Core::StrictJson.parse(raw)
        return respond(nil, parsed) unless parsed.ok?

        envelope = parsed.value
        request_id = safe_request_id(envelope)
        problem = envelope_problem(envelope)
        return respond(request_id, failure(problem)) if problem

        respond(request_id, envelope['action'] == 'init' ? init : preview(envelope['payload']['profile']))
      rescue StandardError => e
        respond(request_id, Core::Result.fail([Core::Diagnostic.error('E_WRITE', '/model', reason: 'internal_error', error: e.class.name)]))
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

        payload = envelope['payload']
        return 'invalid_envelope' unless payload.is_a?(Hash) && (payload.keys - PAYLOAD_KEYS.fetch(envelope['action'])).empty?
        return 'invalid_envelope' if envelope['action'] == 'preview' && !payload['profile'].is_a?(Hash)

        nil
      end

      def failure(reason)
        Core::Result.fail([Core::Diagnostic.error('E_SCHEMA', '/request', reason: reason)])
      end

      # La page se recharge à chaque ouverture : elle retrouve la dernière coupe acceptée.
      def init
        Core::Result.ok(
          'version' => VERSION,
          'profile' => @profile,
          'presets' => @presets.map { |p| { 'id' => p['id'], 'name' => p.dig('profile', 'name'), 'profile' => p['profile'] } },
          'bands' => band_catalogue,
          'items' => item_catalogue
        )
      end

      def preview(profile)
        result = @intake.profile(profile)
        return result unless result.ok?

        @profile = result.value
        section = Geometry::RoadSection.call(result.value, bands: @bands, items: @items)
        Core::Result.ok({ 'profile' => result.value, 'section' => section }, result.diagnostics)
      end

      def band_catalogue
        @bands.fetch('bands').map do |type, e|
          { 'type' => type, 'label' => e['label'], 'default_width_m' => e['default_width_m'], 'min_width_m' => e['min_width_m'],
            'max_width_m' => e['max_width_m'], 'role' => e['role'], 'accepts_items' => e['accepts_items'] }
        end
      end

      def item_catalogue
        @items.fetch('items').map do |kind, e|
          { 'kind' => kind, 'label' => e['label'], 'variants' => e['variants'].map { |id, v| { 'id' => id, 'label' => v['label'] } },
            'default_variant' => e['default_variant'], 'default_height_m' => e['default_height_m'], 'repeat' => e['repeat'],
            'default_spacing_m' => e['default_spacing_m'], 'height_variation' => e['height_variation'] }
        end
      end

      def respond(request_id, result)
        {
          'v' => PROTOCOL, 'request_id' => request_id, 'ok' => result.ok?, 'result' => result.value,
          'diagnostics' => result.diagnostics.map { |d| Messages.to_h(d) }
        }
      end
    end
  end
end
