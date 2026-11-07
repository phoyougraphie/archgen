# frozen_string_literal: true

module Archgen
  module Core
    # Plan d'une voie sans carrefour (AG-039) : réglages effectifs -> coupe -> axe -> rubans -> RoadPlan
    # validé, avec son empreinte `road_digest`. Noyau pur, déterministe, en mètres, repère de la racine.
    module RoadEngine
      module_function

      # settings : réglages effectifs de RoadIntake ; bands, items : catalogues chargés.
      def call(settings, bands:, items:, max_faces: Limits::ROAD_MAX_UNIQUE_FACES)
        profile = settings['profile']
        section = Geometry::RoadSection.call(profile, bands: bands, items: items)
        width = section['width_m']
        ax = Geometry::RoadRibbons.axis_x(width, settings['axis'])
        trace = settings['trace']
        axis = Geometry::RoadAxis.call(trace['points_m'], trace['radii_m'], left_m: ax, right_m: width - ax)
        return axis unless axis.ok?

        stations = axis.value
        line = Geometry::RoadRibbons.cross_line(section)
        estimate = Geometry::RoadRibbons.face_estimate(stations.size, line)
        return Result.fail([budget(max_faces, estimate)]) if estimate > max_faces

        surface = Geometry::RoadRibbons.mesh(stations, line, width: width, axis: settings['axis'])
        plan = assemble(surface, stations, section, line)
        problems = RoadPlanValidator.call(plan)
        return Result.fail(problems) unless problems.empty?

        Result.ok(Canonical.deep_freeze(plan))
      end

      def budget(limit, value)
        Diagnostic.error('E_ROAD_BUDGET', '/trace', reason: 'road_faces', limit: limit, value: value)
      end

      def assemble(surface, stations, section, line)
        node = { 'id' => 'road', 'category' => 'road',
                 'children' => [{ 'id' => 'road/surface', 'category' => 'surface', 'children' => [], 'primitive' => surface }] }
        {
          'schema_version' => 1, 'engine_version' => ROAD_ENGINE_VERSION, 'units' => 'm', 'nodes' => [node],
          'metrics' => {
            'face_count' => surface['faces'].size, 'vertex_count' => surface['vertices'].size,
            'station_count' => stations.size, 'cross_segment_count' => line.size,
            'width_m' => section['width_m'], 'length_m' => Quant.q(length(stations))
          }
        }
      end

      def length(stations)
        stations.each_cons(2).sum { |a, b| Math.hypot(b.point[0] - a.point[0], b.point[1] - a.point[1]) }
      end

      def digest(plan)
        Canonical.digest(plan)
      end
    end

    # Mêmes refus de maillage que le plan du bâtiment, sur la structure du plan de voie.
    class RoadPlanValidator < PlanValidator
      CATEGORIES = %w[road surface].freeze

      def call
        return @out unless header_ok?

        @plan['nodes'].each { |node| check_node(node, allow_instance: false) }
        check_metrics
        @out.sort_by(&:sort_key)
      end

      private

      def categories
        CATEGORIES
      end

      def header_ok?
        problem('plan', 'bad_header') unless @plan['schema_version'] == 1 && @plan['units'] == 'm'
        %w[nodes metrics].each { |key| problem('plan', "missing_#{key}") unless @plan.key?(key) }
        return false unless @out.empty?

        tops = @plan['nodes']
        problem('plan', 'single_road_root') unless tops.size == 1 && tops.first['category'] == 'road'
        @out.empty?
      end

      def check_metrics
        counted = @plan['nodes'].sum { |node| node_faces(node) }
        declared = @plan['metrics']['face_count']
        problem('metrics', 'metric_mismatch', metric: 'face_count', declared: declared, counted: counted) unless declared == counted
      end
    end
  end
end
