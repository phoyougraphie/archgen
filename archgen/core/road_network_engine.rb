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
        problems = radius_problems(nodes, settings['junctions'])
        return Result.fail(problems) unless problems.empty?

        built = nodes.map { |node| N.build(node, roads) }
        problems = built.flat_map(&:errors)
        return Result.fail(problems.sort_by(&:sort_key)) unless problems.empty?

        pieces = roads.map { |road| N.pieces(road, nodes) }
        problems = pieces.flat_map(&:errors).uniq
        return Result.fail(problems.sort_by(&:sort_key)) unless problems.empty?

        build_plan(roads, nodes, built.map { |b| b.value[:faces] }, pieces.map(&:value), items, limits, built.flat_map { |b| b.value[:instances] })
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
      def radius_problems(nodes, junctions)
        by_id = junctions.to_h { |j| [j['id'], j] }
        nodes.each do |node|
          node.radius = by_id[node.id]&.fetch('corner_radius_m') || N::DEFAULT_RADIUS_M
          node.type = by_id[node.id]&.fetch('type') || 'simple'
          node.options = by_id[node.id] || {}
        end
        known = nodes.map(&:id)
        junctions.each_with_index.reject { |j, _| known.include?(j['id']) }.map do |j, _|
          Diagnostic.error('E_ROAD_JUNCTION', "/junctions/#{j['id']}", reason: 'unknown_junction')
        end
      end

      def build_plan(roads, nodes, junction_faces, pieces, items, limits, lights)
        estimate = roads.each_with_index.sum do |road, i|
          pieces[i].sum { |from, to| Geometry::RoadRibbons.face_estimate(N.piece_stations(road, from, to).size, road.line) }
        end + junction_faces.sum(&:size)
        return Result.fail([RoadEngine.budget('road_faces', limits[:unique], estimate)]) if estimate > limits[:unique]

        builder = Geometry::MeshBuilder.new('surface')
        placed = { definitions: {}, instances: [], linear: [], sleepers: [] }
        station_count = 0
        roads.each_with_index do |road, i|
          pieces[i].each_with_index do |(from, to), k|
            stations = N.piece_stations(road, from, to)
            station_count += stations.size
            Geometry::RoadRibbons.sweep(builder, stations, road.line, road.ax)
            merge_items(placed, Geometry::RoadItems.call(stations, road.section, items: items, ax: road.ax, seed: road.settings['seed']),
                        "#{road.id}.#{k + 1}")
          end
        end
        unless lights.empty?
          id, shape = Geometry::RoadSignals.definition
          placed[:definitions][id] ||= shape
          placed[:instances].concat(lights)
        end
        from = builder.to_primitive['faces'].size
        junction_faces.each { |faces| faces.each { |points, material| builder.add_face(points, material) } }
        surface = N.heal(builder.to_primitive, from)
        return Result.fail([Diagnostic.error('E_ROAD_JUNCTION', '/junctions', reason: 'junction_shape')]) unless surface

        plan = RoadEngine.assemble(surface, placed, [], { 'width_m' => roads.map(&:width).max }, [])
        plan['metrics'].merge!(
          'station_count' => station_count, 'cross_segment_count' => roads.sum { |r| r.line.size },
          'length_m' => Quant.q(roads.sum(&:length)), 'road_count' => roads.size,
          'junction_count' => nodes.size, 'piece_count' => pieces.sum(&:size),
          'junction_face_count' => junction_faces.sum(&:size), 'signal_count' => lights.size
        )
        plan['junctions'] = nodes.map do |n|
          {
            'id' => n.id, 'type' => n.type, 'point_m' => n.point.map { |c| Quant.q(c) }, 'arms' => n.arms.size, 'corner_radius_m' => n.radius,
            'cuts_m' => n.arms.map { |a| Quant.q(a.cut) }, 'reach_m' => n.arms.map { |a| Quant.q(a.reach) },
            'outer_radius_m' => roundabout_value(n, 'outer_radius_m', Geometry::RoadRoundabout::DEFAULT_OUTER_M),
            'ring_width_m' => roundabout_value(n, 'ring_width_m', Geometry::RoadRoundabout::DEFAULT_RING_M)
          }.compact
        end
        problems = RoadEngine.budget_problems(plan['metrics'], limits) + RoadPlanValidator.call(plan)
        return Result.fail(problems) unless problems.empty?

        Result.ok(Canonical.deep_freeze(plan))
      end

      def roundabout_value(node, key, default)
        node.type == 'roundabout' ? node.options.fetch(key, default) : nil
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
