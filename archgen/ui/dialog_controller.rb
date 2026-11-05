# frozen_string_literal: true

module Archgen
  module UI
    # Liaison entre le panneau et le service. Toute entrée vient du pont JS, donc n'est
    # jamais crue : enveloppe, action et champs sont contrôlés ici, indépendamment du JS.
    # Possède les jetons de cible et de confirmation ; le service relit toujours la cible.
    class DialogController
      PROTOCOL = 1
      ACTIONS = %w[init load_selection preview generate regenerate].freeze
      MUTATIONS = %w[generate regenerate].freeze
      PAYLOAD_KEYS = {
        'init' => [], 'load_selection' => [], 'preview' => %w[draft target_token],
        'generate' => %w[draft], 'regenerate' => %w[draft target_token confirmation_token]
      }.freeze
      NEEDS_DRAFT = %w[preview generate regenerate].freeze
      MAX_REQUEST_ID = 64
      MAX_REMEMBERED_MUTATIONS = 32

      attr_accessor :mode
      attr_reader :confirmations

      def initialize(service:, registry:, materials:, model_provider:, tokens: TargetTokens.new, confirmations: ConfirmationTokens.new, mode: 'new')
        @service = service
        @registry = registry
        @materials = materials
        @model_provider = model_provider
        @tokens = tokens
        @confirmations = confirmations
        @mode = mode
        @mutations = {}
        @busy = false
        @edit_persistent_id = nil
      end

      # Reçoit toujours une chaîne JSON, retourne toujours une réponse sérialisable.
      def dispatch(raw)
        parsed = Core::StrictJson.parse(raw)
        return respond(nil, parsed) unless parsed.ok?

        envelope = parsed.value
        request_id = safe_request_id(envelope)
        problem = envelope_problem(envelope)
        return respond(request_id, invalid(problem)) if problem

        return perform_mutation(request_id, envelope) if MUTATIONS.include?(envelope['action'])

        respond(request_id, perform(envelope['action'], envelope['payload']))
      rescue StandardError => e
        respond(request_id, failure('E_WRITE', '/model', 'internal_error', error: e.class.name))
      end

      # Sélection revenue sur la cible : rien n'est perdu. Sinon la confirmation tombe.
      def selection_changed(current)
        return false unless @edit_persistent_id

        selection = current.selection
        return false if selection.length == 1 && selection.first.respond_to?(:persistent_id) && selection.first.persistent_id == @edit_persistent_id

        @confirmations.clear
        true
      end

      # Annuler, Rétablir, enregistrer, autre document : la confirmation ne survit pas.
      def invalidate(document_changed: false)
        @confirmations.clear
        return unless document_changed

        @tokens.clear
        @edit_persistent_id = nil
      end

      def close_session
        @tokens.clear
        @confirmations.clear
        @mutations.clear
        @edit_persistent_id = nil
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

        payload_problem(envelope['action'], envelope['payload'])
      end

      def payload_problem(action, payload)
        return 'invalid_envelope' unless payload.is_a?(Hash)
        return 'invalid_envelope' unless (payload.keys - PAYLOAD_KEYS.fetch(action)).empty?
        return 'invalid_envelope' if NEEDS_DRAFT.include?(action) && !payload['draft'].is_a?(Hash)

        nil
      end

      # Une requête de mutation ne s'exécute qu'une fois : le rejeu rend la même réponse.
      def perform_mutation(request_id, envelope)
        return @mutations[request_id] if @mutations.key?(request_id)
        return respond(request_id, failure('E_WRITE', '/model', 'operation_in_progress')) if @busy

        @busy = true
        begin
          response = respond(request_id, perform(envelope['action'], envelope['payload']))
        ensure
          @busy = false
        end
        @mutations.shift while @mutations.size >= MAX_REMEMBERED_MUTATIONS
        @mutations[request_id] = response
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
        when 'generate' then generate(payload)
        when 'regenerate' then regenerate(payload)
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
        @edit_persistent_id = value.record.persistent_id
        @confirmations.clear
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
        body = { 'config' => value.config.to_h, 'projection' => value.projection, 'metrics' => value.plan['metrics'], 'plan_digest' => value.plan_digest }
        body['confirmation'] = confirmation_for(payload, value) if payload['target_token']
        Core::Result.ok(body, result.diagnostics)
      end

      def confirmation_for(payload, value)
        {
          'token' => @confirmations.issue(target_token: payload['target_token'], draft_digest: Core::Canonical.digest(payload['draft'])),
          'expires_in_s' => ConfirmationTokens::TTL_S,
          'message' => Messages::REPLACE_WARNING,
          'changes' => changes(value.base.to_h, value.config.to_h)
        }
      end

      # Ce qui va changer, montré avant de valider un changement de style ou de réglage.
      # Le style vient en tête : c'est lui qui explique les autres écarts.
      def changes(before, after)
        previous_values = flatten(before)
        listed = flatten(after).filter_map do |path, value|
          previous = previous_values[path]
          next if previous == value || path == '/profile/revision'

          label = Messages.field_label(path)
          next unless label

          { 'path' => path, 'label' => label, 'from' => display(path, previous), 'to' => display(path, value) }
        end
        listed.partition { |change| change['path'] == '/profile/id' }.flatten
      end

      def flatten(hash, prefix = '')
        hash.each_with_object({}) do |(key, value), out|
          path = "#{prefix}/#{key}"
          value.is_a?(Hash) ? out.merge!(flatten(value, path)) : out[path] = value
        end
      end

      def display(path, value)
        return @materials.dig(value, 'label') || value if path.start_with?('/materials/')
        return @registry.active_profiles.find { |p| p.id == value }&.label || value if path == '/profile/id'

        Messages.value_text(value, path)
      end

      def generate(payload)
        current = model
        created = @service.create(model: current, draft: payload['draft'])
        return created unless created.ok?

        summary = created.value
        Core::Result.ok(
          summary_body(summary).merge('target_token' => select_created(current, summary)),
          created.diagnostics
        )
      end

      # La racine créée devient la sélection : le panneau peut enchaîner sur son édition.
      def select_created(current, summary)
        entity = current.find_entity_by_persistent_id(summary.persistent_id)
        return nil unless entity

        current.selection.clear
        current.selection.add(entity)
        @edit_persistent_id = summary.persistent_id
        @tokens.issue(summary.target, model: current)
      end

      def regenerate(payload)
        current = model
        target = @tokens.resolve(payload['target_token'], model: current)
        return target unless target.ok?

        consumed = @confirmations.consume(payload['confirmation_token'], target_token: payload['target_token'],
                                                                         draft_digest: Core::Canonical.digest(payload['draft']))
        return consumed unless consumed.ok?

        written = @service.regenerate(model: current, target: target.value, draft: payload['draft'])
        return written unless written.ok?

        summary = written.value
        @edit_persistent_id = summary.persistent_id
        Core::Result.ok(
          summary_body(summary).merge('target_token' => @tokens.issue(summary.target, model: current)),
          written.diagnostics
        )
      end

      def summary_body(summary)
        { 'name' => summary.name, 'revision' => summary.revision, 'metrics' => summary.metrics,
          'config' => load_config_hash(summary) }
      end

      def load_config_hash(summary)
        loaded = @service.load_building(model: model, persistent_id: summary.persistent_id)
        loaded.ok? ? loaded.value.config.to_h : nil
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
