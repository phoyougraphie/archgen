# frozen_string_literal: true

module Archgen
  module Core
    # Contraintes transversales d'une configuration effective. Elles sont hard :
    # bloquantes dans tous les modes de fidélité, indépendantes des profils.
    module ConstraintValidator
      module_function

      def call(config, profile: nil, materials: nil, fidelity_rules: nil)
        data = config.is_a?(BuildingConfig) ? config.to_h : config
        out = []
        check_name(data, out)
        check_levels(data, out)
        check_facade(data, out)
        check_roof(data, out)
        check_materials(data, materials, out) if materials
        out.concat(fidelity_rules.call(data, profile)) if fidelity_rules && profile
        out.sort_by(&:sort_key)
      end

      def wall_top_m(data)
        levels = data['levels']
        return levels['heights_m'].sum unless levels['heights_m'].empty?

        levels['height_m'] * levels['count']
      end

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
        case roof['type']
        when 'flat' then require_zero(roof, %w[pitch_deg lower_pitch_deg inset_m], out)
        when 'gable', 'hip' then check_sloped(roof, out)
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
