# frozen_string_literal: true

module Archgen
  module Core
    # Pipeline pur : configuration → faisabilité/compte estimé → plan → budget exact.
    # Le plan retourné est déjà validé, gelé et sans aucune donnée hôte.
    module GeometryEngine
      SCHEMA_VERSION = 1

      module_function

      # `row` : bâtiment de rangée d'un ensemble, voie à part. Sans lui, le plan d'un bâtiment
      # seul reste identique (docs/ENSEMBLE_CONTRACT.md).
      def generate(config, materials: nil, row: nil)
        input = config.geometry_input
        footprint = footprint_for(input, row)
        inner = row && footprint.trapezoid? ? Geometry::FootprintSolver.inner_problems(footprint, input['structure']['wall_m']) : []
        return Result.fail(inner) unless inner.empty?

        levels = Geometry::FloorPlanner.call(input['levels'], slab_m: input['structure']['slab_m'], ground_m: input.dig('shop', 'height_m'))
        facade = row ? input['facade'].merge('rear_bays' => row.fetch(:rear_bays)) : input['facade']
        candidates = Geometry::FacadeSolver.call(footprint, levels, facade, wall_m: input['structure']['wall_m'])
        return candidates unless candidates.ok?

        openings = Geometry::OpeningSolver.call(candidates.value, porch_input(input, row), footprint: footprint, levels: levels)
        return openings unless openings.ok?

        openings = with_porch(openings, input, footprint, levels, row)
        return openings unless openings.ok?

        assemble(input, footprint, levels, openings.value, materials, row)
      end

      # Le passage tient lieu d'entrée : la travée d'entrée redevient une fenêtre.
      def porch_input(input, row)
        return input unless row&.dig(:porch)

        input.merge('facade' => input['facade'].merge('entry_bay' => nil))
      end
      private_class_method :porch_input

      def with_porch(openings, input, footprint, levels, row)
        return openings unless row&.dig(:porch)

        Geometry::PorchSolver.call(openings.value, footprint: footprint, levels: levels, config: input, porch: row[:porch])
      end
      private_class_method :with_porch

      def footprint_for(input, row)
        width = input['footprint']['width_m']
        depth = input['footprint']['depth_m']
        left = row ? row.fetch(:delta_left_m, 0.0) : 0.0
        right = row ? row.fetch(:delta_right_m, 0.0) : 0.0
        return Geometry::FootprintSolver.call(width_m: width, depth_m: depth) if left.zero? && right.zero?

        Geometry::FootprintSolver.trapezoid(width_m: width, depth_m: depth, delta_left_m: left, delta_right_m: right)
      end
      private_class_method :footprint_for

      def plan_digest(plan)
        Canonical.digest(plan)
      end

      def serialize(plan)
        Canonical.dump(plan)
      end

      def assemble(input, footprint, levels, openings, materials, row)
        grids = Geometry::WallBuilder.grids(footprint, levels, openings, input)
        return grids unless grids.ok?

        estimate = estimate_budget(input, footprint, levels, openings, grids.value)
        return Result.fail(estimate) unless estimate.empty?

        roof_solver = row ? Geometry::RowRoofSolver : Geometry::RoofSolver
        roof = roof_solver.call(footprint, levels.last.top_z_m, input['roof'], materials: input['materials'])
        return roof unless roof.ok?

        details = Geometry::DetailSolver.call(footprint: footprint, levels: levels, openings: openings, config: input)
        return details unless details.ok?

        plan = build_plan(footprint, levels, openings, grids.value, roof.value, details.value, input, row)
        problems = PlanValidator.call(plan, materials: materials)
        return Result.fail(problems) unless problems.empty?

        Result.ok(Canonical.deep_freeze(plan), details.diagnostics)
      end
      private_class_method :assemble

      # Avant toute allocation de maillage : comptes réels de cellules et de faces minimales.
      def estimate_budget(input, footprint, levels, openings, grids)
        cells = grids.sum(&:cell_count)
        solid = grids.sum { |g| (0...g.rows).sum { |r| (0...g.columns).count { |c| g.solid?(c, r) } } }
        factor = input['mode'] == 'structural' ? 2 : 1
        Budget.check(
          'width_m' => footprint.width_m, 'depth_m' => footprint.depth_m, 'wall_top_z_m' => levels.last.top_z_m,
          'opening_count' => openings.size, 'wall_cell_count' => cells, 'unique_face_count' => solid * factor
        )
      end
      private_class_method :estimate_budget

      def build_plan(footprint, levels, openings, grids, roof, details, input, row)
        walls = Geometry::WallBuilder.call(footprint, levels, grids, input)
        walls.first['children'] << Geometry::PorchSolver.passage_node(footprint, row[:porch], input) if row&.dig(:porch)
        children = walls + roof.nodes
        children << Geometry::Node.group('details', 'details', details.nodes) unless details.nodes.empty?
        nodes = [Geometry::Node.group('building', 'building', children)]
        definition_faces = details.definitions.transform_values { |list| count_faces(list) }
        own = count_faces(nodes)
        instances = instance_definitions(nodes)
        {
          'schema_version' => SCHEMA_VERSION,
          'engine_version' => ENGINE_VERSION,
          'units' => 'm',
          'nodes' => nodes,
          'definitions' => details.definitions,
          'openings' => openings.map(&:to_h),
          'metrics' => {
            'width_m' => footprint.width_m, 'depth_m' => footprint.depth_m,
            'wall_top_z_m' => levels.last.top_z_m, 'roof_top_z_m' => roof.top_z_m,
            'opening_count' => openings.size,
            'unique_face_count' => own + definition_faces.values.sum,
            'expanded_face_count' => own + instances.sum { |id| definition_faces.fetch(id) },
            'wall_cell_count' => grids.sum(&:cell_count), 'detail_definition_count' => details.definitions.size
          }
        }
      end
      private_class_method :build_plan

      def count_faces(nodes)
        nodes.sum do |node|
          primitive = node['primitive']
          own = primitive && primitive['type'] != 'instance' ? primitive['faces'].size : 0
          own + count_faces(node['children'])
        end
      end
      private_class_method :count_faces

      def instance_definitions(nodes)
        nodes.flat_map do |node|
          own = node.dig('primitive', 'type') == 'instance' ? [node['primitive']['definition_id']] : []
          own + instance_definitions(node['children'])
        end
      end
      private_class_method :instance_definitions
    end
  end
end
