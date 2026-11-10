# frozen_string_literal: true

module Archgen
  module Core
    # Carrefours depuis « Tracer une voie » (docs/CARREFOURS_DALLE_CONTRACT.md, AG-102) : la nouvelle
    # voie et les voies ou réseaux qu'elle touche forment un seul réseau. Pur : les racines sont
    # données avec leurs réglages et leur matrice ; aucune lecture du modèle ici.
    module RoadMerge
      SNAP_M = Geometry::RoadNetwork::SNAP_M
      MAX_ROADS = 24
      LEVEL_M = 0.01
      INCH = 0.0254

      Root = Struct.new(:ref, :kind, :settings, :matrix, keyword_init: true)
      Merge = Struct.new(:tree, :origin, :absorbed, keyword_init: true)

      module_function

      # new_settings : réglages de la voie tracée (points relatifs à origin, repère du modèle en mètres).
      # roots : Root ; `matrix` en pouces, comme SketchUp. width : ->(profil) { largeur en m }.
      # Résultat : nil si elle ne touche rien ; sinon Merge.
      def call(new_settings, origin, roots, width:)
        mine = polyline(new_settings['trace']['points_m'], origin)
        mine_width = width.call(new_settings['profile'])
        touched = roots.select do |root|
          roads_of(root).any? { |road| touching?(mine, mine_width, model_points(root, road), width.call(road['profile'])) }
        end
        return Result.ok(nil) if touched.empty?

        problems = touched.flat_map { |root| refusals(root, origin) }
        problems << error('network_on_terrain') if new_settings['ground']
        return Result.fail(problems.uniq { |d| d.params['reason'] }) unless problems.empty?

        roads = [{ 'id' => 'v1', 'road' => new_settings }]
        junctions = []
        touched.each do |root|
          roads_of(root).each do |road|
            local = model_points(root, road).map { |x, y| [Quant.q(x - origin[0]), Quant.q(y - origin[1])] }
            id = unique_id(road['__id'] || "v#{roads.size + 1}", roads)
            roads << { 'id' => id, 'road' => road.reject { |k, _| k == '__id' }.merge('trace' => road['trace'].merge('points_m' => local)) }
          end
          junctions.concat(root.settings['junctions'] || []) if root.kind == 'network'
        end
        return Result.fail([error('network_too_many_roads', limit: MAX_ROADS, value: roads.size)]) if roads.size > MAX_ROADS

        tree = { 'roads' => roads }
        tree['junctions'] = junctions unless junctions.empty?
        Result.ok(Merge.new(tree: tree, origin: origin, absorbed: touched.map(&:ref)))
      end

      # Une voie seule, ou chaque voie d'un réseau (avec son id, gardé).
      def roads_of(root)
        return [root.settings] if root.kind == 'road'

        root.settings['roads'].map { |entry| entry['road'].merge('__id' => entry['id']) }
      end
      private_class_method :roads_of

      # Points du modèle, en mètres : le plan d'une racine part du premier point de sa première voie.
      def model_points(root, road)
        first = roads_of(root).first['trace']['points_m'].first
        m = root.matrix
        road['trace']['points_m'].map do |x, y|
          lx = (x - first[0]) / INCH
          ly = (y - first[1]) / INCH
          [((m[0] * lx) + (m[4] * ly) + m[12]) * INCH, ((m[1] * lx) + (m[5] * ly) + m[13]) * INCH]
        end
      end
      private_class_method :model_points

      def polyline(points, origin)
        points.map { |x, y| [x + origin[0], y + origin[1]] }
      end
      private_class_method :polyline

      def refusals(root, origin)
        out = []
        out << error('network_on_terrain') if roads_of(root).any? { |road| road['ground'] }
        out << error('network_merge_levels') if (root.matrix[14] * INCH - origin[2]).abs > LEVEL_M
        out << error('network_merge_rotated') unless (root.matrix[10] - 1.0).abs < 1e-6
        out
      end
      private_class_method :refusals

      # Croisement d'axes, ou bout de l'une sur la chaussée de l'autre (demi-largeur + 1 m).
      def touching?(a, a_width, b, b_width)
        return true if a.each_cons(2).any? { |p1, p2| b.each_cons(2).any? { |q1, q2| crossing?(p1, p2, q1, q2) } }

        [a.first, a.last].any? { |p| distance(p, b) <= (b_width / 2.0) + SNAP_M } ||
          [b.first, b.last].any? { |p| distance(p, a) <= (a_width / 2.0) + SNAP_M }
      end
      private_class_method :touching?

      def crossing?(p1, p2, q1, q2)
        d = [p2[0] - p1[0], p2[1] - p1[1]]
        e = [q2[0] - q1[0], q2[1] - q1[1]]
        den = (d[0] * e[1]) - (d[1] * e[0])
        return false if den.abs < 1e-12

        w = [q1[0] - p1[0], q1[1] - p1[1]]
        t = ((w[0] * e[1]) - (w[1] * e[0])) / den
        u = ((w[0] * d[1]) - (w[1] * d[0])) / den
        t.between?(0.0, 1.0) && u.between?(0.0, 1.0)
      end
      private_class_method :crossing?

      def distance(p, line)
        line.each_cons(2).map do |a, b|
          d = [b[0] - a[0], b[1] - a[1]]
          len2 = (d[0]**2) + (d[1]**2)
          t = len2.zero? ? 0.0 : [[(((p[0] - a[0]) * d[0]) + ((p[1] - a[1]) * d[1])) / len2, 0.0].max, 1.0].min
          Math.hypot(a[0] + (d[0] * t) - p[0], a[1] + (d[1] * t) - p[1])
        end.min
      end
      private_class_method :distance

      def unique_id(id, roads)
        taken = roads.map { |r| r['id'] }
        return id unless taken.include?(id)

        n = 2
        n += 1 while taken.include?("#{id}-#{n}")
        "#{id}-#{n}"
      end
      private_class_method :unique_id

      def error(reason, **params)
        Diagnostic.error('E_ROAD_JUNCTION', '/trace', reason: reason, **params)
      end
      private_class_method :error
    end
  end
end
