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
            'level_m' => entry['level_m'].to_f, 'surface' => surface(entry, spans[i], width) }.merge(band.slice('freeboard_m', 'depth_m', 'height_m', 'slope_percent'))
        end
        shape_water(rows)
        shape_coast(rows)
        {
          'width_m' => q(width),
          'bands' => rows,
          'curbs' => curbs(rows, catalogue),
          'rails' => rails(rows, catalogue, bands.fetch('rail_gauge_m')),
          'items' => placed_items(profile, rows, items.fetch('items')),
          'water' => water_lines(rows)
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

      # Eau (EAU_CONTRACT, AG-051) : le lit d'un plan d'eau est à −(revanche + profondeur) ; contre une berge
      # il remonte en pente de 1 pour 2 jusqu'à la ligne d'eau, contre un quai il va jusqu'au pied du mur.
      # Une berge descend en pente droite du niveau 0 à la ligne d'eau, côté eau.
      BED_SLOPE_RUN = 2.0

      def shape_water(rows)
        rows.each_with_index do |row, i|
          next unless row['type'] == 'water'

          line = -row['freeboard_m']
          bed = -(row['freeboard_m'] + row['depth_m'])
          run = BED_SLOPE_RUN * row['depth_m']
          left = rows[i - 1] if i.positive?
          right = rows[i + 1]
          points = []
          if left && left['type'] == 'riverbank'
            points << [row['x0_m'], line] << [row['x0_m'] + run, bed]
            left['surface'] = [[left['x0_m'], 0.0], [left['x1_m'], line]].map { |x, z| [q(x), q(z)] }
          else
            points << [row['x0_m'], bed]
          end
          if right && right['type'] == 'riverbank'
            points << [row['x1_m'] - run, bed] << [row['x1_m'], line]
            right['surface'] = [[right['x0_m'], line], [right['x1_m'], 0.0]].map { |x, z| [q(x), q(z)] }
          else
            points << [row['x1_m'], bed]
          end
          row['surface'] = points.map { |x, z| [q(x), q(z)] }.chunk_while { |a, b| a == b }.map(&:first)
        end
      end

      # Littoral (EAU_CONTRACT, AG-052) : niveaux cumulés. De la terre vers la mer, chaque bande part du
      # niveau où la précédente s'arrête ; une falaise descend de sa hauteur, une plage de sa pente, une dune
      # revient à son niveau. La mer est une surface au niveau de son bord ; son fond descend du rivage à 3 m
      # de profondeur sur 10 m, puis reste plat (demande du propriétaire, 2026-11-08).
      SEA_DEPTH_M = 3.0
      SEA_SHELF_M = 10.0
      DUNE_FACETS = 8

      def shape_coast(rows)
        sea = rows.index { |r| r['type'] == 'sea' }
        toward_right = sea.nil? || sea == rows.size - 1
        order = toward_right ? rows : rows.reverse
        base = 0.0
        order.each do |row|
          w = row['x1_m'] - row['x0_m']
          drop = case row['type']
                 when 'cliff' then row['height_m']
                 when 'beach' then w * row['slope_percent'] / 100.0
                 else 0.0
                 end
          local = case row['type']
                  when 'cliff', 'beach' then toward_right ? [[row['x0_m'], 0.0], [row['x1_m'], -drop]] : [[row['x0_m'], -drop], [row['x1_m'], 0.0]]
                  when 'dune' then (0..DUNE_FACETS).map { |k| [row['x0_m'] + (w * k / DUNE_FACETS), row['height_m'] * Math.sin(Math::PI * k / DUNE_FACETS)] }
                  when 'sea'
                    if toward_right
                      [[row['x0_m'], 0.0], [row['x0_m'] + SEA_SHELF_M, -SEA_DEPTH_M], [row['x1_m'], -SEA_DEPTH_M]]
                    else
                      [[row['x0_m'], -SEA_DEPTH_M], [row['x1_m'] - SEA_SHELF_M, -SEA_DEPTH_M], [row['x1_m'], 0.0]]
                    end
                  end
          row['surface'] = local if local
          row['base_m'] = q(base)
          unless base.zero?
            row['surface'] = row['surface'].map { |x, z| [x, z + base] }
            row['level_m'] = row['level_m'] + base
          end
          row['surface'] = row['surface'].map { |x, z| [q(x), q(z)] }
          base -= drop
        end
      end

      # Surfaces de l'eau, à part de la ligne de coupe : de bord à bord du plan d'eau, à la ligne d'eau.
      def water_lines(rows)
        rows.select { |r| %w[water sea].include?(r['type']) }.map do |r|
          z = r['base_m'] - (r['type'] == 'water' ? r['freeboard_m'] : 0.0)
          { 'band' => r['index'], 'x0_m' => r['x0_m'], 'x1_m' => r['x1_m'], 'z_m' => q(z) }
        end
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
          band['items'].each_with_index.flat_map do |item, j|
            entry = catalogue.fetch(item['kind'])
            # Un plot de chaussée marque la limite gauche de sa bande (D-10, ADR-42).
            x = entry['placement'] == 'band_left' ? rows[i]['x0_m'] : rows[i]['x0_m'] + (band['width_m'] * (j + 1) / (count + 1))
            x = shelter_x(rows, i, x) if item['kind'] == 'bus_stop' && item['variant'] == 'shelter'
            out = placed(item, entry, rows, i, j, x)
            item['kind'] == 'bus_stop' ? [out] + bus_marking(rows, out) : [out]
          end
        end
      end

      # Abri (docs/MOBILIER_CONTRACT.md §3) : son fond à 0,30 m du bord opposé à la chaussée, 1,40 m de profondeur.
      SHELTER_BACK_M = 0.3
      SHELTER_DEPTH_M = 1.4
      MARKING_INSET_M = 0.6

      def shelter_x(rows, own, x)
        side = toward(rows, own, x)
        return x unless side

        reach = SHELTER_BACK_M + (SHELTER_DEPTH_M / 2)
        side == 'right' ? rows[own]['x0_m'] + reach : rows[own]['x1_m'] - reach
      end

      # Marquage jaune sur la voie de circulation contiguë, côté chaussée ; rien sans voie contiguë.
      def bus_marking(rows, stop)
        side = stop['toward']
        k = side == 'right' ? stop['band'] + 1 : stop['band'] - 1
        lane = side && k.between?(0, rows.size - 1) ? rows[k] : nil
        return [] unless lane && lane['type'] == 'lane'

        edge = side == 'right' ? lane['x0_m'] : lane['x1_m']
        x = edge + (side == 'right' ? MARKING_INSET_M : -MARKING_INSET_M)
        [stop.merge('kind' => 'bus_marking', 'variant' => 'zigzag', 'band' => k, 'x_m' => q(x),
                    'z_m' => q(z_at(lane['surface'], x)), 'height_m' => 0.01).tap { |m| m.delete('count') }]
      end

      def placed(item, entry, rows, band, index, x)
        out = { 'band' => band, 'index' => index, 'kind' => item['kind'], 'variant' => item['variant'],
                'x_m' => q(x), 'z_m' => q(z_at(rows[band]['surface'], x)), 'height_m' => item['height_m'],
                'repeat' => item.key?('positions_m') ? 'positions' : entry['repeat'], 'toward' => toward(rows, band, x) }
        out['count'] = item['count'] if item.key?('count')
        out['positions_m'] = item['positions_m'] if item.key?('positions_m')
        out['facing'] = item['facing'] if item.key?('facing')
        if out['repeat'] == 'spaced'
          out['spacing_m'] = item['spacing_m']
          out['count_per_100m'] = count_over(item['spacing_m'])
        end
        if item['kind'] == 'tree'
          shape = entry['variants'].fetch(item['variant'])
          out['crown_radius_m'] = q(shape['crown_radius_ratio'] * item['height_m'])
          out['crown_base_m'] = q(shape['crown_base_ratio'] * item['height_m'])
          out['height_variation'] = item['height_variation'].to_f
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
