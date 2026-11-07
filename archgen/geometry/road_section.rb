# frozen_string_literal: true

module Archgen
  module Geometry
    # Coupe en travers d'un profil de voirie effectif (docs/VOIRIE_CONTRACT.md) : bords des
    # bandes, ligne de surface, bordures, rails et position des éléments, en mètres, x de
    # gauche à droite depuis le bord gauche, z depuis le niveau 0. Calcul pur, sans hôte.
    module RoadSection
      CURB_WIDTH_M = 0.16
      CURB_MIN_STEP_M = 0.10
      DITCH_FLOOR_RATIO = 0.3
      BALLAST_RAIL_RISE_M = 0.17
      LENGTH_FOR_COUNT_M = 100.0
      CROWN_ROLES = %w[carriageway tram rail].freeze
      # Une bordure ne borde qu'un trottoir, un terre-plein, une bande plantée ou une piste : le ballast n'en a pas.
      CURB_ROLES = %w[pedestrian median planting cycle].freeze

      module_function

      # profile : profil effectif de RoadProfileIntake ; bands, items : catalogues chargés.
      def call(profile, bands:, items:)
        catalogue = bands.fetch('bands')
        width = profile['bands'].sum { |b| b['width_m'] }
        spans = spans(profile)
        rows = profile['bands'].each_with_index.map do |band, i|
          entry = catalogue.fetch(band['type'])
          { 'index' => i, 'type' => band['type'], 'role' => entry['role'], 'x0_m' => q(spans[i][0]), 'x1_m' => q(spans[i][1]),
            'level_m' => entry['level_m'].to_f, 'surface' => surface(entry, spans[i], width) }
        end
        {
          'width_m' => q(width),
          'bands' => rows,
          'curbs' => curbs(rows, catalogue),
          'rails' => rails(rows, catalogue, bands.fetch('rail_gauge_m')),
          'items' => placed_items(profile, rows, items.fetch('items'))
        }
      end

      def q(value)
        Core::Quant.q(value)
      end

      def spans(profile)
        left = 0.0
        profile['bands'].map do |band|
          pair = [left, left + band['width_m']]
          left = pair[1]
          pair
        end
      end

      # Ligne de surface de la bande, de gauche à droite.
      def surface(entry, span, total)
        x0, x1 = span
        w = x1 - x0
        z = entry['level_m'].to_f
        case entry['shape']
        when 'ditch'
          lip = w * (1 - DITCH_FLOOR_RATIO) / 2
          d = -entry['depth_m'].to_f
          [[x0, z], [x0 + lip, d], [x1 - lip, d], [x1, z]]
        when 'bank'
          rise = entry['slope'].to_f * w
          (x0 + x1) / 2 < total / 2 ? [[x0, z + rise], [x1, z]] : [[x0, z], [x1, z + rise]]
        else
          [[x0, z], [x1, z]]
        end.map { |x, zz| [q(x), q(zz)] }
      end

      # Une bordure de 0,16 m entre deux bandes planes dont le niveau diffère d'au moins 0,10 m,
      # prise dans la bande haute, contre la bande basse.
      def curbs(rows, catalogue)
        rows.each_cons(2).filter_map do |a, b|
          next unless catalogue[a['type']]['shape'] == 'flat' && catalogue[b['type']]['shape'] == 'flat'

          step = b['level_m'] - a['level_m']
          next if step.abs < CURB_MIN_STEP_M - 1e-9

          high = step.positive? ? b : a
          next unless CURB_ROLES.include?(high['role'])

          { 'x_m' => b['x0_m'], 'band' => high['index'], 'side' => step.positive? ? 'right' : 'left',
            'width_m' => CURB_WIDTH_M, 'z_low_m' => q([a['level_m'], b['level_m']].min), 'z_high_m' => q([a['level_m'], b['level_m']].max) }
        end
      end

      def rails(rows, catalogue, gauge)
        rows.flat_map do |row|
          kind = catalogue[row['type']]['rails']
          next [] if kind == 'none'

          center = (row['x0_m'] + row['x1_m']) / 2
          top = row['level_m'] + (kind == 'ballast' ? BALLAST_RAIL_RISE_M : 0.0)
          [-1, 1].map { |s| { 'band' => row['index'], 'kind' => kind, 'x_m' => q(center + (s * gauge / 2)), 'z_m' => q(top) } }
        end
      end

      def placed_items(profile, rows, catalogue)
        profile['bands'].each_with_index.flat_map do |band, i|
          count = band['items'].size
          band['items'].each_with_index.map do |item, j|
            x = rows[i]['x0_m'] + (band['width_m'] * (j + 1) / (count + 1))
            placed(item, catalogue.fetch(item['kind']), rows, i, j, x)
          end
        end
      end

      def placed(item, entry, rows, band, index, x)
        out = { 'band' => band, 'index' => index, 'kind' => item['kind'], 'variant' => item['variant'],
                'x_m' => q(x), 'z_m' => q(z_at(rows[band]['surface'], x)), 'height_m' => item['height_m'],
                'repeat' => entry['repeat'], 'toward' => toward(rows, band, x) }
        if entry['repeat'] == 'spaced'
          out['spacing_m'] = item['spacing_m']
          out['count_per_100m'] = count_over(item['spacing_m'])
        end
        if item['kind'] == 'tree'
          shape = entry['variants'].fetch(item['variant'])
          out['crown_radius_m'] = q(shape['crown_radius_ratio'] * item['height_m'])
          out['crown_base_m'] = q(shape['crown_base_ratio'] * item['height_m'])
        end
        out
      end

      # Contrat : premier objet à pas/2, puis tous les pas ; rien au-delà de la longueur.
      def count_over(spacing, length = LENGTH_FOR_COUNT_M)
        spacing = spacing.to_f
        return 0 if spacing / 2 > length

        ((length - (spacing / 2)) / spacing).floor + 1
      end

      # Côté de la voie la plus proche, vers lequel se tourne une crosse ; nil s'il n'y en a pas.
      def toward(rows, own, x)
        best = rows.each_with_index.filter_map do |row, k|
          next if k == own || !CROWN_ROLES.include?(row['role'])

          center = (row['x0_m'] + row['x1_m']) / 2
          [(center - x).abs, k, center > x ? 'right' : 'left']
        end.min
        best && best[2]
      end

      def z_at(points, x)
        points.each_cons(2) do |(xa, za), (xb, zb)|
          next unless x.between?(xa, xb)
          return za if (xb - xa).abs < 1e-12

          return za + ((zb - za) * (x - xa) / (xb - xa))
        end
        points.last[1]
      end
    end
  end
end
