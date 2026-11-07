# frozen_string_literal: true

module Archgen
  module Core
    # Barrière des réglages d'une voie (docs/VOIRIE_CONTRACT.md, Tronçon) : forme, coupe, tracé.
    # La géométrie du tracé (rayons, replis, recouvrements) est jugée ensuite par Geometry::RoadAxis.
    class RoadIntake
      SUPPORTED_VERSION = 1
      DEFAULTS = { 'road_version' => SUPPORTED_VERSION, 'seed' => 1, 'axis' => 'center' }.freeze

      # schemas : { 'road' => Hash } ; profiles : RoadProfileIntake.
      def initialize(schema, profiles:)
        @schema = SchemaValidator.new(schema)
        @profiles = profiles
      end

      def settings(input)
        parsed = input.is_a?(String) ? StrictJson.parse(input) : Result.ok(input)
        return parsed unless parsed.ok?

        tree = parsed.value
        version = version_problem(tree)
        return Result.fail([version]) if version

        problems = @schema.validate(tree)
        return Result.fail(problems) unless problems.empty?

        profile = @profiles.profile(tree['profile'])
        diagnostics = profile.diagnostics.map { |d| repath(d) }
        problems = diagnostics.select(&:error?) + trace_problems(tree['trace'])
        return Result.fail(problems.sort_by(&:sort_key)) unless problems.empty?

        Result.ok(Canonical.deep_freeze(effective(tree, profile.value)), diagnostics)
      end

      private

      def version_problem(tree)
        return nil unless tree.is_a?(Hash) && tree['road_version'].is_a?(Numeric) && tree['road_version'] != SUPPORTED_VERSION

        Diagnostic.error('E_VERSION', '/road_version', reason: 'unsupported_road', value: tree['road_version'], supported: SUPPORTED_VERSION)
      end

      def repath(diagnostic)
        params = diagnostic.params.transform_keys(&:to_sym)
        path = "/profile#{diagnostic.path}"
        diagnostic.error? ? Diagnostic.error(diagnostic.code, path, **params) : Diagnostic.warning(diagnostic.code, path, **params)
      end

      def trace_problems(trace)
        points = trace['points_m']
        out = []
        return [error('/trace/points_m', 'too_few_points', value: points.size, limit: 2)] if points.size < 2

        out << error('/trace/points_m/0', 'first_point_not_road_origin') unless points[0].all?(&:zero?)
        points.each_with_index do |p, i|
          next if p.all? { |c| c.abs <= Limits::ROAD_MAX_COORDINATE_M }

          out << error("/trace/points_m/#{i}", 'coordinate_range', limit: Limits::ROAD_MAX_COORDINATE_M)
        end
        if trace['radii_m'].size != points.size - 2
          out << error('/trace/radii_m', 'radii_count', expected: points.size - 2, value: trace['radii_m'].size)
        end
        out
      end

      def error(path, reason, **params)
        Diagnostic.error('E_ROAD_TRACE', path, reason: reason, **params)
      end

      def effective(tree, profile)
        {
          'road_version' => SUPPORTED_VERSION,
          'seed' => tree.fetch('seed', DEFAULTS['seed']).to_i,
          'axis' => tree.fetch('axis', DEFAULTS['axis']),
          'trace' => {
            'points_m' => tree['trace']['points_m'].map { |p| p.map { |c| Quant.q(c.to_f) } },
            'radii_m' => tree['trace']['radii_m'].map { |r| Quant.q(r.to_f) }
          },
          'profile' => profile
        }.merge(tree['ground'] ? { 'ground' => Geometry::RoadGround.settings(tree['ground'].transform_values { |v| Quant.q(v.to_f) }) } : {})
      end
    end
  end
end
