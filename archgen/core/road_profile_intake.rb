# frozen_string_literal: true

module Archgen
  module Core
    # Barrière d'une coupe de voirie (docs/VOIRIE_CONTRACT.md). Le schéma juge la forme,
    # les catalogues fermés jugent les types, plages et éléments. Rien n'est ramené
    # dans une plage : une valeur hors plage est refusée sur son chemin.
    class RoadProfileIntake
      SUPPORTED_VERSION = 1

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

        value = Canonical.deep_freeze(effective(tree))
        Result.ok(value, (clearance_warnings(value) + composition_warnings(value)).sort_by(&:sort_key))
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
        band.fetch('items', []).each_with_index do |item, j|
          item_path = "#{path}/items/#{j}"
          out << if entry['accepts_items']
                   item_problems(item, item_path)
                 else
                   [Diagnostic.error('E_ROAD_ITEM', item_path, reason: 'band_accepts_no_items', band: band['type'])]
                 end
        end
        out.flatten
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
        out
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
          { 'type' => band['type'], 'width_m' => Quant.q(band['width_m'].to_f),
            'items' => band.fetch('items', []).map { |item| effective_item(item) } }
        end
        out
      end

      def effective_item(item)
        entry = @items.fetch(item['kind'])
        out = { 'kind' => item['kind'], 'variant' => item.fetch('variant', entry['default_variant']),
                'height_m' => Quant.q(item.fetch('height_m', entry['default_height_m']).to_f) }
        out['spacing_m'] = Quant.q(item.fetch('spacing_m', entry['default_spacing_m']).to_f) if entry['repeat'] == 'spaced'
        out['height_variation'] = Quant.q(item.fetch('height_variation', 0).to_f) if entry['height_variation']
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
