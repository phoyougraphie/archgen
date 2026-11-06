# frozen_string_literal: true

module Archgen
  module Core
    # Plateforme et indicateurs sous l'emprise. Pur : grille et réglages en entrée, aucune
    # altitude inventée. Le bâtiment n'est pas relu : seules ses dimensions comptent.
    module SiteAssise
      MAX_LISTED_POINTS = 10
      AREA_EPSILON = 1e-9

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

      # Même assise sous un anneau convexe, dans le sens antihoraire : les nœuds à l'intérieur,
      # plus l'altitude interpolée aux stations de ses bords. Un rectangle donne le résultat de `call`.
      def for_ring(grid, settings, ring:)
        touching = grid.cells.filter_map do |cell|
          area = clipped_area(ring, cell[:bounds])
          [cell, area] if area > AREA_EPSILON
        end
        stations = ring_stations(ring, settings.dig('survey', 'step_m'))
        known = stations.map { |x, y| [Quant.q(x), Quant.q(y), grid.altitude_at(x, y)] }
        missing = touching.flat_map { |cell, _| cell[:corners] }.select { |point| point[2].nil? }.uniq + known.select { |point| point[2].nil? }
        return Result.fail([survey_problem(missing)]) unless missing.empty?

        inside = touching.flat_map { |cell, _| cell[:corners] }.uniq.select { |x, y, _| inside?(ring, x, y) }.map { |x, y, z| [Quant.q(x), Quant.q(y), z] }
        altitudes = (inside + known).uniq { |x, y, _| [x, y] }.map { |point| point[2] }
        relief = Quant.q(altitudes.max - altitudes.min)
        return Result.fail([relief_problem(relief)]) if relief > Limits::SITE_RELIEF_MAX_M + Quant::EPSILON

        platform = Quant.q(reference(altitudes, settings) + settings.dig('platform', 'offset_m'))
        Result.ok(Canonical.deep_freeze(ring_indicators(touching, altitudes, platform, relief)))
      end

      def ring_stations(ring, step)
        ring.each_with_index.flat_map do |a, index|
          b = ring[(index + 1) % ring.size]
          length = Math.hypot(b[0] - a[0], b[1] - a[1])
          SurveyGrid.even_stations(length, step).map { |u| [a[0] + ((b[0] - a[0]) * u / length), a[1] + ((b[1] - a[1]) * u / length)] }
        end
      end
      private_class_method :ring_stations

      def inside?(ring, x, y)
        ring.each_with_index.all? do |a, index|
          b = ring[(index + 1) % ring.size]
          ((b[0] - a[0]) * (y - a[1])) - ((b[1] - a[1]) * (x - a[0])) >= -Quant::EPSILON
        end
      end
      private_class_method :inside?

      # Aire de l'anneau dans la cellule : découpe par les quatre côtés de la cellule.
      def clipped_area(ring, bounds)
        x0, x1, y0, y1 = bounds
        polygon = clip(ring, 0, x0, 1.0)
        polygon = clip(polygon, 0, x1, -1.0)
        polygon = clip(polygon, 1, y0, 1.0)
        polygon = clip(polygon, 1, y1, -1.0)
        return 0.0 if polygon.size < 3

        polygon.each_with_index.sum { |a, i| (a[0] * polygon[(i + 1) % polygon.size][1]) - (polygon[(i + 1) % polygon.size][0] * a[1]) }.abs / 2.0
      end
      private_class_method :clipped_area

      # Garde le côté où sign × (coordonnée − limite) ≥ 0.
      def clip(polygon, axis, limit, sign)
        polygon.each_with_index.flat_map do |a, i|
          b = polygon[(i + 1) % polygon.size]
          da = sign * (a[axis] - limit)
          db = sign * (b[axis] - limit)
          out = da >= 0.0 ? [a] : []
          out << [a[0] + ((b[0] - a[0]) * da / (da - db)), a[1] + ((b[1] - a[1]) * da / (da - db))] if (da >= 0.0) != (db >= 0.0)
          out
        end
      end
      private_class_method :clip

      def ring_indicators(touching, altitudes, platform, relief)
        cut, fill = touching.reduce([0.0, 0.0]) do |(c, f), (cell, area)|
          heights = cell[:corners].map { |point| point[2] }
          [c + (area / 4.0 * heights.sum { |z| [z - platform, 0.0].max }), f + (area / 4.0 * heights.sum { |z| [platform - z, 0.0].max })]
        end
        cut_max = Quant.q([altitudes.max - platform, 0.0].max)
        fill_max = Quant.q([platform - altitudes.min, 0.0].max)
        {
          'platform_z_m' => platform,
          'terrain_min_z_m' => altitudes.min,
          'terrain_max_z_m' => altitudes.max,
          'relief_m' => relief,
          'cut_max_m' => cut_max,
          'fill_max_m' => fill_max,
          # Un angle de cellule hors de l'anneau peut dépasser la plateforme : sans déblai dans l'anneau, pas de volume.
          'cut_volume_m3' => cut_max.zero? ? 0.0 : Quant.q(cut),
          'fill_volume_m3' => fill_max.zero? ? 0.0 : Quant.q(fill)
        }
      end
      private_class_method :ring_indicators

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
