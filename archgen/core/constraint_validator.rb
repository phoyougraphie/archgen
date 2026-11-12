# frozen_string_literal: true

module Archgen
  module Core
    # Contraintes transversales d'une configuration effective. Elles sont hard :
    # bloquantes dans tous les modes de fidélité, indépendantes des profils.
    module ConstraintValidator
      SHOP_MIN_HEIGHT_M = 3.2

      module_function

      def call(config, profile: nil, materials: nil, fidelity_rules: nil)
        data = config.is_a?(BuildingConfig) ? config.to_h : config
        out = []
        check_name(data, out)
        check_levels(data, out)
        check_facade(data, out)
        check_roof(data, out)
        check_materials(data, materials, out) if materials
        check_glazing(data, out)
        check_shop(data, out)
        out.concat(fidelity_rules.call(data, profile)) if fidelity_rules && profile
        out.sort_by(&:sort_key)
      end

      def wall_top_m(data)
        levels = data['levels']
        return levels['heights_m'].sum unless levels['heights_m'].empty?

        shop = data.dig('shop', 'height_m')
        return shop + (levels['height_m'] * (levels['count'] - 1)) if shop && data['ground_floor'] == 'shop'

        levels['height_m'] * levels['count']
      end

      # Vitrage et matière du verre vont ensemble ; absents, le bâtiment est celui d'avant AG-064.
      def check_glazing(data, out)
        glazing = data['features'].fetch('glazing', false)
        glass = data['materials'].key?('glass')
        out << Diagnostic.error('E_SCHEMA', '/materials/glass', reason: 'glass_required') if glazing && !glass
        out << Diagnostic.error('E_SCHEMA', '/materials/glass', reason: 'glass_without_glazing') if glass && !glazing
        out << Diagnostic.error('E_SCHEMA', '/features/glazing', reason: 'glazing_false_written') if data['features'].key?('glazing') && !glazing
        out << Diagnostic.error('E_SCHEMA', '/features/chimneys', reason: 'chimneys_false_written') if data['features'].key?('chimneys') && !data['features']['chimneys']
        check_muntins(data, glazing, out)
        out << Diagnostic.error('E_SCHEMA', '/features/dormers', reason: 'dormers_false_written') if data['features'].key?('dormers') && !data['features']['dormers']
        out << Diagnostic.error('E_SCHEMA', '/features/genoise', reason: 'genoise_false_written') if data['features'].key?('genoise') && !data['features']['genoise']
        stepped = data['features']['stepped_gable']
        out << Diagnostic.error('E_SCHEMA', '/features/stepped_gable', reason: 'stepped_gable_false_written') if data['features'].key?('stepped_gable') && !stepped
        out << Diagnostic.error('E_ROOF_GEOMETRY', '/features/stepped_gable', reason: 'stepped_gable_ridge') if stepped && data['roof']['ridge'] != 'perpendicular'
        if stepped && data['roof']['overhang_m'] > 0.05 + Quant::EPSILON
          out << Diagnostic.error('E_ROOF_GEOMETRY', '/roof/overhang_m', reason: 'stepped_gable_overhang', limit: 0.05)
        end
        check_timber(data, out)
        out << Diagnostic.error('E_SCHEMA', '/structure/ground_slab', reason: 'ground_slab_false_written') if data['structure'].key?('ground_slab') && data['structure']['ground_slab'] != true
        front = data['features']['shop_front']
        out << Diagnostic.error('E_SCHEMA', '/features/shop_front', reason: 'shop_front_without_shop') if front && data['ground_floor'] != 'shop'
        out << Diagnostic.error('E_SCHEMA', '/materials/awning', reason: 'awning_material_required') if front == 'awning' && !data['materials'].key?('awning')
        out << Diagnostic.error('E_SCHEMA', '/materials/awning', reason: 'awning_material_without_awning') if front != 'awning' && data['materials'].key?('awning')
        %w[pilotis structural_grid sun_shades].each do |key|
          out << Diagnostic.error('E_SCHEMA', "/features/#{key}", reason: "#{key}_false_written") if data['features'].key?(key) && !data['features'][key]
        end
        if data['features']['structural_grid']
          %w[timber_frame classical shutters].each do |rival|
            out << Diagnostic.error('E_SCHEMA', '/features/structural_grid', reason: "structural_grid_with_#{rival}") if data['features'][rival]
          end
        end
        if data['features']['pilotis']
          out << Diagnostic.error('E_SCHEMA', '/features/pilotis', reason: 'pilotis_levels') if data['levels']['count'] < 2
          out << Diagnostic.error('E_SCHEMA', '/features/pilotis', reason: 'pilotis_with_shop') if data['ground_floor'] == 'shop'
        end
        out << Diagnostic.error('E_SCHEMA', '/features/classical', reason: 'classical_false_written') if data['features'].key?('classical') && !data['features']['classical']
        out << Diagnostic.error('E_SCHEMA', '/features/classical', reason: 'classical_with_timber') if data['features']['classical'] && data['features']['timber_frame']
        cladding = data['features']['cladding'] == true
        out << Diagnostic.error('E_SCHEMA', '/features/cladding', reason: 'cladding_false_written') if data['features'].key?('cladding') && !cladding
        out << Diagnostic.error('E_SCHEMA', '/materials/cladding', reason: 'cladding_material_required') if cladding && !data['materials'].key?('cladding')
        out << Diagnostic.error('E_SCHEMA', '/materials/cladding', reason: 'cladding_material_without_cladding') if !cladding && data['materials'].key?('cladding')
        shutters = data['features']['shutters'] == true
        out << Diagnostic.error('E_SCHEMA', '/features/shutters', reason: 'shutters_false_written') if data['features'].key?('shutters') && !shutters
        out << Diagnostic.error('E_SCHEMA', '/materials/shutters', reason: 'shutters_material_required') if shutters && !data['materials'].key?('shutters')
        out << Diagnostic.error('E_SCHEMA', '/materials/shutters', reason: 'shutters_material_without_shutters') if !shutters && data['materials'].key?('shutters')
      end
      private_class_method :check_glazing

      # AG-070 : petits bois écrits seulement s'ils sont vrais, avec le vitrage et leur nombre de rangs.
      def check_muntins(data, glazing, out)
        features = data['features']
        muntins = features['muntins'] == true
        rows = data['facade'].key?('muntin_rows')
        out << Diagnostic.error('E_SCHEMA', '/features/muntins', reason: 'muntins_false_written') if features.key?('muntins') && !muntins
        out << Diagnostic.error('E_SCHEMA', '/features/muntins', reason: 'muntins_without_glazing') if muntins && !glazing
        out << Diagnostic.error('E_SCHEMA', '/facade/muntin_rows', reason: 'muntin_rows_required') if muntins && !rows
        out << Diagnostic.error('E_SCHEMA', '/facade/muntin_rows', reason: 'muntin_rows_without_muntins') if rows && !muntins
      end
      private_class_method :check_muntins

      # AG-083 : le pan de bois occupe l'épaisseur devant le mur ; rien d'autre ne s'y pose.
      TIMBER_RIVALS = %w[surrounds shutters cornice cladding].freeze

      def check_timber(data, out)
        features = data['features']
        timber = features['timber_frame'] == true
        out << Diagnostic.error('E_SCHEMA', '/features/timber_frame', reason: 'timber_false_written') if features.key?('timber_frame') && !timber
        out << Diagnostic.error('E_SCHEMA', '/materials/timber', reason: 'timber_material_required') if timber && !data['materials'].key?('timber')
        out << Diagnostic.error('E_SCHEMA', '/materials/timber', reason: 'timber_material_without_timber') if !timber && data['materials'].key?('timber')
        return unless timber

        TIMBER_RIVALS.each do |rival|
          out << Diagnostic.error('E_SCHEMA', '/features/timber_frame', reason: "timber_with_#{rival}") if features[rival]
        end
      end
      private_class_method :check_timber

      # AG-065 : la hauteur de commerce n'existe qu'avec un rez-de-chaussée commerçant, et
      # seulement sans hauteurs par niveau, qui priment.
      def check_shop(data, out)
        shop = data['ground_floor'] == 'shop'
        height = data.key?('shop')
        heights = data['levels']['heights_m']
        out << Diagnostic.error('E_SCHEMA', '/shop', reason: 'shop_without_ground_floor') if height && !shop
        return unless shop

        if heights.any?
          out << Diagnostic.error('E_SCHEMA', '/shop/height_m', reason: 'shop_with_heights') if height
          if heights.first < SHOP_MIN_HEIGHT_M - Quant::EPSILON
            out << Diagnostic.error('E_SCHEMA', '/levels/heights_m/0', reason: 'shop_ground_too_low', limit: SHOP_MIN_HEIGHT_M, value: heights.first)
          end
        elsif !height
          out << Diagnostic.error('E_SCHEMA', '/shop/height_m', reason: 'shop_height_required')
        end
      end
      private_class_method :check_shop

      def check_name(data, out)
        trimmed = data['name'].strip
        out << Diagnostic.error('E_SCHEMA', '/name', reason: 'blank') if trimmed.empty?
      end
      private_class_method :check_name

      def check_levels(data, out)
        levels = data['levels']
        heights = levels['heights_m']
        unless heights.empty? || heights.size == levels['count']
          out << Diagnostic.error('E_SCHEMA', '/levels/heights_m', reason: 'count_mismatch', expected: levels['count'])
          return
        end
        top = wall_top_m(data)
        return unless top > Limits::MAX_WALL_TOP_M + Quant::EPSILON

        out << Diagnostic.error('E_BUDGET', '/levels', reason: 'wall_top', limit: Limits::MAX_WALL_TOP_M, value: top)
      end
      private_class_method :check_levels

      def check_facade(data, out)
        facade = data['facade']
        return if facade['entry_bay'] < facade['front_bays']

        out << Diagnostic.error('E_SCHEMA', '/facade/entry_bay', reason: 'entry_bay_out_of_range', limit: facade['front_bays'])
      end
      private_class_method :check_facade

      def check_roof(data, out)
        roof = data['roof']
        out << roof_error('ridge', 'ridge_axis_roof', type: roof['type']) if roof.key?('ridge') && roof['type'] != 'gable'
        case roof['type']
        when 'flat' then require_zero(roof, %w[pitch_deg lower_pitch_deg inset_m], out)
        when 'gable', 'hip' then check_sloped(roof, out)
        when 'sawtooth'
          check_sloped(roof, out)
          require_zero(roof, %w[overhang_m], out)
        when 'mansard' then check_mansard(data, roof, out)
        end
        check_eave(data, roof, out)
      end
      private_class_method :check_roof

      def check_sloped(roof, out)
        require_zero(roof, %w[lower_pitch_deg inset_m], out)
        require_range(roof, 'pitch_deg', 5.0, 65.0, out)
      end
      private_class_method :check_sloped

      def check_mansard(data, roof, out)
        require_range(roof, 'pitch_deg', 5.0, 45.0, out)
        require_range(roof, 'lower_pitch_deg', 45.0, 80.0, out)
        unless roof['lower_pitch_deg'] > roof['pitch_deg']
          out << roof_error('lower_pitch_deg', 'lower_not_steeper')
        end
        out << roof_error('inset_m', 'inset_not_positive') unless roof['inset_m'].positive?
        half_span = [data['footprint']['width_m'], data['footprint']['depth_m']].min / 2.0
        return if half_span - roof['inset_m'] >= 0.2 - Quant::EPSILON

        out << roof_error('inset_m', 'no_remaining_span', limit: half_span - 0.2)
      end
      private_class_method :check_mansard

      # Une rive sous Z=0 est rejetée (contrat géométrique, Toitures).
      def check_eave(data, roof, out)
        pitch = roof['type'] == 'mansard' ? roof['lower_pitch_deg'] : roof['pitch_deg']
        eave = wall_top_m(data) - (Math.tan(pitch * Math::PI / 180.0) * roof['overhang_m'])
        out << roof_error('overhang_m', 'eave_below_ground', value: eave) if eave.negative?
      end
      private_class_method :check_eave

      def require_zero(roof, keys, out)
        keys.each { |key| out << roof_error(key, 'inactive_field_not_zero') unless roof[key].zero? }
      end
      private_class_method :require_zero

      def require_range(roof, key, min, max, out)
        return if roof[key].between?(min, max)

        out << roof_error(key, 'out_of_range', min: min, max: max, type: roof['type'])
      end
      private_class_method :require_range

      def roof_error(key, reason, **params)
        Diagnostic.error('E_ROOF_GEOMETRY', "/roof/#{key}", reason: reason, **params)
      end
      private_class_method :roof_error

      def check_materials(data, materials, out)
        data['materials'].each do |role, id|
          next if materials.key?(id)

          out << Diagnostic.error('E_SCHEMA', "/materials/#{role}", reason: 'unknown_material', value: id)
        end
      end
      private_class_method :check_materials
    end
  end
end
