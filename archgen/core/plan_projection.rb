# frozen_string_literal: true

module Archgen
  module Core
    # Projection 2D pour l'aperçu : coordonnées numériques seulement, jamais de
    # SVG ou de HTML injecté. Même vérité géométrique que le plan (ADR-07).
    module PlanProjection
      module_function

      def call(plan)
        metrics = plan['metrics']
        width = metrics['width_m']
        depth = metrics['depth_m']
        wall_top = metrics['wall_top_z_m']
        points = roof_points(plan)
        {
          'plan_view' => {
            'footprint' => [[0.0, 0.0], [width, 0.0], [width, depth], [0.0, depth]],
            'roof_outline' => hull(points.map { |p| [p[0], p[1]] })
          },
          'front_elevation' => {
            'wall_contour' => [[0.0, 0.0], [width, 0.0], [width, wall_top], [0.0, wall_top]],
            'roof_silhouette' => hull(points.map { |p| [p[0], p[2]] }),
            'openings' => front_openings(plan)
          },
          'summary' => {
            'window_count' => plan['openings'].count { |o| o['kind'] == 'window' },
            'door_count' => plan['openings'].count { |o| o['kind'] == 'door' },
            'roof_top_z_m' => metrics['roof_top_z_m']
          }
        }
      end

      def front_openings(plan)
        plan['openings'].select { |o| o['facade_id'] == 'front' }.map do |o|
          { 'id' => o['id'], 'kind' => o['kind'], 'x_min_m' => o['u_min_m'], 'x_max_m' => o['u_max_m'], 'z_min_m' => o['z_min_m'], 'z_max_m' => o['z_max_m'] }
        end
      end
      private_class_method :front_openings

      def roof_points(plan)
        found = []
        collect = lambda do |node|
          found.concat(node['primitive']['vertices']) if %w[roof_face gable_end].include?(node['category'])
          node['children'].each(&collect)
        end
        plan['nodes'].each(&collect)
        found
      end
      private_class_method :roof_points

      # Enveloppe convexe (chaîne monotone), sens antihoraire, ordre déterministe.
      def hull(points)
        sorted = points.uniq.sort
        return sorted if sorted.size < 3

        lower = half_hull(sorted)
        upper = half_hull(sorted.reverse)
        lower[0...-1] + upper[0...-1]
      end
      private_class_method :hull

      def half_hull(points)
        chain = []
        points.each do |p|
          chain.pop while chain.size >= 2 && turn(chain[-2], chain[-1], p) <= 0
          chain << p
        end
        chain
      end
      private_class_method :half_hull

      def turn(a, b, c)
        ((b[0] - a[0]) * (c[1] - a[1])) - ((b[1] - a[1]) * (c[0] - a[0]))
      end
      private_class_method :turn
    end
  end
end
