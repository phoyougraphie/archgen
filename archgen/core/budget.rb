# frozen_string_literal: true

module Archgen
  module Core
    # Plafonds bloquants, contrôlés sur estimation puis sur le plan exact.
    module Budget
      HINT = 'reduce_bays_levels_or_detail'
      CHECKS = {
        'width_m' => [Limits::MAX_FOOTPRINT_M, '/footprint/width_m'],
        'depth_m' => [Limits::MAX_FOOTPRINT_M, '/footprint/depth_m'],
        'wall_top_z_m' => [Limits::MAX_WALL_TOP_M, '/levels'],
        'roof_top_z_m' => [Limits::MAX_ROOF_TOP_M, '/roof'],
        'opening_count' => [Limits::MAX_OPENINGS, '/facade'],
        'unique_face_count' => [Limits::MAX_UNIQUE_FACES, '/facade'],
        'expanded_face_count' => [Limits::MAX_EXPANDED_FACES, '/facade'],
        'wall_cell_count' => [Limits::MAX_WALL_CELLS, '/facade'],
        'detail_definition_count' => [Limits::MAX_DETAIL_DEFINITIONS, '/features']
      }.freeze

      module_function

      def check(metrics)
        CHECKS.filter_map do |key, (limit, path)|
          value = metrics[key]
          next if value.nil? || value <= limit + (value.is_a?(Float) ? Quant::EPSILON : 0)

          Diagnostic.error('E_BUDGET', path, reason: key, limit: limit, value: value, hint: HINT)
        end
      end
    end
  end
end
