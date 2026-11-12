# frozen_string_literal: true

module Archgen
  module UI
    # Liaison entre le panneau de voirie, le tracé en cours et le service de voie (AG-038, AG-042).
    # Le panneau compose la coupe et règle rayon et axe ; le tracé ne vient que de l'outil. Ruby juge
    # tout, calcule la coupe dessinée et l'aperçu ; une écriture exige l'empreinte montrée.
    class RoadController
      PROTOCOL = 1
      include RecipeActions

      ACTIONS = (%w[init preview create clear load_selection regenerate retain_terrain survey_ground] + RecipeActions::ACTIONS).freeze
      MUTATIONS = %w[create regenerate].freeze
      PAYLOAD_KEYS = {
        'init' => [], 'preview' => %w[profile road], 'create' => %w[profile road road_digest], 'clear' => [],
        'load_selection' => [], 'regenerate' => %w[profile road road_digest], 'retain_terrain' => [], 'survey_ground' => %w[profile road]
      }.merge(RecipeActions::PAYLOAD_KEYS).freeze
      MAX_REQUEST_ID = 64
      START_PRESET = 'ville'
      DEFAULT_RADIUS_M = 20.0
      AXES = %w[center left right].freeze

      attr_reader :session
      attr_accessor :mode, :tool_active

      # service, session, model_provider : absents, le panneau ne fait que composer une coupe.
      def initialize(intake:, bands:, items:, presets:, service: nil, session: nil, model_provider: nil, recipes: nil)
        @recipes = recipes
        @intake = intake
        @bands = bands
        @items = items
        @presets = presets.fetch('presets')
        @profile = @presets.find { |p| p['id'] == START_PRESET }.fetch('profile')
        @service = service
        @session = session || Core::TraceSession.new
        @model_provider = model_provider
        @mode = 'trace'
        @overlay = {}
        @mutations = {}
      end

      # Contour de la voie à dessiner dans la vue, en mètres dans le repère du modèle.
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

      # Le tracé a changé (outil) : on garde le dernier aperçu pour la vue.
      def trace_state
        { 'points' => @session.points.size, 'finished' => @session.finished?, 'length_m' => Core::Quant.q(@session.length_m) }
      end

      def close_session
        @session.clear
        @overlay = {}
        @edit = nil
        @terrain = nil
        @survey = nil
        @mutations.clear
      end

      def document_changed
        close_session
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
        return 'invalid_envelope' if PAYLOAD_KEYS.fetch(envelope['action']).include?('profile') && !payload['profile'].is_a?(Hash)
        return 'invalid_envelope' if payload.key?('road') && !payload['road'].is_a?(Hash)
        return 'invalid_envelope' if payload['road'].is_a?(Hash) && payload['road'].key?('on_ground') && ![true, false].include?(payload['road']['on_ground'])

        nil
      end

      def failure(code, path, reason, **params)
        Core::Result.fail([Core::Diagnostic.error(code, path, reason: reason, **params)])
      end

      def perform(action, payload)
        case action
        when 'init' then init
        when 'preview' then preview(payload)
        when 'create' then create(payload)
        when 'clear' then clear
        when 'load_selection' then load_selection
        when 'regenerate' then regenerate(payload)
        when 'retain_terrain' then retain_terrain
        when 'survey_ground' then survey_ground(payload)
        when *RecipeActions::ACTIONS then recipe_action(action, payload)
        end
      end

      # La page se recharge à chaque ouverture : elle retrouve la dernière coupe acceptée.
      def init
        @mutations.clear
        Core::Result.ok(
          'version' => VERSION, 'mode' => @mode, 'tool_active' => @tool_active == true, 'writes' => !@service.nil?,
          'profile' => @profile, 'default_radius_m' => DEFAULT_RADIUS_M,
          'presets' => @presets.map { |p| { 'id' => p['id'], 'name' => p.dig('profile', 'name'), 'profile' => p['profile'] } },
          'families' => RoadFamilies.group(@presets.map { |p| p['id'] }),
          'recipes' => recipe_list,
          'bands' => band_catalogue, 'items' => item_catalogue, 'trace' => trace_state
        )
      end

      # La coupe est jugée et dessinée ; si un tracé ou une voie chargée existe, la voie entière est calculée.
      def preview(payload)
        section = section_for(payload['profile'])
        return section unless section.ok?

        # Un refus de la voie n'est pas un refus de la coupe : il voyage dans son propre bloc.
        road = road_preview(payload)
        body = road && summary(road)
        body['merge'] = merge_state(road) if body && body['ok']
        Core::Result.ok(section.value.merge('road' => body, 'ground' => ground_state), section.diagnostics)
      end

      # AG-102 : une voie tracée qui touche d'autres voies ARCHGEN formera avec elles un réseau.
      def merge_state(road)
        return nil unless @mode == 'trace' && @service.respond_to?(:merge_for)

        merge = @service.merge_for(model, road.value.settings, @session.origin_m)
        return { 'refused' => merge.errors.map { |d| Messages.to_h(d) } } unless merge.ok?

        merge.value ? { 'count' => merge.value.absorbed.size } : nil
      end

      def section_for(profile)
        result = @intake.profile(profile)
        return result unless result.ok?

        @profile = result.value
        Core::Result.ok({ 'profile' => result.value, 'section' => Geometry::RoadSection.call(result.value, bands: @bands, items: @items) },
                        result.diagnostics)
      end

      # nil quand il n'y a rien à calculer : ni tracé terminé, ni voie chargée.
      def road_preview(payload)
        return nil unless @service

        tree = road_tree(payload)
        return nil unless tree

        result = tree.ok? ? @service.preview(tree: tree.value, survey: tree.value['ground'] ? @survey : nil) : tree
        @overlay = @mode == 'trace' ? outline(result) : {}
        result
      end

      # Les diagnostics de coupe (/profile) sont déjà rendus avec la coupe.
      def summary(result)
        own = result.diagnostics.reject { |d| d.path.start_with?('/profile') }.map { |d| Messages.to_h(d) }
        return { 'ok' => false, 'diagnostics' => own } unless result.ok?

        metrics = result.value.plan['metrics']
        { 'ok' => true, 'road_digest' => result.value.road_digest, 'diagnostics' => own,
          'metrics' => metrics.slice('length_m', 'width_m', 'station_count', 'item_count', 'sleeper_count', 'definition_count', 'unique_face_count', 'expanded_face_count',
                                     'grade_max_percent', 'cut_max_m', 'fill_max_m', 'earthwork_reach_m', 'water_drop_m', 'lock_count', 'origin_z_m'),
          'locks' => result.value.plan.dig('water', 'locks') || [] }
      end

      # Réglages de voie : tracé de l'outil (création) ou tracé enregistré (modification).
      def road_tree(payload)
        road = payload['road'] || {}
        axis = road.fetch('axis', 'center')
        return failure('E_SCHEMA', '/road/axis', 'enum', allowed: AXES) unless AXES.include?(axis)

        radius = road['radius_m']
        return failure('E_SCHEMA', '/road/radius_m', 'type', expected: 'number') unless radius.nil? || radius.is_a?(Numeric)

        # Régime de l'eau (EAU_CONTRACT) : transmis tel quel, jugé par RoadIntake.
        water = road['water']
        return failure('E_SCHEMA', '/road/water', 'type', expected: 'object') unless water.nil? || water.is_a?(Hash)

        if @mode == 'edit'
          return nil unless @edit

          trace = @edit.settings['trace']
          radii = radius.nil? ? trace['radii_m'] : Array.new(trace['radii_m'].size, radius)
          # Une voie garde son terrain ou son absence de terrain : la case ne change rien en modification.
          kept = @edit.settings.merge('profile' => payload['profile'], 'axis' => axis, 'trace' => trace.merge('radii_m' => radii))
          kept = water ? kept.merge('water' => water) : kept.reject { |k, _| k == 'water' }
          return Core::Result.ok(kept)
        end
        return nil unless @session.finished?

        points = @session.relative_points
        radii = Array.new([points.size - 2, 0].max, radius.nil? ? DEFAULT_RADIUS_M : radius)
        tree = { 'trace' => { 'points_m' => points, 'radii_m' => radii }, 'axis' => axis, 'profile' => payload['profile'] }
        tree['ground'] = {} if road['on_ground'] == true
        tree['water'] = water if water
        Core::Result.ok(tree)
      end

      # Contour de l'emprise, dans le repère du modèle, pour la vue.
      def outline(result)
        return { refused: true, rings: [] } unless result.ok?

        settings = result.value.settings
        width = result.value.plan['metrics']['width_m']
        ax = Geometry::RoadRibbons.axis_x(width, settings['axis'])
        stations = Geometry::RoadAxis.call(settings['trace']['points_m'], settings['trace']['radii_m'], left_m: ax, right_m: width - ax).value
        origin = @session.origin_m
        ring = stations.map { |s| shifted(s, ax, origin) } + stations.reverse.map { |s| shifted(s, ax - width, origin) }
        { refused: false, rings: [ring] }
      end

      def shifted(station, offset, origin)
        [station.point[0] + (station.normal[0] * offset) + origin[0], station.point[1] + (station.normal[1] * offset) + origin[1]]
      end

      def model
        @model_provider&.call
      end

      def create(payload)
        return failure('E_TARGET_STALE', '/trace', 'trace_unfinished') unless @mode == 'trace' && @session.finished?

        tree = road_tree(payload)
        return tree unless tree&.ok?

        # Voie sur un terrain : l'empreinte montrée a été calculée avec le relevé.
        computed = @service.preview(tree: tree.value, survey: tree.value['ground'] ? @survey : nil)
        return computed unless computed.ok?
        return failure('E_CONFIRMATION_STALE', '/road_digest', 'confirmation_mismatch') unless computed.value.road_digest == payload['road_digest']

        ground = tree.value['ground'] ? { terrain: @terrain, survey_digest: @survey && Core::Canonical.digest(@survey) } : {}
        written = @service.create(model: model, tree: tree.value, origin_m: @session.origin_m, **ground)
        return written unless written.ok?

        select_root(written.value.persistent_id)
        @session.clear
        @overlay = {}
        Core::Result.ok({ 'created' => true, 'revision' => written.value.revision, 'metrics' => written.value.metrics }, written.diagnostics)
      end

      def clear
        @session.clear
        @overlay = {}
        Core::Result.ok('trace' => trace_state)
      end

      def load_selection
        return failure('E_TARGET_STALE', '/model', 'model_unavailable') unless @service

        loaded = @service.load_selection(model: model)
        return loaded unless loaded.ok?

        @edit = loaded.value
        @survey = nil
        settings = @edit.settings
        radii = settings['trace']['radii_m'].uniq
        Core::Result.ok({ 'profile' => settings['profile'], 'axis' => settings['axis'], 'radius_m' => radii.size == 1 ? radii.first : nil,
                          'vertex_count' => settings['trace']['points_m'].size, 'revision' => @edit.target.revision,
                          'on_ground' => settings.key?('ground'), 'water' => settings['water'] })
      end

      def regenerate(payload)
        return failure('E_TARGET_STALE', '/target', 'invalid_target') unless @mode == 'edit' && @edit

        tree = road_tree(payload)
        return tree unless tree&.ok?

        # Voie sur un terrain : l'empreinte montrée a été calculée avec le relevé.
        computed = @service.preview(tree: tree.value, survey: tree.value['ground'] ? @survey : nil)
        return computed unless computed.ok?
        return failure('E_CONFIRMATION_STALE', '/road_digest', 'confirmation_mismatch') unless computed.value.road_digest == payload['road_digest']

        changes = { 'profile' => tree.value['profile'], 'axis' => tree.value['axis'], 'trace' => { 'radii_m' => tree.value['trace']['radii_m'] } }
        # Régime retiré avec la dernière bande d'eau : nil l'efface des réglages enregistrés.
        changes['water'] = tree.value['water']
        written = @service.regenerate(model: model, target: @edit.target, changes: changes)
        return written unless written.ok?

        reloaded = @service.load_selection(model: model)
        @edit = reloaded.value if reloaded.ok?
        Core::Result.ok({ 'regenerated' => true, 'revision' => written.value.revision, 'metrics' => written.value.metrics }, written.diagnostics)
      end

      # Terrain : la sélection courante est retenue (TerrainSurveyor), rien n'est écrit.
      def retain_terrain
        return failure('E_TARGET_STALE', '/model', 'model_unavailable') unless @service

        retained = Adapters::SketchUp::TerrainSurveyor.new.retain(model)
        return retained unless retained.ok?

        @terrain = retained.value
        @survey = nil
        Core::Result.ok('ground' => ground_state)
      end

      # Relevé du couloir sur demande : création à partir du tracé, modification à la place de la racine.
      def survey_ground(payload)
        tree = road_tree(payload)
        return failure('E_TARGET_STALE', '/trace', 'trace_unfinished') unless tree
        return tree unless tree.ok?

        grid = if @mode == 'edit'
                 @service.survey_existing(model: model, instance: @edit.record.instance, tree: tree.value)
               else
                 return failure('E_SITE_TERRAIN', '/site/terrain', 'terrain_missing') unless @terrain

                 @service.survey(model: model, tree: tree.value, origin_m: @session.origin_m, terrain: @terrain)
               end
        return grid unless grid&.ok?

        @survey = grid.value
        preview(payload)
      end

      def ground_state
        { 'terrain' => !@terrain.nil?, 'surveyed' => !@survey.nil?,
          'points' => @survey ? @survey['s_m'].size * @survey['u_m'].size : 0 }
      end

      def select_root(persistent_id)
        current = model
        entity = current&.find_entity_by_persistent_id(persistent_id)
        return unless entity

        current.selection.clear
        current.selection.add(entity)
      end

      def band_catalogue
        @bands.fetch('bands').map do |type, e|
          { 'type' => type, 'label' => e['label'], 'default_width_m' => e['default_width_m'], 'min_width_m' => e['min_width_m'],
            'max_width_m' => e['max_width_m'], 'role' => e['role'], 'accepts_items' => e['accepts_items'], 'settings' => e.fetch('settings', {}) }
        end
      end

      def item_catalogue
        @items.fetch('items').map do |kind, e|
          { 'kind' => kind, 'label' => e['label'], 'variants' => e['variants'].map { |id, v| { 'id' => id, 'label' => v['label'] } },
            'default_variant' => e['default_variant'], 'default_height_m' => e['default_height_m'], 'repeat' => e['repeat'],
            'default_spacing_m' => e['default_spacing_m'], 'height_variation' => e['height_variation'],
            'default_count' => e['default_count'], 'min_count' => e['min_count'], 'max_count' => e['max_count'] }
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
