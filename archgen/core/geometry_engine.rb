# frozen_string_literal: true

module Archgen
  module Core
    # Pipeline pur : configuration → faisabilité/compte estimé → plan → budget exact.
    # Le plan retourné est déjà validé, gelé et sans aucune donnée hôte.
    module GeometryEngine
      SCHEMA_VERSION = 1

      module_function

      def generate(config, materials: nil)
        input = config.geometry_input
        if input['lod'] != 0
          return Result.fail([Diagnostic.error('E_PROFILE_UNAVAILABLE', '/lod', reason: 'lod_not_implemented', lod: input['lod'])])
        end

        footprint = Geometry::FootprintSolver.call(width_m: input['footprint']['width_m'], depth_m: input['footprint']['depth_m'])
        levels = Geometry::FloorPlanner.call(input['levels'], slab_m: input['structure']['slab_m'])
        candidates = Geometry::FacadeSolver.call(footprint, levels, input['facade'])
        return candidates unless candidates.ok?

        openings = Geometry::OpeningSolver.call(candidates.value, input, footprint: footprint, levels: levels)
        return openings unless openings.ok?

        assemble(input, footprint, levels, openings.value, materials)
      end

      def plan_digest(plan)
        Canonical.digest(plan)
      end

      def serialize(plan)
        Canonical.dump(plan)
      end

      def assemble(input, footprint, levels, openings, materials)
        grids = Geometry::WallBuilder.grids(footprint, levels, openings, input)
        return grids unless grids.ok?

        estimate = estimate_budget(input, footprint, levels, openings, grids.value)
        return Result.fail(estimate) unless estimate.empty?

        roof = Geometry::RoofSolver.call(footprint, levels.last.top_z_m, input['roof'], materials: input['materials'])
        return roof unless roof.ok?

        plan = build_plan(footprint, levels, openings, grids.value, roof.value, input)
        problems = PlanValidator.call(plan, materials: materials)
        return Result.fail(problems) unless problems.empty?

        Result.ok(Canonical.deep_freeze(plan))
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

      def build_plan(footprint, levels, openings, grids, roof, input)
        children = Geometry::WallBuilder.call(footprint, levels, grids, input) + roof.nodes
        nodes = [Geometry::Node.group('building', 'building', children)]
        faces = count_faces(nodes)
        {
          'schema_version' => SCHEMA_VERSION,
          'engine_version' => ENGINE_VERSION,
          'units' => 'm',
          'nodes' => nodes,
          'definitions' => {},
          'openings' => openings.map(&:to_h),
          'metrics' => {
            'width_m' => footprint.width_m, 'depth_m' => footprint.depth_m,
            'wall_top_z_m' => levels.last.top_z_m, 'roof_top_z_m' => roof.top_z_m,
            'opening_count' => openings.size, 'unique_face_count' => faces, 'expanded_face_count' => faces,
            'wall_cell_count' => grids.sum(&:cell_count), 'detail_definition_count' => 0
          }
        }
      end
      private_class_method :build_plan

      def count_faces(nodes)
        nodes.sum do |node|
          own = node['primitive'] ? node['primitive']['faces'].size : 0
          own + count_faces(node['children'])
        end
      end
      private_class_method :count_faces
    end
  end
end
