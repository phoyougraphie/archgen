# frozen_string_literal: true

module Archgen
  module Core
    # Plan d'une voie sans carrefour : réglages effectifs -> coupe -> axe -> rubans et éléments
    # (AG-039, AG-040) -> RoadPlan validé, avec son empreinte `road_digest`. Noyau pur, déterministe,
    # en mètres, repère de la racine.
    module RoadEngine
      LIMITS = {
        unique: Limits::ROAD_MAX_UNIQUE_FACES, items: Limits::ROAD_MAX_ITEMS, expanded: Limits::ROAD_MAX_EXPANDED_FACES,
        sleepers: Limits::ROAD_MAX_SLEEPERS
      }.freeze
      FAMILY_ORDER = %w[road_vegetation road_lighting road_furniture road_rails].freeze

      module_function

      # settings : réglages effectifs de RoadIntake ; bands, items : catalogues chargés.
      # survey : grille relevée du couloir (Geometry::RoadGround), exigée si les réglages ont `ground`.
      def call(settings, bands:, items:, limits: {}, survey: nil)
        limits = LIMITS.merge(limits)
        section = Geometry::RoadSection.call(settings['profile'], bands: bands, items: items)
        width = section['width_m']
        ax = Geometry::RoadRibbons.axis_x(width, settings['axis'])
        trace = settings['trace']
        axis = Geometry::RoadAxis.call(trace['points_m'], trace['radii_m'], left_m: ax, right_m: width - ax)
        return axis unless axis.ok?

        stations = axis.value
        line = Geometry::RoadRibbons.cross_line(section)
        ground = nil
        if settings['ground']
          ground = on_ground(settings, section, stations, line, ax, survey)
          return ground unless ground.ok?

          stations = ground.value[:stations]
        end
        water_line = water_line(section)
        estimate = Geometry::RoadRibbons.face_estimate(stations.size, line + water_line)
        return Result.fail([budget('road_faces', limits[:unique], estimate)]) if estimate > limits[:unique]

        count = item_estimate(stations, section, ax)
        return Result.fail([budget('road_items', limits[:items], count)]) if count > limits[:items]

        sleepers = Geometry::RoadItems.sleeper_estimate(stations, section, ax)
        return Result.fail([budget('road_sleepers', limits[:sleepers], sleepers)]) if sleepers > limits[:sleepers]

        locked = ground && ground.value[:locks].any?
        surface = if locked
                    lock_surface(ground.value, stations, line, ax, section)
                  else
                    Geometry::RoadRibbons.mesh(stations, line, width: width, axis: settings['axis'])
                  end
        placed = Geometry::RoadItems.call(stations, section, items: items, ax: ax, seed: settings['seed'])
        lift_instances(placed, stations) if ground
        plan = assemble(surface, placed, stations, section, line)
        if locked
          add_locks(plan, ground.value, stations, water_line, ax, section)
        else
          add_water(plan, stations, water_line, width, settings['axis']) unless water_line.empty?
        end
        add_earthwork(plan, ground.value) if ground
        plan['metrics']['water_drop_m'] = Quant.q(ground.value[:drop]) if ground && settings['water']
        if ground && ground.value[:canal]
          plan['metrics']['lock_count'] = ground.value[:locks].size
          plan['water'] = { 'locks' => ground.value[:locks].map { |l| { 's_m' => Quant.q(l.c0), 'length_m' => Quant.q(l.c1 - l.c0), 'drop_m' => Quant.q(l.drop) } } }
        end
        problems = budget_problems(plan['metrics'], limits) + RoadPlanValidator.call(plan)
        return Result.fail(problems) unless problems.empty?

        Result.ok(Canonical.deep_freeze(plan))
      end

      # Axes et points du relevé du couloir d'une voie à `ground`, avant tout relevé (repère du tracé).
      def ground_axes(settings, bands:, items:)
        section = Geometry::RoadSection.call(settings['profile'], bands: bands, items: items)
        width = section['width_m']
        ax = Geometry::RoadRibbons.axis_x(width, settings['axis'])
        trace = settings['trace']
        axis = Geometry::RoadAxis.call(trace['points_m'], trace['radii_m'], left_m: ax, right_m: width - ax)
        return axis unless axis.ok?

        g = Geometry::RoadGround
        axes = g.axes(length(axis.value), ax, width - ax, g.settings(settings['ground']))
        return axes unless axes.ok?

        Result.ok(axes.value.merge('points_m' => g.corridor_points(axis.value, axes.value)))
      end

      # Voie sur un terrain (AG-049, étape 1) : profil en long, stations à cote (repère de la racine,
      # z = 0 au premier point), contrôle des terrassements, talus.
      def on_ground(settings, section, stations, line, ax, survey)
        g = Geometry::RoadGround
        ground = g.settings(settings['ground'])
        width = section['width_m']
        length = length(stations)
        axes = g.axes(length, ax, width - ax, ground)
        return axes unless axes.ok?
        return Result.fail([Diagnostic.error('E_ROAD_GROUND', '/ground', reason: 'survey_missing')]) unless survey
        unless survey['s_m'] == axes.value['s_m'] && survey['u_m'] == axes.value['u_m']
          return Result.fail([Diagnostic.error('E_ROAD_GROUND', '/ground', reason: 'survey_axes')])
        end

        # Une rivière se règle sur le terrain sous son eau ; une voie, sous sa chaussée ; sinon toute l'emprise.
        lanes = section['bands'].select { |b| b['role'] == (settings['water'] ? 'water' : 'carriageway') }
        lanes = section['bands'] if lanes.empty?
        span = [lanes.map { |b| ax - b['x1_m'] }.min, lanes.map { |b| ax - b['x0_m'] }.max]
        samples = g.profile(survey, length, span, ground, section, water: settings['water'])
        return samples unless samples.ok?

        locks = []
        if settings.dig('water', 'mode') == 'canal'
          planned = Geometry::RoadLocks.plan(samples.value, settings['water'], stations, length)
          return planned unless planned.ok?

          locks = planned.value[:locks]
          samples = Result.ok(planned.value[:samples])
        end
        placed = g.stations(stations, samples.value)
        work = g.earthwork(survey, placed, line, ax)
        return work unless work.ok?

        z0 = placed.first[0].z
        slopes = g.slopes(survey, placed, line, ax, ground, z0)
        return slopes unless slopes.ok?

        relative = placed.map { |st, _| Geometry::RoadAxis::Station.new(point: st.point, normal: st.normal, vertex: st.vertex, z: Quant.q(st.z - z0)) }
        grades = samples.value.each_cons(2).map { |(s0, z0a), (s1, z1)| ((z1 - z0a) / (s1 - s0)).abs * 100 }
        drop = samples.value.first[1] - samples.value.last[1]
        Result.ok({ stations: relative, z0: z0, slopes: slopes.value, work: work.value, grade: grades.max || 0.0, drop: drop,
                    locks: locks, ss: placed.map(&:last), canal: settings.dig('water', 'mode') == 'canal' })
      end

      # Les objets posés par RoadItems sont à la cote de la coupe : on ajoute celle du profil à leur abscisse.
      def lift_instances(placed, stations)
        (placed[:instances] + placed[:sleepers]).each do |node|
          m = node['primitive']['matrix']
          m[14] = Quant.q(m[14] + z_under(stations, m[12], m[13]))
        end
      end

      # Cote du profil sous un point : projeté sur l'axe, interpolée entre les stations.
      def z_under(stations, x, y)
        best = nil
        stations.each_cons(2) do |a, b|
          d = [b.point[0] - a.point[0], b.point[1] - a.point[1]]
          len2 = (d[0] * d[0]) + (d[1] * d[1])
          t = len2.zero? ? 0.0 : [[(((x - a.point[0]) * d[0]) + ((y - a.point[1]) * d[1])) / len2, 0.0].max, 1.0].min
          px = a.point[0] + (d[0] * t)
          py = a.point[1] + (d[1] * t)
          dist = Math.hypot(x - px, y - py)
          best = [dist, a.z + ((b.z - a.z) * t)] if best.nil? || dist < best[0]
        end
        best ? best[1] : 0.0
      end

      # Surface de l'eau (EAU_CONTRACT, AG-051) : un ruban à la ligne d'eau, dans un groupe à part pour que
      # ses bords ne coupent pas les murs de quai dans SketchUp.
      def water_line(section)
        section.fetch('water', []).map { |w| [[w['x0_m'], w['z_m']], [w['x1_m'], w['z_m']], 'road/water_surface'] }
      end

      # Canal à écluses (AG-054) : lit et eau ramenés au niveau bas dans chaque chambre, murs de chute,
      # portes sous un groupe à part.
      def lock_surface(ground, stations, line, ax, section)
        l = Geometry::RoadLocks
        builder = Geometry::MeshBuilder.new('surface')
        beds = l.beds(section)
        z0 = ground[:z0]
        l.sweep(builder, stations, ground[:ss], line, ax, ground[:locks], z0, beds)
        l.chute_walls(builder, stations, ground[:ss], ax, ground[:locks], z0, beds)
        builder.to_primitive
      end

      def add_locks(plan, ground, stations, water_line, ax, section)
        l = Geometry::RoadLocks
        builder = Geometry::MeshBuilder.new('surface')
        l.sweep(builder, stations, ground[:ss], water_line, ax, ground[:locks], ground[:z0], [], all: true)
        water = builder.to_primitive
        gates = l.gates(stations, ground[:ss], ax, ground[:locks], ground[:z0], section)
        children = plan['nodes'][0]['children']
        children.insert(1, { 'id' => 'road/water', 'category' => 'road_surface', 'children' => [], 'primitive' => water })
        children << { 'id' => 'road/locks', 'category' => 'road_furniture', 'children' => gates }
        count = water['faces'].size + gates.sum { |g| g['primitive']['faces'].size }
        m = plan['metrics']
        m['unique_face_count'] += count
        m['expanded_face_count'] += count
        m['water_face_count'] = water['faces'].size
        m['linear_face_count'] += count - water['faces'].size
      end

      def add_water(plan, stations, line, width, axis)
        primitive = Geometry::RoadRibbons.mesh(stations, line, width: width, axis: axis)
        plan['nodes'][0]['children'].insert(1, { 'id' => 'road/water', 'category' => 'road_surface', 'children' => [], 'primitive' => primitive })
        count = primitive['faces'].size
        m = plan['metrics']
        m['unique_face_count'] += count
        m['expanded_face_count'] += count
        m['water_face_count'] = count
      end

      def add_earthwork(plan, ground)
        builder = Geometry::MeshBuilder.new('surface')
        ground[:slopes][:faces].each { |f| builder.add_face(f, 'road/bank') }
        primitive = builder.to_primitive
        root = plan['nodes'][0]
        root['children'].insert(1, { 'id' => 'road/earthwork', 'category' => 'road_surface', 'children' => [], 'primitive' => primitive })
        count = primitive['faces'].size
        m = plan['metrics']
        m['unique_face_count'] += count
        m['expanded_face_count'] += count
        m.merge!('earthwork_face_count' => count, 'earthwork_reach_m' => Quant.q(ground[:slopes][:reach]),
                 'grade_max_percent' => Quant.q(ground[:grade]), 'cut_max_m' => Quant.q(ground[:work][:cut]),
                 'fill_max_m' => Quant.q(ground[:work][:fill]), 'origin_z_m' => Quant.q(ground[:z0]))
        plan['ground'] = { 'outline_m' => ground[:slopes][:outline].map { |p| p.map { |c| Quant.q(c) } } }
      end

      def budget(reason, limit, value)
        Diagnostic.error('E_ROAD_BUDGET', '/trace', reason: reason, limit: limit, value: value)
      end

      # Objets répétés et poteaux à prévoir, avant de les poser.
      def item_estimate(stations, section, ax)
        section['items'].sum do |item|
          length = Geometry::RoadItems.polyline_length(Geometry::RoadItems.offset_line(stations, ax - item['x_m']))
          if item['repeat'] == 'spaced'
            Geometry::RoadSection.count_over(item['spacing_m'], length)
          else
            post = Geometry::RoadItems.linear_spec(item['kind'], item['variant'], item['height_m'])[:post]
            post ? (length / post[2]).floor + 2 : 0
          end
        end
      end

      def budget_problems(metrics, limits)
        out = []
        out << budget('road_faces', limits[:unique], metrics['unique_face_count']) if metrics['unique_face_count'] > limits[:unique]
        objects = metrics['item_count'] - metrics['sleeper_count']
        out << budget('road_items', limits[:items], objects) if objects > limits[:items]
        out << budget('road_sleepers', limits[:sleepers], metrics['sleeper_count']) if metrics['sleeper_count'] > limits[:sleepers]
        out << budget('road_expanded_faces', limits[:expanded], metrics['expanded_face_count']) if metrics['expanded_face_count'] > limits[:expanded]
        out
      end

      def assemble(surface, placed, stations, section, line)
        # Un groupe par famille, chacun sous sa balise : on masque la végétation ou les rails d'un clic.
        children = [{ 'id' => 'road/surface', 'category' => 'road_surface', 'children' => [], 'primitive' => surface }]
        grouped = (placed[:linear] + placed[:instances] + placed[:sleepers]).group_by { |node| Geometry::RoadItems.family(node) }
        FAMILY_ORDER.each do |family|
          nodes = grouped[family]
          children << { 'id' => "road/#{family.delete_prefix('road_')}", 'category' => family, 'children' => nodes } if nodes
        end
        definitions = placed[:definitions].sort.to_h
        definition_faces = definitions.transform_values { |nodes| nodes.sum { |n| n['primitive']['faces'].size } }
        linear_faces = placed[:linear].sum { |n| n['primitive']['faces'].size }
        all_instances = placed[:instances] + placed[:sleepers]
        instanced = all_instances.sum { |n| definition_faces.fetch(n['primitive']['definition_id']) }
        {
          'schema_version' => 1, 'engine_version' => ROAD_ENGINE_VERSION, 'units' => 'm',
          'nodes' => [{ 'id' => 'road', 'category' => 'road', 'children' => children }],
          'definitions' => definitions,
          'metrics' => {
            'surface_face_count' => surface['faces'].size, 'vertex_count' => surface['vertices'].size,
            'station_count' => stations.size, 'cross_segment_count' => line.size,
            'width_m' => section['width_m'], 'length_m' => Quant.q(length(stations)),
            'linear_face_count' => linear_faces, 'definition_count' => definitions.size,
            'item_count' => all_instances.size, 'sleeper_count' => placed[:sleepers].size,
            'rail_count' => placed[:linear].count { |n| n['id'].start_with?('rail/') },
            'unique_face_count' => surface['faces'].size + linear_faces + definition_faces.values.sum,
            'expanded_face_count' => surface['faces'].size + linear_faces + instanced
          }
        }
      end

      def length(stations)
        stations.each_cons(2).sum { |a, b| Math.hypot(b.point[0] - a.point[0], b.point[1] - a.point[1]) }
      end

      def digest(plan)
        Canonical.digest(plan)
      end
    end

    # Mêmes refus de maillage que le plan du bâtiment, sur la structure du plan de voie : surface,
    # éléments continus (solides fermés), instances de définitions partagées.
    class RoadPlanValidator < PlanValidator
      CATEGORIES = %w[road road_surface road_vegetation road_lighting road_furniture road_rails linear item part].freeze

      def call
        return @out unless header_ok?

        @plan['nodes'].each { |node| check_node(node, allow_instance: true) }
        @plan['definitions'].each do |id, nodes|
          @ids = {}
          problem(id, 'empty_definition') if nodes.empty?
          nodes.each { |node| check_node(node, allow_instance: false) }
        end
        check_metrics
        @out.sort_by(&:sort_key)
      end

      private

      def categories
        CATEGORIES
      end

      def header_ok?
        problem('plan', 'bad_header') unless @plan['schema_version'] == 1 && @plan['units'] == 'm'
        %w[nodes definitions metrics].each { |key| problem('plan', "missing_#{key}") unless @plan.key?(key) }
        return false unless @out.empty?

        tops = @plan['nodes']
        problem('plan', 'single_road_root') unless tops.size == 1 && tops.first['category'] == 'road'
        @out.empty?
      end

      def check_metrics
        own = @plan['nodes'].sum { |node| node_faces(node) }
        definition_faces = @plan['definitions'].transform_values { |nodes| nodes.sum { |n| node_faces(n) } }
        instances = []
        @plan['nodes'].each { |node| collect_instances(node, instances) }
        counted = {
          'unique_face_count' => own + definition_faces.values.sum,
          'item_count' => instances.size,
          'expanded_face_count' => own + instances.sum { |id| definition_faces.fetch(id, 0) }
        }
        counted.each do |key, value|
          declared = @plan['metrics'][key]
          problem('metrics', 'metric_mismatch', metric: key, declared: declared, counted: value) unless declared == value
        end
      end
    end
  end
end
