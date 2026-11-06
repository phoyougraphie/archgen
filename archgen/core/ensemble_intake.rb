# frozen_string_literal: true

module Archgen
  module Core
    # Barrière des réglages d'un ensemble (docs/ENSEMBLE_CONTRACT.md). La géométrie du tracé
    # est jugée ensuite par Geometry::ParcelLayout : ici, seulement la forme des réglages.
    class EnsembleIntake
      SUPPORTED_VERSION = 1
      DEFAULTS = {
        'ensemble_version' => SUPPORTED_VERSION,
        'seed' => 1,
        'parcel' => { 'target_width_m' => 12.0, 'depth_m' => 9.0, 'bay_width_m' => 3.0 },
        'building' => { 'schema_version' => 1 }
      }.freeze
      LAYOUT_DEFAULTS = { 'side' => 'left' }.freeze
      STREET_WIDTH_DEFAULT_M = 12.0
      ACCESS_DEFAULTS = { 'count' => 'auto', 'width_m' => 3.5, 'height_m' => 2.7 }.freeze
      # Ces champs sont calculés par parcelle : les saisir reviendrait à les ignorer.
      COMPUTED_BUILDING_FIELDS = %w[/footprint /seed /facade/front_bays /facade/side_bays /facade/entry_bay].freeze

      # schemas : { 'ensemble' => Hash, 'draft' => Hash }.
      def initialize(schemas)
        @settings = SchemaValidator.new(schemas.fetch('ensemble'))
        @draft = SchemaValidator.new(schemas.fetch('draft'))
      end

      # Saisie partielle : les champs absents prennent les valeurs de départ du contrat.
      def settings(input)
        parsed = input.is_a?(String) ? StrictJson.parse(input) : Result.ok(input)
        return parsed unless parsed.ok?

        tree = parsed.value
        version = version_problem(tree)
        return Result.fail([version]) if version

        problems = @settings.validate(tree)
        return Result.fail(problems) unless problems.empty?

        problems = building_problems(tree.fetch('building', {})) + shape_problems(tree)
        return Result.fail(problems.sort_by(&:sort_key)) unless problems.empty?

        Result.ok(Canonical.deep_freeze(effective(tree)))
      end

      private

      def version_problem(tree)
        return nil unless tree.is_a?(Hash) && tree['ensemble_version'].is_a?(Numeric) && tree['ensemble_version'] != SUPPORTED_VERSION

        Diagnostic.error('E_VERSION', '/ensemble_version', reason: 'unsupported', value: tree['ensemble_version'], supported: SUPPORTED_VERSION)
      end

      def building_problems(building)
        schema = @draft.validate(DEFAULTS['building'].merge(building)).map { |d| Diagnostic.error(d.code, "/building#{d.path}", **d.params.transform_keys(&:to_sym)) }
        computed = COMPUTED_BUILDING_FIELDS.filter_map do |pointer|
          keys = pointer.delete_prefix('/').split('/')
          present?(building, keys) ? Diagnostic.error('E_SCHEMA', "/building#{pointer}", reason: 'computed_by_parcel') : nil
        end
        schema + computed
      end

      def present?(tree, keys)
        parent = keys[0...-1].empty? ? tree : tree.dig(*keys[0...-1])
        parent.is_a?(Hash) && parent.key?(keys.last)
      end

      def shape_problems(tree)
        return closed_problems(tree) if tree.dig('trace', 'closed')

        open_problems(tree)
      end

      def closed_problems(tree)
        return [] unless tree.key?('layout')

        [Diagnostic.error('E_SCHEMA', '/layout', reason: 'layout_on_closed_trace')]
      end

      def open_problems(tree)
        out = []
        out << Diagnostic.error('E_SCHEMA', '/access', reason: 'access_on_open_trace') if tree.key?('access')
        layout = tree.fetch('layout', {})
        if layout.key?('street_width_m') && layout['side'] != 'both'
          out << Diagnostic.error('E_SCHEMA', '/layout/street_width_m', reason: 'street_width_without_both')
        end
        out
      end

      def effective(tree)
        merged = Merge.leaves(DEFAULTS, tree)
        merged = tree.dig('trace', 'closed') ? closed_defaults(merged) : open_defaults(merged)
        normalized = @settings.normalize(merged)
        normalized.merge('trace' => normalized['trace'].merge('points_m' => normalized.dig('trace', 'points_m').map { |p| Quant.q3(p) }))
      end

      def closed_defaults(merged)
        merged.merge('access' => Merge.leaves(ACCESS_DEFAULTS, merged.fetch('access', {})))
      end

      def open_defaults(merged)
        layout = Merge.leaves(LAYOUT_DEFAULTS, merged.fetch('layout', {}))
        layout = Merge.leaves({ 'street_width_m' => STREET_WIDTH_DEFAULT_M }, layout) if layout['side'] == 'both'
        merged.merge('layout' => layout)
      end
    end
  end
end
