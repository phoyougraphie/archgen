# frozen_string_literal: true

module Archgen
  module Core
    # Terrain ASCII Grid en Lambert-93 → maillage dans le repère de la carte
    # (docs/CARTOGRAPHIE_CONTRACT.md §4, AG-128, D-42). Pur : reçoit des octets et l'origine de la carte.
    module MapTerrain
      module_function

      MAX_BYTES = 64 * 1024 * 1024
      MAX_FILE_POINTS = 1000 * 1000
      MAX_MESH_SIDE = 250
      MIN_STEP_M = 2.0
      MAX_NODATA = 0.01
      MARGIN_M = 20.0
      HEADERS = %w[ncols nrows cellsize].freeze

      # Lambert-93 (IGN, ALG0003 et ALG0019) sur l'ellipsoïde GRS 80.
      module Lambert93
        module_function

        N = 0.7256077650532670
        C = 11_754_255.426096
        XS = 700_000.0
        YS = 12_655_612.049876
        E = 0.0818191910428158
        A = 6_378_137.0
        LON0 = 3.0 * Math::PI / 180

        # [lat, lon] en degrés → [E, N] en mètres, convergence γ (radians) et facteur d'échelle k.
        def call(lat, lon)
          phi = lat * Math::PI / 180
          lam = lon * Math::PI / 180
          s = Math.sin(phi)
          iso = Math.log(Math.tan((Math::PI / 4) + (phi / 2)) * (((1 - (E * s)) / (1 + (E * s)))**(E / 2)))
          r = C * Math.exp(-N * iso)
          gamma = N * (lam - LON0)
          normal = A / Math.sqrt(1 - (E * E * s * s))
          { east: XS + (r * Math.sin(gamma)), north: YS - (r * Math.cos(gamma)), gamma: gamma, k: (N * r) / (normal * Math.cos(phi)) }
        end
      end

      def error(reason, **params)
        Result.fail([Diagnostic.error('E_MAP', '/terrain', reason: reason, **params)])
      end

      # origin : [lat, lon] de la carte ; extent : [[xmin, ymin], [xmax, ymax]] en mètres locaux, ou nil.
      def call(bytes, origin:, extent: nil, material: 'earth')
        grid = parse(bytes)
        return grid if grid.is_a?(Result)

        place(grid, origin, extent, material)
      end

      # --- Lecture

      def parse(bytes)
        return error('terrain_file', reason_detail: 'too_large', limit: MAX_BYTES) if bytes.bytesize > MAX_BYTES

        lines = bytes.dup.force_encoding('UTF-8').scrub.each_line.map(&:strip).reject(&:empty?)
        header = {}
        while (m = lines.first&.match(/\A([A-Za-z_]+)\s+(\S+)\z/))
          header[m[1].downcase] = m[2]
          lines.shift
        end
        missing = HEADERS.reject { |k| header.key?(k) }
        missing << 'xllcorner' unless header.key?('xllcorner') || header.key?('xllcenter')
        missing << 'yllcorner' unless header.key?('yllcorner') || header.key?('yllcenter')
        return error('terrain_file', reason_detail: 'header', missing: missing) unless missing.empty?

        cols = Integer(header['ncols'], exception: false)
        rows = Integer(header['nrows'], exception: false)
        cell = Float(header['cellsize'], exception: false)
        return error('terrain_file', reason_detail: 'header') unless cols&.positive? && rows&.positive? && cell&.positive?
        return error('terrain_too_large', value: cols * rows, limit: MAX_FILE_POINTS) if cols * rows > MAX_FILE_POINTS

        centered = header.key?('xllcenter')
        x0 = Float(header['xllcenter'] || header['xllcorner'], exception: false)
        y0 = Float(header['yllcenter'] || header['yllcorner'], exception: false)
        return error('terrain_file', reason_detail: 'header') unless x0 && y0

        # Coordonnées du centre de la cellule en bas à gauche.
        x0 += cell / 2 unless centered
        y0 += cell / 2 unless centered
        nodata = Float(header.fetch('nodata_value', '-99999'), exception: false)
        values = lines.join(' ').split(/\s+/).map { |t| Float(t, exception: false) }
        return error('terrain_file', reason_detail: 'values', value: values.size, expected: cols * rows) unless values.size == cols * rows && values.none?(&:nil?)

        # Ligne 0 du fichier = nord ; on range en z[ligne depuis le sud][colonne].
        z = values.each_slice(cols).to_a.reverse
        { cols: cols, rows: rows, cell: cell, x0: x0, y0: y0, z: z, nodata: nodata }
      end

      # --- Recalage, découpe, décimation, maillage

      def place(grid, origin, extent, material)
        filled = fill_nodata(grid)
        return filled if filled.is_a?(Result)

        l93 = Lambert93.call(*origin)
        to_local = lambda do |e, n|
          de = e - l93[:east]
          dn = n - l93[:north]
          c = Math.cos(l93[:gamma])
          s = Math.sin(l93[:gamma])
          [((de * c) - (dn * s)) / l93[:k], ((de * s) + (dn * c)) / l93[:k]]
        end
        to_grid = lambda do |x, y|
          c = Math.cos(l93[:gamma])
          s = Math.sin(l93[:gamma])
          de = ((x * c) + (y * s)) * l93[:k]
          dn = ((-x * s) + (y * c)) * l93[:k]
          [l93[:east] + de, l93[:north] + dn]
        end
        e_origin, n_origin = to_grid.call(0.0, 0.0)
        z_origin = sample(grid, e_origin, n_origin)
        return error('terrain_outside_map') unless z_origin

        cols, rows = window(grid, extent, to_grid)
        return error('terrain_outside_map') if cols.size < 2 || rows.size < 2

        stride = [(MIN_STEP_M / grid[:cell]).ceil, 1].max
        stride += 1 while (((cols.size - 1) / stride) + 1) > MAX_MESH_SIDE || (((rows.size - 1) / stride) + 1) > MAX_MESH_SIDE
        cs = cols.each_slice(stride).map(&:first)
        cs << cols.last unless cs.last == cols.last
        rs = rows.each_slice(stride).map(&:first)
        rs << rows.last unless rs.last == rows.last

        builder = Geometry::MeshBuilder.new('surface')
        point = lambda do |i, j|
          x, y = to_local.call(grid[:x0] + (cs[i] * grid[:cell]), grid[:y0] + (rs[j] * grid[:cell]))
          [x, y, grid[:z][rs[j]][cs[i]] - z_origin]
        end
        (0...(rs.size - 1)).each do |j|
          (0...(cs.size - 1)).each do |i|
            a = point.call(i, j)
            b = point.call(i + 1, j)
            c = point.call(i + 1, j + 1)
            d = point.call(i, j + 1)
            builder.add_face([a, b, c], material)
            builder.add_face([a, c, d], material)
          end
        end
        primitive = builder.to_primitive
        Result.ok({ 'nodes' => [{ 'id' => 'terrain', 'category' => 'site', 'children' => [], 'primitive' => primitive }],
                    'metrics' => { 'step_m' => Quant.q(stride * grid[:cell]), 'points' => cs.size * rs.size,
                                   'face_count' => primitive['faces'].size, 'z_origin_m' => Quant.q(z_origin),
                                   'nodata_filled' => filled, 'gamma_deg' => Quant.q(l93[:gamma] * 180 / Math::PI),
                                   'scale' => Quant.q(l93[:k]) } })
      end

      # Indices de colonnes et de lignes couvrant l'emprise de la carte, plus 20 m ; tout le fichier sans emprise.
      def window(grid, extent, to_grid)
        all_cols = (0...grid[:cols]).to_a
        all_rows = (0...grid[:rows]).to_a
        return [all_cols, all_rows] unless extent

        (xmin, ymin), (xmax, ymax) = extent
        corners = [[xmin - MARGIN_M, ymin - MARGIN_M], [xmax + MARGIN_M, ymin - MARGIN_M],
                   [xmax + MARGIN_M, ymax + MARGIN_M], [xmin - MARGIN_M, ymax + MARGIN_M]].map { |x, y| to_grid.call(x, y) }
        es = corners.map(&:first)
        ns = corners.map(&:last)
        i0 = ((es.min - grid[:x0]) / grid[:cell]).floor.clamp(0, grid[:cols] - 1)
        i1 = ((es.max - grid[:x0]) / grid[:cell]).ceil.clamp(0, grid[:cols] - 1)
        j0 = ((ns.min - grid[:y0]) / grid[:cell]).floor.clamp(0, grid[:rows] - 1)
        j1 = ((ns.max - grid[:y0]) / grid[:cell]).ceil.clamp(0, grid[:rows] - 1)
        [(i0..i1).to_a, (j0..j1).to_a]
      end

      # Altitude bilinéaire en (E, N), nil hors du fichier.
      def sample(grid, east, north)
        u = (east - grid[:x0]) / grid[:cell]
        v = (north - grid[:y0]) / grid[:cell]
        return nil if u.negative? || v.negative? || u > grid[:cols] - 1 || v > grid[:rows] - 1

        i = [u.floor, grid[:cols] - 2].min.clamp(0, grid[:cols] - 1)
        j = [v.floor, grid[:rows] - 2].min.clamp(0, grid[:rows] - 1)
        fu = u - i
        fv = v - j
        z = grid[:z]
        at = ->(a, b) { z[[b, grid[:rows] - 1].min][[a, grid[:cols] - 1].min] }
        (at.call(i, j) * (1 - fu) * (1 - fv)) + (at.call(i + 1, j) * fu * (1 - fv)) +
          (at.call(i, j + 1) * (1 - fu) * fv) + (at.call(i + 1, j + 1) * fu * fv)
      end

      # Points NODATA : refus au-delà de 1 %, sinon moyenne des voisins valides, de proche en proche.
      def fill_nodata(grid)
        z = grid[:z]
        holes = []
        z.each_with_index { |row, j| row.each_with_index { |v, i| holes << [i, j] if (v - grid[:nodata]).abs < 1e-9 } }
        return 0 if holes.empty?

        total = grid[:cols] * grid[:rows]
        return error('terrain_nodata', value: holes.size, limit: (total * MAX_NODATA).floor) if holes.size > total * MAX_NODATA

        missing = holes.to_h { |h| [h, true] }
        until missing.empty?
          progress = false
          missing.keys.sort.each do |i, j|
            near = [[i - 1, j], [i + 1, j], [i, j - 1], [i, j + 1]].select do |a, b|
              a.between?(0, grid[:cols] - 1) && b.between?(0, grid[:rows] - 1) && !missing.key?([a, b])
            end
            next if near.empty?

            z[j][i] = near.sum { |a, b| z[b][a] } / near.size
            missing.delete([i, j])
            progress = true
          end
          return error('terrain_nodata', value: holes.size, limit: (total * MAX_NODATA).floor) unless progress
        end
        holes.size
      end
    end
  end
end
