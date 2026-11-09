# frozen_string_literal: true

module Archgen
  module Core
    # Profil résolu après héritage : données gelées.
    StyleProfile = Struct.new(:id, :revision, :kind, :status, :family_id, :label, :requires, :defaults, :rules, keyword_init: true) do
      def ref
        { 'id' => id, 'revision' => revision }
      end
    end

    # Registre des profils. Charge toute la hiérarchie avant publication : une entrée
    # incohérente bloque le registre plutôt que de publier un profil douteux.
    class StyleRegistry
      # Registre fermé des capacités connues du noyau, implémentées ou non.
      KNOWN_CAPABILITIES = %w[rectangle rect_opening flat gable hip mansard cornice balcony surrounds glazing chimneys muntins shutters dormers genoise].freeze
      RULE_PARAMS = {
        'window_ratio' => %w[max min], 'level_count' => %w[max min], 'roof_type' => %w[values],
        'material_allowed' => %w[role values], 'feature_chance' => %w[feature probability]
      }.freeze
      ROOF_TYPES = %w[flat gable hip mansard].freeze

      attr_reader :materials

      # capabilities : capacités réellement disponibles, injectées (U02) puis réelles.
      def self.load(profiles, schema:, config_validator:, capabilities:, materials:)
        Loader.new(profiles, schema, config_validator, capabilities, materials).call
      end

      def initialize(resolved, capabilities, materials)
        @resolved = resolved
        @capabilities = capabilities
        @materials = materials
        freeze
      end

      # Résultat : profil actif exact, ou sa révision courante si aucune n'est donnée.
      def fetch(profile_id, revision: nil, allow_internal: false)
        candidates = @resolved.values.select { |p| p.id == profile_id }
        return unavailable(profile_id, revision, 'unknown_profile') if candidates.empty?

        profile = pick(candidates, revision)
        return unavailable(profile_id, revision, 'missing_revision') unless profile
        return unavailable(profile_id, revision, 'not_selectable') unless selectable?(profile, allow_internal)

        missing = profile.requires - @capabilities
        return unavailable(profile_id, revision, 'missing_capability', missing: missing) unless missing.empty?

        Result.ok(profile)
      end

      # Seules les feuilles actives dont tous les prérequis sont disponibles, à leur dernière
      # révision : une révision plus ancienne reste lisible par `fetch`, sans être proposée (AG-064).
      def active_profiles
        @resolved.values
                 .select { |p| p.status == 'active' && p.kind == 'profile' && (p.requires - @capabilities).empty? }
                 .group_by(&:id).map { |_, revisions| revisions.max_by(&:revision) }
                 .sort_by { |p| [p.id, p.revision] }
      end

      private

      def pick(candidates, revision)
        return candidates.find { |p| p.revision == revision } if revision

        candidates.max_by(&:revision)
      end

      def selectable?(profile, allow_internal)
        return profile.status == 'active' if profile.kind == 'profile' && !allow_internal

        allow_internal ? profile.status != 'planned' : false
      end

      def unavailable(id, revision, reason, **params)
        Result.fail([Diagnostic.error('E_PROFILE_UNAVAILABLE', '/profile', reason: reason, id: id, revision: revision, **params)])
      end

      # Validation et résolution de la hiérarchie.
      class Loader
        def initialize(profiles, schema, config_validator, capabilities, materials)
          @profiles = profiles
          @schema = SchemaValidator.new(schema)
          @config_validator = config_validator
          @capabilities = capabilities
          @materials = materials
          @errors = []
          @by_ref = {}
          @resolved = {}
        end

        def call
          index
          return Result.fail(@errors) unless @errors.empty?

          @by_ref.each_key { |ref| resolve(ref, []) }
          @resolved.each_value { |profile| check_active(profile) }
          return Result.fail(@errors) unless @errors.empty?

          Result.ok(StyleRegistry.new(@resolved.freeze, @capabilities.dup.freeze, @materials))
        end

        private

        def index
          @profiles.each do |raw|
            problems = @schema.validate(raw)
            label = raw.is_a?(Hash) ? "#{raw['id']}@#{raw['revision']}" : '?'
            problems.each { |d| error("/profiles/#{label}#{d.path}", d.params['reason']) }
            next unless problems.empty?

            ref = [raw['id'], raw['revision']]
            error("/profiles/#{label}", 'duplicate_revision') if @by_ref.key?(ref)
            @by_ref[ref] = raw
          end
        end

        def error(path, reason, **params)
          @errors << Diagnostic.error('E_PROFILE_UNAVAILABLE', path, reason: reason, **params)
        end

        def resolve(ref, chain)
          return @resolved[ref] if @resolved.key?(ref)

          raw = @by_ref[ref]
          path = "/profiles/#{ref.join('@')}"
          return error(path, 'cycle') && nil if chain.include?(ref)

          parent = resolve_parent(raw, ref, chain, path)
          check_kind(raw, parent, path)
          check_rules(raw, path)
          @resolved[ref] = build(raw, parent, path)
        end

        def resolve_parent(raw, ref, chain, path)
          link = raw['parent']
          return nil unless link

          parent_ref = [link['id'], link['revision']]
          unless @by_ref.key?(parent_ref)
            error(path, 'missing_parent', parent: parent_ref.join('@'))
            return nil
          end
          resolve(parent_ref, chain + [ref])
        end

        def check_kind(raw, parent, path)
          case raw['kind']
          when 'base'
            error(path, 'base_with_parent') if raw['parent']
            error(path, 'illegal_status') unless raw['status'] == 'internal'
          when 'family'
            error(path, 'family_parent_not_base') unless parent&.kind == 'base'
            error(path, 'family_id_mismatch') unless raw['family_id'] == raw['id']
            error(path, 'illegal_status') unless raw['status'] == 'internal'
          when 'profile'
            error(path, 'profile_parent_not_family') unless parent&.kind == 'family'
            error(path, 'family_id_mismatch') unless parent.nil? || raw['family_id'] == parent.id
            error(path, 'illegal_status') unless %w[active planned].include?(raw['status'])
          end
        end

        def check_rules(raw, path)
          raw['rules'].each { |rule| check_rule(rule, "#{path}/rules/#{rule['id']}") }
        end

        def check_rule(rule, path)
          expected = RULE_PARAMS.fetch(rule['rule'])
          params = rule['params']
          error(path, 'rule_params', expected: expected) unless params.keys.sort == expected
          case rule['rule']
          when 'window_ratio', 'level_count'
            error(path, 'min_greater_than_max') if params['min'] && params['max'] && params['min'] > params['max']
          when 'roof_type'
            error(path, 'unknown_roof') unless (params['values'].to_a - ROOF_TYPES).empty?
          when 'feature_chance'
            error(path, 'chance_must_be_decorative') unless rule['kind'] == 'decorative'
          end
        end

        def build(raw, parent, path)
          StyleProfile.new(
            id: raw['id'], revision: raw['revision'], kind: raw['kind'], status: raw['status'],
            family_id: raw['family_id'], label: raw['label'],
            requires: Canonical.deep_freeze(((parent&.requires || []) + raw['requires']).uniq),
            defaults: Canonical.deep_freeze(Merge.leaves(parent&.defaults || {}, raw['defaults'])),
            rules: Canonical.deep_freeze(merge_rules(parent&.rules || [], raw['rules'], path))
          ).freeze
        end

        # Fusion par id : l'enfant remplace l'entrée complète, jamais une règle hard.
        def merge_rules(inherited, own, path)
          merged = inherited.to_h { |rule| [rule['id'], rule] }
          own.each do |rule|
            previous = merged[rule['id']]
            error("#{path}/rules/#{rule['id']}", 'hard_rule_changed') if previous && previous['kind'] == 'hard' && previous != rule
            merged[rule['id']] = rule
          end
          rules = merged.values
          chances = rules.select { |r| r['rule'] == 'feature_chance' }.map { |r| r['params']['feature'] }
          error(path, 'duplicate_feature_chance') unless chances.uniq.size == chances.size
          rules
        end

        # Une feuille active : capacités connues, défauts complets et valides.
        def check_active(profile)
          return unless profile.kind == 'profile' && profile.status == 'active'

          path = "/profiles/#{profile.id}@#{profile.revision}"
          unknown = profile.requires - KNOWN_CAPABILITIES
          error(path, 'unknown_capability', unknown: unknown) unless unknown.empty?
          base = profile.defaults.reject { |key, _| key == 'shop' }.merge('schema_version' => 1, 'name' => 'Validation', 'profile' => profile.ref)
          candidates = [base]
          # AG-065 : une hauteur de commerce du style se juge sur un rez-de-chaussée commerçant.
          candidates << base.merge('ground_floor' => 'shop', 'shop' => profile.defaults['shop']) if profile.defaults.key?('shop')
          problems = candidates.flat_map { |candidate| defaults_problems(candidate) }.uniq { |d| [d.code, d.path, d.params] }
          problems.select(&:error?).each { |d| error("#{path}/defaults#{d.path}", d.params['reason'].to_s, code: d.code) }
        end

        def defaults_problems(candidate)
          problems = @config_validator.validate(candidate)
          problems.empty? ? ConstraintValidator.call(@config_validator.normalize(candidate), materials: @materials) : problems
        end
      end
      private_constant :Loader
    end

    # Fusion feuille par feuille ; les tableaux remplacent.
    module Merge
      module_function

      def leaves(base, overrides)
        base.merge(overrides) do |_key, left, right|
          left.is_a?(Hash) && right.is_a?(Hash) ? leaves(left, right) : right
        end
      end
    end
  end
end
