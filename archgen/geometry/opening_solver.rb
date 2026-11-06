# frozen_string_literal: true

module Archgen
  module Geometry
    # Percements et dégagements. Aucun réajustement implicite : une position
    # impossible est refusée avec un diagnostic localisé.
    module OpeningSolver
      EPS = Core::Quant::EPSILON
      CLEARANCE = Core::Quant::CLEARANCE_M

      module_function

      def call(candidates, config, footprint:, levels:)
        openings = candidates.map { |c| build(c, config, levels) }
        problems = openings.flat_map { |o| check_extents(o, config, footprint, levels) }
        problems.concat(check_pairs(openings, config))
        return Core::Result.fail(problems.sort_by(&:sort_key)) unless problems.empty?

        Core::Result.ok(sort(openings))
      end

      def sort(openings)
        openings.sort_by { |o| [FACADE_ORDER.index(o.facade_id), o.level_index, o.bay_index, o.id] }
      end

      def build(candidate, config, levels)
        facade = config['facade']
        door = candidate.facade_id == 'front' && candidate.level_index.zero? && candidate.bay_index == facade['entry_bay']
        base = levels[candidate.level_index].base_z_m
        center = door ? candidate.center_u_m : candidate.center_u_m + jitter(candidate, config)
        width = door ? facade['door_width_m'] : facade['window_width_m']
        z_min = door ? 0.0 : base + facade['sill_m']
        height = door ? facade['door_height_m'] : facade['window_height_m']
        Opening.new(
          id: "opening/#{candidate.facade_id}/#{candidate.level_index}/#{candidate.bay_index}",
          facade_id: candidate.facade_id, level_index: candidate.level_index, bay_index: candidate.bay_index,
          kind: door ? 'door' : 'window',
          u_min_m: Core::Quant.q(center - (width / 2.0)), u_max_m: Core::Quant.q(center + (width / 2.0)),
          z_min_m: Core::Quant.q(z_min), z_max_m: Core::Quant.q(z_min + height)
        )
      end
      private_class_method :build

      def jitter(candidate, config)
        amount = config['facade']['jitter_m']
        return 0.0 if amount.zero?

        key = Core::DeterministicRandom.opening_key(candidate.facade_id, candidate.level_index, candidate.bay_index)
        amount * ((2.0 * Core::DeterministicRandom.unit(config['seed'], key)) - 1.0)
      end
      private_class_method :jitter

      def width_path(opening)
        opening.kind == 'door' ? '/facade/door_width_m' : '/facade/window_width_m'
      end
      private_class_method :width_path

      def height_path(opening)
        opening.kind == 'door' ? '/facade/door_height_m' : '/facade/window_height_m'
      end
      private_class_method :height_path

      def check_extents(opening, config, footprint, levels)
        problems = []
        facade = footprint.facade(opening.facade_id)
        wall = config['structure']['wall_m']
        start_clearance = [wall, facade.inner_start(wall)].max + CLEARANCE
        end_clearance = [wall, facade.length_m - facade.inner_end(wall)].max + CLEARANCE
        if opening.u_min_m < start_clearance - EPS || facade.length_m - opening.u_max_m < end_clearance - EPS
          problems << clearance(width_path(opening), 'facade_end', opening, limit: [start_clearance, end_clearance].max)
        end
        limit = top_limit(opening, config, levels)
        problems << clearance(height_path(opening), 'level_top', opening, limit: limit) if opening.z_max_m > limit + EPS
        problems
      end
      private_class_method :check_extents

      def top_limit(opening, config, levels)
        level = levels[opening.level_index]
        last = opening.level_index == levels.size - 1
        last ? level.top_z_m - CLEARANCE : level.top_z_m - config['structure']['slab_m'] - CLEARANCE
      end
      private_class_method :top_limit

      def check_pairs(openings, config)
        openings.group_by(&:facade_id).values.flat_map do |group|
          group.combination(2).filter_map { |a, b| pair_problem(a, b, config) }
        end
      end
      private_class_method :check_pairs

      # Si les projections fermées se recouvrent sur un axe, dégagement sur l'autre.
      def pair_problem(a, b, config)
        gap_u = [a.u_min_m - b.u_max_m, b.u_min_m - a.u_max_m].max
        gap_z = [a.z_min_m - b.z_max_m, b.z_min_m - a.z_max_m].max
        overlap_u = gap_u <= EPS
        overlap_z = gap_z <= EPS
        return nil unless overlap_u || overlap_z
        return nil if overlap_z && !overlap_u && gap_u >= CLEARANCE - EPS
        return nil if overlap_u && !overlap_z && gap_z >= CLEARANCE - EPS

        path = overlap_z ? pair_width_path(a, b, config) : height_path(b)
        clearance(path, 'opening_spacing', b, other: a.id)
      end
      private_class_method :pair_problem

      def pair_width_path(a, b, config)
        return '/facade/jitter_m' if config['facade']['jitter_m'].positive? && a.kind == 'window' && b.kind == 'window'

        width_path(b.kind == 'door' ? b : a)
      end
      private_class_method :pair_width_path

      def clearance(path, reason, opening, **params)
        Core::Diagnostic.error('E_OPENING_CLEARANCE', path, reason: reason, id: opening.id, **params)
      end
      private_class_method :clearance
    end
  end
end
