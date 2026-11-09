# frozen_string_literal: true

require 'json'

module Archgen
  module UI
    # Panneau de parcelle (docs/DETAILS_CONTRACT.md, AG-069) : réglages propres d'un bâtiment d'une
    # rue ou d'un îlot. Testable sans SketchUp ; ParcelPanel ne fait que choisir la cible.
    class ParcelController
      PROTOCOL = 1
      ACTIONS = %w[init preview apply].freeze
      MUTATIONS = %w[apply].freeze
      PAYLOAD_KEYS = { 'init' => [], 'preview' => %w[own], 'apply' => %w[own ensemble_digest] }.freeze
      MAX_REQUEST_ID = 64
      MAX_REMEMBERED = 32
      OPERATION = 'ARCHGEN : personnaliser un bâtiment'

      attr_reader :parcel_id

      def initialize(service:, registry:, intake:, model_provider:)
        @service = service
        @registry = registry
        @intake = intake
        @model_provider = model_provider
        @mutations = {}
        @busy = false
      end

      # La racine d'ensemble est sélectionnée, l'édition refermée : on relit ses réglages.
      def load(parcel_id)
        @parcel_id = nil
        @target = nil
        @settings = nil
        loaded = @service.load_selection(model: @model_provider.call)
        return loaded unless loaded.ok?

        @parcel_id = parcel_id
        @target = loaded.value.target
        @settings = loaded.value.settings
        Core::Result.ok(true)
      end

      def forget
        @parcel_id = nil
        @target = nil
        @settings = nil
        @mutations.clear
      end

      def dispatch(raw)
        parsed = Core::StrictJson.parse(raw)
        return respond(nil, parsed) unless parsed.ok?

        envelope = parsed.value
        request_id = safe_request_id(envelope)
        problem = envelope_problem(envelope)
        return respond(request_id, failure('E_SCHEMA', '/request', problem)) if problem
        return perform_mutation(request_id, envelope['payload']) if MUTATIONS.include?(envelope['action'])

        respond(request_id, envelope['action'] == 'init' ? init : preview(envelope['payload']))
      rescue StandardError => e
        respond(request_id, failure('E_WRITE', '/model', 'internal_error', error: e.class.name))
      end

      private

      def init
        return not_loaded unless @settings

        street = Core::EnsembleParcels.street_values(@settings, @parcel_id, registry: @registry, intake: @intake)
        return street unless street.ok?

        Core::Result.ok('version' => VERSION, 'parcel_id' => @parcel_id, 'street' => street.value, 'own' => own_fields(current_own),
                        'custom_count' => (@settings['parcels'] || {}).size)
      end

      def preview(payload)
        return not_loaded unless @settings

        tree = tree_with(payload['own'])
        return tree unless tree.ok?

        computed = @service.preview(tree: tree.value)
        return Core::Result.ok('refused' => true, 'problems' => computed.errors.map { |d| Messages.to_h(d) }) unless computed.ok?

        Core::Result.ok({ 'ensemble_digest' => computed.value.ensemble_digest, 'changed' => computed.value.ensemble_digest != @target.ensemble_digest },
                        computed.diagnostics)
      end

      def apply(payload)
        return not_loaded unless @settings

        tree = tree_with(payload['own'])
        return tree unless tree.ok?

        computed = @service.preview(tree: tree.value)
        return computed unless computed.ok?
        return failure('E_CONFIRMATION_STALE', '/ensemble_digest', 'preview_changed') unless computed.value.ensemble_digest == payload['ensemble_digest']

        written = @service.regenerate(model: @model_provider.call, target: @target, replace: tree.value, operation: OPERATION)
        return written unless written.ok?

        @target = written.value.target
        @settings = computed.value.settings
        Core::Result.ok({ 'written' => true, 'own' => own_fields(current_own), 'custom_count' => (@settings['parcels'] || {}).size }, written.diagnostics)
      end

      def current_own
        (@settings['parcels'] || {})[@parcel_id] || {}
      end

      # Le panneau envoie des champs plats ; la hauteur du commerce y est `shop_height_m`.
      def own_fields(own)
        out = own.reject { |key, _| key == 'shop' }
        out['shop_height_m'] = own.dig('shop', 'height_m') if own.dig('shop', 'height_m')
        out
      end

      FIELDS = %w[levels roof ground_floor shop_height_m chimneys glazing muntins shutters dormers genoise stepped_gable cladding width_m].freeze

      # Champ absent : la valeur de la rue. Plus aucun champ : la parcelle n'a plus de réglage propre.
      def tree_with(fields)
        return failure('E_SCHEMA', '/own', 'invalid_envelope') unless fields.is_a?(Hash) && (fields.keys - FIELDS).empty?

        own = fields.reject { |key, value| key == 'shop_height_m' || value.nil? }
        own['shop'] = { 'height_m' => fields['shop_height_m'] } unless fields['shop_height_m'].nil?
        parcels = (@settings['parcels'] || {}).reject { |key, _| key == @parcel_id }
        parcels[@parcel_id] = own unless own.empty?
        tree = @settings.reject { |key, _| key == 'parcels' }
        Core::Result.ok(parcels.empty? ? tree : tree.merge('parcels' => parcels))
      end

      def perform_mutation(request_id, payload)
        return @mutations[request_id] if @mutations.key?(request_id)
        return respond(request_id, failure('E_WRITE', '/model', 'operation_in_progress')) if @busy

        @busy = true
        begin
          response = respond(request_id, apply(payload))
        ensure
          @busy = false
        end
        @mutations.shift while @mutations.size >= MAX_REMEMBERED
        @mutations[request_id] = response
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

      def not_loaded
        failure('E_TARGET_STALE', '/selection', 'parcel_not_loaded')
      end

      def failure(code, path, reason, **params)
        Core::Result.fail([Core::Diagnostic.error(code, path, reason: reason, **params)])
      end

      def respond(request_id, result)
        { 'v' => PROTOCOL, 'request_id' => request_id, 'ok' => result.ok?, 'result' => result.value,
          'diagnostics' => result.diagnostics.map { |d| Messages.to_h(d) } }
      end
    end
  end
end
