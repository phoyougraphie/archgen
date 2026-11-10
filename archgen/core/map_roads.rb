# frozen_string_literal: true

module Archgen
  module Core
    # Voies d'une carte → réseaux ARCHGEN (docs/CARTOGRAPHIE_CONTRACT.md §2, AG-126, D-40).
    # Entrée : la carte de MapReader, en mètres. Sortie : des réglages de réseau prêts pour
    # RoadNetworkIntake, et le compte de ce qui est écarté. Aucune écriture, aucun aléa.
    module MapRoads
      module_function

      TYPES = {
        'motorway' => 'autoroute', 'trunk' => 'autoroute',
        'primary' => 'nationale', 'secondary' => 'nationale',
        'tertiary' => 'campagne', 'unclassified' => 'campagne',
        'residential' => 'ville', 'living_street' => 'ville',
        'service' => 'rural', 'track' => 'rural',
        'pedestrian' => 'pieton', 'footway' => 'pieton', 'path' => 'pieton', 'steps' => 'pieton',
        'cycleway' => 'verte'
      }.freeze
      LEVEL_KEYS = %w[bridge tunnel layer].freeze
      TOLERANCE_M = 0.5
      MAX_POINTS = 64
      RADII_M = [10.0, 5.0, 0.0].freeze
      MAX_PER_NETWORK = 24
      MAX_ROADS = 400
      MIN_LENGTH_M = 1.0

      # presets : catalogue road_presets ; road_intake : RoadIntake ; bands, items : catalogues de voirie.
      def call(map, presets:, road_intake:, bands:, items:)
        profiles = presets.fetch('presets').to_h { |p| [p['id'], p['profile']] }
        skipped = Hash.new(0)
        roads = []
        # Un point partagé par deux voies (nœud OSM commun) est un carrefour : la simplification le garde.
        shared = Hash.new(0)
        map['ways'].each { |way| dedupe(way['points_m']).uniq.each { |p| shared[p] += 1 } }
        fixed = shared.select { |_, n| n > 1 }.keys.to_h { |p| [p, true] }
        map['ways'].each do |way|
          preset = TYPES[way['tags']['highway']]
          next skipped['highway_unknown'] += 1 unless preset
          next skipped['level'] += 1 if level?(way['tags'])

          points = simplify(dedupe(way['points_m']), fixed)
          next skipped['too_short'] += 1 if points.size < 2 || length(points) < MIN_LENGTH_M

          chunks(points).each_with_index do |chunk, k|
            roads << { 'way' => way['id'], 'id' => road_id(way['id'], k), 'points' => chunk, 'profile' => profiles.fetch(preset) }
          end
        end
        if roads.size > MAX_ROADS
          return Result.fail([Diagnostic.error('E_MAP', '/map/ways', reason: 'map_too_large', value: roads.size, limit: MAX_ROADS)])
        end

        accepted = roads.filter_map do |road|
          radii = fitting_radii(road, road_intake, bands, items)
          unless radii
            skipped['trace_refused'] += 1
            next
          end

          road.merge('radii' => radii)
        end
        Result.ok({ 'networks' => networks(accepted), 'road_count' => accepted.size, 'skipped' => skipped.sort.to_h })
      end

      def level?(tags)
        LEVEL_KEYS.any? { |k| tags.key?(k) && !%w[no 0].include?(tags[k]) }
      end

      def road_id(way, k)
        digits = way.to_s[/\d+\z/] || way.to_s.downcase.gsub(/[^a-z0-9]/, '')
        "w#{digits[0, 24]}-#{k + 1}"
      end

      def dedupe(points)
        points.each_with_object([]) { |p, out| out << p unless out.last == p }
      end

      def length(points)
        points.each_cons(2).sum { |a, b| Math.hypot(b[0] - a[0], b[1] - a[1]) }
      end

      # Douglas-Peucker à 0,5 m, itératif ; les extrémités restent.
      def simplify(points, fixed = {})
        return points if points.size < 3

        keep = points.map { |p| fixed.key?(p) }
        keep[0] = keep[-1] = true
        anchors = keep.each_index.select { |i| keep[i] }
        stack = anchors.each_cons(2).to_a
        until stack.empty?
          first, last = stack.pop
          index, distance = farthest(points, first, last)
          next unless index && distance > TOLERANCE_M

          keep[index] = true
          stack << [first, index] << [index, last]
        end
        points.each_index.select { |i| keep[i] }.map { |i| points[i] }
      end

      def farthest(points, first, last)
        a = points[first]
        b = points[last]
        ((first + 1)...last).map { |i| [i, segment_distance(points[i], a, b)] }.max_by(&:last)
      end

      def segment_distance(p, a, b)
        dx = b[0] - a[0]
        dy = b[1] - a[1]
        len2 = (dx * dx) + (dy * dy)
        return Math.hypot(p[0] - a[0], p[1] - a[1]) if len2.zero?

        t = (((p[0] - a[0]) * dx) + ((p[1] - a[1]) * dy)) / len2
        t = t.clamp(0.0, 1.0)
        Math.hypot(p[0] - (a[0] + (t * dx)), p[1] - (a[1] + (t * dy)))
      end

      # Voies de 64 points au plus ; deux morceaux voisins partagent leur sommet de coupe.
      def chunks(points)
        return [points] if points.size <= MAX_POINTS

        out = []
        start = 0
        while start < points.size - 1
          stop = [start + MAX_POINTS - 1, points.size - 1].min
          out << points[start..stop]
          start = stop
        end
        out
      end

      # Le plus grand rayon uniforme de 10, 5 ou 0 m que la voie accepte ; nil si aucun.
      def fitting_radii(road, road_intake, bands, items)
        # Une voie seule part de son origine : le contrôle se fait sur le tracé ramené à son premier point.
        x0, y0 = road['points'].first
        local = road['points'].map { |x, y| [Quant.q(x - x0), Quant.q(y - y0)] }
        RADII_M.each do |r|
          radii = Array.new([road['points'].size - 2, 0].max, r)
          settings = road_intake.settings({ 'trace' => { 'points_m' => local, 'radii_m' => radii }, 'profile' => road['profile'] })
          next unless settings.ok?

          section = Geometry::RoadSection.call(settings.value['profile'], bands: bands, items: items)
          ax = Geometry::RoadRibbons.axis_x(section['width_m'], settings.value['axis'])
          axis = Geometry::RoadAxis.call(local, radii, left_m: ax, right_m: section['width_m'] - ax)
          return radii if axis.ok?
        end
        nil
      end

      # Voies reliées par un point commun (nœud OSM partagé) : composantes, parcours en largeur,
      # morceaux de 24 voies au plus.
      def networks(roads)
        by_point = Hash.new { |h, k| h[k] = [] }
        roads.each_with_index { |road, i| road['points'].each { |p| by_point[p] << i } }
        seen = Array.new(roads.size, false)
        out = []
        roads.each_index do |start|
          next if seen[start]

          order = []
          queue = [start]
          seen[start] = true
          until queue.empty?
            i = queue.shift
            order << i
            roads[i]['points'].flat_map { |p| by_point[p] }.uniq.sort.each do |j|
              next if seen[j]

              seen[j] = true
              queue << j
            end
          end
          order.each_slice(MAX_PER_NETWORK) { |slice| out << network(slice.map { |i| roads[i] }) }
        end
        out
      end

      def network(roads)
        { 'network_version' => 1,
          'roads' => roads.map do |r|
            { 'id' => r['id'], 'road' => { 'road_version' => 1, 'trace' => { 'points_m' => r['points'], 'radii_m' => r['radii'] }, 'profile' => r['profile'] } }
          end }
      end
    end
  end
end
