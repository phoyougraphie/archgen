# frozen_string_literal: true

module Archgen
  module Core
    # D'une parcelle à son bâtiment de rangée (docs/ENSEMBLE_CONTRACT.md) : configuration
    # effective complète, puis plan. Les diagnostics du moteur sont localisés sur la parcelle.
    module ParcelBuilding
      SEED_HEX_CHARS = 8
      Built = Struct.new(:config, :plan, :rear_bays, keyword_init: true)

      module_function

      # Résultat : Built. Une parcelle d'angle attend sa capacité géométrique (AG-030).
      def call(settings, parcel, registry:, intake:, materials: nil)
        return unavailable_corner(parcel) if parcel['corner']

        config = config_for(settings, parcel, registry: registry, intake: intake)
        return config unless config.ok?

        hip = hip_problem(config.value)
        return Result.fail([hip]) if hip

        rear_bays = bays(parcel['rear_m'], settings.dig('parcel', 'bay_width_m'), 0)
        plan = GeometryEngine.generate(config.value, materials: materials, row: { rear_bays: rear_bays })
        return localized(plan, parcel) unless plan.ok?

        Result.ok(Built.new(config: config.value, plan: plan.value, rear_bays: rear_bays), plan.diagnostics + config.diagnostics)
      end

      def config_for(settings, parcel, registry:, intake:)
        resolved = ConfigResolver.resolve(request(settings, parcel), registry: registry, intake: intake)
        resolved.ok? ? resolved : localized(resolved, parcel)
      end

      # Stable : ne dépend que de la seed de l'ensemble et de l'identifiant de la parcelle.
      def seed(ensemble_seed, parcel_id)
        DeterministicRandom.hex(ensemble_seed, "parcel/#{parcel_id}/seed")[0, SEED_HEX_CHARS].to_i(16)
      end

      def bays(length, bay_width, minimum)
        [((length + Quant::EPSILON) / bay_width).floor, minimum].max
      end

      def request(settings, parcel)
        building = settings['building']
        front = bays(parcel['width_m'], settings.dig('parcel', 'bay_width_m'), 1)
        Merge.leaves(
          building,
          'footprint' => { 'width_m' => parcel['width_m'], 'depth_m' => parcel['depth_m'] },
          'seed' => seed(settings['seed'], parcel['id']),
          'facade' => { 'front_bays' => front, 'side_bays' => 0, 'entry_bay' => front / 2 }
        )
      end
      private_class_method :request

      def hip_problem(config)
        return nil unless config.dig('roof', 'type') == 'hip'

        Diagnostic.error('E_STREET_ROOF', '/building/roof/type', reason: 'hip_in_row')
      end
      private_class_method :hip_problem

      def unavailable_corner(parcel)
        Result.fail([Diagnostic.error('E_STREET_CORNER', "/parcels/#{parcel['id']}", reason: 'corner_parcel_unavailable', id: parcel['id'])])
      end
      private_class_method :unavailable_corner

      def localized(result, parcel)
        Result.fail(result.errors.map do |d|
          Diagnostic.error(d.code, "/parcels/#{parcel['id']}#{d.path}", **d.params.transform_keys(&:to_sym))
        end)
      end
      private_class_method :localized
    end
  end
end
