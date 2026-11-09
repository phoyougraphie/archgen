# frozen_string_literal: true

module Archgen
  module UI
    # Liaison entre le panneau de rue, le tracé en cours et le service d'ensemble. Le tracé ne
    # vient que de l'outil : le panneau n'envoie que des réglages, jamais de géométrie.
    class StreetController
      PROTOCOL = 1
      ACTIONS = %w[init preview create clear load_selection edit_preview regenerate retain_terrain site_preview adapt_site remove_site].freeze
      MUTATIONS = %w[create regenerate adapt_site remove_site].freeze
      PAYLOAD_KEYS = {
        'init' => [], 'preview' => %w[settings], 'create' => %w[settings ensemble_digest], 'clear' => [],
        'load_selection' => [], 'edit_preview' => %w[settings], 'regenerate' => %w[settings ensemble_digest],
        'retain_terrain' => [], 'site_preview' => %w[site], 'adapt_site' => %w[site site_digest], 'remove_site' => []
      }.freeze
      MAX_REQUEST_ID = 64
      # Toits qu'une rangée peut tirer (D-14) ; la croupe reste refusée en rangée.
      VARIETY_ROOFS = %w[flat gable mansard].freeze
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
        @terrain = nil
        @mutations.clear
      end

      def document_changed
        forget
        @terrain = nil
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
        return 'invalid_envelope' if PAYLOAD_KEYS.fetch(envelope['action']).include?('site') && !payload['site'].is_a?(Hash)

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
        when 'retain_terrain' then retain_terrain
        when 'site_preview' then site_preview(payload)
        end
      end

      # Une page neuve recompte ses identifiants depuis le début : voir DialogController#init.
      def init
        @mutations.clear
        Core::Result.ok(
          'version' => VERSION,
          'profiles' => ordered_profiles.map { |p| { 'id' => p.id, 'label' => p.label, 'family' => family_label(p) }.merge(variety_hints(p)) },
          'defaults' => DEFAULT_SETTINGS,
          'side' => @session.side,
          'tool_active' => @tool_active == true,
          'site_defaults' => Core::SiteIntake::DEFAULTS,
          'site_materials' => Composition.materials.fetch('materials').map { |id, entry| { 'id' => id, 'label' => entry['label'] } },
          'mode' => @mode
        )
      end

      # Ce que le style dit des rues variées : ses toits, et sa fourchette de niveaux s'il en a une.
      # Le panneau coche ces toits par défaut ; les autres restent proposés, marqués hors style.
      def variety_hints(profile)
        roofs = profile.rules.find { |r| r['rule'] == 'roof_type' }&.dig('params', 'values')
        levels = profile.rules.find { |r| r['rule'] == 'level_count' }&.fetch('params')
        out = { 'roofs' => roofs ? VARIETY_ROOFS & roofs : VARIETY_ROOFS }
        out['details'] = details_hints(profile)
        levels ? out.merge('levels' => { 'min' => levels['min'], 'max' => levels['max'] }) : out
      end

      # AG-078 : même ordre et mêmes familles que le panneau du bâtiment.
      def ordered_profiles
        order = Messages::SIGNATURES.keys
        @registry.active_profiles.sort_by { |p| order.index(p.id) || order.size }
      end

      def family_label(profile)
        family = @registry.fetch(profile.family_id, allow_internal: true)
        family.ok? ? family.value.label : ''
      end

      # AG-067 : ce que le style coche lui-même, pour les cases Détails d'une rue laissées telles quelles.
      def details_hints(profile)
        features = profile.defaults.fetch('features', {})
        { 'revision' => profile.revision, 'glazing' => features['glazing'] == true, 'chimneys' => features['chimneys'] == true,
        'muntins' => features['muntins'] == true, 'shutters' => features['shutters'] == true, 'dormers' => features['dormers'] == true,
        'genoise' => features['genoise'] == true, 'stepped_gable' => features['stepped_gable'] == true, 'cladding' => features['cladding'] == true,
        'timber_frame' => features['timber_frame'] == true, 'classical' => features['classical'] == true,
          'shop_height_m' => profile.defaults.dig('shop', 'height_m') || Core::ConfigResolver::DEFAULT_SHOP_HEIGHT_M }
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
        Core::Result.ok(body({ 'metrics' => computed.value.plan['metrics'], 'variety' => computed.value.plan['variety'],
                               'ensemble_digest' => computed.value.ensemble_digest }.compact), computed.diagnostics)
      end

      def tree_for(settings)
        # Une case Varier décochée envoie `variety: null` : la rue garde alors un seul gabarit.
        tree = settings.reject { |key, value| %w[layout access].include?(key) || (key == 'variety' && value.nil?) }.merge('trace' => @session.trace)
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
          response = respond(request_id, mutate(action, payload))
        ensure
          @busy = false
        end
        @mutations.shift while @mutations.size >= MAX_REMEMBERED
        @mutations[request_id] = response
      end

      def mutate(action, payload)
        case action
        when 'create' then create(payload)
        when 'regenerate' then regenerate(payload)
        when 'adapt_site' then adapt_site(payload)
        when 'remove_site' then remove_site
        end
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

        status = @service.site_status(model: @model_provider.call, target: @edit_target)
        return status unless status.ok?

        @terrain = Adapters::SketchUp::TerrainRef.new(document_key: @model_provider.call.guid, persistent_id: status.value['terrain_pid']) if status.value && !@terrain
        Core::Result.ok(edit_body(computed.value, 'settings' => @edit_settings, 'revision' => @edit_target.revision, 'site' => site_state(status.value),
                                  'custom_count' => (@edit_settings['parcels'] || {}).size))
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
        Core::Result.ok(edit_body(computed.value, 'revision' => written.value.revision, 'written' => true), merged_warnings(written.diagnostics))
      end

      # --- Terrain : le jeton survit au rechargement, car il faut resélectionner l'ensemble.

      def retain_terrain
        retained = @service.retain_terrain(model: @model_provider.call)
        return retained unless retained.ok?

        @terrain = retained.value
        Core::Result.ok('retained' => true)
      end

      def site_preview(payload)
        return not_loaded unless @edit_target
        return failure('E_SITE_TERRAIN', '/site/terrain', 'terrain_not_retained') unless @terrain

        computed = @service.preview_site(model: @model_provider.call, target: @edit_target, terrain: @terrain, site: payload['site'])
        return computed unless computed.ok?

        metrics = computed.value.site_plan['metrics']
        Core::Result.ok({ 'site_digest' => computed.value.site_digest, 'metrics' => metrics, 'lines' => Messages.ensemble_site_lines(metrics) }, merged_warnings(computed.diagnostics))
      end

      def adapt_site(payload)
        return not_loaded unless @edit_target
        return failure('E_SITE_TERRAIN', '/site/terrain', 'terrain_not_retained') unless @terrain

        written = @service.adapt_to_site(model: @model_provider.call, target: @edit_target, terrain: @terrain, site: payload['site'], site_digest: payload['site_digest'])
        written.ok? ? site_written(written) : written
      end

      def remove_site
        return not_loaded unless @edit_target

        written = @service.remove_site(model: @model_provider.call, target: @edit_target)
        written.ok? ? site_written(written) : written
      end

      def site_written(written)
        @edit_target = written.value.target
        status = @service.site_status(model: @model_provider.call, target: @edit_target)
        Core::Result.ok({ 'revision' => written.value.revision, 'site' => site_state(status.ok? ? status.value : nil) }, merged_warnings(written.diagnostics))
      end

      def site_state(status)
        return { 'has_site' => false } unless status

        { 'has_site' => true, 'settings' => status['settings'], 'moved' => status['moved'] }
      end

      # 200 parcelles donneraient 200 lignes : les avertissements de terrain se résument par code.
      MERGED = { 'W_SITE_DOOR_GAP' => 'door_gap_many', 'W_SITE_BURIED' => 'terrain_above_many' }.freeze

      def merged_warnings(diagnostics)
        merged, others = diagnostics.partition { |d| MERGED.key?(d.code) }
        summaries = merged.group_by(&:code).map do |code, group|
          next group.first if group.size == 1

          Core::Diagnostic.warning(code, '/site/platform', reason: MERGED.fetch(code), count: group.size, value: group.map { |d| d.params['value'] }.max)
        end
        others + summaries
      end

      def edit_body(computed, extra = {})
        { 'metrics' => computed.plan['metrics'], 'variety' => computed.plan['variety'], 'ensemble_digest' => computed.ensemble_digest,
          'changed' => computed.ensemble_digest != @edit_target.ensemble_digest }.compact.merge(extra)
      end

      # Les réglages du panneau sur les réglages enregistrés. Le tracé ne change pas. La variété envoyée
      # remplace l'enregistrée en entier (sa liste de toits ne se fusionne pas) ; null la retire.
      # La graine ne change que si le panneau en envoie une.
      def edit_tree(settings)
        stored = @edit_settings
        tree = stored.reject { |key, _| %w[layout access].include?(key) }.merge(
          'building' => Core::Merge.leaves(stored['building'], settings.fetch('building', {})),
          'parcel' => Core::Merge.leaves(stored['parcel'], settings.fetch('parcel', {}))
        )
        # Même style : la révision enregistrée reste ; autre style : sa révision courante (AG-064).
        chosen = settings.dig('building', 'profile')
        tree['building'] = tree['building'].merge('profile' => chosen) if chosen && chosen['id'] != stored.dig('building', 'profile', 'id')
        tree['seed'] = settings['seed'] if settings.key?('seed')
        # AG-069 : le panneau de rue peut retirer tous les réglages propres (null), jamais en écrire.
        tree.delete('parcels') if settings.key?('parcels') && settings['parcels'].nil?
        if settings.key?('variety')
          settings['variety'].nil? ? tree.delete('variety') : tree['variety'] = settings['variety']
        end
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
