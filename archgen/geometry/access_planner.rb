# frozen_string_literal: true

module Archgen
  module Geometry
    # Accès à la cour d'une forme fermée (docs/ENSEMBLE_CONTRACT.md, Accès à la cour). Pur et
    # déterministe : une cour sans accès n'est jamais produite, et un nombre qui ne tient pas
    # est refusé sans être réduit.
    module AccessPlanner
      FORMS = %w[gap].freeze
      PERIMETER_ONE_M = 80.0
      PERIMETER_TWO_M = 160.0
      NOISE = 1e-6

      module_function

      # layout : le résultat de ParcelLayout ; rend la même forme, avec `accesses`.
      def call(layout, settings, form:)
        count = access_count(settings.dig('access', 'count'), layout['metrics']['facade_length_m'])
        chosen = choose(layout['parcels'], settings, count)
        return chosen unless chosen.ok?

        apply(layout, chosen.value, settings, form)
      end

      def access_count(requested, perimeter)
        return requested unless requested == 'auto'
        return 1 if perimeter < PERIMETER_ONE_M

        perimeter < PERIMETER_TWO_M ? 2 : 3
      end

      def choose(parcels, settings, count)
        width = settings.dig('access', 'width_m')
        by_segment = parcels.group_by { |p| p['segment'] }
        order = by_segment.keys.sort_by { |segment| [Core::DeterministicRandom.unit(settings['seed'], "access/#{segment}"), segment] }
        chosen = []
        index = 0
        misses = 0
        while chosen.size < count
          return too_many(count, chosen.size) if misses == order.size

          segment = order[index % order.size]
          index += 1
          pick = best_candidate(by_segment.fetch(segment), chosen, width)
          misses = pick ? 0 : misses + 1
          chosen << pick if pick
        end
        Core::Result.ok(chosen)
      end
      private_class_method :choose

      # Jamais en angle ni contre un autre segment : une candidate a ses deux voisines sur le
      # même segment. Puis la plus proche du milieu ; à égalité, le plus petit rang.
      def best_candidate(row, chosen, width)
        length = row.sum { |p| p['width_m'] }
        taken = chosen.map { |p| p['id'] }
        position = 0.0
        scored = row.each_with_index.filter_map do |parcel, rank|
          middle = position + (parcel['width_m'] / 2.0)
          position += parcel['width_m']
          next unless candidate?(row, parcel, rank, width, taken)

          [((middle - (length / 2.0)).abs / NOISE).round, rank, parcel]
        end
        scored.min_by { |distance, rank, _| [distance, rank] }&.last
      end
      private_class_method :best_candidate

      def candidate?(row, parcel, rank, width, taken)
        return false if parcel['corner'] || parcel['width_m'] <= width + NOISE
        return false if rank.zero? || rank == row.size - 1
        return false if taken.include?(parcel['id'])

        [row[rank - 1], row[rank + 1]].none? { |neighbour| taken.include?(neighbour['id']) }
      end
      private_class_method :candidate?

      def too_many(count, placed)
        Core::Result.fail([Core::Diagnostic.error('E_STREET_ACCESS', '/access/count', reason: 'access_no_room', value: count, placed: placed)])
      end
      private_class_method :too_many

      def apply(layout, chosen, settings, form)
        width = settings.dig('access', 'width_m')
        parcels = layout['parcels']
        chosen.each { |access| parcels = open_gap(parcels, access, width) }
        accesses = chosen.map { |access| access_entry(access, width, form) }.sort_by { |a| a['id'] }
        Core::Result.ok(Core::Canonical.deep_freeze(
                          'parcels' => parcels,
                          'accesses' => accesses,
                          'metrics' => layout['metrics'].merge('parcel_count' => parcels.size, 'access_count' => accesses.size)
                        ))
      end
      private_class_method :apply

      # La parcelle disparaît ; ses deux voisines s'étendent à parts égales jusqu'au vide.
      def open_gap(parcels, access, width)
        index = parcels.index { |p| p['id'] == access['id'] }
        extra = (access['width_m'] - width) / 2.0
        before = parcels[index - 1]
        after = parcels[index + 1]
        rest = parcels.dup
        rest[index - 1] = ParcelLayout.reshaped(before, shift_m: 0.0, width_m: before['width_m'] + extra)
        rest[index + 1] = ParcelLayout.reshaped(after, shift_m: -extra, width_m: after['width_m'] + extra)
        rest.delete_at(index)
        rest
      end
      private_class_method :open_gap

      def access_entry(access, width, form)
        { 'id' => access['id'], 'segment' => access['segment'], 'form' => form, 'width_m' => width,
          'center_m' => access['origin_m'].zip(access['tangent']).map { |o, t| Core::Quant.q(o + (t * access['width_m'] / 2.0)) } }
      end
      private_class_method :access_entry
    end
  end
end
