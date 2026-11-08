# frozen_string_literal: true

module Archgen
  module Geometry
    # Pose des éléments d'une coupe le long de l'axe (docs/VOIRIE_CONTRACT.md, Éléments) :
    # - répétés : un objet tous les `spacing_m` sur leur ligne de pose, le premier à pas / 2 ;
    #   instances de définitions partagées par type, variante et hauteur ;
    # - continus : haies, barrières, glissières extrudées le long de leur ligne, avec poteaux.
    module RoadItems
      # Profil (u latéral à gauche, z) des éléments continus, et poteaux : [largeur, hauteur, pas] ou nil.
      def self.linear_spec(kind, variant, h)
        case [kind, variant]
        in ['hedge', _] then { shapes: [rect(-0.4, 0.4, 0, h)], part: 'hedge', post: nil }
        in ['fence', 'mesh'] then { shapes: [rect(-0.01, 0.01, 0.05, h)], part: 'steel', post: [0.06, h, 2.5, 'steel'] }
        in ['fence', _] then { shapes: [rect(-0.03, 0.03, 0.35 * h, 0.45 * h), rect(-0.03, 0.03, 0.85 * h, 0.95 * h)], part: 'wood', post: [0.1, h, 2.0, 'wood'] }
        in ['guard', 'concrete'] then { shapes: [[[-0.3, 0.0], [0.3, 0.0], [0.08, h], [-0.08, h]]], part: 'concrete', post: nil }
        in ['guard', _] then { shapes: [rect(-0.05, 0.05, h - 0.31, h)], part: 'steel', post: [0.1, h - 0.05, 2.0, 'steel'] }
        # Ganivelle (AG-052, ADR-35) : les lattes jointives simplifiées en une paroi de bois de 2 cm, poteaux tous les 2 m.
        in ['sand_fence', _] then { shapes: [rect(-0.01, 0.01, 0.05, h)], part: 'wood', post: [0.08, h + 0.05, 2.0, 'wood'] }
        in ['low_wall', _] then { shapes: [rect(-0.15, 0.15, 0, h)], part: 'stone', post: nil }
        end
      end

      # Polygone (u, z) parcouru dans le sens direct vu depuis l'avant de la voie.
      def self.rect(u0, u1, z0, z1)
        [[u0, z0], [u1, z0], [u1, z1], [u0, z1]]
      end

      module_function

      RAIL_HEAD_M = 0.07
      RAIL_HEIGHT_M = 0.17
      SLEEPER_PITCH_M = 0.6
      # Les définitions de voirie portent la version de leur moteur : une forme changée n'est jamais
      # confondue avec une ancienne, ni avec un détail de bâtiment, dans le modèle.
      PREFIX = "road#{ROAD_ENGINE_VERSION}/".freeze
      SLEEPER_ID = "#{PREFIX}sleeper".freeze
      # Famille de chaque objet, donc sa balise dans le modèle.
      FAMILIES = {
        'tree' => 'road_vegetation', 'hedge' => 'road_vegetation', 'lamp' => 'road_lighting',
        'bollard' => 'road_furniture', 'pole' => 'road_furniture', 'post' => 'road_furniture', 'fence' => 'road_furniture',
        'guard' => 'road_furniture', 'road_stud' => 'road_furniture', 'crossing_stud' => 'road_furniture', 'sand_fence' => 'road_furniture', 'low_wall' => 'road_furniture', 'signal' => 'road_furniture', 'crossing_light' => 'road_furniture', 'crossing_gate' => 'road_furniture', 'rail' => 'road_rails', 'sleeper' => 'road_rails'
      }.freeze

      def family(node)
        FAMILIES.fetch(node['id'].split('/').first)
      end

      # Retourne { definitions:, instances:, linear:, sleepers: } en données de plan.
      # stations : RoadAxis ; section : RoadSection ; ax : x de l'axe dans la coupe ; seed : réglage de la voie.
      def call(stations, section, items:, ax:, seed:)
        definitions = {}
        instances = []
        linear = []
        section['items'].each do |item|
          offset = ax - item['x_m']
          line = offset_line(stations, offset)
          if item['repeat'] == 'spaced'
            place_spaced(item, line, items, seed, definitions, instances)
          else
            sweep_linear(item, stations, offset, line, definitions, instances, linear)
          end
        end
        sleepers = []
        lay_track(stations, section, ax, definitions, linear, sleepers)
        { definitions: definitions, instances: instances, linear: linear, sleepers: sleepers }
      end

      # Voie sur ballast : deux rails de 0,07 × 0,17 m, dessus à la cote de la coupe, posés sur des
      # traverses de 2,60 m tous les 0,60 m, dont le dessus dépasse le ballast de 2 cm.
      def lay_track(stations, section, ax, definitions, linear, sleepers)
        section['rails'].select { |r| r['kind'] == 'ballast' }.each_with_index do |rail, k|
          half = RAIL_HEAD_M / 2
          linear << { 'id' => "rail/#{rail['band']}/#{k}", 'category' => 'linear', 'children' => [],
                      'primitive' => extrude(stations, ax - rail['x_m'], rail['z_m'] - RAIL_HEIGHT_M,
                                             rect(-half, half, 0.0, RAIL_HEIGHT_M), RoadRibbons::RAIL_MATERIAL) }
        end
        section['bands'].select { |b| b['type'] == 'rail' }.each do |band|
          definitions[SLEEPER_ID] ||= RoadItemShapes.definition('sleeper', 'concrete', 0.15)
          line = offset_line(stations, ax - ((band['x0_m'] + band['x1_m']) / 2))
          spaced_positions(polyline_length(line), SLEEPER_PITCH_M).each_with_index do |s, rank|
            point, dir = point_at(line, s)
            sleepers << instance("sleeper/#{band['index']}/#{rank}", SLEEPER_ID, point, dir, band['level_m'], 'left')
          end
        end
      end

      def sleeper_estimate(stations, section, ax)
        section['bands'].select { |b| b['type'] == 'rail' }.sum do |band|
          Geometry::RoadSection.count_over(SLEEPER_PITCH_M, polyline_length(offset_line(stations, ax - ((band['x0_m'] + band['x1_m']) / 2))))
        end
      end

      def offset_line(stations, offset)
        stations.map { |s| [s.point[0] + (s.normal[0] * offset), s.point[1] + (s.normal[1] * offset)] }
      end

      # Abscisses de pose : pas / 2, puis tous les pas, jamais au-delà de la ligne.
      def spaced_positions(length, spacing)
        out = []
        s = spacing / 2.0
        while s <= length + 1e-9
          out << s
          s += spacing
        end
        out
      end

      def place_spaced(item, line, items, seed, definitions, instances)
        entry = items.fetch('items').fetch(item['kind'])
        length = polyline_length(line)
        spaced_positions(length, item['spacing_m']).each_with_index do |s, rank|
          height = chosen_height(item, entry, seed, rank)
          id = definition_id(item['kind'], item['variant'], height)
          definitions[id] ||= RoadItemShapes.definition(item['kind'], item['variant'], height, crown: crown(item, entry, height))
          point, dir = point_at(line, s)
          instances << instance("#{item['kind']}/#{item['band']}/#{item['index']}/#{rank}", id, point, dir, item['z_m'], item['toward'])
        end
      end

      # Variation : h(1 − v), h ou h(1 + v), tirée par une clé stable (contrat).
      def chosen_height(item, entry, seed, rank)
        v = item['height_variation'].to_f
        return item['height_m'] if v.zero? || !entry['height_variation']

        pick = (Core::DeterministicRandom.unit(seed, "road/item/#{item['band']}/#{item['index']}/#{rank}") * 3).floor
        Core::Quant.q(item['height_m'] * [1 - v, 1.0, 1 + v][pick])
      end

      def crown(item, entry, height)
        return nil unless item['kind'] == 'tree'

        shape = entry['variants'].fetch(item['variant'])
        { 'radius' => Core::Quant.q(shape['crown_radius_ratio'] * height), 'base' => Core::Quant.q(shape['crown_base_ratio'] * height) }
      end

      def definition_id(kind, variant, height)
        "#{PREFIX}#{kind}/#{variant}/#{(height * 1000).round}"
      end

      def polyline_length(line)
        line.each_cons(2).sum { |a, b| Math.hypot(b[0] - a[0], b[1] - a[1]) }
      end

      # Point et direction à l'abscisse s le long de la ligne.
      def point_at(line, s)
        walked = 0.0
        line.each_cons(2) do |a, b|
          len = Math.hypot(b[0] - a[0], b[1] - a[1])
          next if len < 1e-12

          if s <= walked + len + 1e-9
            t = [(s - walked) / len, 1.0].min
            return [[a[0] + ((b[0] - a[0]) * t), a[1] + ((b[1] - a[1]) * t)], [(b[0] - a[0]) / len, (b[1] - a[1]) / len]]
          end
          walked += len
        end
        a, b = line.last(2)
        len = Math.hypot(b[0] - a[0], b[1] - a[1])
        [b, [(b[0] - a[0]) / len, (b[1] - a[1]) / len]]
      end

      # Repère local : Y vers la chaussée la plus proche ; « left » = gauche de la voie, sinon on tourne d'un demi-tour.
      def instance(id, definition_id, point, dir, z, toward)
        x = toward == 'right' ? [-dir[0], -dir[1]] : dir
        y = [-x[1], x[0]]
        matrix = [x[0], x[1], 0.0, 0.0, y[0], y[1], 0.0, 0.0, 0.0, 0.0, 1.0, 0.0,
                  Core::Quant.q(point[0]), Core::Quant.q(point[1]), Core::Quant.q(z), 1.0].map { |c| c.zero? ? 0.0 : c }
        { 'id' => id, 'category' => 'item', 'children' => [], 'primitive' => { 'type' => 'instance', 'definition_id' => definition_id, 'matrix' => matrix } }
      end

      def sweep_linear(item, stations, offset, line, definitions, instances, linear)
        spec = linear_spec(item['kind'], item['variant'], item['height_m'])
        spec[:shapes].each_with_index do |polygon, k|
          linear << { 'id' => "#{item['kind']}/#{item['band']}/#{item['index']}/#{k}", 'category' => 'linear', 'children' => [],
                      'primitive' => extrude(stations, offset, item['z_m'], polygon, RoadItemShapes.material(spec[:part])) }
        end
        return unless spec[:post]

        width, height, pitch, part = spec[:post]
        id = "#{PREFIX}post/#{part}/#{(width * 1000).round}/#{(height * 1000).round}"
        definitions[id] ||= RoadItemShapes.definition('post', part, height, crown: width)
        post_positions(polyline_length(line), pitch).each_with_index do |s, rank|
          point, dir = point_at(line, s)
          instances << instance("post/#{item['band']}/#{item['index']}/#{rank}", id, point, dir, item['z_m'], 'left')
        end
      end

      # Un poteau à chaque bout et tous les pas entre les deux.
      def post_positions(length, pitch)
        out = (0..(length / pitch).floor).map { |k| k * pitch }
        out << length if length - out.last > 0.1
        out
      end

      # Solide fermé : le polygone balayé de station en station, fermé à chaque bout.
      def extrude(stations, offset, z0, polygon, material)
        builder = MeshBuilder.new('solid')
        ring = lambda do |s|
          polygon.map { |u, z| [s.point[0] + (s.normal[0] * (offset + u)), s.point[1] + (s.normal[1] * (offset + u)), z0 + z + (s.z || 0.0)] }
        end
        rings = stations.map { |s| ring.call(s) }
        faces = []
        rings.each_cons(2) do |a, b|
          polygon.each_index do |j|
            n = (j + 1) % polygon.size
            faces << [a[j], a[n], b[n], b[j]]
          end
        end
        faces << rings.first.reverse
        faces << rings.last
        faces = faces.map(&:reverse) if signed_volume(faces).negative?
        faces.each { |f| builder.add_face(f, material) }
        builder.to_primitive
      end

      def signed_volume(faces)
        faces.sum do |f|
          (1...(f.size - 1)).sum do |i|
            a = f[0]
            b = f[i]
            c = f[i + 1]
            ((a[0] * ((b[1] * c[2]) - (b[2] * c[1]))) - (a[1] * ((b[0] * c[2]) - (b[2] * c[0]))) + (a[2] * ((b[0] * c[1]) - (b[1] * c[0])))) / 6.0
          end
        end
      end
    end
  end
end
