# frozen_string_literal: true

module Archgen
  module Core
    # Plan d'un réseau de voies (ADR-36) : chaque voie suit son axe ; là où deux voies se croisent,
    # où l'une finit sur l'autre ou où deux bouts se rejoignent, un carrefour simple naît tout seul.
    # Les tronçons entre carrefours et les carrefours partagent un seul maillage de surface.
    # Noyau pur, déterministe, en mètres, repère du réseau (premier point de la première voie).
    module RoadNetworkEngine
      N = Geometry::RoadNetwork

      module_function

      # settings : réglages effectifs de RoadNetworkIntake ; bands, items : catalogues chargés.
      def call(settings, bands:, items:, limits: {})
        limits = RoadEngine::LIMITS.merge(limits)
        roads = []
        problems = []
        settings['roads'].each_with_index do |entry, i|
          road = road(entry, i, bands, items)
          road.ok? ? roads << road.value : problems.concat(road.errors)
        end
        return Result.fail(problems) unless problems.empty?

        nodes = N.detect(roads)
        problems = radius_problems(nodes, settings['junctions'], roads)
        problems += pair_problems(nodes, settings['junctions']) if problems.empty?
        return Result.fail(problems) unless problems.empty?

        built = nodes.map { |node| N.build(node, roads) }
        problems = built.flat_map(&:errors)
        return Result.fail(problems.sort_by(&:sort_key)) unless problems.empty?

        problems = link_problems(nodes)
        return Result.fail(problems) unless problems.empty?

        pieces = roads.map { |road| N.pieces(road, nodes) }
        problems = pieces.flat_map(&:errors).uniq
        return Result.fail(problems.sort_by(&:sort_key)) unless problems.empty?

        build_plan(roads, nodes, built.map { |b| b.value[:faces] }, pieces.map(&:value), items, limits, built.flat_map { |b| b.value[:instances] },
                   built.flat_map { |b| b.value[:solids] || [] })
      end

      def road(entry, index, bands, items)
        settings = entry['road']
        section = Geometry::RoadSection.call(settings['profile'], bands: bands, items: items)
        width = section['width_m']
        ax = Geometry::RoadRibbons.axis_x(width, settings['axis'])
        trace = settings['trace']
        axis = Geometry::RoadAxis.call(trace['points_m'], trace['radii_m'], left_m: ax, right_m: width - ax)
        return Result.fail(axis.errors.map { |d| repath(d, "/roads/#{index}/road") }) unless axis.ok?

        Result.ok(N.road(index, entry['id'], settings, entry['origin_m'], axis.value, section))
      end

      def repath(diagnostic, base)
        Diagnostic.error(diagnostic.code, "#{base}#{diagnostic.path}", **diagnostic.params.transform_keys(&:to_sym))
      end

      # Rayon des bordures de chaque carrefour ; un réglage qui ne vise aucun carrefour est refusé.
      def radius_problems(nodes, junctions, roads)
        by_id = junctions.to_h { |j| [j['id'], j] }
        nodes.each do |node|
          node.radius = by_id[node.id]&.fetch('corner_radius_m') || N::DEFAULT_RADIUS_M
          node.type = by_id[node.id]&.fetch('type') || 'simple'
          node.options = by_id[node.id] || {}
          # Sur l'eau, le nœud est un pont : « simple », la valeur par défaut, y devient « bridge » ; tout autre
          # type choisi est refusé à la construction (water_crossing).
          node.type = 'bridge' if node.type == 'simple' && node.hits.any? { |r, _| Geometry::RoadBridge.wet?(roads[r]) }
        end
        known = nodes.map(&:id)
        unknown = junctions.each_with_index.reject { |j, _| known.include?(j['id']) }.map do |j, _|
          Diagnostic.error('E_ROAD_JUNCTION', "/junctions/#{j['id']}", reason: 'unknown_junction')
        end
        unknown + nodes.filter_map do |node|
          next if node.type == 'bridge' || (node.options.keys & Geometry::RoadBridge::SETTINGS).empty?

          Diagnostic.error('E_ROAD_JUNCTION', "/junctions/#{node.id}", reason: 'bridge_setting_unavailable', type: node.type)
        end
      end

      def build_plan(roads, nodes, junction_faces, pieces, items, limits, lights, bridges = [])
        estimate = roads.each_with_index.sum do |road, i|
          pieces[i].sum { |from, to| Geometry::RoadRibbons.face_estimate(N.piece_stations(road, from, to).size, road.line) }
        end + junction_faces.sum(&:size)
        return Result.fail([RoadEngine.budget('road_faces', limits[:unique], estimate)]) if estimate > limits[:unique]

        builder = Geometry::MeshBuilder.new('surface')
        placed = { definitions: {}, instances: [], linear: [], sleepers: [] }
        water = Geometry::MeshBuilder.new('surface')
        station_count = 0
        roads.each_with_index do |road, i|
          profile = Geometry::RoadCrossing.profile(road, nodes)
          gaps = Geometry::RoadCrossing.gaps(road, nodes)
          water_line = RoadEngine.water_line(road.section)
          pieces[i].each_with_index do |(from, to), k|
            stations = N.piece_stations(road, from, to)
            stations = Geometry::RoadCrossing.lift(stations, from, to, profile) if profile
            station_count += stations.size
            Geometry::RoadRibbons.sweep(builder, stations, road.line, road.ax)
            Geometry::RoadRibbons.sweep(water, stations, water_line, road.ax) unless water_line.empty?
            tag = "#{road.id}.#{k + 1}"
            if gaps.empty?
              piece_items = Geometry::RoadItems.call(stations, road.section, items: items, ax: road.ax, seed: road.settings['seed'])
              RoadEngine.lift_instances(piece_items, stations) if profile
              merge_items(placed, piece_items, tag)
            else
              crossing_items(placed, road, from, to, gaps, items, tag, profile)
            end
          end
        end
        unless lights.empty?
          id, shape = Geometry::RoadSignals.definition
          placed[:definitions][id] ||= shape if lights.any? { |l| l['primitive']['definition_id'] == id }
          Geometry::RoadCrossing.definitions.each { |cid, cshape| placed[:definitions][cid] ||= cshape if lights.any? { |l| l['primitive']['definition_id'] == cid } }
          placed[:instances].concat(lights)
        end
        from = builder.to_primitive['faces'].size
        junction_faces.each { |faces| faces.each { |points, material| builder.add_face(points, material) } }
        surface = N.heal(builder.to_primitive, from)
        return Result.fail([Diagnostic.error('E_ROAD_JUNCTION', '/junctions', reason: 'junction_shape')]) unless surface

        plan = RoadEngine.assemble(surface, placed, [], { 'width_m' => roads.map(&:width).max }, [])
        add_extras(plan, water.to_primitive, bridges)
        plan['metrics'].merge!(
          'station_count' => station_count, 'cross_segment_count' => roads.sum { |r| r.line.size },
          'length_m' => Quant.q(roads.sum(&:length)), 'road_count' => roads.size,
          'junction_count' => nodes.size, 'piece_count' => pieces.sum(&:size),
          'junction_face_count' => junction_faces.sum(&:size), 'signal_count' => lights.size,
          'crossing_count' => nodes.count { |n| n.type == 'level_crossing' }
        )
        plan['metrics']['bridge_count'] = nodes.count(&:bridge) if nodes.any?(&:bridge)
        plan['junctions'] = nodes.map do |n|
          {
            'id' => n.id, 'type' => n.type, 'point_m' => n.point.map { |c| Quant.q(c) }, 'arms' => n.arms.size, 'corner_radius_m' => n.radius,
            'cuts_m' => n.arms.map { |a| Quant.q(a.cut) }, 'reach_m' => n.arms.map { |a| Quant.q(a.reach) },
            'outer_radius_m' => roundabout_value(n, 'outer_radius_m', Geometry::RoadRoundabout::DEFAULT_OUTER_M),
            'ring_width_m' => roundabout_value(n, 'ring_width_m', Geometry::RoadRoundabout::DEFAULT_RING_M),
            'deck_m' => n.crossing && Quant.q(n.crossing.height), 'ramp_m' => n.crossing && Quant.q(n.crossing.ramp),
            'pair' => n.type == 'double_roundabout' ? n.options['pair'] : nil,
            'link_m' => link_length(n, nodes)
          }.merge(bridge_entry(n)).compact
        end
        problems = RoadEngine.budget_problems(plan['metrics'], limits) + RoadPlanValidator.call(plan)
        return Result.fail(problems) unless problems.empty?

        Result.ok(Canonical.deep_freeze(plan))
      end

      MIN_LINK_M = 5.0

      # Surface de l'eau (cours d'eau du réseau) et ouvrages des ponts, dans leurs groupes.
      def add_extras(plan, water, bridges)
        children = plan['nodes'][0]['children']
        m = plan['metrics']
        unless water['faces'].empty?
          children.insert(1, { 'id' => 'road/water', 'category' => 'road_surface', 'children' => [], 'primitive' => water })
          m['water_face_count'] = water['faces'].size
        end
        unless bridges.empty?
          children << { 'id' => 'road/bridges', 'category' => 'road_surface', 'children' => bridges }
          m['linear_face_count'] += bridges.sum { |b| b['primitive']['faces'].size }
        end
        count = water['faces'].size + bridges.sum { |b| b['primitive']['faces'].size }
        m['unique_face_count'] += count
        m['expanded_face_count'] += count
      end

      def bridge_entry(node)
        return {} unless node.bridge

        b = node.bridge
        { 'bridge_kind' => b[:kind], 'over' => node.crossing.road.id, 'span_m' => Quant.q(b[:span]), 'clearance_m' => Quant.q(b[:clearance]) }
      end

      # Double giratoire (ADR-37) : deux nœuds voisins sur une même voie, réglés par le premier ; le second
      # prend ses réglages et le bout de voie entre eux devient la liaison.
      def pair_problems(nodes, junctions)
        set = junctions.map { |j| j['id'] }
        paired = {}
        nodes.select { |n| n.type == 'double_roundabout' }.filter_map do |node|
          next error(node, 'pair_missing') unless node.options['pair']

          other = nodes.find { |n| n.id == node.options['pair'] }
          next error(node, 'unknown_pair', pair: node.options['pair'].to_s) if other.nil? || other.equal?(node)
          next error(node, 'pair_already_set', pair: other.id) if set.include?(other.id) || paired[other.id] || paired[node.id]

          road, sa, sb = shared(node, other, nodes)
          next error(node, 'not_neighbours', pair: other.id) unless road

          paired[node.id] = paired[other.id] = true
          other.type = 'double_roundabout'
          other.radius = node.radius
          other.options = node.options.merge('id' => other.id, 'pair' => node.id, 'link' => [road, sa])
          node.options = node.options.merge('link' => [road, sb])
          nil
        end
      end

      def error(node, reason, **params)
        Diagnostic.error('E_ROAD_JUNCTION', "/junctions/#{node.id}", reason: reason, **params)
      end

      # Voie commune aux deux nœuds sans autre nœud entre eux : [index, abscisse du premier, du second].
      def shared(a, b, nodes)
        a.hits.each do |ra, sa|
          b.hits.each do |rb, sb|
            next unless ra == rb && (sa - sb).abs > 1e-6

            lo, hi = [sa, sb].minmax
            between = nodes.any? { |n| !n.equal?(a) && !n.equal?(b) && n.hits.any? { |r, s| r == ra && s > lo && s < hi } }
            return [ra, sa, sb] unless between
          end
        end
        nil
      end

      # Liaison : ce qui reste de la voie entre les deux anneaux, 5 m au moins.
      def link_problems(nodes)
        nodes.select { |n| n.type == 'double_roundabout' && n.options['pair'] && n.id < n.options['pair'] }.filter_map do |node|
          other = nodes.find { |n| n.id == node.options['pair'] }
          mine = node.arms.find(&:link)
          theirs = other.arms.find(&:link)
          gap = (mine.s - theirs.s).abs - mine.cut - theirs.cut
          next if gap >= MIN_LINK_M - 1e-9

          error(node, 'link_too_short', pair: other.id, value: Quant.q(gap), limit: MIN_LINK_M)
        end
      end

      def link_length(node, nodes)
        return nil unless node.type == 'double_roundabout'

        other = nodes.find { |n| n.id == node.options['pair'] }
        mine = node.arms.find(&:link)
        theirs = other.arms.find(&:link)
        Quant.q((mine.s - theirs.s).abs - mine.cut - theirs.cut)
      end

      def roundabout_value(node, key, default)
        %w[roundabout double_roundabout].include?(node.type) ? node.options.fetch(key, default) : nil
      end

      # Voie ferrée d'un passage à niveau : rails et traverses continus ; les autres objets s'interrompent
      # sur l'emprise de la route (intervalles `gaps`).
      def crossing_items(placed, road, from, to, gaps, items, tag, profile = nil)
        stations_for = lambda do |a, b|
          st = N.piece_stations(road, a, b)
          profile ? Geometry::RoadCrossing.lift(st, a, b, profile) : st
        end
        full = Geometry::RoadItems.call(stations_for.call(from, to), road.section, items: items, ax: road.ax, seed: road.settings['seed'])
        rails = { definitions: full[:definitions], instances: [], sleepers: full[:sleepers],
                  linear: full[:linear].select { |n| n['id'].start_with?('rail/') } }
        merge_items(placed, rails, tag)
        bounds = [from] + gaps.flatten.map { |g| g.clamp(from, to) }.sort + [to]
        bounds.each_slice(2).with_index do |(a, b), k|
          next if b - a < 0.5

          part_stations = stations_for.call(a, b)
          part = Geometry::RoadItems.call(part_stations, road.section, items: items, ax: road.ax, seed: road.settings['seed'])
          RoadEngine.lift_instances(part, part_stations) if profile
          others = { definitions: part[:definitions], instances: part[:instances], sleepers: [],
                     linear: part[:linear].reject { |n| n['id'].start_with?('rail/') } }
          merge_items(placed, others, "#{tag}.#{k + 1}")
        end
      end

      # Éléments d'un tronçon : leurs noms prennent celui de la voie et du tronçon, les formes restent partagées.
      def merge_items(placed, more, tag)
        placed[:definitions].merge!(more[:definitions]) { |_, kept, _| kept }
        %i[instances linear sleepers].each do |key|
          placed[key].concat(more[key].map { |node| node.merge('id' => "#{node['id']}@#{tag}") })
        end
      end
    end
  end
end
