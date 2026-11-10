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

        # AG-097 : largeur des fenêtres à l'échelle tirée, au pas de 5 cm ; seconde résolution.
        scale = parcel.dig('variety', 'ground', 'width_scale')
        if scale
          width = ((config.value.dig('facade', 'window_width_m') * scale / 0.05).round * 0.05).round(2)
          config = config_for(settings, parcel.merge('window_width_m' => width), registry: registry, intake: intake)
          return config unless config.ok?
        end

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
      # configuration, ils entrent ici. La seed n'y entre que si le jitter, les cheminées ou les teintes (AG-104) la font compter.
      def share_key(ready)
        data = ready.config.to_h
        seeded = data.dig('facade', 'jitter_m').positive? || (data['features']['chimneys'] && data['lod'] == 1) || data.dig('facade', 'tint')
        ignored = seeded ? %w[name] : %w[name seed]
        Canonical.digest('config' => data.reject { |key, _| ignored.include?(key) }, 'row' => ready.row.transform_keys(&:to_s))
      end

      def relocate(diagnostic, parcel)
        path = "/parcels/#{parcel['id']}#{diagnostic.path}"
        params = diagnostic.params.transform_keys(&:to_sym)
        diagnostic.error? ? Diagnostic.error(diagnostic.code, path, **params) : Diagnostic.warning(diagnostic.code, path, **params)
      end

      # Publique : EnsembleVariety y juge un tirage contre les règles du style.
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
        # Rues variées (AG-061) : niveaux et toit tirés pour cette parcelle.
        pick = parcel['variety'] || {}
        building = Merge.leaves(building, 'levels' => { 'count' => pick['levels'] }) if pick['levels']
        building = Merge.leaves(building, 'roof' => { 'type' => pick['roof'] }) if pick['roof']
        # AG-097 : commerce tiré ; un réglage propre `ground_floor` passe ensuite.
        building = Merge.leaves(building, 'ground_floor' => pick.dig('ground', 'shop') ? 'shop' : 'dwelling') if pick['ground']&.key?('shop')
        # Réglages propres (AG-068) : après la variété.
        building = Merge.leaves(building, EnsembleParcels.building_overrides(parcel['own'])) if parcel['own']
        # AG-096 : un autre style que la rue (ADR-49) ; ses défauts passent avant les réglages de la rue.
        building = Merge.leaves(building, 'facade' => { 'window_width_m' => parcel['window_width_m'] }) if parcel['window_width_m']
        own_profile = EnsembleParcels.profile_for(parcel['own'])
        building = building.merge('profile' => own_profile) if own_profile
        ground = pick['ground'] || {}
        entry = ground['entry_bay'] && ground['entry_bay'] < front ? ground['entry_bay'] : front / 2
        Merge.leaves(
          building,
          'footprint' => { 'width_m' => parcel['width_m'], 'depth_m' => parcel['depth_m'] },
          'seed' => seed(settings['seed'], parcel['id']),
          'facade' => { 'front_bays' => front, 'side_bays' => 0, 'entry_bay' => entry }
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
