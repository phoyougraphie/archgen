# frozen_string_literal: true

module Archgen
  module Core
    # Évalue les règles de style d'un profil selon le mode de fidélité. Le registre
    # est fermé : une règle est une clé connue, jamais du code chargé depuis un profil.
    # Les contraintes hard du noyau restent dans ConstraintValidator.
    module FidelityRules
      SEVERITY = {
        'hard' => { 'strict' => :error, 'plausible' => :error, 'creative' => :error },
        'historical' => { 'strict' => :error, 'plausible' => :warning, 'creative' => :ignore },
        'soft' => { 'strict' => :warning, 'plausible' => :warning, 'creative' => :ignore },
        'decorative' => { 'strict' => :ignore, 'plausible' => :ignore, 'creative' => :ignore }
      }.freeze

      module_function

      def call(data, profile)
        profile.rules.flat_map { |rule| evaluate(rule, data) }
      end

      def severity(kind, fidelity)
        SEVERITY.fetch(kind).fetch(fidelity)
      end

      def evaluate(rule, data)
        level = severity(rule['kind'], data['fidelity'])
        return [] if level == :ignore

        violation = violation_for(rule, data)
        return [] unless violation

        path, params = violation
        args = { id: rule['id'], kind: rule['kind'], rule: rule['rule'], **params }
        [level == :error ? Diagnostic.error('E_HISTORICAL', path, **args) : Diagnostic.warning('W_HISTORICAL', path, **args)]
      end
      private_class_method :evaluate

      def violation_for(rule, data)
        params = rule['params']
        case rule['rule']
        when 'window_ratio'
          facade = data['facade']
          out_of_range('/facade/window_height_m', facade['window_height_m'] / facade['window_width_m'], params)
        when 'level_count' then out_of_range('/levels/count', data['levels']['count'], params)
        when 'roof_type' then not_allowed('/roof/type', data['roof']['type'], params['values'])
        when 'material_allowed'
          not_allowed("/materials/#{params['role']}", data['materials'][params['role']], params['values'])
        end
      end
      private_class_method :violation_for

      def out_of_range(path, value, params)
        return nil if value.between?(params['min'], params['max'])

        [path, { value: value, min: params['min'], max: params['max'] }]
      end
      private_class_method :out_of_range

      def not_allowed(path, value, allowed)
        return nil if allowed.include?(value)

        [path, { value: value, allowed: allowed }]
      end
      private_class_method :not_allowed
    end
  end
end
