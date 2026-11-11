# frozen_string_literal: true

module Archgen
  module UI
    # Pont du panneau « Importer une carte » (docs/CARTOGRAPHIE_CONTRACT.md §5, AG-129). Les accès à
    # l'hôte (choix de fichier, lecture, téléchargement, confirmation) sont des ports injectés.
    class MapController
      PROTOCOL = 1
      MAX_REQUEST_ID = 64
      ACTIONS = %w[init choose download preview import].freeze
      PAYLOAD_KEYS = {
        'init' => [], 'choose' => %w[kind], 'download' => %w[lat lon size_m],
        'preview' => %w[map_path terrain_path lat lon style layers ign source], 'import' => []
      }.freeze

      # ports : georef -> [lat, lon] ou nil ; pick(kind) -> chemin ou nil ; read(path) -> octets ;
      # confirm(texte) -> booléen ; fetch(request, &done) envoie la requête et rappelle done(status, body) ;
      # save(name, octets) -> chemin enregistré ; model -> modèle actif.
      def initialize(service:, registry:, ports:)
        @service = service
        @registry = registry
        @ports = ports
        @preview = nil
      end

      attr_writer :on_downloaded

      def dispatch(raw)
        parsed = Core::StrictJson.parse(raw)
        return respond(nil, parsed) unless parsed.ok?

        envelope = parsed.value
        id = envelope.is_a?(Hash) && envelope['request_id'].is_a?(String) && envelope['request_id'].size <= MAX_REQUEST_ID ? envelope['request_id'] : nil
        problem = envelope_problem(envelope, id)
        return respond(id, failure('E_SCHEMA', '/request', problem)) if problem

        respond(id, send("act_#{envelope['action']}", envelope['payload']))
      rescue StandardError => e
        respond(id, failure('E_WRITE', '/model', 'internal_error', error: e.class.name))
      end

      private

      def envelope_problem(envelope, id)
        return 'invalid_envelope' unless envelope.is_a?(Hash) && (envelope.keys - %w[v request_id action payload]).empty? && id
        return 'unsupported_protocol' unless envelope['v'] == PROTOCOL
        return 'unknown_action' unless ACTIONS.include?(envelope['action'])

        payload = envelope['payload']
        'invalid_envelope' unless payload.is_a?(Hash) && (payload.keys - PAYLOAD_KEYS.fetch(envelope['action'])).empty?
      end

      def act_init(_payload)
        styles = Messages::SIGNATURES.keys.filter_map { |sid| @registry.fetch(sid).value }.map { |p| { 'id' => p.id, 'label' => p.label } }
        Core::Result.ok({ 'georef' => @ports[:georef].call, 'styles' => styles,
                          'max_size_m' => Adapters::SketchUp::OverpassClient::MAX_SIDE_M,
                          'hosts' => Adapters::SketchUp::OverpassClient::HOSTS })
      end

      def act_choose(payload)
        return failure('E_SCHEMA', '/payload/kind', 'enum') unless %w[map terrain].include?(payload['kind'])

        Core::Result.ok({ 'kind' => payload['kind'], 'path' => @ports[:pick].call(payload['kind']) })
      end

      # Confirmation à chaque envoi, avec l'hôte et l'emprise ; la réponse arrive plus tard (on_downloaded).
      def act_download(payload)
        lat, lon, size = payload.values_at('lat', 'lon', 'size_m')
        return failure('E_MAP', '/download', 'map_download', reason_detail: 'position') unless lat.is_a?(Numeric) && lon.is_a?(Numeric) && lat.between?(-85, 85) && lon.between?(-180, 180)

        problem = Adapters::SketchUp::OverpassClient.size_problem(size)
        return Core::Result.fail([problem]) if problem

        box = Adapters::SketchUp::OverpassClient.bbox(lat, lon, size)
        request = Adapters::SketchUp::OverpassClient.request(box)
        host = request['url'][%r{https://([^/]+)}, 1]
        text = "ARCHGEN va demander à #{host} les voies et bâtiments OpenStreetMap de cette emprise :\n" \
               "sud #{box[0]}, ouest #{box[1]}, nord #{box[2]}, est #{box[3]}.\n" \
               "Rien d’autre n’est envoyé que l’emprise et « ARCHGEN/#{Archgen::VERSION} ». Continuer ?"
        return Core::Result.ok({ 'started' => false }) unless @ports[:confirm].call(text)

        @ports[:fetch].call(request) do |status, body|
          downloaded(status, body, host, box)
        end
        Core::Result.ok({ 'started' => true, 'host' => host, 'bbox' => box })
      end

      # Réponse du téléchargement : toute erreur revient au panneau, jamais en silence dans la console.
      def downloaded(status, body, host, box)
        begin
          checked = Adapters::SketchUp::OverpassClient.check(status, body)
          result = if checked.ok?
                     model = @ports[:model].call
                     path = @ports[:save].call(Adapters::SketchUp::OverpassClient.file_name(model.respond_to?(:path) ? model.path : '', Time.now), body)
                     Core::Result.ok({ 'path' => path, 'source' => { 'kind' => 'download', 'host' => host, 'bbox' => box, 'date' => Time.now.strftime('%Y-%m-%d') } })
                   else
                     checked
                   end
        rescue StandardError => e
          result = failure('E_MAP', '/download', 'map_download', reason_detail: 'save', error: e.class.name)
        end
        @on_downloaded&.call(respond(nil, result))
      end

      def act_preview(payload)
        path = payload['map_path']
        return failure('E_MAP', '/map', 'map_file', reason_detail: 'missing') unless path.is_a?(String) && !path.empty?

        format = path.downcase.end_with?('.geojson', '.json') ? 'geojson' : 'osm'
        origin = payload['lat'].is_a?(Numeric) && payload['lon'].is_a?(Numeric) ? [payload['lat'], payload['lon']] : @ports[:georef].call
        terrain = payload['terrain_path'].to_s.empty? ? nil : @ports[:read].call(payload['terrain_path'])
        layers = Array(payload['layers']) & Adapters::SketchUp::MapImportService::LAYERS
        result = @service.preview(map_bytes: @ports[:read].call(path), format: format, origin: origin, style: payload['style'].to_s,
                                  layers: layers, terrain_bytes: terrain, ign: payload['ign'] == true,
                                  source: (payload['source'].is_a?(Hash) ? payload['source'] : { 'kind' => 'file' }))
        @preview = result.ok? ? result.value : nil
        return result unless result.ok?

        Core::Result.ok({ 'counts' => @preview.counts, 'skipped' => @preview.skipped, 'attribution' => @preview.attribution,
                          'origin' => @preview.origin }, result.diagnostics)
      end

      def act_import(_payload)
        return failure('E_TARGET_STALE', '/preview', 'preview_missing') unless @preview

        frame = @ports[:frame]&.call
        result = @service.import(model: @ports[:model].call, preview: @preview, frame: frame)
        @preview = nil if result.ok?
        result
      end

      def failure(code, path, reason, **params)
        Core::Result.fail([Core::Diagnostic.error(code, path, reason: reason, **params)])
      end

      def respond(id, result)
        { 'v' => PROTOCOL, 'request_id' => id, 'ok' => result.ok?, 'result' => result.value,
          'diagnostics' => result.diagnostics.map { |d| Messages.to_h(d) } }
      end
    end
  end
end
