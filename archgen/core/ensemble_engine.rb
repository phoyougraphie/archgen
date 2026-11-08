# frozen_string_literal: true

module Archgen
  module Core
    # Du tracé au plan d'ensemble (docs/ENSEMBLE_CONTRACT.md, Plan d'ensemble). Pur et
    # déterministe. Deux parcelles identiques partagent une définition, calculée une seule fois.
    module EnsembleEngine
      SCHEMA_VERSION = 1
      KEY_CHARS = 16
      DEFAULT_LIMITS = {
        unique: Limits::ENSEMBLE_MAX_UNIQUE_FACES,
        expanded: Limits::ENSEMBLE_MAX_EXPANDED_FACES
      }.freeze

      module_function

      # Le bloc, facultatif, reçoit (parcelles traitées, total) : il alimente la barre d'état.
      def call(settings, registry:, intake:, materials: nil, limits: DEFAULT_LIMITS, rules: nil, &progress)
        layout = layout_for(settings, registry: registry, rules: rules)
        return layout unless layout.ok?

        parcels = layout.value['parcels']
        if settings['variety']
          checked = EnsembleVariety.problems(settings, parcels.first, registry: registry, intake: intake)
          return Result.fail(checked) unless checked.empty?

          parcels = EnsembleVariety.assign(settings, parcels)
        end
        prepared = parcels.map { |parcel| ParcelBuilding.prepare(settings, parcel, registry: registry, intake: intake) }
        errors = prepared.flat_map(&:errors)
        return Result.fail(errors.sort_by(&:sort_key)) unless errors.empty?

        assemble(parcels, prepared, layout.value, materials, limits, progress, variety: settings['variety'] ? EnsembleVariety.summary(parcels) : nil)
      end

      # Les parcelles définitives, accès de cour compris. Une forme fermée n'en sort jamais sans accès.
      def layout_for(settings, registry:, rules: nil)
        layout = Geometry::ParcelLayout.call(settings)
        return layout unless layout.ok?
        return Result.ok(layout.value.merge('accesses' => [])) unless settings.dig('trace', 'closed')

        form = access_form(settings, registry, rules || Composition.ensemble_rules)
        form.ok? ? Geometry::AccessPlanner.call(layout.value, settings, form: form.value) : form
      end

      def digest(plan)
        Canonical.digest(plan)
      end

      # La forme vient du catalogue, au couple profil/révision exact. Une entrée n'est publiée
      # qu'avec sa capacité (ADR-31) : un profil sans entrée ne ferme pas d'îlot.
      def access_form(settings, registry, rules)
        reference = settings.dig('building', 'profile')
        return Result.fail([Diagnostic.error('E_PROFILE_UNAVAILABLE', '/building/profile', reason: 'profile_required')]) unless reference&.fetch('id', nil)

        profile = registry.fetch(reference['id'], revision: reference['revision'])
        unless profile.ok?
          return Result.fail(profile.errors.map { |d| Diagnostic.error(d.code, "/building#{d.path}", **d.params.transform_keys(&:to_sym)) })
        end

        form = rules.dig('access_forms', profile.value.id, profile.value.revision.to_s)
        return Result.ok(form) if Geometry::AccessPlanner::FORMS.include?(form)

        Result.fail([Diagnostic.error('E_STREET_ACCESS', '/building/profile', reason: 'access_form_unavailable', id: profile.value.id)])
      end
      private_class_method :access_form

      def assemble(parcels, prepared, layout, materials, limits, progress, variety: nil)
        definitions = {}
        placed = []
        diagnostics = []
        unique = 0
        expanded = 0
        parcels.zip(prepared).each_with_index do |(parcel, ready), index|
          id = definition_id(ready.value)
          unless definitions.key?(id)
            built = ParcelBuilding.generate(ready.value, parcel, materials: materials)
            return Result.fail(built.errors) unless built.ok?

            definitions[id] = built
            unique += built.value.plan['metrics']['unique_face_count']
          end
          diagnostics.concat(relocated_warnings(definitions[id], ready, parcel))
          expanded += definitions[id].value.plan['metrics']['expanded_face_count']
          budget = budget_problem(unique, expanded, limits)
          return Result.fail([budget]) if budget

          entry = { 'id' => parcel['id'], 'definition_id' => id, 'matrix' => matrix(parcel) }
          entry['variety'] = parcel['variety'] if parcel['variety']
          placed << entry
          progress&.call(index + 1, parcels.size)
        end
        finish(definitions, placed, layout, unique, expanded, diagnostics, variety)
      end
      private_class_method :assemble

      # Identifiant tiré du contenu : indépendant de la parcelle qui l'a demandé en premier.
      def definition_id(ready)
        "row/#{ParcelBuilding.share_key(ready)[0, KEY_CHARS]}"
      end
      private_class_method :definition_id

      # Un avertissement de définition partagée vaut pour chaque parcelle qui l'utilise.
      def relocated_warnings(built, ready, parcel)
        own = ready.warnings + built.value.plan_warnings
        own.uniq(&:to_h).map { |d| ParcelBuilding.relocate(d, parcel) }
      end
      private_class_method :relocated_warnings

      def budget_problem(unique, expanded, limits)
        return budget_error('ensemble_unique_faces', limits[:unique], unique) if unique > limits[:unique]
        return budget_error('ensemble_expanded_faces', limits[:expanded], expanded) if expanded > limits[:expanded]

        nil
      end
      private_class_method :budget_problem

      def budget_error(reason, limit, value)
        Diagnostic.error('E_STREET_BUDGET', '/parcel/target_width_m', reason: reason, limit: limit, value: value)
      end
      private_class_method :budget_error

      # Colonnes (T, gauche, K) : x le long de la façade, y vers l'arrière.
      def matrix(parcel)
        t = parcel['tangent']
        origin = parcel['origin_m']
        [t[0], t[1], 0.0, 0.0, -t[1], t[0], 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, origin[0], origin[1], 0.0, 1.0].map { |c| c.zero? ? 0.0 : c }
      end
      private_class_method :matrix

      def finish(definitions, placed, layout, unique, expanded, diagnostics, variety = nil)
        plan = {
          'schema_version' => SCHEMA_VERSION,
          'engine_version' => ENGINE_VERSION,
          'units' => 'm',
          'definitions' => definitions.transform_values { |built| built.value.plan },
          'parcels' => placed,
          'accesses' => layout['accesses'],
          'metrics' => {
            'parcel_count' => placed.size,
            'definition_count' => definitions.size,
            'unique_face_count' => unique,
            'expanded_face_count' => expanded,
            'facade_length_m' => layout['metrics']['facade_length_m'],
            'access_count' => layout['accesses'].size
          }
        }
        plan['variety'] = variety if variety
        problems = EnsemblePlanValidator.call(plan)
        return Result.fail(problems) unless problems.empty?

        Result.ok(Canonical.deep_freeze(plan), diagnostics.sort_by(&:sort_key))
      end
      private_class_method :finish
    end

    # Dernière barrière de l'ensemble : chaque définition a déjà passé PlanValidator. Tout est
    # recalculé depuis le plan, sans croire le moteur.
    module EnsemblePlanValidator
      RIGID_TOLERANCE = 1e-5

      module_function

      def call(plan)
        problems = plan['parcels'].flat_map { |parcel| parcel_problems(parcel, plan['definitions']) }
        problems.concat(identity_problems(plan))
        problems.concat(metric_problems(plan))
        problems.sort_by(&:sort_key)
      end

      def parcel_problems(parcel, definitions)
        out = []
        out << problem(parcel['id'], 'missing_definition') unless definitions.key?(parcel['definition_id'])
        out << problem(parcel['id'], 'non_rigid_matrix') unless rigid?(parcel['matrix'])
        out
      end
      private_class_method :parcel_problems

      def identity_problems(plan)
        ids = plan['parcels'].map { |parcel| parcel['id'] }
        ids.uniq.size == ids.size ? [] : [problem('parcels', 'duplicate_parcel_id')]
      end
      private_class_method :identity_problems

      def metric_problems(plan)
        declared = plan['metrics']
        counted = {
          'parcel_count' => plan['parcels'].size,
          'definition_count' => plan['definitions'].size,
          'unique_face_count' => plan['definitions'].values.sum { |row| row['metrics']['unique_face_count'] },
          'expanded_face_count' => plan['parcels'].sum { |parcel| plan['definitions'].dig(parcel['definition_id'], 'metrics', 'expanded_face_count').to_i }
        }
        counted.filter_map do |key, value|
          problem('metrics', 'metric_mismatch', metric: key, declared: declared[key], counted: value) unless declared[key] == value
        end
      end
      private_class_method :metric_problems

      # Rotation autour de Z et translation : tout autre placement ferait sortir du plan.
      def rigid?(m)
        return false unless m.is_a?(Array) && m.size == 16 && m.all? { |c| c.is_a?(Numeric) && c.finite? }

        norm = Math.hypot(m[0], m[1])
        ok = (norm - 1.0).abs < RIGID_TOLERANCE && (m[4] + m[1]).abs < RIGID_TOLERANCE && (m[5] - m[0]).abs < RIGID_TOLERANCE
        ok && [m[2], m[3], m[6], m[7], m[8], m[9], m[11], m[14]].all? { |c| c.abs < RIGID_TOLERANCE } && (m[10] - 1.0).abs < RIGID_TOLERANCE && (m[15] - 1.0).abs < RIGID_TOLERANCE
      end
      private_class_method :rigid?

      def problem(id, reason, **params)
        Diagnostic.error('E_PLAN', '/plan', reason: reason, id: id.to_s, **params)
      end
      private_class_method :problem
    end
  end
end
