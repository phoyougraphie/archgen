# frozen_string_literal: true

module Archgen
  module Core
    # Plan d'une voie sans carrefour : réglages effectifs -> coupe -> axe -> rubans et éléments
    # (AG-039, AG-040) -> RoadPlan validé, avec son empreinte `road_digest`. Noyau pur, déterministe,
    # en mètres, repère de la racine.
    module RoadEngine
      LIMITS = {
        unique: Limits::ROAD_MAX_UNIQUE_FACES, items: Limits::ROAD_MAX_ITEMS, expanded: Limits::ROAD_MAX_EXPANDED_FACES
      }.freeze

      module_function

      # settings : réglages effectifs de RoadIntake ; bands, items : catalogues chargés.
      def call(settings, bands:, items:, limits: {})
        limits = LIMITS.merge(limits)
        section = Geometry::RoadSection.call(settings['profile'], bands: bands, items: items)
        width = section['width_m']
        ax = Geometry::RoadRibbons.axis_x(width, settings['axis'])
        trace = settings['trace']
        axis = Geometry::RoadAxis.call(trace['points_m'], trace['radii_m'], left_m: ax, right_m: width - ax)
        return axis unless axis.ok?

        stations = axis.value
        line = Geometry::RoadRibbons.cross_line(section)
        estimate = Geometry::RoadRibbons.face_estimate(stations.size, line)
        return Result.fail([budget('road_faces', limits[:unique], estimate)]) if estimate > limits[:unique]

        count = item_estimate(stations, section, ax)
        return Result.fail([budget('road_items', limits[:items], count)]) if count > limits[:items]

        surface = Geometry::RoadRibbons.mesh(stations, line, width: width, axis: settings['axis'])
        placed = Geometry::RoadItems.call(stations, section, items: items, ax: ax, seed: settings['seed'])
        plan = assemble(surface, placed, stations, section, line)
        problems = budget_problems(plan['metrics'], limits) + RoadPlanValidator.call(plan)
        return Result.fail(problems) unless problems.empty?

        Result.ok(Canonical.deep_freeze(plan))
      end

      def budget(reason, limit, value)
        Diagnostic.error('E_ROAD_BUDGET', '/trace', reason: reason, limit: limit, value: value)
      end

      # Objets répétés et poteaux à prévoir, avant de les poser.
      def item_estimate(stations, section, ax)
        section['items'].sum do |item|
          length = Geometry::RoadItems.polyline_length(Geometry::RoadItems.offset_line(stations, ax - item['x_m']))
          if item['repeat'] == 'spaced'
            Geometry::RoadSection.count_over(item['spacing_m'], length)
          else
            post = Geometry::RoadItems.linear_spec(item['kind'], item['variant'], item['height_m'])[:post]
            post ? (length / post[2]).floor + 2 : 0
          end
        end
      end

      def budget_problems(metrics, limits)
        out = []
        out << budget('road_faces', limits[:unique], metrics['unique_face_count']) if metrics['unique_face_count'] > limits[:unique]
        out << budget('road_items', limits[:items], metrics['item_count']) if metrics['item_count'] > limits[:items]
        out << budget('road_expanded_faces', limits[:expanded], metrics['expanded_face_count']) if metrics['expanded_face_count'] > limits[:expanded]
        out
      end

      def assemble(surface, placed, stations, section, line)
        children = [{ 'id' => 'road/surface', 'category' => 'surface', 'children' => [], 'primitive' => surface }]
        children << { 'id' => 'road/linear', 'category' => 'linear', 'children' => placed[:linear] } unless placed[:linear].empty?
        children << { 'id' => 'road/items', 'category' => 'item', 'children' => placed[:instances] } unless placed[:instances].empty?
        definitions = placed[:definitions].sort.to_h
        definition_faces = definitions.transform_values { |nodes| nodes.sum { |n| n['primitive']['faces'].size } }
        linear_faces = placed[:linear].sum { |n| n['primitive']['faces'].size }
        instanced = placed[:instances].sum { |n| definition_faces.fetch(n['primitive']['definition_id']) }
        {
          'schema_version' => 1, 'engine_version' => ROAD_ENGINE_VERSION, 'units' => 'm',
          'nodes' => [{ 'id' => 'road', 'category' => 'road', 'children' => children }],
          'definitions' => definitions,
          'metrics' => {
            'surface_face_count' => surface['faces'].size, 'vertex_count' => surface['vertices'].size,
            'station_count' => stations.size, 'cross_segment_count' => line.size,
            'width_m' => section['width_m'], 'length_m' => Quant.q(length(stations)),
            'linear_face_count' => linear_faces, 'definition_count' => definitions.size,
            'item_count' => placed[:instances].size,
            'unique_face_count' => surface['faces'].size + linear_faces + definition_faces.values.sum,
            'expanded_face_count' => surface['faces'].size + linear_faces + instanced
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

    # Mêmes refus de maillage que le plan du bâtiment, sur la structure du plan de voie : surface,
    # éléments continus (solides fermés), instances de définitions partagées.
    class RoadPlanValidator < PlanValidator
      CATEGORIES = %w[road surface linear item part].freeze

      def call
        return @out unless header_ok?

        @plan['nodes'].each { |node| check_node(node, allow_instance: true) }
        @plan['definitions'].each do |id, nodes|
          @ids = {}
          problem(id, 'empty_definition') if nodes.empty?
          nodes.each { |node| check_node(node, allow_instance: false) }
        end
        check_metrics
        @out.sort_by(&:sort_key)
      end

      private

      def categories
        CATEGORIES
      end

      def header_ok?
        problem('plan', 'bad_header') unless @plan['schema_version'] == 1 && @plan['units'] == 'm'
        %w[nodes definitions metrics].each { |key| problem('plan', "missing_#{key}") unless @plan.key?(key) }
        return false unless @out.empty?

        tops = @plan['nodes']
        problem('plan', 'single_road_root') unless tops.size == 1 && tops.first['category'] == 'road'
        @out.empty?
      end

      def check_metrics
        own = @plan['nodes'].sum { |node| node_faces(node) }
        definition_faces = @plan['definitions'].transform_values { |nodes| nodes.sum { |n| node_faces(n) } }
        instances = []
        @plan['nodes'].each { |node| collect_instances(node, instances) }
        counted = {
          'unique_face_count' => own + definition_faces.values.sum,
          'item_count' => instances.size,
          'expanded_face_count' => own + instances.sum { |id| definition_faces.fetch(id, 0) }
        }
        counted.each do |key, value|
          declared = @plan['metrics'][key]
          problem('metrics', 'metric_mismatch', metric: key, declared: declared, counted: value) unless declared == value
        end
      end
    end
  end
end
