# frozen_string_literal: true

module Archgen
  module Core
    # Brouillon + profil (ou base) → configuration effective validée et gelée.
    module ConfigResolver
      TOP_LEVEL_STYLE_BLOCKS = %w[facade roof structure materials features].freeze
      DEFAULT_GLASS = 'glass'
      KEPT_ON_STYLE_CHANGE =%w[name mode lod seed fidelity footprint levels building_type].freeze
      ROOF_PRESETS = {
        'flat' => { 'pitch_deg' => 0.0, 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0 },
        'gable' => { 'pitch_deg' => 25.0, 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0 },
        'hip' => { 'pitch_deg' => 25.0, 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0 },
        'mansard' => { 'pitch_deg' => 25.0, 'lower_pitch_deg' => 65.0, 'inset_m' => 0.9 }
      }.freeze
      INACTIVE_ROOF_FIELDS = {
        'flat' => %w[pitch_deg lower_pitch_deg inset_m],
        'gable' => %w[lower_pitch_deg inset_m],
        'hip' => %w[lower_pitch_deg inset_m],
        'mansard' => []
      }.freeze

      module_function

      # Création et import de brouillon sans base ; édition avec `base`.
      def resolve(request, registry:, intake:, base: nil, allow_internal: false)
        draft = intake.draft(request)
        return draft unless draft.ok?

        selection = select_profile(draft.value, base, registry, allow_internal)
        return selection unless selection.ok?

        profile, start = selection.value
        finish(start, draft.value, profile, registry, intake)
      end

      # Relit un effectif stocké : aucun défaut, aucune chance tirée à nouveau.
      def load_effective(input, registry:, intake:, allow_internal: false)
        effective = intake.effective(input)
        return effective unless effective.ok?

        profile = registry.fetch(effective.value['profile']['id'], revision: effective.value['profile']['revision'], allow_internal: allow_internal)
        return profile unless profile.ok?

        verify(effective.value, profile.value, registry)
      end

      def select_profile(draft, base, registry, allow_internal)
        return select_for_creation(draft, registry, allow_internal) unless base

        select_for_edit(draft, base, registry, allow_internal)
      end
      private_class_method :select_profile

      def select_for_creation(draft, registry, allow_internal)
        ref = draft['profile']
        unless ref && ref['id']
          return Result.fail([Diagnostic.error('E_PROFILE_UNAVAILABLE', '/profile', reason: 'profile_required')])
        end

        fetched = registry.fetch(ref['id'], revision: ref['revision'], allow_internal: allow_internal)
        return fetched unless fetched.ok?

        Result.ok([fetched.value, with_chances(fetched.value.defaults, fetched.value, draft['seed'])])
      end
      private_class_method :select_for_creation

      def select_for_edit(draft, base, registry, allow_internal)
        data = base.to_h
        ref = draft['profile']
        return reuse_profile(data, registry, allow_internal) if ref.nil?

        unless ref['id'] && ref['revision']
          return Result.fail([Diagnostic.error('E_SCHEMA', '/profile/revision', reason: 'exact_revision_required')])
        end
        return reuse_profile(data, registry, allow_internal) if ref == data['profile']

        fetched = registry.fetch(ref['id'], revision: ref['revision'], allow_internal: allow_internal)
        return fetched unless fetched.ok?

        kept = data.slice(*KEPT_ON_STYLE_CHANGE)
        styled = fetched.value.defaults.slice(*TOP_LEVEL_STYLE_BLOCKS)
        Result.ok([fetched.value, with_chances(kept.merge(styled), fetched.value, draft['seed'] || data['seed'])])
      end
      private_class_method :select_for_edit

      def reuse_profile(data, registry, allow_internal)
        fetched = registry.fetch(data['profile']['id'], revision: data['profile']['revision'], allow_internal: allow_internal)
        return fetched unless fetched.ok?

        Result.ok([fetched.value, data])
      end
      private_class_method :reuse_profile

      # Chances décoratives, après le choix de la graine et avant tout override.
      def with_chances(values, profile, seed)
        effective_seed = seed || values['seed']
        features = values.fetch('features', {}).dup
        profile.rules.each do |rule|
          next unless rule['rule'] == 'feature_chance'

          feature = rule['params']['feature']
          draw = DeterministicRandom.unit(effective_seed, DeterministicRandom.feature_key(feature))
          features[feature] = draw < rule['params']['probability']
        end
        values.merge('features' => features)
      end
      private_class_method :with_chances

      def finish(start, draft, profile, registry, intake)
        problems = []
        roof = merged_roof(start['roof'], draft['roof'], problems)
        return Result.fail(problems) unless problems.empty?

        merged = Merge.leaves(start, draft.reject { |k, _| %w[roof schema_version profile].include?(k) })
        merged = with_glazing(merged.merge(
                                'schema_version' => 1,
                                'name' => canonical_name(merged['name']),
                                'profile' => profile.ref,
                                'roof' => roof
                              ))
        effective = intake.effective(merged)
        return effective unless effective.ok?

        verify(effective.value, profile, registry)
      end
      private_class_method :finish

      # AG-064 : un vitrage décoché n'est pas écrit, ni sa matière ; coché, il prend le verre
      # du catalogue si le style n'en donne pas. Un bâtiment d'avant garde ainsi son empreinte.
      def with_glazing(config)
        features = config['features'].dup
        materials = config['materials'].dup
        if features['glazing']
          materials['glass'] ||= DEFAULT_GLASS
        else
          features.delete('glazing')
          materials.delete('glass')
        end
        config.merge('features' => features, 'materials' => materials)
      end
      private_class_method :with_glazing

      def canonical_name(name)
        name.nil? ? BuildingConfig::DEFAULT_NAME : name.strip
      end
      private_class_method :canonical_name

      # Un changement de type repart des valeurs de ce type, puis des champs explicites.
      def merged_roof(start, explicit, problems)
        explicit ||= {}
        type = explicit['type'] || start['type']
        base = type == start['type'] ? start : { 'type' => type, 'overhang_m' => 0.0 }.merge(ROOF_PRESETS.fetch(type))
        INACTIVE_ROOF_FIELDS.fetch(type).each do |field|
          next unless explicit[field].is_a?(Numeric) && !explicit[field].zero?

          problems << Diagnostic.error('E_ROOF_GEOMETRY', "/roof/#{field}", reason: 'inactive_field_not_zero', type: type)
        end
        roof = base.merge(explicit)
        INACTIVE_ROOF_FIELDS.fetch(type).each { |field| roof[field] = 0.0 }
        roof
      end
      private_class_method :merged_roof

      def verify(effective, profile, registry)
        rules = FidelityRules.method(:call)
        diagnostics = ConstraintValidator.call(effective, profile: profile, materials: registry.materials, fidelity_rules: rules)
        return Result.fail(diagnostics) if diagnostics.any?(&:error?)

        Result.ok(BuildingConfig.new(effective), diagnostics)
      end
      private_class_method :verify
    end
  end
end
