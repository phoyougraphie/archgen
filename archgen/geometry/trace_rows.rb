# frozen_string_literal: true

module Archgen
  module Geometry
    # Une rangée se parcourt le bâti à sa gauche. `sources[i]` est le segment du tracé
    # d'origine qui a donné le segment i : les diagnostics parlent toujours du tracé saisi.
    TraceRow = Struct.new(:id, :points, :closed, :sources, keyword_init: true) do
      def segment_count
        closed ? points.size : points.size - 1
      end

      def segment(index)
        [points[index], points[(index + 1) % points.size]]
      end
    end

    # Du tracé saisi aux rangées de façades (docs/ENSEMBLE_CONTRACT.md, Tracé et segments).
    module TraceRows
      FOLD_LIMIT = 1e-9

      module_function

      def call(settings)
        points = settings.dig('trace', 'points_m')
        closed = settings.dig('trace', 'closed')
        problems = point_problems(points, closed)
        return Core::Result.fail(problems) unless problems.empty?

        problems = segment_problems(points, closed)
        return Core::Result.fail(problems) unless problems.empty?

        closed ? closed_rows(points) : open_rows(points, settings['layout'])
      end

      def point_problems(points, closed)
        minimum = closed ? 3 : 2
        return [trace_error('/trace/points_m', 'too_few_points', limit: minimum, value: points.size)] if points.size < minimum
        return [trace_error('/trace/points_m/0', 'first_point_not_origin')] unless points.first == [0.0, 0.0]

        limit = Core::Limits::ENSEMBLE_MAX_COORDINATE_M
        points.each_with_index.filter_map do |point, index|
          trace_error("/trace/points_m/#{index}", 'point_out_of_range', limit: limit) if point.any? { |c| c.abs > limit }
        end
      end
      private_class_method :point_problems

      def segment_problems(points, closed)
        segments = segments_of(points, closed)
        problems = segments.each_with_index.filter_map do |(a, b), index|
          short_segment(index, Planar.length(Planar.sub(b, a)))
        end
        return problems unless problems.empty?

        crossing_problems(segments, closed)
      end
      private_class_method :segment_problems

      def segments_of(points, closed)
        count = closed ? points.size : points.size - 1
        (0...count).map { |i| [points[i], points[(i + 1) % points.size]] }
      end
      private_class_method :segments_of

      def short_segment(source, length)
        limit = Core::Limits::ENSEMBLE_MIN_SEGMENT_M
        return nil if length >= limit - Core::Quant::EPSILON

        trace_error("/trace/segments/#{source}", 'segment_short', limit: limit, value: length.round(3))
      end
      private_class_method :short_segment

      def crossing_problems(segments, closed)
        count = segments.size
        pairs = (0...count).to_a.combination(2).select { |i, j| crossing_pair?(segments[i], segments[j], consecutive?(i, j, count, closed)) }
        pairs.map { |i, j| trace_error("/trace/segments/#{i}", 'self_intersection', other: j) }
      end
      private_class_method :crossing_problems

      def consecutive?(first, second, count, closed)
        second - first == 1 || (closed && first.zero? && second == count - 1)
      end
      private_class_method :consecutive?

      # Deux segments consécutifs se touchent par construction : seul un repli est une faute.
      def crossing_pair?(first, second, consecutive)
        return reversed?(first, second) if consecutive

        Planar.segment_distance(first[0], first[1], second[0], second[1]) < Core::Quant::EPSILON
      end
      private_class_method :crossing_pair?

      def reversed?(first, second)
        a = Planar.unit(Planar.sub(first[1], first[0]))
        b = Planar.unit(Planar.sub(second[1], second[0]))
        Planar.cross(a, b).abs < FOLD_LIMIT && Planar.dot(a, b).negative?
      end
      private_class_method :reversed?

      def closed_rows(points)
        count = points.size
        return ok_rows([TraceRow.new(id: 'ring', points: points, closed: true, sources: (0...count).to_a)]) if Planar.signed_area(points).positive?

        reversed = TraceRow.new(id: 'ring', points: points.reverse, closed: true, sources: (0...count).map { |i| (count - 2 - i) % count })
        ok_rows([reversed])
      end
      private_class_method :closed_rows

      def open_rows(points, layout)
        count = points.size - 1
        forward = TraceRow.new(id: 'left', points: points, closed: false, sources: (0...count).to_a)
        backward = TraceRow.new(id: 'right', points: points.reverse, closed: false, sources: (0...count).map { |i| count - 1 - i })
        case layout['side']
        when 'left' then ok_rows([forward])
        when 'right' then ok_rows([backward])
        else offset_rows([forward, backward], layout['street_width_m'] / 2.0)
        end
      end
      private_class_method :open_rows

      def ok_rows(rows)
        Core::Result.ok(rows)
      end
      private_class_method :ok_rows

      def offset_rows(rows, distance)
        problems = []
        moved = rows.map do |row|
          points = offset_points(row.points, distance)
          problems.concat(offset_problems(row, points))
          TraceRow.new(id: row.id, points: points, closed: false, sources: row.sources)
        end
        problems.empty? ? Core::Result.ok(moved) : Core::Result.fail(problems.uniq.sort_by(&:sort_key))
      end
      private_class_method :offset_rows

      # Décalage à gauche, en onglet : les deux façades restent à la distance voulue de l'axe.
      def offset_points(points, distance)
        normals = points.each_cons(2).map { |a, b| Planar.left(Planar.unit(Planar.sub(b, a))) }
        points.each_with_index.map do |point, index|
          before = normals[index - 1] if index.positive?
          after = normals[index]
          shift = if before && after
                    Planar.scale(Planar.add(before, after), distance / (1.0 + Planar.dot(before, after)))
                  else
                    Planar.scale(before || after, distance)
                  end
          Planar.add(point, shift)
        end
      end
      private_class_method :offset_points

      # Une façade décalée peut s'inverser dans un angle serré : le segment disparaît alors.
      def offset_problems(row, moved)
        (0...row.segment_count).filter_map do |index|
          vector = Planar.sub(moved[index + 1], moved[index])
          original = Planar.sub(row.points[index + 1], row.points[index])
          length = Planar.dot(vector, original).positive? ? Planar.length(vector) : 0.0
          short_segment(row.sources[index], length)
        end
      end
      private_class_method :offset_problems

      def trace_error(path, reason, **params)
        Core::Diagnostic.error('E_STREET_TRACE', path, reason: reason, **params)
      end
      private_class_method :trace_error
    end
  end
end
