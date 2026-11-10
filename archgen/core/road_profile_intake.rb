# frozen_string_literal: true

module Archgen
  module Core
    # Barrière d'une coupe de voirie (docs/VOIRIE_CONTRACT.md). Le schéma juge la forme,
    # les catalogues fermés jugent les types, plages et éléments. Rien n'est ramené
    # dans une plage : une valeur hors plage est refusée sur son chemin.
    class RoadProfileIntake
      SUPPORTED_VERSION = 1
      # Abri d'arrêt de bus (docs/MOBILIER_CONTRACT.md §3).
      SHELTER_MIN_BAND_M = 1.6
      SHELTER_HALF_M = 1.5
      SHELTER_CLEAR_M = 2.0

      # schema : road-profile V1 ; bands, items : contenu des catalogues road_bands et road_items.
      def initialize(schema, bands:, items:)
        @schema = SchemaValidator.new(schema)
        @bands = bands.fetch('bands')
        @items = items.fetch('items')
      end

      attr_reader :bands, :items

      # Retourne un Result<profil effectif gelé>, avec ses avertissements.
      def profile(input)
        parsed = input.is_a?(String) ? StrictJson.parse(input) : Result.ok(input)
        return parsed unless parsed.ok?

        tree = parsed.value
        version = version_problem(tree)
        return Result.fail([version]) if version

        problems = @schema.validate(tree)
        return Result.fail(problems) unless problems.empty?

        problems = tree['bands'].each_with_index.flat_map { |band, i| band_problems(band, i) }
        return Result.fail(problems.sort_by(&:sort_key)) unless problems.empty?

        problems = water_problems(effective(tree))
        return Result.fail(problems.sort_by(&:sort_key)) unless problems.empty?

        value = Canonical.deep_freeze(effective(tree))
        Result.ok(value, (clearance_warnings(value) + composition_warnings(value) + shelter_warnings(value)).sort_by(&:sort_key))
      end

      private

      def version_problem(tree)
        return nil unless tree.is_a?(Hash) && tree['road_profile_version'].is_a?(Numeric) && tree['road_profile_version'] != SUPPORTED_VERSION

        Diagnostic.error('E_VERSION', '/road_profile_version', reason: 'unsupported_road_profile', value: tree['road_profile_version'], supported: SUPPORTED_VERSION)
      end

      def band_problems(band, index)
        path = "/bands/#{index}"
        entry = @bands[band['type']]
        return [Diagnostic.error('E_ROAD_BAND', "#{path}/type", reason: 'unknown_type', value: band['type'])] unless entry

        out = []
        width = band['width_m']
        unless width.between?(entry['min_width_m'], entry['max_width_m'])
          out << Diagnostic.error('E_ROAD_BAND', "#{path}/width_m", reason: 'width_range', value: width,
                                                                     min: entry['min_width_m'], max: entry['max_width_m'])
        end
        out.concat(setting_problems(band, entry, path))
        band.fetch('items', []).each_with_index do |item, j|
          item_path = "#{path}/items/#{j}"
          allowed = entry['accepts_items'] && @items.dig(item['kind'], 'bands')
          if allowed && !allowed.include?(band['type'])
            out << Diagnostic.error('E_ROAD_ITEM', "#{item_path}/kind", reason: 'item_band_mismatch', kind: item['kind'], band: band['type'], allowed: allowed)
            next
          end
          if item['kind'] == 'bus_stop' && item.fetch('variant', 'shelter') == 'shelter' && band['width_m'] < SHELTER_MIN_BAND_M
            out << Diagnostic.error('E_ROAD_ITEM', item_path, reason: 'bus_stop_band_too_narrow', value: band['width_m'], min: SHELTER_MIN_BAND_M)
          end
          out << if entry['accepts_items']
                   item_problems(item, item_path)
                 else
                   [Diagnostic.error('E_ROAD_ITEM', item_path, reason: 'band_accepts_no_items', band: band['type'])]
                 end
        end
        out.flatten
      end

      # Réglages propres à un type de bande (EAU_CONTRACT : revanche et profondeur de l'eau).
      SETTING_KEYS = %w[freeboard_m depth_m height_m slope_percent].freeze

      def setting_problems(band, entry, path)
        allowed = entry.fetch('settings', {})
        (band.keys & SETTING_KEYS).filter_map do |key|
          range = allowed[key]
          next Diagnostic.error('E_ROAD_BAND', "#{path}/#{key}", reason: 'band_setting_unavailable', band: band['type']) unless range
          next if band[key].between?(range['min'], range['max'])

          Diagnostic.error('E_ROAD_BAND', "#{path}/#{key}", reason: 'setting_range', value: band[key], min: range['min'], max: range['max'])
        end
      end

      # Bords de l'eau (EAU_CONTRACT, AG-051) : chaque côté d'un plan d'eau touche un quai ou une berge ;
      # une berge touche un seul plan d'eau ; les pentes du lit et de la berge tiennent dans leur largeur.
      WATER_EDGES = %w[quay riverbank].freeze

      def water_problems(profile)
        bands = profile['bands']
        out = coast_problems(bands)
        bands.each_with_index do |band, i|
          left = i.positive? ? bands[i - 1] : nil
          right = bands[i + 1]
          case band['type']
          when 'water'
            { 'left' => left, 'right' => right }.each do |side, other|
              next if other && WATER_EDGES.include?(other['type'])

              out << Diagnostic.error('E_ROAD_BAND', "/bands/#{i}", reason: 'water_unbounded', side: side, band_number: i + 1)
            end
            slopes = [left, right].compact.count { |b| b['type'] == 'riverbank' }
            need = Quant.q(2 * band['depth_m'] * slopes)
            if slopes.positive? && band['width_m'] < need
              out << Diagnostic.error('E_ROAD_BAND', "/bands/#{i}/width_m", reason: 'water_too_narrow', value: band['width_m'], min: need)
            end
          when 'riverbank'
            waters = [left, right].compact.select { |b| b['type'] == 'water' }
            if waters.size != 1
              out << Diagnostic.error('E_ROAD_BAND', "/bands/#{i}", reason: 'bank_without_water', band_number: i + 1)
            elsif band['width_m'] < waters.first['freeboard_m']
              out << Diagnostic.error('E_ROAD_BAND', "/bands/#{i}/width_m", reason: 'bank_too_steep', value: band['width_m'], min: waters.first['freeboard_m'])
            end
          end
        end
        out
      end

      # Littoral (EAU_CONTRACT, AG-052) : une seule mer, première ou dernière bande ; falaise et plage
      # descendent vers elle, donc ne vont pas sans mer.
      def coast_problems(bands)
        seas = bands.each_index.select { |i| bands[i]['type'] == 'sea' }
        out = seas.each_with_index.filter_map do |i, k|
          next if k.zero? && (i.zero? || i == bands.size - 1)

          Diagnostic.error('E_ROAD_BAND', "/bands/#{i}", reason: 'sea_not_outer', band_number: i + 1)
        end
        return out unless seas.empty?

        bands.each_with_index do |band, i|
          next unless %w[cliff beach].include?(band['type'])

          out << Diagnostic.error('E_ROAD_BAND', "/bands/#{i}", reason: 'coast_without_sea', band_number: i + 1)
        end
        out
      end

      def item_problems(item, path)
        entry = @items[item['kind']]
        return [Diagnostic.error('E_ROAD_ITEM', "#{path}/kind", reason: 'unknown_kind', value: item['kind'])] unless entry

        out = []
        if item.key?('variant') && !entry['variants'].key?(item['variant'])
          out << Diagnostic.error('E_ROAD_ITEM', "#{path}/variant", reason: 'unknown_variant', value: item['variant'], allowed: entry['variants'].keys)
        end
        out.concat(height_problems(item, entry, path))
        out.concat(spacing_problems(item, entry, path))
        out.concat(count_problems(item, entry, path))
        out.concat(position_problems(item, entry, path))
        out
      end

      # Pose à des positions (docs/MOBILIER_CONTRACT.md §2, AG-121) ; la longueur se vérifie au moteur.
      def position_problems(item, entry, path)
        unless item.key?('positions_m')
          return [] unless entry['repeat'] == 'positions'

          return [Diagnostic.error('E_ROAD_ITEM', path, reason: 'positions_required', kind: item['kind'])]
        end
        return [Diagnostic.error('E_ROAD_ITEM', "#{path}/positions_m", reason: 'continuous_item', kind: item['kind'])] if entry['repeat'] == 'continuous'
        return [Diagnostic.error('E_ROAD_ITEM', "#{path}/spacing_m", reason: 'positions_with_spacing', kind: item['kind'])] if item.key?('spacing_m')
        return [] if item['positions_m'].each_cons(2).all? { |a, b| b > a }

        [Diagnostic.error('E_ROAD_ITEM', "#{path}/positions_m", reason: 'positions_order')]
      end

      # Arceaux d'une attache vélos (docs/MOBILIER_CONTRACT.md, AG-120).
      def count_problems(item, entry, path)
        return [] unless item.key?('count')
        return [Diagnostic.error('E_ROAD_ITEM', "#{path}/count", reason: 'count_unavailable', kind: item['kind'])] unless entry['default_count']
        return [] if item['count'].is_a?(Integer) && item['count'].between?(entry['min_count'], entry['max_count'])

        [Diagnostic.error('E_ROAD_ITEM', "#{path}/count", reason: 'count_range', value: item['count'], min: entry['min_count'], max: entry['max_count'])]
      end

      def height_problems(item, entry, path)
        height = item.fetch('height_m', entry['default_height_m'])
        min = entry['min_height_m']
        max = entry['max_height_m']
        return [Diagnostic.error('E_ROAD_ITEM', "#{path}/height_m", reason: 'height_range', value: height, min: min, max: max)] unless height.between?(min, max)
        return [] unless item.key?('height_variation')
        return [Diagnostic.error('E_ROAD_ITEM', "#{path}/height_variation", reason: 'variation_unavailable', kind: item['kind'])] unless entry['height_variation']

        variation = item['height_variation']
        return [] if (height * (1 - variation)).between?(min, max) && (height * (1 + variation)).between?(min, max)

        [Diagnostic.error('E_ROAD_ITEM', "#{path}/height_variation", reason: 'variation_range', value: variation, min: min, max: max)]
      end

      def spacing_problems(item, entry, path)
        return [] unless item.key?('spacing_m')
        return [Diagnostic.error('E_ROAD_ITEM', "#{path}/spacing_m", reason: 'continuous_item', kind: item['kind'])] unless entry['repeat'] == 'spaced'
        return [] if item['spacing_m'] >= entry['min_spacing_m']

        [Diagnostic.error('E_ROAD_ITEM', "#{path}/spacing_m", reason: 'spacing_range', value: item['spacing_m'], min: entry['min_spacing_m'])]
      end

      def effective(tree)
        out = { 'road_profile_version' => SUPPORTED_VERSION }
        out['name'] = tree['name'] if tree.key?('name')
        out['bands'] = tree['bands'].map do |band|
          out_band = { 'type' => band['type'], 'width_m' => Quant.q(band['width_m'].to_f) }
          @bands.fetch(band['type']).fetch('settings', {}).sort.each do |key, range|
            out_band[key] = Quant.q(band.fetch(key, range['default']).to_f)
          end
          out_band.merge('items' => band.fetch('items', []).map { |item| effective_item(item) })
        end
        out
      end

      def effective_item(item)
        entry = @items.fetch(item['kind'])
        out = { 'kind' => item['kind'], 'variant' => item.fetch('variant', entry['default_variant']),
                'height_m' => Quant.q(item.fetch('height_m', entry['default_height_m']).to_f) }
        if item.key?('positions_m')
          out['positions_m'] = item['positions_m'].map { |s| Quant.q(s.to_f) }
        elsif entry['repeat'] == 'spaced'
          out['spacing_m'] = Quant.q(item.fetch('spacing_m', entry['default_spacing_m']).to_f)
        end
        out['height_variation'] = Quant.q(item.fetch('height_variation', 0).to_f) if entry['height_variation']
        out['count'] = item.fetch('count', entry['default_count']) if entry['default_count']
        out
      end

      # Bords de chaque bande, de gauche à droite.
      def edges(profile)
        left = 0.0
        profile['bands'].map do |band|
          pair = [left, left + band['width_m']]
          left = pair[1]
          pair
        end
      end

      # Arbre ou lampadaire de la même bande à moins de 2 m d'un abri, compté le long de la voie
      # comme sur une droite (docs/MOBILIER_CONTRACT.md §3).
      def shelter_warnings(profile)
        profile['bands'].each_with_index.flat_map do |band, i|
          stops = band['items'].each_with_index.select { |item, _| item['kind'] == 'bus_stop' && item['variant'] == 'shelter' }
          stops.flat_map do |stop, j|
            band['items'].each_with_index.filter_map do |item, k|
              next unless %w[tree lamp].include?(item['kind'])

              near = stop['positions_m'].find { |p| close_to?(item, p) }
              next unless near

              Diagnostic.warning('W_ROAD_CLEARANCE', "/bands/#{i}/items/#{j}", reason: 'bus_stop_clearance', kind: item['kind'], item_number: k + 1, value: near)
            end
          end
        end
      end

      def close_to?(item, position)
        reach = SHELTER_HALF_M + SHELTER_CLEAR_M
        return item['positions_m'].any? { |s| (s - position).abs < reach } if item.key?('positions_m')

        spacing = item['spacing_m']
        rank = [((position - (spacing / 2)) / spacing).round, 0].max
        ((spacing / 2) + (rank * spacing) - position).abs < reach
      end

      # Couronne d'arbre au-dessus d'une voie, trop basse (contrat : W_ROAD_CLEARANCE).
      # Les trois hauteurs possibles sont essayées : la plus petite descend, la plus grande s'étend.
      def clearance_warnings(profile)
        spans = edges(profile)
        profile['bands'].each_with_index.flat_map do |band, i|
          count = band['items'].size
          band['items'].each_with_index.flat_map do |item, j|
            next [] unless item['kind'] == 'tree'

            center = spans[i][0] + (band['width_m'] * (j + 1) / (count + 1))
            crossed_bands(profile, spans, i, center, item).map do |k|
              Diagnostic.warning('W_ROAD_CLEARANCE', "/bands/#{i}/items/#{j}", reason: 'crown_over_band', band: k, band_number: k + 1,
                                                                              clearance_m: @bands[profile['bands'][k]['type']]['clearance_m'])
            end
          end
        end
      end

      def crossed_bands(profile, spans, own, center, item)
        shape = @items['tree']['variants'][item['variant']]
        v = item['height_variation']
        heights = [item['height_m'] * (1 - v), item['height_m'], item['height_m'] * (1 + v)]
        profile['bands'].each_index.select do |k|
          clearance = @bands[profile['bands'][k]['type']]['clearance_m']
          next false if k == own || clearance.nil?

          heights.any? do |h|
            reach = shape['crown_radius_ratio'] * h
            shape['crown_base_ratio'] * h < clearance && spans[k][0] < center + reach && spans[k][1] > center - reach
          end
        end
      end

      def composition_warnings(profile)
        roles = profile['bands'].map { |band| @bands[band['type']]['role'] }
        roles.each_cons(2).with_index.filter_map do |(a, b), i|
          pair = [a, b]
          reason = if pair.include?('rail') && pair.include?('carriageway')
                     'rail_next_to_carriageway'
                   elsif pair.include?('ditch') && pair.include?('carriageway')
                     'ditch_next_to_carriageway'
                   end
          reason && Diagnostic.warning('W_ROAD_COMPOSITION', "/bands/#{i}", reason: reason, band_number: i + 1, next_number: i + 2)
        end
      end
    end
  end
end
