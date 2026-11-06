# frozen_string_literal: true

module Archgen
  module UI
    # Liaison entre le panneau de rue, le tracé en cours et le service d'ensemble. Le tracé ne
    # vient que de l'outil : le panneau n'envoie que des réglages, jamais de géométrie.
    class StreetController
      PROTOCOL = 1
      ACTIONS = %w[init preview create clear].freeze
      PAYLOAD_KEYS = { 'init' => [], 'preview' => %w[settings], 'create' => %w[settings ensemble_digest], 'clear' => [] }.freeze
      MAX_REQUEST_ID = 64
      MAX_REMEMBERED = 32
      DEFAULT_SETTINGS = {
        'building' => { 'profile' => { 'id' => 'haussmann' }, 'mode' => 'shell', 'lod' => 0 },
        'parcel' => { 'target_width_m' => 12.0, 'depth_m' => 9.0, 'bay_width_m' => 3.0 },
        'layout' => { 'street_width_m' => 12.0 }
      }.freeze

      attr_reader :session
      # La page peut se charger après l'activation de l'outil : `init` lui redonne cet état.
      attr_writer :tool_active

      def initialize(service:, session:, registry:, model_provider:)
        @service = service
        @session = session
        @registry = registry
        @model_provider = model_provider
        @settings = DEFAULT_SETTINGS
        @mutations = {}
        @busy = false
        @overlay = {}
      end

      # Contours à dessiner dans la vue, en mètres dans le repère du modèle.
      attr_reader :overlay

      def dispatch(raw)
        parsed = Core::StrictJson.parse(raw)
        return respond(nil, parsed) unless parsed.ok?

        envelope = parsed.value
        request_id = safe_request_id(envelope)
        problem = envelope_problem(envelope)
        return respond(request_id, failure('E_SCHEMA', '/request', problem)) if problem
        return perform_create(request_id, envelope['payload']) if envelope['action'] == 'create'

        respond(request_id, perform(envelope['action'], envelope['payload']))
      rescue StandardError => e
        respond(request_id, failure('E_WRITE', '/model', 'internal_error', error: e.class.name))
      end

      # L'outil a changé le tracé : le panneau reçoit cet état, sans requête.
      def state
        refresh.then { |result| { 'ok' => result.ok?, 'result' => result.value, 'diagnostics' => result.diagnostics.map { |d| Messages.to_h(d) } } }
      end

      def close_session
        @session.clear
        @overlay = {}
        @mutations.clear
      end

      def document_changed
        @session.clear
        @overlay = {}
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
        return 'invalid_envelope' if PAYLOAD_KEYS.fetch(envelope['action']).include?('settings') && !payload['settings'].is_a?(Hash)

        nil
      end

      def failure(code, path, reason, **params)
        Core::Result.fail([Core::Diagnostic.error(code, path, reason: reason, **params)])
      end

      def perform(action, payload)
        case action
        when 'init' then init
        when 'preview' then preview(payload)
        when 'clear' then clear
        end
      end

      # Une page neuve recompte ses identifiants depuis le début : voir DialogController#init.
      def init
        @mutations.clear
        Core::Result.ok(
          'version' => VERSION,
          'profiles' => @registry.active_profiles.map { |p| { 'id' => p.id, 'label' => p.label } },
          'defaults' => DEFAULT_SETTINGS,
          'side' => @session.side,
          'tool_active' => @tool_active == true
        )
      end

      def preview(payload)
        remember(payload['settings'])
        refresh
      end

      def clear
        @session.clear
        refresh
      end

      def remember(settings)
        @session.side = settings.dig('layout', 'side') if Core::TraceSession::SIDES.include?(settings.dig('layout', 'side'))
        @settings = settings
      end

      def body(extra = {})
        { 'trace' => trace_state }.merge(extra)
      end

      def trace_state
        { 'state' => @session.state, 'closed' => @session.closed?, 'side' => @session.side, 'points' => @session.points.size,
          'length_m' => @session.empty? ? 0.0 : @session.length_m.round(2) }
      end

      # Ce que le panneau montre et ce que la vue dessine viennent du même calcul.
      def refresh
        @overlay = {}
        return Core::Result.ok(body) if @session.points.size < 2

        tree = tree_for(@settings)
        @overlay = overlay_for(tree)
        computed = @service.preview(tree: tree)
        unless computed.ok?
          @overlay = @overlay.merge(refused: true)
          # Le tracé reste affiché : un Result en erreur perdrait sa valeur.
          return Core::Result.ok(body('refused' => true, 'problems' => computed.errors.map { |d| Messages.to_h(d) }))
        end
        Core::Result.ok(body('metrics' => computed.value.plan['metrics'], 'ensemble_digest' => computed.value.ensemble_digest), computed.diagnostics)
      end

      def tree_for(settings)
        tree = settings.reject { |key, _| key == 'layout' }.merge('trace' => @session.trace)
        return tree if @session.closed?

        tree.merge('layout' => layout_for(settings))
      end

      def layout_for(settings)
        return { 'side' => @session.side } unless @session.side == 'both'

        width = settings.dig('layout', 'street_width_m')
        width ? { 'side' => 'both', 'street_width_m' => width } : { 'side' => 'both' }
      end

      def overlay_for(tree)
        settings = Composition.ensemble_intake.settings(tree)
        return {} unless settings.ok?

        layout = Geometry::ParcelLayout.call(settings.value)
        return {} unless layout.ok?

        first = @session.points.first
        { rings: layout.value['parcels'].map { |p| p['ring_m'].map { |x, y| [x + first[0], y + first[1]] } } }
      end

      def perform_create(request_id, payload)
        return @mutations[request_id] if @mutations.key?(request_id)
        return respond(request_id, failure('E_WRITE', '/model', 'operation_in_progress')) if @busy

        @busy = true
        begin
          response = respond(request_id, create(payload))
        ensure
          @busy = false
        end
        @mutations.shift while @mutations.size >= MAX_REMEMBERED
        @mutations[request_id] = response
      end

      def create(payload)
        return failure('E_TARGET_STALE', '/trace', 'trace_not_ready') unless @session.state == 'ready'

        remember(payload['settings'])
        tree = tree_for(@settings)
        computed = @service.preview(tree: tree)
        return computed unless computed.ok?
        return failure('E_CONFIRMATION_STALE', '/ensemble_digest', 'preview_changed') unless computed.value.ensemble_digest == payload['ensemble_digest']

        model = @model_provider.call
        created = @service.create(model: model, tree: tree, origin_m: @session.origin_m)
        return created unless created.ok?

        select_root(model, created.value.persistent_id)
        @session.clear
        @overlay = {}
        Core::Result.ok(body('created' => { 'persistent_id' => created.value.persistent_id, 'metrics' => created.value.metrics }), created.diagnostics)
      end

      def select_root(model, persistent_id)
        entity = model.find_entity_by_persistent_id(persistent_id)
        model.selection.clear
        model.selection.add(entity)
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
