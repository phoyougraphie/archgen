# frozen_string_literal: true

module Archgen
  module Core
    # Plateforme et indicateurs sous l'emprise. Pur : grille et réglages en entrée, aucune
    # altitude inventée. Le bâtiment n'est pas relu : seules ses dimensions comptent.
    module SiteAssise
      MAX_LISTED_POINTS = 10

      module_function

      # Retourne un Result<Hash> gelé, en mètres et mètres cubes quantifiés.
      def call(grid, settings, width_m:, depth_m:)
        points = grid.points_within(width_m, depth_m)
        missing = points.select { |point| point[2].nil? }
        return Result.fail([survey_problem(missing)]) unless missing.empty?

        altitudes = points.map { |point| point[2] }
        relief = Quant.q(altitudes.max - altitudes.min)
        return Result.fail([relief_problem(relief)]) if relief > Limits::SITE_RELIEF_MAX_M + Quant::EPSILON

        platform = Quant.q(reference(altitudes, settings) + settings.dig('platform', 'offset_m'))
        Result.ok(Canonical.deep_freeze(indicators(grid, altitudes, platform, relief, width_m, depth_m)))
      end

      def reference(altitudes, settings)
        settings.dig('platform', 'policy') == 'high' ? altitudes.max : altitudes.sum / altitudes.size
      end
      private_class_method :reference

      def indicators(grid, altitudes, platform, relief, width_m, depth_m)
        cut, fill = volumes(grid, platform, width_m, depth_m)
        {
          'platform_z_m' => platform,
          'terrain_min_z_m' => altitudes.min,
          'terrain_max_z_m' => altitudes.max,
          'relief_m' => relief,
          'cut_max_m' => Quant.q([altitudes.max - platform, 0.0].max),
          'fill_max_m' => Quant.q([platform - altitudes.min, 0.0].max),
          'cut_volume_m3' => Quant.q(cut),
          'fill_volume_m3' => Quant.q(fill)
        }
      end
      private_class_method :indicators

      # Quadrature par cellule : aire multipliée par la moyenne des hauteurs aux quatre angles.
      def volumes(grid, platform, width_m, depth_m)
        grid.cells_within(width_m, depth_m).reduce([0.0, 0.0]) do |(cut, fill), (dx, dy, corners)|
          area = dx * dy / corners.size
          [cut + (area * corners.sum { |z| [z - platform, 0.0].max }),
           fill + (area * corners.sum { |z| [platform - z, 0.0].max })]
        end
      end
      private_class_method :volumes

      def survey_problem(missing)
        Diagnostic.error('E_SITE_SURVEY', '/site/survey', reason: 'missing_points', count: missing.size,
                                                          points: missing.first(MAX_LISTED_POINTS).map { |point| point.first(2) })
      end
      private_class_method :survey_problem

      def relief_problem(relief)
        Diagnostic.error('E_SITE_RELIEF', '/site/platform', reason: 'relief_exceeded', limit: Limits::SITE_RELIEF_MAX_M, value: relief)
      end
      private_class_method :relief_problem
    end
  end
end
