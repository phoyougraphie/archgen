# frozen_string_literal: true

module Archgen
  module Core
    # Mode simple de l'import (ADR-58) : chaque voie OSM devient une bande de chaussée à plat, de largeur
    # fixée par son type, sans carrefour calculé. Rien n'est refusé pour sa géométrie : toutes les rues
    # s'affichent. Les bandes se superposent aux croisements ; la plus importante est posée au-dessus.
    module MapStreets
      module_function

      # type => [largeur (m), matière du catalogue de voirie, rang de superposition]
      TYPES = {
        'motorway' => [14.0, 'road/lane', 9], 'trunk' => [12.0, 'road/lane', 9],
        'primary' => [10.0, 'road/lane', 8], 'secondary' => [9.0, 'road/lane', 7], 'tertiary' => [8.0, 'road/lane', 6],
        'motorway_link' => [6.0, 'road/lane', 8], 'trunk_link' => [6.0, 'road/lane', 8], 'primary_link' => [6.0, 'road/lane', 7],
        'secondary_link' => [6.0, 'road/lane', 6], 'tertiary_link' => [6.0, 'road/lane', 5],
        'unclassified' => [6.0, 'road/lane', 5], 'residential' => [6.0, 'road/lane', 5], 'living_street' => [5.0, 'road/lane', 4],
        'service' => [4.0, 'road/lane', 3], 'track' => [3.0, 'road/track', 2],
        'pedestrian' => [5.0, 'road/sidewalk', 2], 'footway' => [2.0, 'road/sidewalk', 1], 'path' => [1.5, 'road/path', 1],
        'steps' => [2.0, 'road/sidewalk', 1], 'cycleway' => [2.5, 'road/cycle', 1]
      }.freeze
      BASE_Z_M = 0.03
      STEP_Z_M = 0.01
      MITER_LIMIT = 2.5
      MAX_STREETS = 2000

      # map : MapReader. Rend Result.ok({ 'nodes', 'face_count', 'street_count', 'skipped' }).
      def call(map)
        skipped = Hash.new(0)
        nodes = []
        map['ways'].each do |way|
          spec = TYPES[way['tags']['highway']]
          next skipped['highway_unknown'] += 1 unless spec
          next skipped['tunnel'] += 1 if tunnel?(way['tags'])

          points = MapRoads.dedupe(way['points_m'])
          next skipped['too_short'] += 1 if points.size < 2 || MapRoads.length(points) < 0.5

          width, material, rank = spec
          primitive = ribbon(points, width / 2.0, BASE_Z_M + (rank * STEP_Z_M), material)
          nodes << { 'id' => "street/#{way['id']}", 'category' => 'road_surface', 'children' => [], 'primitive' => primitive }
        end
        if nodes.size > MAX_STREETS
          return Result.fail([Diagnostic.error('E_MAP', '/map/ways', reason: 'map_too_large', value: nodes.size, limit: MAX_STREETS)])
        end

        Result.ok({ 'nodes' => nodes, 'face_count' => nodes.sum { |n| n['primitive']['faces'].size }, 'street_count' => nodes.size,
                    'skipped' => skipped.sort.to_h })
      end

      def tunnel?(tags)
        tags.key?('tunnel') && !%w[no 0].include?(tags['tunnel'])
      end

      # Bande à plat : bords décalés avec onglets bornés ; un quadrilatère par segment, toujours convexe
      # (sinon le segment reprend ses bords droits) ; un triangle comble l'extérieur d'un virage serré.
      def ribbon(points, half, z, material)
        builder = Geometry::MeshBuilder.new('surface')
        lefts, rights = edges(points, half)
        points.each_cons(2).with_index do |(a, b), i|
          quad = [rights[i][:out], rights[i + 1][:in], lefts[i + 1][:in], lefts[i][:out]]
          quad = straight(a, b, half) unless convex?(quad)
          builder.add_face(quad.map { |x, y| [x, y, z] }, material)
        end
        points.each_index do |i|
          next if i.zero? || i == points.size - 1

          [lefts[i], rights[i]].each do |side|
            next unless side[:gap]

            tri = [points[i], side[:gap][0], side[:gap][1]]
            tri = tri.reverse if signed_area(tri).negative?
            builder.add_face(tri.map { |x, y| [x, y, z] }, material) if signed_area(tri) > 1e-4
          end
        end
        builder.to_primitive
      end

      # Pour chaque sommet : point d'entrée (fin du segment précédent) et de sortie (début du suivant), à
      # gauche et à droite ; un onglet partagé si l'angle le permet, sinon deux points et un trou à combler.
      def edges(points, half)
        normals = points.each_cons(2).map do |a, b|
          len = Math.hypot(b[0] - a[0], b[1] - a[1])
          [-(b[1] - a[1]) / len, (b[0] - a[0]) / len]
        end
        [1, -1].map do |sign|
          points.each_index.map do |i|
            before = normals[[i - 1, 0].max]
            after = normals[[i, normals.size - 1].min]
            p = points[i]
            offset = ->(n) { [p[0] + (sign * half * n[0]), p[1] + (sign * half * n[1])] }
            if i.zero? || i == points.size - 1
              q = offset.call(i.zero? ? after : before)
              next({ in: q, out: q })
            end
            mid = [before[0] + after[0], before[1] + after[1]]
            norm = Math.hypot(*mid)
            cos = (before[0] * after[0]) + (before[1] * after[1])
            scale = norm < 1e-9 ? Float::INFINITY : 2.0 / (norm * norm)
            # Longueur de l'onglet : 2 / |n1 + n2| demi-largeurs.
            if norm > 1e-9 && 2.0 / norm <= MITER_LIMIT && cos > -0.5
              q = [p[0] + (sign * half * mid[0] * scale), p[1] + (sign * half * mid[1] * scale)]
              { in: q, out: q }
            else
              a = offset.call(before)
              b = offset.call(after)
              { in: a, out: b, gap: [a, b] }
            end
          end
        end
      end

      def straight(a, b, half)
        len = Math.hypot(b[0] - a[0], b[1] - a[1])
        n = [-(b[1] - a[1]) / len * half, (b[0] - a[0]) / len * half]
        [[a[0] - n[0], a[1] - n[1]], [b[0] - n[0], b[1] - n[1]], [b[0] + n[0], b[1] + n[1]], [a[0] + n[0], a[1] + n[1]]]
      end

      def convex?(quad)
        crosses = quad.each_index.map do |i|
          a = quad[i]
          b = quad[(i + 1) % 4]
          c = quad[(i + 2) % 4]
          ((b[0] - a[0]) * (c[1] - b[1])) - ((b[1] - a[1]) * (c[0] - b[0]))
        end
        crosses.all? { |c| c > 1e-6 } && signed_area(quad) > 1e-4
      end

      def signed_area(poly)
        MapBuildings.polygon_area(poly)
      end
    end
  end
end
