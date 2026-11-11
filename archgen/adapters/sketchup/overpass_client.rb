# frozen_string_literal: true

require 'uri'

module Archgen
  module Adapters
    module SketchUp
      # Téléchargement OpenStreetMap par l'API Overpass (ADR-57, docs/CARTOGRAPHIE_CONTRACT.md §1).
      # Ce module prépare la requête et juge la réponse ; l'envoi est fait par l'interface, après
      # confirmation, avec Sketchup::Http. Seuls l'emprise et l'en-tête User-Agent partent.
      module OverpassClient
        module_function

        HOSTS = %w[https://overpass-api.de/api/interpreter https://overpass.kumi.systems/api/interpreter].freeze
        MAX_SIDE_M = 2000.0
        MIN_SIDE_M = 50.0
        TIMEOUT_S = 25

        # Emprise [sud, ouest, nord, est] en degrés d'un carré de `size_m` centré sur (lat, lon).
        def bbox(lat, lon, size_m)
          half = size_m / 2.0
          projection = Core::MapProjection.new(lat, lon)
          south, west = projection.inverse(-half, -half)
          north, east = projection.inverse(half, half)
          [south, west, north, east].map { |v| v.round(7) }
        end

        def size_problem(size_m)
          return nil if size_m.is_a?(Numeric) && size_m.between?(MIN_SIDE_M, MAX_SIDE_M)

          Core::Diagnostic.error('E_MAP', '/download/size_m', reason: 'map_download', reason_detail: 'size', min: MIN_SIDE_M, limit: MAX_SIDE_M)
        end

        # Requête fixe : voies et contours de bâtiments de l'emprise, avec leurs nœuds.
        def query(box)
          s, w, n, e = box
          area = "(#{s},#{w},#{n},#{e})"
          "[out:xml][timeout:#{TIMEOUT_S}];(way[\"highway\"]#{area};way[\"building\"]#{area};);(._;>;);out body;"
        end

        def request(box, host_index: 0)
          { 'url' => HOSTS.fetch(host_index), 'method' => 'POST',
            'headers' => { 'User-Agent' => "ARCHGEN/#{Archgen::VERSION}", 'Content-Type' => 'application/x-www-form-urlencoded' },
            'body' => "data=#{URI.encode_www_form_component(query(box))}" }
        end

        # Juge la réponse : Result.ok(octets) ou un refus localisé.
        def check(status, body)
          detail = if status.to_i == 429 then 'quota'
                   elsif status.to_i != 200 then 'status'
                   elsif body.nil? || body.empty? then 'empty'
                   elsif body.bytesize > Core::MapReader::MAX_BYTES then 'too_large'
                   end
          return Core::Result.ok(body) unless detail

          Core::Result.fail([Core::Diagnostic.error('E_MAP', '/download', reason: 'map_download', reason_detail: detail, status: status.to_i)])
        end

        # Fichier de provenance : `<modèle>_osm_<AAAAMMJJ>.osm`, à côté du SKP.
        def file_name(model_path, date)
          base = model_path.to_s.empty? ? 'archgen' : File.basename(model_path, '.*')
          "#{base}_osm_#{date.strftime('%Y%m%d')}.osm"
        end
      end
    end
  end
end
