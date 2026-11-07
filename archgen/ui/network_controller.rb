# frozen_string_literal: true

module Archgen
  module UI
    # Liaison entre le panneau de réseau, l'outil de tracé et NetworkService (AG-048). On trace les
    # voies une à une, chacune avec son type de coupe ; les carrefours naissent tout seuls et se règlent
    # ici. Ruby juge tout et calcule l'aperçu ; une écriture exige l'empreinte montrée.
    class NetworkController
      PROTOCOL = 1
      ACTIONS = %w[init add_road remove_road set_junction preview create clear load_selection regenerate].freeze
      MUTATIONS = %w[create regenerate].freeze
      PAYLOAD_KEYS = {
        'init' => [], 'add_road' => %w[preset axis radius_m], 'remove_road' => %w[id], 'set_junction' => %w[junction],
        'preview' => [], 'create' => %w[road_digest], 'clear' => [], 'load_selection' => [], 'regenerate' => %w[road_digest]
      }.freeze
      JUNCTION_KEYS = %w[id type corner_radius_m outer_radius_m ring_width_m pair].freeze
      MAX_REQUEST_ID = 64
      MAX_ROADS = 24
      DEFAULT_RADIUS_M = 20.0
      AXES = %w[center left right].freeze
      MAX_PLAN_FACES = 40_000

      attr_reader :session
      attr_accessor :mode, :tool_active

      def initialize(presets:, catalog:, service: nil, session: nil, model_provider: nil)
        @presets = presets.fetch('presets')
        @colors = catalog.transform_values { |m| m['srgb'] }
        @service = service
        @session = session || Core::TraceSession.new
        @model_provider = model_provider
        @mode = 'trace'
        reset
      end

      # Contours des voies déjà ajoutées, en mètres dans le repère du modèle, pour la vue.
      attr_reader :overlay

      def dispatch(raw)
        parsed = Core::StrictJson.parse(raw)
        return respond(nil, parsed) unless parsed.ok?

        envelope = parsed.value
        request_id = safe_request_id(envelope)
        problem = envelope_problem(envelope)
        return respond(request_id, failure('E_SCHEMA', '/request', problem)) if problem
        return @mutations[request_id] if MUTATIONS.include?(envelope['action']) && @mutations.key?(request_id)

        response = respond(request_id, perform(envelope['action'], envelope['payload']))
        @mutations[request_id] = response if MUTATIONS.include?(envelope['action'])
        response
      rescue StandardError => e
        respond(request_id, failure('E_WRITE', '/model', 'internal_error', error: e.class.name))
      end

      def trace_state
        { 'points' => @session.points.size, 'finished' => @session.finished?, 'length_m' => Core::Quant.q(@session.length_m) }
      end

      def close_session
        @session.clear
        reset
      end

      def document_changed
        close_session
      end

      private

      def reset
        @roads = []
        @junctions = []
        @edit = nil
        @overlay = {}
        @mutations = {}
        @next = 1
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

        nil
      end

      def failure(code, path, reason, **params)
        Core::Result.fail([Core::Diagnostic.error(code, path, reason: reason, **params)])
      end

      def perform(action, payload)
        case action
        when 'init' then init
        when 'add_road' then add_road(payload)
        when 'remove_road' then remove_road(payload)
        when 'set_junction' then set_junction(payload)
        when 'preview' then preview
        when 'create' then create(payload)
        when 'clear' then clear
        when 'load_selection' then load_selection
        when 'regenerate' then regenerate(payload)
        end
      end

      def init
        @mutations.clear
        Core::Result.ok(
          'version' => VERSION, 'mode' => @mode, 'tool_active' => @tool_active == true, 'writes' => !@service.nil?,
          'default_radius_m' => DEFAULT_RADIUS_M, 'presets' => @presets.map { |p| { 'id' => p['id'], 'name' => p.dig('profile', 'name') } },
          'trace' => trace_state, 'state' => state
        )
      end

      def state
        { 'roads' => @roads.map { |r| r.slice('id', 'preset', 'name', 'axis') }, 'junctions' => @junctions.map(&:dup), 'loaded' => !@edit.nil? }
      end

      # Ajoute la voie qu'on vient de tracer, avec son type de coupe.
      def add_road(payload)
        return failure('E_TARGET_STALE', '/trace', 'add_road_in_edit') if @mode == 'edit'
        return failure('E_TARGET_STALE', '/trace', 'trace_unfinished') unless @session.finished?
        return failure('E_ROAD_TRACE', '/roads', 'too_many_roads', limit: MAX_ROADS) if @roads.size >= MAX_ROADS

        preset = @presets.find { |p| p['id'] == payload['preset'] }
        return failure('E_SCHEMA', '/preset', 'enum', allowed: @presets.map { |p| p['id'] }) unless preset

        axis = payload.fetch('axis', 'center')
        return failure('E_SCHEMA', '/axis', 'enum', allowed: AXES) unless AXES.include?(axis)

        radius = payload.fetch('radius_m', DEFAULT_RADIUS_M)
        return failure('E_SCHEMA', '/radius_m', 'type', expected: 'number') unless radius.is_a?(Numeric)

        origin = @session.origin_m
        points = @session.relative_points.map { |x, y| [x + origin[0], y + origin[1]] }
        @roads << { 'id' => "v#{@next}", 'preset' => preset['id'], 'name' => preset.dig('profile', 'name'), 'profile' => preset['profile'],
                    'axis' => axis, 'radius_m' => radius, 'points' => points, 'z' => origin[2] }
        @next += 1
        @session.clear
        preview
      end

      # Retirer une voie retire aussi les réglages des carrefours qu'elle touchait.
      def remove_road(payload)
        index = @roads.index { |r| r['id'] == payload['id'] }
        return failure('E_SCHEMA', '/id', 'unknown_road') unless index
        return failure('E_TARGET_STALE', '/id', 'first_road_kept') if @mode == 'edit' && index.zero?

        id = @roads.delete_at(index)['id']
        @junctions.reject! { |j| j['id'].split('+').any? { |part| part.start_with?("#{id}@") } || j['pair'].to_s.split('+').any? { |part| part.start_with?("#{id}@") } }
        preview
      end

      # Un réglage par nœud ; « simple » sans autre réglage efface le réglage.
      def set_junction(payload)
        entry = payload['junction']
        return failure('E_SCHEMA', '/junction', 'type', expected: 'object') unless entry.is_a?(Hash) && entry['id'].is_a?(String)
        return failure('E_SCHEMA', '/junction', 'unknown_key') unless (entry.keys - JUNCTION_KEYS).empty?

        @junctions.reject! { |j| j['id'] == entry['id'] }
        kept = entry.compact
        @junctions << kept unless kept.keys == ['id'] || kept == { 'id' => entry['id'], 'type' => 'simple' }
        @junctions.sort_by! { |j| j['id'] }
        preview
      end

      def tree
        return nil if @roads.empty?

        origin = @roads.first['points'].first
        roads = @roads.map do |r|
          points = r['points'].map { |x, y| [Core::Quant.q(x - origin[0]), Core::Quant.q(y - origin[1])] }
          radii = r['radii_m'] || Array.new([points.size - 2, 0].max, r['radius_m'])
          { 'id' => r['id'], 'road' => (r['settings'] || {}).merge('trace' => { 'points_m' => points, 'radii_m' => radii },
                                                                  'axis' => r['axis'], 'profile' => r['profile']) }
        end
        { 'network_version' => 1, 'roads' => roads, 'junctions' => @junctions }
      end

      def preview
        t = tree
        @overlay = {}
        return Core::Result.ok('state' => state, 'network' => nil, 'trace' => trace_state) unless t && @service

        result = @service.preview(tree: t)
        @overlay = outline if @mode == 'trace'
        Core::Result.ok({ 'state' => state, 'network' => summary(result), 'trace' => trace_state })
      end

      def summary(result)
        diagnostics = result.diagnostics.map { |d| Messages.to_h(d) }
        return { 'ok' => false, 'diagnostics' => diagnostics } unless result.ok?

        plan = result.value.plan
        metrics = plan['metrics']
        {
          'ok' => true, 'road_digest' => result.value.road_digest, 'diagnostics' => diagnostics,
          'metrics' => metrics.slice('length_m', 'road_count', 'junction_count', 'piece_count', 'item_count', 'signal_count',
                                     'unique_face_count', 'expanded_face_count'),
          'junctions' => plan['junctions'], 'plan' => plan_view(plan)
        }
      end

      # Vue en plan : faces vues de dessus, couleur de leur matière, en mètres du repère du réseau.
      def plan_view(plan)
        surface = plan['nodes'][0]['children'].find { |c| c['id'] == 'road/surface' }['primitive']
        v = surface['vertices']
        faces = surface['faces'].filter_map do |f|
          pts = f['indices'].map { |i| v[i] }
          area = pts.each_index.sum { |i| (pts[i][0] * pts[(i + 1) % pts.size][1]) - (pts[(i + 1) % pts.size][0] * pts[i][1]) }
          next unless area > 1e-9

          [pts.map { |p| [p[0].round(2), p[1].round(2)] }, @colors.fetch(f['material'], '#999999')]
        end
        { 'faces' => faces.first(MAX_PLAN_FACES), 'truncated' => faces.size > MAX_PLAN_FACES }
      end

      # Contours des voies ajoutées, en mètres du modèle.
      def outline
        rings = @roads.filter_map do |r|
          profile = Composition.road_profile_intake.profile(r['profile'])
          next unless profile.ok?

          section = Geometry::RoadSection.call(profile.value, bands: Composition.road_bands, items: Composition.road_items)
          width = section['width_m']
          ax = Geometry::RoadRibbons.axis_x(width, r['axis'])
          o = r['points'].first
          local = r['points'].map { |x, y| [x - o[0], y - o[1]] }
          axis = Geometry::RoadAxis.call(local, Array.new([local.size - 2, 0].max, r['radius_m']), left_m: ax, right_m: width - ax)
          next unless axis.ok?

          stations = axis.value
          shift = ->(s, off) { [s.point[0] + (s.normal[0] * off) + o[0], s.point[1] + (s.normal[1] * off) + o[1]] }
          stations.map { |s| shift.call(s, ax) } + stations.reverse.map { |s| shift.call(s, ax - width) }
        end
        { refused: false, rings: rings }
      end

      def model
        @model_provider&.call
      end

      def confirmed(payload)
        t = tree
        return failure('E_TARGET_STALE', '/roads', 'no_road') unless t

        computed = @service.preview(tree: t)
        return computed unless computed.ok?
        return failure('E_CONFIRMATION_STALE', '/road_digest', 'confirmation_mismatch') unless computed.value.road_digest == payload['road_digest']

        Core::Result.ok(t)
      end

      def create(payload)
        return failure('E_TARGET_STALE', '/target', 'invalid_target') unless @mode == 'trace'

        t = confirmed(payload)
        return t unless t.ok?

        first = @roads.first
        written = @service.create(model: model, tree: t.value, origin_m: first['points'].first + [first['z'] || 0.0])
        return written unless written.ok?

        select_root(written.value.persistent_id)
        reset
        @session.clear
        Core::Result.ok({ 'created' => true, 'revision' => written.value.revision, 'metrics' => written.value.metrics, 'state' => state },
                        written.diagnostics)
      end

      def clear
        @session.clear
        @mode == 'trace' ? reset : nil
        Core::Result.ok('trace' => trace_state, 'state' => state)
      end

      # Modifier : les voies restent dans le repère du réseau (origine 0, 0) ; seuls les carrefours et
      # la liste des voies changent, la racine garde sa place.
      def load_selection
        return failure('E_TARGET_STALE', '/model', 'model_unavailable') unless @service

        loaded = @service.load_selection(model: model)
        return loaded unless loaded.ok?

        reset
        @edit = loaded.value
        settings = @edit.settings
        @roads = settings['roads'].map do |entry|
          road = entry['road']
          preset = @presets.find { |p| p['profile']['bands'] == road['profile']['bands'] }
          { 'id' => entry['id'], 'preset' => preset && preset['id'], 'name' => road.dig('profile', 'name'), 'profile' => road['profile'],
            'axis' => road['axis'], 'radii_m' => road['trace']['radii_m'], 'points' => road['trace']['points_m'],
            'settings' => road.reject { |k, _| %w[trace axis profile].include?(k) } }
        end
        @junctions = settings['junctions'].map(&:dup)
        preview.then { |p| Core::Result.ok(p.value.merge('revision' => @edit.target.revision)) }
      end

      def regenerate(payload)
        return failure('E_TARGET_STALE', '/target', 'invalid_target') unless @mode == 'edit' && @edit

        t = confirmed(payload)
        return t unless t.ok?

        written = @service.regenerate(model: model, target: @edit.target, changes: { 'roads' => t.value['roads'], 'junctions' => t.value['junctions'] })
        return written unless written.ok?

        reloaded = @service.load_selection(model: model)
        @edit = reloaded.value if reloaded.ok?
        Core::Result.ok({ 'regenerated' => true, 'revision' => written.value.revision, 'metrics' => written.value.metrics, 'state' => state },
                        written.diagnostics)
      end

      def select_root(persistent_id)
        current = model
        entity = current&.find_entity_by_persistent_id(persistent_id)
        return unless entity

        current.selection.clear
        current.selection.add(entity)
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
