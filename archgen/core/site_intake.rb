# frozen_string_literal: true

module Archgen
  module Core
    # Barrière des réglages d'assise et des grilles de relevé (docs/TERRAIN_CONTRACT.md).
    # Les chemins de diagnostic commencent par /site : ce format est séparé du bâtiment.
    class SiteIntake
      SUPPORTED_VERSION = 1
      ROOT = '/site'
      SURVEY = '/site/survey'
      DEFAULTS = {
        'site_version' => SUPPORTED_VERSION,
        'platform' => { 'policy' => 'high', 'offset_m' => 0.0 },
        'earthwork' => 'plinth',
        'embankment_ratio' => 1.5,
        'plinth_material' => 'concrete',
        'entrance' => 'steps', # AG-105 : écrit à la création ; absent d'un terrain enregistré, rien ne change
        'survey' => { 'step_m' => 2.0 }
      }.freeze
      # Clés venues après coup : absentes d'un terrain enregistré, elles ne sont pas une altération.
      OPTIONAL = %w[entrance].freeze

      # schemas : { 'site' => Hash, 'survey' => Hash } ; materials : le catalogue des identifiants.
      def initialize(schemas, materials:)
        @settings = SchemaValidator.new(schemas.fetch('site'))
        @survey = SchemaValidator.new(schemas.fetch('survey'))
        @materials = materials
      end

      # Saisie partielle : les champs absents prennent les valeurs de départ du contrat.
      def settings(input)
        read_settings(input) { |tree| Merge.leaves(DEFAULTS, tree) }
      end

      # Réglages enregistrés : aucun défaut réappliqué, un champ absent est une altération.
      def stored_settings(input)
        read_settings(input) { |tree| tree }
      end

      # Grille venue de l'adaptateur ou d'une fixture, relue contre les axes attendus.
      def grid(tree, width_m:, depth_m:, settings:)
        problems = rebase(@survey.validate(tree), SURVEY)
        return Result.fail(problems) unless problems.empty?

        planned = SurveyGrid.plan(width_m: width_m, depth_m: depth_m, settings: settings)
        return planned unless planned.ok?

        normalized = quantized(tree)
        problem = shape_problem(normalized, planned.value)
        problem ? Result.fail([problem]) : Result.ok(SurveyGrid.new(normalized))
      end

      # Grille d'une parcelle, relue contre les axes attendus pour sa boîte.
      def parcel_grid(tree, axes)
        problems = rebase(@survey.validate(tree), SURVEY)
        return Result.fail(problems) unless problems.empty?

        normalized = quantized(tree)
        problem = shape_problem(normalized, axes)
        problem ? Result.fail([problem]) : Result.ok(SurveyGrid.new(normalized))
      end

      private

      def read_settings(input)
        parsed = input.is_a?(String) ? StrictJson.parse(input) : Result.ok(input)
        return Result.fail(rebase(parsed.errors, ROOT)) unless parsed.ok?

        tree = parsed.value
        version = version_problem(tree)
        return Result.fail([version]) if version

        problems = rebase(@settings.validate(tree), ROOT)
        return Result.fail(problems) unless problems.empty?

        finish(@settings.normalize(yield(tree)))
      end

      def finish(effective)
        problems = missing_fields(DEFAULTS.reject { |key, _| OPTIONAL.include?(key) }, effective, ROOT)
        problems << unknown_material(effective) if effective.key?('plinth_material') && !@materials.key?(effective['plinth_material'])
        problems.empty? ? Result.ok(Canonical.deep_freeze(effective)) : Result.fail(problems)
      end

      def version_problem(tree)
        return nil unless tree.is_a?(Hash) && tree['site_version'].is_a?(Numeric) && tree['site_version'] != SUPPORTED_VERSION

        Diagnostic.error('E_VERSION', '/site/site_version', reason: 'unsupported', value: tree['site_version'], supported: SUPPORTED_VERSION)
      end

      def missing_fields(reference, value, path)
        reference.flat_map do |key, expected|
          child = "#{path}/#{key}"
          next [Diagnostic.error('E_SCHEMA', child, reason: 'required')] unless value.key?(key)

          expected.is_a?(Hash) ? missing_fields(expected, value[key], child) : []
        end
      end

      def unknown_material(effective)
        Diagnostic.error('E_SCHEMA', '/site/plinth_material', reason: 'unknown_material', value: effective['plinth_material'])
      end

      def quantized(tree)
        {
          'schema_version' => tree['schema_version'].to_i,
          'xs_m' => tree['xs_m'].map { |v| Quant.q(v.to_f) },
          'ys_m' => tree['ys_m'].map { |v| Quant.q(v.to_f) },
          'z_m' => tree['z_m'].map { |row| row.map { |v| v.nil? ? nil : Quant.q(v.to_f) } }
        }
      end

      def shape_problem(grid, planned)
        return Diagnostic.error('E_SCHEMA', SURVEY, reason: 'grid_axes') unless grid['xs_m'] == planned['xs_m'] && grid['ys_m'] == planned['ys_m']
        return nil if grid['z_m'].size == grid['ys_m'].size && grid['z_m'].all? { |row| row.size == grid['xs_m'].size }

        Diagnostic.error('E_SCHEMA', SURVEY, reason: 'grid_shape')
      end

      def rebase(diagnostics, prefix)
        diagnostics.map do |d|
          path = "#{prefix}#{d.path}"
          params = d.params.transform_keys(&:to_sym)
          d.error? ? Diagnostic.error(d.code, path, **params) : Diagnostic.warning(d.code, path, **params)
        end
      end
    end
  end
end
