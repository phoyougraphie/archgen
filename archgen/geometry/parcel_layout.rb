# frozen_string_literal: true

module Archgen
  module Geometry
    # Des rangées aux parcelles (docs/ENSEMBLE_CONTRACT.md, Découpe en parcelles). Pur et
    # déterministe. Une parcelle est un trapèze à façade et arrière parallèles, donc convexe.
    module ParcelLayout
      NOISE = 1e-9
      DIRECTION_DIGITS = 12

      module_function

      def call(settings)
        rows = TraceRows.call(settings)
        return rows unless rows.ok?

        parcel = settings['parcel']
        plans = rows.value.map { |row| row_plan(row, parcel) }
        problems = plans.flat_map { |plan| plan[:problems] }
        return Core::Result.fail(problems.sort_by(&:sort_key)) unless problems.empty?

        count = plans.sum { |plan| plan[:cuts].sum { |cut| cut[:widths].size } }
        budget = budget_problem(count)
        return Core::Result.fail([budget]) if budget

        finish(rows.value, plans, parcel['depth_m'])
      end

      # La même parcelle, avancée le long de sa façade et élargie : ses onglets ne changent pas.
      def reshaped(source, shift_m:, width_m:)
        width = Core::Quant.q(width_m)
        left = source['delta_left_m']
        right = source['delta_right_m']
        depth = source['depth_m']
        tangent = source['tangent']
        origin = Planar.add(source['origin_m'], Planar.scale(tangent, shift_m))
        local = [[0.0, 0.0], [width, 0.0], [Core::Quant.q(width - right), depth], [left, depth]]
        source.merge(
          'width_m' => width,
          'rear_m' => Core::Quant.q(width - left - right),
          'origin_m' => Core::Quant.q3(origin),
          'local_ring_m' => local,
          'ring_m' => local.map { |x, y| Core::Quant.q3(to_model(origin, tangent, x, y)) }
        )
      end

      def budget_problem(count)
        limit = Core::Limits::ENSEMBLE_MAX_PARCELS
        return nil if count <= limit

        Core::Diagnostic.error('E_STREET_BUDGET', '/parcel/target_width_m', reason: 'parcel_count', limit: limit, value: count)
      end
      private_class_method :budget_problem

      def finish(rows, plans, depth)
        parcels = rows.zip(plans).flat_map { |row, plan| row_parcels(row, plan, depth) }
        problems = clearance_problems(parcels, rows)
        return Core::Result.fail(problems.sort_by(&:sort_key)) unless problems.empty?

        lengths = plans.map { |plan| plan[:cuts].sum { |cut| cut[:length] } }
        Core::Result.ok(Core::Canonical.deep_freeze(
                          'parcels' => parcels.map { |p| p.reject { |k, _| k.is_a?(Symbol) } },
                          'metrics' => {
                            'parcel_count' => parcels.size,
                            'row_count' => rows.size,
                            'facade_length_m' => Core::Quant.q(lengths.sum)
                          }
                        ))
      end
      private_class_method :finish

      # --- Une rangée

      def row_plan(row, parcel)
        deltas = vertex_deltas(row, parcel['depth_m'])
        cuts = (0...row.segment_count).map { |i| cut_segment(row, i, deltas, parcel['target_width_m']) }
        { cuts: cuts, problems: cuts.flat_map { |cut| cut[:problems] } }
      end
      private_class_method :row_plan

      # δ = D × tan(φ / 2) ; φ, positif vers le bâti, c'est-à-dire vers la gauche du parcours.
      def vertex_deltas(row, depth)
        count = row.points.size
        (0...count).map do |index|
          next 0.0 if !row.closed && (index.zero? || index == count - 1)

          before = Planar.sub(row.points[index], row.points[(index - 1) % count])
          after = Planar.sub(row.points[(index + 1) % count], row.points[index])
          depth * Math.tan(Math.atan2(Planar.cross(before, after), Planar.dot(before, after)) / 2.0)
        end
      end
      private_class_method :vertex_deltas

      def cut_segment(row, index, deltas, target)
        a, b = row.segment(index)
        length = Planar.length(Planar.sub(b, a))
        start_delta = deltas[index]
        end_delta = deltas[(index + 1) % row.points.size]
        widths = segment_widths(length, start_delta, end_delta, target)
        {
          index: index, source: row.sources[index], a: a, b: b, length: length, widths: widths,
          start_delta: start_delta, end_delta: end_delta,
          problems: corner_problems(row.sources[index], widths, start_delta, end_delta)
        }
      end
      private_class_method :cut_segment

      def segment_widths(length, start_delta, end_delta, target)
        minimum = Core::Limits::ENSEMBLE_REAR_MIN_M
        start_width = mitred?(start_delta) ? [target, start_delta + minimum].max : nil
        end_width = mitred?(end_delta) ? [target, end_delta + minimum].max : nil
        rest = length - start_width.to_f - end_width.to_f
        return [length] if rest < -NOISE

        middle = (rest / target).round
        return spread(rest, start_width, end_width, length) if middle.zero?

        [start_width, *Array.new(middle, rest / middle), end_width].compact
      end
      private_class_method :segment_widths

      def mitred?(delta)
        delta.abs > NOISE
      end
      private_class_method :mitred?

      # Le reste, trop court pour une parcelle, revient aux parcelles d'angle à parts égales.
      def spread(rest, start_width, end_width, length)
        corners = [start_width, end_width].compact
        return [length] if corners.empty?

        corners.map { |width| width + (rest / corners.size) }
      end
      private_class_method :spread

      def corner_problems(source, widths, start_delta, end_delta)
        minimum = Core::Limits::ENSEMBLE_REAR_MIN_M
        rears = rear_lengths(widths, start_delta, end_delta)
        return [] if rears.min >= minimum - Core::Quant::EPSILON

        [Core::Diagnostic.error('E_STREET_CORNER', "/trace/segments/#{source}", reason: 'rear_too_short',
                                                                          limit: minimum, value: rears.min.round(3), missing_m: (minimum - rears.min).round(3))]
      end
      private_class_method :corner_problems

      def rear_lengths(widths, start_delta, end_delta)
        last = widths.size - 1
        widths.each_with_index.map do |width, rank|
          width - (rank.zero? ? start_delta : 0.0) - (rank == last ? end_delta : 0.0)
        end
      end
      private_class_method :rear_lengths

      def row_parcels(row, plan, depth)
        sequence = 0
        plan[:cuts].flat_map do |cut|
          segment_parcels(row, cut, depth).tap do |parcels|
            parcels.each do |parcel|
              parcel[:sequence] = sequence
              sequence += 1
            end
          end
        end
      end
      private_class_method :row_parcels

      def segment_parcels(row, cut, depth)
        tangent = Planar.unit(Planar.sub(cut[:b], cut[:a]))
        cuts = boundaries(cut[:widths], cut[:length])
        last = cut[:widths].size - 1
        cut[:widths].each_index.map do |rank|
          parcel(
            row: row, cut: cut, rank: rank, tangent: tangent, depth: depth,
            from: cuts[rank], to: cuts[rank + 1],
            delta_left: rank.zero? ? cut[:start_delta] : 0.0,
            delta_right: rank == last ? cut[:end_delta] : 0.0
          )
        end
      end
      private_class_method :segment_parcels

      # Abscisses quantifiées une seule fois : deux voisines partagent exactement la même limite.
      def boundaries(widths, length)
        total = 0.0
        inner = widths[0...-1].map { |width| total += width }
        [0.0, *inner, length].map { |x| Core::Quant.q(x) }
      end
      private_class_method :boundaries

      def parcel(row:, cut:, rank:, tangent:, depth:, from:, to:, delta_left:, delta_right:)
        width = Core::Quant.q(to - from)
        left = Core::Quant.q(delta_left)
        right = Core::Quant.q(delta_right)
        origin = Planar.add(cut[:a], Planar.scale(tangent, from))
        local = [[0.0, 0.0], [width, 0.0], [Core::Quant.q(width - right), depth], [left, depth]]
        {
          'id' => "#{row.id}/#{cut[:source]}/#{rank}",
          'row' => row.id,
          'segment' => cut[:source],
          'rank' => rank,
          'corner' => mitred?(delta_left) || mitred?(delta_right),
          'width_m' => width,
          'depth_m' => depth,
          'rear_m' => Core::Quant.q(width - left - right),
          'delta_left_m' => left,
          'delta_right_m' => right,
          'origin_m' => Core::Quant.q3(origin),
          'tangent' => tangent.map { |c| c.round(DIRECTION_DIGITS) },
          'local_ring_m' => local,
          'ring_m' => local.map { |x, y| Core::Quant.q3(to_model(origin, tangent, x, y)) }
        }
      end
      private_class_method :parcel

      def to_model(origin, tangent, x, y)
        Planar.add(Planar.add(origin, Planar.scale(tangent, x)), Planar.scale(Planar.left(tangent), y))
      end
      private_class_method :to_model

      # --- L'ensemble

      def clearance_problems(parcels, rows)
        closed = rows.to_h { |row| [row.id, row.closed] }
        sizes = parcels.group_by { |p| p['row'] }.transform_values(&:size)
        segment_counts = rows.to_h { |row| [row.id, row.segment_count] }
        limit = Core::Limits::ENSEMBLE_CLEARANCE_M
        parcels.combination(2).filter_map do |first, second|
          next if neighbours?(first, second, closed, sizes)
          next unless boxes_within?(first, second, limit)

          clearance_problem(first, second, limit, contiguous?(first, second, closed, segment_counts))
        end
      end
      private_class_method :clearance_problems

      def neighbours?(first, second, closed, sizes)
        return false unless first['row'] == second['row']

        gap = (first[:sequence] - second[:sequence]).abs
        gap == 1 || (closed[first['row']] && gap == sizes[first['row']] - 1)
      end
      private_class_method :neighbours?

      # L'écart minimal vise une cour étroite ou un tracé replié : deux segments contigus se
      # rejoignent par construction à l'angle, où l'arrière minimal fait déjà foi.
      def contiguous?(first, second, closed, segment_counts)
        return false unless first['row'] == second['row']

        distance = (first['segment'] - second['segment']).abs
        distance <= 1 || (closed[first['row']] && distance == segment_counts[first['row']] - 1)
      end
      private_class_method :contiguous?

      def boxes_within?(first, second, limit)
        (0..1).all? do |axis|
          a = first['ring_m'].map { |p| p[axis] }
          b = second['ring_m'].map { |p| p[axis] }
          a.min <= b.max + limit && b.min <= a.max + limit
        end
      end
      private_class_method :boxes_within?

      def clearance_problem(first, second, limit, contiguous)
        distance = Planar.convex_distance(first['ring_m'], second['ring_m'])
        if distance < Core::Quant::EPSILON
          overlap_error(first, second, 'parcels_overlap', distance)
        elsif !contiguous && distance < limit - Core::Quant::EPSILON
          overlap_error(first, second, 'parcels_too_close', distance, limit: limit)
        end
      end
      private_class_method :clearance_problem

      def overlap_error(first, second, reason, distance, **params)
        Core::Diagnostic.error('E_STREET_OVERLAP', "/parcels/#{first['id']}", reason: reason, id: first['id'], other: second['id'], value: distance.round(3), **params)
      end
      private_class_method :overlap_error
    end
  end
end
