# frozen_string_literal: true

module Archgen
  module Core
    # Lecteur pur d'extraits cartographiques (docs/CARTOGRAPHIE_CONTRACT.md §1, AG-125) : OpenStreetMap XML
    # (`.osm`, réponse Overpass comprise) et GeoJSON. Il reçoit des octets, ne lit aucun fichier et
    # n'ouvre aucune connexion. Seules les clés de la liste fermée sont gardées.
    module MapReader
      module_function

      MAX_BYTES = 50 * 1024 * 1024
      KEYS = %w[highway name building building:levels height lanes bridge tunnel layer].freeze
      TAG = %r{<(/?)([A-Za-z?!][\w:.-]*)([^>]*?)(/?)>}m
      ATTR = /([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/
      ENTITIES = { 'amp' => '&', 'lt' => '<', 'gt' => '>', 'quot' => '"', 'apos' => "'" }.freeze

      # format : 'osm' ou 'geojson' ; origin : [lat, lon] ou nil (centre de l'emprise lue).
      # Rend Result.ok({ 'origin', 'ways', 'buildings', 'skipped' }).
      def call(bytes, format:, origin: nil)
        return error('map_file', reason_detail: 'too_large', limit: MAX_BYTES) if bytes.bytesize > MAX_BYTES

        text = bytes.dup.force_encoding('UTF-8')
        return error('map_file', reason_detail: 'invalid_utf8') unless text.valid_encoding?

        raw = format == 'geojson' ? geojson(text) : osm(text)
        return raw if raw.is_a?(Result)

        assemble(raw, origin)
      end

      def error(reason, **params)
        Result.fail([Diagnostic.error('E_MAP', '/map', reason: reason, **params)])
      end

      # --- OpenStreetMap XML

      def osm(text)
        return error('map_file', reason_detail: 'doctype', line: line_of(text, text.index('<!D') || text.index('<!E'))) if text.match?(/<!(DOCTYPE|ENTITY)/i)

        nodes = {}
        ways = []
        relations = 0
        current = nil
        text.scan(TAG) do
          closing, name, attrs, self_closing = Regexp.last_match.captures
          offset = Regexp.last_match.begin(0)
          case name
          when 'node'
            next if closing == '/'

            a = attributes(attrs)
            lat = Float(a['lat'], exception: false)
            lon = Float(a['lon'], exception: false)
            return coordinates_error(text, offset) unless lat && lon && lat.between?(-90, 90) && lon.between?(-180, 180)

            nodes[a['id']] = [lat, lon]
          when 'way'
            if closing == '/'
              ways << current if current
              current = nil
            else
              current = { 'id' => attributes(attrs)['id'], 'refs' => [], 'tags' => {} }
              if self_closing == '/'
                ways << current
                current = nil
              end
            end
          when 'nd'
            current['refs'] << attributes(attrs)['ref'] if current
          when 'tag'
            next unless current

            a = attributes(attrs)
            current['tags'][a['k']] = a['v'] if KEYS.include?(a['k'])
          when 'relation'
            relations += 1 unless closing == '/'
          end
        end
        return error('map_file', reason_detail: 'not_osm') if nodes.empty? && ways.empty? && !text.include?('<osm')

        skipped = Hash.new(0)
        skipped['relation'] += relations if relations.positive?
        features = ways.filter_map do |way|
          points = way['refs'].map { |ref| nodes[ref] }
          if points.include?(nil)
            skipped['missing_nodes'] += 1
            next
          end
          closed = way['refs'].size >= 4 && way['refs'].first == way['refs'].last
          { 'id' => "way/#{way['id']}", 'tags' => way['tags'], 'latlon' => points, 'closed' => closed }
        end
        [features, skipped]
      end

      def attributes(text)
        text.scan(ATTR).to_h { |k, double, single| [k, decode(double || single)] }
      end

      def decode(value)
        value.gsub(/&(#x[0-9A-Fa-f]+|#\d+|\w+);/) do
          code = Regexp.last_match(1)
          if code.start_with?('#x') then [code[2..].to_i(16)].pack('U')
          elsif code.start_with?('#') then [code[1..].to_i].pack('U')
          else ENTITIES.fetch(code, "&#{code};")
          end
        end
      end

      def coordinates_error(text, offset)
        error('map_coordinates', line: line_of(text, offset))
      end

      def line_of(text, offset)
        text[0, offset.to_i].count("\n") + 1
      end

      # --- GeoJSON

      def geojson(text)
        parsed = StrictJson.parse(text, max_bytes: MAX_BYTES, max_depth: 64)
        return error('map_file', reason_detail: 'json') unless parsed.ok?

        tree = parsed.value
        list = tree.is_a?(Hash) && tree['type'] == 'FeatureCollection' ? tree['features'] : nil
        return error('map_file', reason_detail: 'not_geojson') unless list.is_a?(Array)

        skipped = Hash.new(0)
        features = list.each_with_index.filter_map do |feature, i|
          geometry = feature.is_a?(Hash) ? feature['geometry'] : nil
          kind = geometry.is_a?(Hash) ? geometry['type'] : nil
          coordinates = case kind
                        when 'LineString' then geometry['coordinates']
                        when 'Polygon' then geometry['coordinates'].is_a?(Array) ? geometry['coordinates'][0] : nil
                        end
          unless coordinates.is_a?(Array) && coordinates.all? { |c| lonlat?(c) }
            skipped[kind == 'MultiPolygon' ? 'multipolygon' : 'geometry'] += 1
            next
          end

          props = feature['properties'].is_a?(Hash) ? feature['properties'] : {}
          id = feature['id'] || props['@id'] || "feature/#{i}"
          tags = props.select { |k, v| KEYS.include?(k) && v.is_a?(String) }
          points = coordinates.map { |lon, lat| [lat.to_f, lon.to_f] }
          { 'id' => id.to_s, 'tags' => tags, 'latlon' => points, 'closed' => kind == 'Polygon' }
        end
        [features, skipped]
      end

      def lonlat?(c)
        c.is_a?(Array) && c.size >= 2 && c[0].is_a?(Numeric) && c[1].is_a?(Numeric) && c[0].between?(-180, 180) && c[1].between?(-90, 90)
      end

      # --- Tri, origine, projection

      def assemble((features, skipped), origin)
        ways = []
        buildings = []
        features.each do |f|
          if f['tags'].key?('building') && f['closed']
            buildings << f
          elsif f['tags'].key?('highway') && f['latlon'].size >= 2
            ways << f
          else
            skipped['other'] += 1
          end
        end
        return error('map_empty') if ways.empty? && buildings.empty?

        used = (ways + buildings).flat_map { |f| f['latlon'] }
        origin ||= [(used.map(&:first).minmax.sum / 2.0), (used.map(&:last).minmax.sum / 2.0)]
        projection = MapProjection.new(*origin)
        out_ways = sort(ways).map { |f| { 'id' => f['id'], 'tags' => f['tags'], 'points_m' => f['latlon'].map { |p| projection.call(*p) } } }
        out_buildings = sort(buildings).map do |f|
          ring = f['latlon'].map { |p| projection.call(*p) }
          ring.pop if ring.size > 1 && ring.first == ring.last
          { 'id' => f['id'], 'tags' => f['tags'], 'ring_m' => ring }
        end
        Result.ok({ 'origin' => origin.map(&:to_f), 'ways' => out_ways, 'buildings' => out_buildings, 'skipped' => skipped.sort.to_h })
      end

      # Ordre stable : identifiant numérique OSM, sinon texte.
      def sort(features)
        features.sort_by { |f| [f['id'][/\d+\z/].to_i, f['id']] }
      end
    end
  end
end
