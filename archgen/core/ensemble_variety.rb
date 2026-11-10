# frozen_string_literal: true

module Archgen
  module Core
    # Rues variées (AG-061 ; docs/RUE_VARIEE_CONTRACT.md, ADR-44) : nombre de niveaux et toit tirés par
    # parcelle. Pur et déterministe : mêmes réglages, même seed, même rue.
    module EnsembleVariety
      DEFAULT_STEP = 2

      module_function

      # Contrôles du réglage contre les règles du style, sur une parcelle témoin : chaque bout de la
      # fourchette et chaque toit de la liste passent par la même résolution qu'un bâtiment.
      def problems(settings, parcel, registry:, intake:)
        variety = settings['variety']
        out = []
        out << Diagnostic.error('E_STREET_VARIETY', '/variety/roofs', reason: 'variety_hip_roof') if variety.fetch('roofs', []).include?('hip')
        return out unless out.empty?

        levels = variety['levels']
        if levels
          [levels['min'], levels['max']].uniq.each do |count|
            found = rule_error(settings, parcel, { 'levels' => count }, '/levels/count', registry, intake)
            next unless found

            out << Diagnostic.error('E_STREET_VARIETY', '/variety/levels', reason: 'variety_style_levels',
                                                                         min: found.params['min'], max: found.params['max'], value: count)
            break
          end
        end
        variety.fetch('roofs', []).each_with_index do |roof, i|
          found = rule_error(settings, parcel, { 'roof' => roof }, '/roof/type', registry, intake)
          next unless found

          out << Diagnostic.error('E_STREET_VARIETY', "/variety/roofs/#{i}", reason: 'variety_style_roof', value: roof, allowed: Array(found.params['allowed']).join(', '))
        end
        out
      end

      def rule_error(settings, parcel, pick, path, registry, intake)
        resolved = ParcelBuilding.config_for(settings, parcel.merge('variety' => pick), registry: registry, intake: intake)
        return nil if resolved.ok?

        resolved.errors.find { |d| d.code == 'E_HISTORICAL' && d.path.end_with?(path) }
      end

      # Parcelles avec leur tirage `variety` : { 'levels' => n, 'roof' => type }, les clés absentes
      # n'étant pas tirées. La voisine est la parcelle précédente de la même rangée.
      def assign(settings, parcels)
        variety = settings['variety']
        levels = variety['levels']
        roofs = variety['roofs']
        seed = settings['seed']
        previous = {}
        first = {}
        # AG-107 : un contour fermé rejoint sa première parcelle ; il reste au plus `restant × écart` pour y revenir.
        sizes = parcels.group_by { |p| p['id'].split('/').first }.transform_values(&:size)
        seen = Hash.new(0)
        closed = settings.dig('trace', 'closed')
        parcels.map do |parcel|
          row = parcel['id'].split('/').first
          index = seen[row]
          seen[row] += 1
          pick = {}
          if levels
            lo, hi = window(levels, previous[row])
            lo, hi = closing(levels, lo, hi, first[row], sizes[row] - index) if closed && first.key?(row) && sizes[row] > 2
            pick['levels'] = lo + (DeterministicRandom.unit(seed, "parcel/#{parcel['id']}/levels") * (hi - lo + 1)).floor
            previous[row] = pick['levels']
            first[row] ||= pick['levels']
          end
          pick['roof'] = roofs[(DeterministicRandom.unit(seed, "parcel/#{parcel['id']}/roof") * roofs.size).floor] if roofs
          ground = ground_pick(variety['ground'], settings, parcel) if variety['ground']
          pick['ground'] = ground if ground && !ground.empty?
          parcel.merge('variety' => pick)
        end
      end

      WIDTH_RANGE = [0.85, 1.15].freeze

      # AG-097 : rez-de-chaussée moins répétitifs. Travée de la porte (hors des bouts dès 3 travées),
      # commerce selon la part demandée, échelle de la largeur des fenêtres au pas de 5 %.
      def ground_pick(ground, settings, parcel)
        seed = settings['seed']
        key = "parcel/#{parcel['id']}/ground"
        out = {}
        if ground['entry']
          bays = ParcelBuilding.bays(parcel['width_m'], settings.dig('parcel', 'bay_width_m'), 1)
          low, high = bays >= 3 ? [1, bays - 2] : [0, bays - 1]
          out['entry_bay'] = low + (DeterministicRandom.unit(seed, "#{key}/entry") * (high - low + 1)).floor
        end
        out['shop'] = DeterministicRandom.unit(seed, "#{key}/shop") < ground['shop_share'] if ground.key?('shop_share')
        if ground['widths']
          steps = ((WIDTH_RANGE[1] - WIDTH_RANGE[0]) / 0.05).round
          out['width_scale'] = (WIDTH_RANGE[0] + (0.05 * (DeterministicRandom.unit(seed, "#{key}/width") * (steps + 1)).floor)).round(2)
        end
        out
      end
      private_class_method :ground_pick

      # Fenêtre réduite pour que les `remaining` pas jusqu'à la première parcelle restent possibles.
      # Jamais vide : la voisine précédente était elle-même à `remaining + 1` pas au plus de la première.
      def closing(levels, lo, hi, start, remaining)
        step = levels.fetch('max_step', DEFAULT_STEP)
        [[lo, start - (remaining * step)].max, [hi, start + (remaining * step)].min]
      end
      private_class_method :closing

      # Fenêtre permise : la fourchette, réduite à ± l'écart autour de la voisine. Elle n'est jamais vide,
      # la voisine étant elle-même dans la fourchette.
      def window(levels, neighbour)
        lo = levels['min']
        hi = levels['max']
        return [lo, hi] unless neighbour

        step = levels.fetch('max_step', DEFAULT_STEP)
        [[lo, neighbour - step].max, [hi, neighbour + step].min]
      end

      # Répartition pour l'aperçu : niveaux et toits comptés.
      def summary(parcels)
        picks = parcels.map { |p| p['variety'] || {} }
        out = { 'levels' => picks.filter_map { |v| v['levels'] }.tally.sort.to_h.transform_keys(&:to_s),
                'roofs' => picks.filter_map { |v| v['roof'] }.tally.sort.to_h }
        # AG-097 : seulement avec un tirage de rez-de-chaussée ; une rue variée d'avant garde son plan.
        out['shops'] = picks.count { |v| v.dig('ground', 'shop') } if picks.any? { |v| v['ground'] }
        out
      end
    end
  end
end
