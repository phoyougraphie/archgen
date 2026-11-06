# frozen_string_literal: true

module Archgen
  module Core
    # D'une parcelle à son bâtiment de rangée (docs/ENSEMBLE_CONTRACT.md) : configuration
    # effective complète, puis plan. Les diagnostics du moteur sont localisés sur la parcelle.
    module ParcelBuilding
      SEED_HEX_CHARS = 8
      Built = Struct.new(:config, :plan, :rear_bays, :plan_warnings, keyword_init: true)
      # Tout ce qui décide de la géométrie, avant de la calculer.
      Prepared = Struct.new(:config, :row, :warnings, keyword_init: true)

      module_function

      # Résultat : Built.
      def call(settings, parcel, registry:, intake:, materials: nil)
        ready = prepare(settings, parcel, registry: registry, intake: intake)
        ready.ok? ? generate(ready.value, parcel, materials: materials) : ready
      end

      def prepare(settings, parcel, registry:, intake:)
        config = config_for(settings, parcel, registry: registry, intake: intake)
        return config unless config.ok?

        hip = hip_problem(config.value)
        return Result.fail([hip]) if hip

        row = { rear_bays: bays(parcel['rear_m'], settings.dig('parcel', 'bay_width_m'), 0),
                delta_left_m: parcel['delta_left_m'], delta_right_m: parcel['delta_right_m'] }
        row[:porch] = parcel['porch'] if parcel['porch']
        Result.ok(Prepared.new(config: config.value, row: row, warnings: config.warnings))
      end

      def generate(ready, parcel, materials: nil)
        plan = GeometryEngine.generate(ready.config, materials: materials, row: ready.row)
        return localized(plan, parcel) unless plan.ok?

        built = Built.new(config: ready.config, plan: plan.value, rear_bays: ready.row[:rear_bays], plan_warnings: plan.warnings)
        Result.ok(built, (ready.warnings + plan.warnings).map { |d| relocate(d, parcel) })
      end

      # Deux parcelles de même clé ont le même plan. Reculs et travées arrière n'étant pas dans la
      # configuration, ils entrent ici. La seed n'y entre que si le jitter la rend géométrique.
      def share_key(ready)
        data = ready.config.to_h
        ignored = data.dig('facade', 'jitter_m').zero? ? %w[name seed] : %w[name]
        Canonical.digest('config' => data.reject { |key, _| ignored.include?(key) }, 'row' => ready.row.transform_keys(&:to_s))
      end

      def relocate(diagnostic, parcel)
        path = "/parcels/#{parcel['id']}#{diagnostic.path}"
        params = diagnostic.params.transform_keys(&:to_sym)
        diagnostic.error? ? Diagnostic.error(diagnostic.code, path, **params) : Diagnostic.warning(diagnostic.code, path, **params)
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

      def localized(result, parcel)
        Result.fail(result.errors.map { |d| relocate(d, parcel) })
      end
      private_class_method :localized
    end
  end
end
