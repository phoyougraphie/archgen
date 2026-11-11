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
        input = Tint.apply(config.geometry_input)
        dropped = row && input['features']['pilotis']
        input = Canonical.deep_freeze(input.merge('features' => input['features'].reject { |key, _| key == 'pilotis' })) if dropped
        result = generate_input(input, materials, row)
        return result unless dropped && result.ok?

        Result.ok(result.value, [Diagnostic.warning('W_DETAIL', '/features/pilotis', reason: 'pilotis_in_row')] + result.diagnostics)
      end

      def generate_input(input, materials, row)
        return winged(input, materials, row) if input['wing']

        setback = input.dig('levels', 'attic_setback_m').to_f
        return attic(input, materials, row, setback) if setback.positive?

        footprint = footprint_for(input, row)
        inner = row && footprint.trapezoid? ? Geometry::FootprintSolver.inner_problems(footprint, input['structure']['wall_m']) : []
        return Result.fail(inner) unless inner.empty?

        levels = Geometry::FloorPlanner.call(input['levels'], slab_m: input['structure']['slab_m'], ground_m: input.dig('shop', 'height_m'))
        facade = row ? input['facade'].merge('rear_bays' => row.fetch(:rear_bays)) : input['facade']
        candidates = Geometry::FacadeSolver.call(footprint, levels, facade, wall_m: input['structure']['wall_m'])
        return candidates unless candidates.ok?

        # AG-091 : sur pilotis, le rez-de-chaussée n'a ni mur ni baie. En rangée, les voisins s'appuient
        # sur lui : les pilotis sont omis et dits (AG-094).
        candidates = Result.ok(candidates.value.reject { |c| c.level_index.zero? }) if input['features']['pilotis']

        openings = Geometry::OpeningSolver.call(candidates.value, porch_input(input, row), footprint: footprint, levels: levels)
        return openings unless openings.ok?

        openings = with_porch(openings, input, footprint, levels, row)
        return openings unless openings.ok?

        openings = Result.ok(unblocked(openings.value, input['_blocked_rear'])) if input['_blocked_rear']

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

      # --- Attique en retrait (AG-135, ADR-63)

      ATTIC_MIN_DEPTH_M = 4.0

      # Le corps : tous les niveaux sauf le dernier, sous un toit plat qui devient la terrasse. L'attique :
      # le dernier niveau, reculé de `setback` depuis la façade avant, sous le toit du style, avec un
      # garde-corps au bord de la terrasse. Deux plans calculés à part, réunis sous une seule racine.
      def attic(input, materials, row, setback)
        levels = input['levels']
        count = levels['count']
        return Result.fail([attic_error('attic_single_level')]) if count < 2

        depth = input['footprint']['depth_m']
        return Result.fail([attic_error('attic_too_deep', limit: Quant.q(depth - ATTIC_MIN_DEPTH_M))]) if depth - setback < ATTIC_MIN_DEPTH_M

        heights = levels['heights_m'] || []
        body_levels = levels.reject { |k, _| k == 'attic_setback_m' }.merge('count' => count - 1, 'heights_m' => heights.first(count - 1))
        flat = input['roof'].reject { |k, _| k == 'ridge' }.merge('type' => 'flat', 'overhang_m' => 0.0, 'pitch_deg' => 0.0)
        body = generate_input(input.merge('levels' => body_levels, 'roof' => flat), materials, row)
        return body unless body.ok?

        footprint = footprint_for(input, row)
        x0 = Quant.q(footprint.left_x(setback))
        x1 = Quant.q(footprint.right_x(setback))
        top_depth = Quant.q(depth - setback)
        top_row = row && row.reject { |k, _| k == :porch }.merge(delta_left_m: Quant.q(footprint.left_x(depth) - x0), delta_right_m: Quant.q(x1 - footprint.right_x(depth)))
        top_input = input.reject { |k, _| %w[shop ground_floor].include?(k) }.merge(
          'levels' => { 'count' => 1, 'height_m' => heights[count - 1] || levels['height_m'], 'heights_m' => [] },
          'footprint' => input['footprint'].merge('width_m' => Quant.q(x1 - x0), 'depth_m' => top_depth),
          # Un attique plus étroit que le corps (parcelle d'angle) garde des travées de même largeur.
          'facade' => input['facade'].merge('entry_bay' => nil, 'front_bays' => [(input['facade']['front_bays'] * (x1 - x0) / input['footprint']['width_m']).floor, 1].max),
          'structure' => input['structure'].merge('ground_slab' => false),
          'features' => input['features'].reject { |k, _| %w[balcony pilotis shop_front].include?(k) }
        )
        top = generate_input(top_input, materials, top_row)
        return top unless top.ok?

        rails = {}
        rail_nodes = []
        if input['lod'] == 1
          ground = Geometry::FootprintSolver.call(width_m: Quant.q(x1 - x0), depth_m: top_depth)
          rail_nodes = Geometry::DetailSolver.terrace_rails(ground, setback, top_input, rails)
        end
        z0 = body.value['metrics']['roof_top_z_m']
        plan = stack(body.value, top.value, rail_nodes, rails, [x0, setback, z0])
        problems = PlanValidator.call(plan, materials: materials)
        return Result.fail(problems) unless problems.empty?

        Result.ok(Canonical.deep_freeze(plan), body.diagnostics + top.diagnostics)
      end
      private_class_method :attic

      def attic_error(reason, **params)
        Diagnostic.error('E_ROOF_GEOMETRY', '/levels/attic_setback_m', reason: reason, **params)
      end
      private_class_method :attic_error

      def stack(body, top, rail_nodes, rails, offset)
        moved = shifted(top['nodes'].first['children'] + rail_nodes, offset)
        root = body['nodes'].first
        nodes = [root.merge('children' => root['children'] + [Geometry::Node.group('attic', 'building', moved)])]
        definitions = body['definitions'].merge(top['definitions']).merge(rails)
        definition_faces = definitions.transform_values { |list| count_faces(list) }
        own = count_faces(nodes)
        openings = body['openings'] + top['openings'].map do |o|
          o.merge('id' => "attic/#{o['id']}", 'level_index' => o['level_index'] + body['openings'].map { |b| b['level_index'] }.max.to_i + 1,
                  'z_min_m' => Quant.q(o['z_min_m'] + offset[2]), 'z_max_m' => Quant.q(o['z_max_m'] + offset[2]))
        end
        metrics = body['metrics'].merge(
          'wall_top_z_m' => Quant.q(top['metrics']['wall_top_z_m'] + offset[2]), 'roof_top_z_m' => Quant.q(top['metrics']['roof_top_z_m'] + offset[2]),
          'opening_count' => openings.size,
          'unique_face_count' => own + definition_faces.values.sum,
          'expanded_face_count' => own + instance_definitions(nodes).sum { |id| definition_faces.fetch(id) },
          'wall_cell_count' => body['metrics']['wall_cell_count'] + top['metrics']['wall_cell_count'], 'detail_definition_count' => definitions.size
        )
        body.merge('nodes' => nodes, 'definitions' => definitions, 'openings' => openings, 'metrics' => metrics)
      end
      private_class_method :stack

      # Nœuds déplacés de `offset` (mètres), renommés « <prefix>/… » ; `turn` : demi-tour autour de Z
      # avant le déplacement (aile tournée vers le jardin). Maillages requantifiés.
      def shifted(nodes, offset, prefix: 'attic', turn: false)
        dx, dy, dz = offset
        s = turn ? -1.0 : 1.0
        nodes.map do |node|
          moved = node.merge('id' => "#{prefix}/#{node['id']}", 'children' => shifted(node['children'], offset, prefix: prefix, turn: turn))
          primitive = node['primitive']
          next moved unless primitive

          moved['primitive'] = if primitive['type'] == 'instance'
                                 m = primitive['matrix'].dup
                                 [0, 1, 4, 5, 8, 9, 12, 13].each { |i| m[i] = Quant.q(m[i] * s) } if turn
                                 m[12] = Quant.q(m[12] + dx)
                                 m[13] = Quant.q(m[13] + dy)
                                 m[14] = Quant.q(m[14] + dz)
                                 primitive.merge('matrix' => m.map { |c| c.zero? ? 0.0 : c })
                               else
                                 primitive.merge('vertices' => primitive['vertices'].map { |x, y, z| Quant.q3([(s * x) + dx, (s * y) + dy, z + dz]) })
                               end
          moved
        end
      end

      # --- Ailes (AG-138, ADR-66) : formes en L, en T et en U

      # Le corps tel qu'il serait seul, plus une ou deux ailes accolées à son mur arrière, tournées vers
      # le jardin (leur façade avant regarde l'arrière), faîtage perpendiculaire à celui du corps.
      def winged(input, materials, row)
        wing = input['wing']
        return Result.fail([wing_error('wing_in_row')]) if row

        width = input['footprint']['width_m']
        depth = input['footprint']['depth_m']
        positions = wing['position'] == 'both' ? %w[left right] : [wing['position']]
        ww = wing['width_m']
        if ww * positions.size > width + Quant::EPSILON
          return Result.fail([wing_error('wing_too_wide', limit: Quant.q(width / positions.size))])
        end

        levels = input['levels']
        count = wing['levels'] || levels['count']
        heights = levels['heights_m'] || []
        roof = input['roof']
        roof = roof.merge('ridge' => 'perpendicular') if roof['type'] == 'gable'
        wing_input = input.reject { |k, _| %w[wing shop ground_floor].include?(k) }.merge(
          'footprint' => { 'width_m' => ww, 'depth_m' => wing['depth_m'] },
          'levels' => { 'count' => count, 'height_m' => levels['height_m'], 'heights_m' => heights.first(count) },
          'facade' => input['facade'].merge('entry_bay' => nil, 'front_bays' => [(input['facade']['front_bays'] * ww / width).floor, 1].max),
          'roof' => roof,
          'features' => input['features'].reject { |k, _| %w[balcony balcony_wrap bow_window pilotis shop_front].include?(k) },
          # Le mur arrière de l'aile est contre le corps : aucune baie.
          '_blocked_rear' => [[-Float::INFINITY, Float::INFINITY, Float::INFINITY]]
        )
        built = generate_input(wing_input, materials, nil)
        return built unless built.ok?

        xs = positions.to_h do |pos|
          [pos, case pos
                when 'left' then 0.0
                when 'right' then width - ww
                else (width - ww) / 2.0
                end]
        end
        # AG-140 : le mur arrière du corps n'a pas de baie derrière une aile, jusqu'au faîte de son toit
        # (le toit de l'aile passait devant ces fenêtres). Abscisse de façade arrière : u = L − x.
        top = built.value['metrics']['roof_top_z_m']
        blocked = xs.values.map { |x| [width - x - ww, width - x, top] }
        main = generate_input(input.reject { |k, _| k == 'wing' }.merge('_blocked_rear' => blocked), materials, nil)
        return main unless main.ok?

        parts = positions.map { |pos| ["wing/#{pos}", built.value, [Quant.q(xs[pos] + ww), Quant.q(depth + wing['depth_m']), 0.0]] }
        plan = joined(main.value, parts)
        problems = PlanValidator.call(plan, materials: materials)
        return Result.fail(problems) unless problems.empty?

        Result.ok(Canonical.deep_freeze(plan), main.diagnostics + built.diagnostics)
      end
      private_class_method :winged

      # Baies de façade arrière retirées si elles touchent une bande [u0, u1] sous la cote z.
      def unblocked(openings, spans)
        openings.reject do |o|
          o.facade_id == 'rear' && spans.any? { |u0, u1, z| o.u_max_m > u0 - 0.3 && o.u_min_m < u1 + 0.3 && o.z_min_m < z }
        end
      end
      private_class_method :unblocked

      def wing_error(reason, **params)
        Diagnostic.error('E_ROOF_GEOMETRY', '/wing', reason: reason, **params)
      end
      private_class_method :wing_error

      def joined(main, parts)
        root = main['nodes'].first
        extra = parts.map { |prefix, plan, offset| Geometry::Node.group(prefix, 'building', shifted(plan['nodes'].first['children'], offset, prefix: prefix, turn: true)) }
        nodes = [root.merge('children' => root['children'] + extra)]
        definitions = parts.reduce(main['definitions']) { |acc, (_, plan, _)| acc.merge(plan['definitions']) }
        definition_faces = definitions.transform_values { |list| count_faces(list) }
        own = count_faces(nodes)
        openings = main['openings'] + parts.flat_map { |prefix, plan, _| plan['openings'].map { |o| o.merge('id' => "#{prefix}/#{o['id']}") } }
        metrics = main['metrics'].merge(
          'wall_top_z_m' => ([main] + parts.map { |p| p[1] }).map { |p| p['metrics']['wall_top_z_m'] }.max,
          'roof_top_z_m' => ([main] + parts.map { |p| p[1] }).map { |p| p['metrics']['roof_top_z_m'] }.max,
          'opening_count' => openings.size,
          'unique_face_count' => own + definition_faces.values.sum,
          'expanded_face_count' => own + instance_definitions(nodes).sum { |id| definition_faces.fetch(id) },
          'wall_cell_count' => main['metrics']['wall_cell_count'] + parts.sum { |p| p[1]['metrics']['wall_cell_count'] },
          'detail_definition_count' => definitions.size
        )
        main.merge('nodes' => nodes, 'definitions' => definitions, 'openings' => openings, 'metrics' => metrics)
      end
      private_class_method :joined
      private_class_method :shifted

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

        roof = roof_for(input, footprint, levels, row)
        return roof unless roof.ok?

        ridge = cross_ridge?(input, footprint, row) ? 'perpendicular' : 'parallel'

        details = Geometry::DetailSolver.call(footprint: footprint, levels: levels, openings: openings, config: input,
                                              roof_top_z_m: roof.value.top_z_m, row: !row.nil?, ridge: ridge)
        return details unless details.ok?

        plan = build_plan(footprint, levels, openings, grids.value, roof.value, details.value, input, row)
        problems = PlanValidator.call(plan, materials: materials)
        return Result.fail(problems) unless problems.empty?

        Result.ok(Canonical.deep_freeze(plan), ridge_warnings(input, footprint, row) + details.diagnostics)
      end
      private_class_method :assemble

      # AG-079 : faîtage perpendiculaire, sauf sur une parcelle d'angle, qui garde le parallèle et le dit.
      def cross_ridge?(input, footprint, row)
        input['roof']['ridge'] == 'perpendicular' && !(row && footprint.trapezoid?)
      end
      private_class_method :cross_ridge?

      def ridge_warnings(input, footprint, row)
        return [] unless input['roof']['ridge'] == 'perpendicular' && row && footprint.trapezoid?

        [Diagnostic.warning('W_DETAIL', '/roof/ridge', reason: 'ridge_corner')]
      end
      private_class_method :ridge_warnings

      def roof_for(input, footprint, levels, row)
        top = levels.last.top_z_m
        if cross_ridge?(input, footprint, row)
          return Geometry::RoofSolver.call(footprint, top, input['roof'], materials: input['materials'], side_overhang: row.nil?)
        end

        roof_solver = row && input['roof']['type'] != 'sawtooth' ? Geometry::RowRoofSolver : Geometry::RoofSolver
        roof_solver.call(footprint, top, input['roof'].reject { |key, _| key == 'ridge' }, materials: input['materials'])
      end
      private_class_method :roof_for

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
        walls.first['children'].concat(Geometry::WallBuilder.ground(footprint, openings, input))
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
