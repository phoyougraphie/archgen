# frozen_string_literal: true

module Archgen
  module Core
    # Mêmes refus de maillage que le plan du bâtiment, sur la structure du plan d'assise.
    class SitePlanValidator < PlanValidator
      CATEGORIES = %w[site platform plinth embankment].freeze

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
        problem('plan', 'single_site_root') unless tops.size == 1 && tops.first['category'] == 'site'
        @out.empty?
      end

      def check_metrics
        counted = @plan['nodes'].sum { |node| node_faces(node) }
        declared = @plan['metrics']['site_face_count']
        problem('metrics', 'metric_mismatch', metric: 'site_face_count', declared: declared, counted: counted) unless declared == counted
      end
    end
  end
end
