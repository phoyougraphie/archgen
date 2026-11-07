# frozen_string_literal: true

module Archgen
  module Core
    # Barrière des réglages d'un réseau de voies (docs/VOIRIE_CONTRACT.md, Carrefours ; ADR-36).
    # Chaque voie passe par RoadIntake, son tracé ramené à son premier point ; les carrefours
    # naissent ensuite tout seuls, dans le moteur. Les réglages de carrefour sont facultatifs.
    class RoadNetworkIntake
      SUPPORTED_VERSION = 1

      def initialize(schema, roads:)
        @schema = SchemaValidator.new(schema)
        @roads = roads
      end

      def settings(input)
        parsed = input.is_a?(String) ? StrictJson.parse(input) : Result.ok(input)
        return parsed unless parsed.ok?

        tree = parsed.value
        version = version_problem(tree)
        return Result.fail([version]) if version

        problems = @schema.validate(tree)
        return Result.fail(problems) unless problems.empty?

        problems = id_problems(tree)
        diagnostics = []
        roads = tree['roads'].each_with_index.map do |entry, i|
          road, origin, found = road(entry['road'], i)
          diagnostics.concat(found)
          road && { 'id' => entry['id'], 'origin_m' => origin, 'road' => road }
        end
        problems += diagnostics.select(&:error?)
        return Result.fail(problems.sort_by(&:sort_key)) unless problems.empty?

        Result.ok(Canonical.deep_freeze(effective(tree, roads)), diagnostics.sort_by(&:sort_key))
      end

      private

      def version_problem(tree)
        return nil unless tree.is_a?(Hash) && tree['network_version'].is_a?(Numeric) && tree['network_version'] != SUPPORTED_VERSION

        Diagnostic.error('E_VERSION', '/network_version', reason: 'unsupported_network', value: tree['network_version'], supported: SUPPORTED_VERSION)
      end

      def id_problems(tree)
        out = []
        seen = {}
        tree['roads'].each_with_index do |entry, i|
          out << Diagnostic.error('E_ROAD_TRACE', "/roads/#{i}/id", reason: 'duplicate_road_id') if seen[entry['id']]
          seen[entry['id']] = true
        end
        seen = {}
        tree.fetch('junctions', []).each_with_index do |entry, i|
          out << Diagnostic.error('E_ROAD_JUNCTION', "/junctions/#{i}/id", reason: 'duplicate_junction') if seen[entry['id']]
          seen[entry['id']] = true
        end
        out
      end

      # Voie i : tracé en repère du réseau -> réglages effectifs en repère de la voie, et son origine.
      def road(tree, index)
        base = "/roads/#{index}/road"
        points = tree.is_a?(Hash) && tree['trace'].is_a?(Hash) && tree['trace']['points_m']
        first = points.is_a?(Array) && points.first.is_a?(Array) && points.first.size == 2 && points.first.all?(Numeric) ? points.first : nil
        origin = first ? first.map { |c| Quant.q(c.to_f) } : [0.0, 0.0]
        local = first ? tree.merge('trace' => tree['trace'].merge('points_m' => moved(points, origin))) : tree
        result = @roads.settings(local)
        found = result.diagnostics.map { |d| repath(d, base) }
        if index.zero? && first && !origin.all?(&:zero?)
          found << Diagnostic.error('E_ROAD_TRACE', "#{base}/trace/points_m/0", reason: 'first_point_not_network_origin')
        end
        if origin.any? { |c| c.abs > Limits::ROAD_MAX_COORDINATE_M }
          found << Diagnostic.error('E_ROAD_TRACE', "#{base}/trace/points_m/0", reason: 'coordinate_range', limit: Limits::ROAD_MAX_COORDINATE_M)
        end
        [result.ok? ? result.value : nil, origin, found]
      end

      def moved(points, origin)
        points.map { |p| p.is_a?(Array) && p.size == 2 && p.all?(Numeric) ? [p[0] - origin[0], p[1] - origin[1]] : p }
      end

      def repath(diagnostic, base)
        params = diagnostic.params.transform_keys(&:to_sym)
        path = "#{base}#{diagnostic.path}"
        diagnostic.error? ? Diagnostic.error(diagnostic.code, path, **params) : Diagnostic.warning(diagnostic.code, path, **params)
      end

      def effective(tree, roads)
        {
          'network_version' => SUPPORTED_VERSION,
          'roads' => roads,
          'junctions' => tree.fetch('junctions', []).map do |j|
            { 'id' => j['id'], 'type' => j.fetch('type', 'simple'),
              'corner_radius_m' => Quant.q(j.fetch('corner_radius_m', Geometry::RoadNetwork::DEFAULT_RADIUS_M).to_f) }.merge(
              j.slice('outer_radius_m', 'ring_width_m').transform_values { |v| Quant.q(v.to_f) }
            )
          end.sort_by { |j| j['id'] }
        }
      end
    end
  end
end
