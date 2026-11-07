# frozen_string_literal: true

module Archgen
  module Geometry
    # Rubans d'une voie : la ligne de coupe (surfaces des bandes, bordures, contremarches) balayée
    # le long des stations de l'axe. Une seule surface : deux rubans voisins partagent leurs sommets.
    module RoadRibbons
      PLANAR_SPLIT_M = 1e-6

      module_function

      # Ligne de coupe continue, de gauche à droite : [[x, z], [x, z], matériau].
      def cross_line(section)
        bands = section['bands']
        curbs = section['curbs']
        out = []
        last = nil
        bands.each do |band|
          start = band['surface'].first
          out << riser(last, start, bands, band, curbs) if last && (last[1] - start[1]).abs > 1e-9
          split(band, curbs).each_cons(2) do |a, b|
            out << [a[0], b[0], a[1]]
          end
          last = band['surface'].last
        end
        out
      end

      def material(type)
        "road/#{type}"
      end

      # Contremarche entre deux bandes : matière de la bordure s'il y en a une, sinon de la bande haute.
      def riser(last, start, bands, band, curbs)
        curb = curbs.find { |c| (c['x_m'] - start[0]).abs < 1e-9 }
        high = last[1] > start[1] ? bands[band['index'] - 1] : band
        [last, start, curb ? 'road/curb' : material(high['type'])]
      end

      # Points de surface de la bande, coupés au bord de ses bordures : [[x, z], matériau du segment qui suit].
      def split(band, curbs)
        points = band['surface'].map { |p| [p, material(band['type'])] }
        own = curbs.select { |c| c['band'] == band['index'] }
        return points if own.empty?

        x0, z = band['surface'].first
        x1 = band['surface'].last[0]
        starts = own.any? { |c| c['side'] == 'right' }
        ends = own.any? { |c| c['side'] == 'left' }
        width = own.first['width_m']
        out = [[[x0, z], starts ? 'road/curb' : material(band['type'])]]
        out << [[x0 + width, z], material(band['type'])] if starts
        out << [[x1 - width, z], 'road/curb'] if ends
        out << [[x1, z], nil]
        out
      end

      # x de coupe -> décalage à gauche de l'axe, selon la position de l'axe dans l'emprise.
      def axis_x(width, axis)
        { 'left' => 0.0, 'center' => width / 2.0, 'right' => width }.fetch(axis)
      end

      def mesh(stations, line, width:, axis:)
        builder = MeshBuilder.new('surface')
        ax = axis_x(width, axis)
        stations.each_cons(2) do |a, b|
          line.each do |(xa, za), (xb, zb), mat|
            quad = [place(a, ax - xa, za), place(a, ax - xb, zb), place(b, ax - xb, zb), place(b, ax - xa, za)]
            if planar?(quad)
              builder.add_face(quad, mat)
            else
              builder.add_face([quad[0], quad[1], quad[2]], mat)
              builder.add_face([quad[0], quad[2], quad[3]], mat)
            end
          end
        end
        builder.to_primitive
      end

      def place(station, offset, z)
        [station.point[0] + (station.normal[0] * offset), station.point[1] + (station.normal[1] * offset), z]
      end

      def planar?(quad)
        q = quad.map { |p| Core::Quant.q3(p) }
        n = cross(sub(q[1], q[0]), sub(q[3], q[0]))
        size = Math.sqrt(dot(n, n))
        return true if size < 1e-12

        (dot(n, sub(q[2], q[0])) / size).abs < PLANAR_SPLIT_M
      end

      def sub(a, b)
        [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
      end

      def cross(a, b)
        [(a[1] * b[2]) - (a[2] * b[1]), (a[2] * b[0]) - (a[0] * b[2]), (a[0] * b[1]) - (a[1] * b[0])]
      end

      def dot(a, b)
        (a[0] * b[0]) + (a[1] * b[1]) + (a[2] * b[2])
      end

      # Faces à prévoir avant de les construire, pour refuser tôt un tracé trop lourd.
      def face_estimate(stations_count, line)
        (stations_count - 1) * line.size * 2
      end
    end
  end
end
