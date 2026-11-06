# frozen_string_literal: true

module Archgen
  module UI
    # Liaison entre le panneau de rue, le tracé en cours et le service d'ensemble. Le tracé ne
    # vient que de l'outil : le panneau n'envoie que des réglages, jamais de géométrie.
    class StreetController
      PROTOCOL = 1
      ACTIONS = %w[init preview create clear load_selection edit_preview regenerate].freeze
      MUTATIONS = %w[create regenerate].freeze
      PAYLOAD_KEYS = {
        'init' => [], 'preview' => %w[settings], 'create' => %w[settings ensemble_digest], 'clear' => [],
        'load_selection' => [], 'edit_preview' => %w[settings], 'regenerate' => %w[settings ensemble_digest]
      }.freeze
      MAX_REQUEST_ID = 64
      MAX_REMEMBERED = 32
      DEFAULT_SETTINGS = {
        'building' => { 'profile' => { 'id' => 'haussmann' }, 'mode' => 'shell', 'lod' => 0 },
        'parcel' => { 'target_width_m' => 12.0, 'depth_m' => 9.0, 'bay_width_m' => 3.0 },
        'layout' => { 'street_width_m' => 12.0 },
        'access' => { 'count' => 'auto', 'width_m' => 3.5, 'height_m' => 2.7 }
      }.freeze

      attr_reader :session
      # La page peut se charger après l'activation de l'outil : `init` lui redonne cet état.
      attr_writer :tool_active
      attr_accessor :mode

      def initialize(service:, session:, registry:, model_provider:)
        @service = service
        @session = session
        @registry = registry
        @model_provider = model_provider
        @settings = DEFAULT_SETTINGS
        @mutations = {}
        @busy = false
        @overlay = {}
        @mode = 'new'
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
        return perform_mutation(request_id, envelope['action'], envelope['payload']) if MUTATIONS.include?(envelope['action'])

        respond(request_id, perform(envelope['action'], envelope['payload']))
      rescue StandardError => e
        respond(request_id, failure('E_WRITE', '/model', 'internal_error', error: e.class.name))
      end

      # L'outil a changé le tracé : le panneau reçoit cet état, sans requête.
      def state
        refresh.then { |result| { 'ok' => result.ok?, 'result' => result.value, 'diagnostics' => result.diagnostics.map { |d| Messages.to_h(d) } } }
      end

      def close_session
        forget
        @mutations.clear
      end

      def document_changed
        forget
      end

      private

      def forget
        @session.clear
        @overlay = {}
        @edit_target = nil
        @edit_settings = nil
      end

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
        when 'load_selection' then load_selection
        when 'edit_preview' then edit_preview(payload)
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
          'tool_active' => @tool_active == true,
          'mode' => @mode
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
        tree = settings.reject { |key, _| %w[layout access].include?(key) }.merge('trace' => @session.trace)
        return settings.key?('access') ? tree.merge('access' => settings['access']) : tree if @session.closed?

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

        layout = Core::EnsembleEngine.layout_for(settings.value, registry: @registry)
        # Un îlot pas encore constructible garde ses parcelles visibles, sans ses accès.
        layout = Geometry::ParcelLayout.call(settings.value) unless layout.ok?
        return {} unless layout.ok?

        first = @session.points.first
        { rings: (layout.value['parcels'].map { |p| p['ring_m'] } + porch_rings(layout.value['parcels'])).map { |ring| ring.map { |x, y| [x + first[0], y + first[1]] } } }
      end

      # Le passage se voit dans l'aperçu : son emprise, de la façade à l'arrière.
      def porch_rings(parcels)
        parcels.select { |p| p['porch'] }.map do |parcel|
          t = parcel['tangent']
          low = (parcel['width_m'] - parcel['porch']['width_m']) / 2.0
          high = low + parcel['porch']['width_m']
          [[low, 0.0], [high, 0.0], [high, parcel['depth_m']], [low, parcel['depth_m']]].map do |x, y|
            [parcel['origin_m'][0] + (x * t[0]) - (y * t[1]), parcel['origin_m'][1] + (x * t[1]) + (y * t[0])]
          end
        end
      end

      def perform_mutation(request_id, action, payload)
        return @mutations[request_id] if @mutations.key?(request_id)
        return respond(request_id, failure('E_WRITE', '/model', 'operation_in_progress')) if @busy

        @busy = true
        begin
          response = respond(request_id, action == 'create' ? create(payload) : regenerate(payload))
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

      # --- Modifier : la racine sélectionnée donne les réglages ; le tracé ne change pas.

      def load_selection
        forget
        loaded = @service.load_selection(model: @model_provider.call)
        return loaded unless loaded.ok?

        @edit_target = loaded.value.target
        @edit_settings = loaded.value.settings
        computed = @service.preview(tree: @edit_settings)
        return computed unless computed.ok?

        Core::Result.ok(edit_body(computed.value, 'settings' => @edit_settings, 'revision' => @edit_target.revision))
      end

      def edit_preview(payload)
        return not_loaded unless @edit_settings

        computed = @service.preview(tree: edit_tree(payload['settings']))
        return Core::Result.ok('refused' => true, 'problems' => computed.errors.map { |d| Messages.to_h(d) }) unless computed.ok?

        Core::Result.ok(edit_body(computed.value), computed.diagnostics)
      end

      def regenerate(payload)
        return not_loaded unless @edit_settings

        tree = edit_tree(payload['settings'])
        computed = @service.preview(tree: tree)
        return computed unless computed.ok?
        return failure('E_CONFIRMATION_STALE', '/ensemble_digest', 'preview_changed') unless computed.value.ensemble_digest == payload['ensemble_digest']

        written = @service.regenerate(model: @model_provider.call, target: @edit_target, replace: tree)
        return written unless written.ok?

        @edit_target = written.value.target
        @edit_settings = computed.value.settings
        Core::Result.ok(edit_body(computed.value, 'revision' => written.value.revision, 'written' => true), written.diagnostics)
      end

      def edit_body(computed, extra = {})
        { 'metrics' => computed.plan['metrics'], 'ensemble_digest' => computed.ensemble_digest,
          'changed' => computed.ensemble_digest != @edit_target.ensemble_digest }.merge(extra)
      end

      # Les réglages du panneau sur les réglages enregistrés. Le tracé et la seed ne changent pas.
      def edit_tree(settings)
        stored = @edit_settings
        tree = stored.reject { |key, _| %w[layout access].include?(key) }.merge(
          'building' => Core::Merge.leaves(stored['building'], settings.fetch('building', {})),
          'parcel' => Core::Merge.leaves(stored['parcel'], settings.fetch('parcel', {}))
        )
        return tree.merge('access' => Core::Merge.leaves(stored['access'], settings.fetch('access', {}))) if stored.dig('trace', 'closed')

        tree.merge('layout' => edit_layout(stored['layout'], settings.fetch('layout', {})))
      end

      def edit_layout(stored, changes)
        side = changes['side'] || stored['side']
        return { 'side' => side } unless side == 'both'

        { 'side' => 'both', 'street_width_m' => changes['street_width_m'] || stored.fetch('street_width_m', DEFAULT_SETTINGS.dig('layout', 'street_width_m')) }
      end

      def not_loaded
        failure('E_TARGET_STALE', '/target', 'edit_not_loaded')
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
