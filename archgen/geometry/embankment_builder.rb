# frozen_string_literal: true

module Archgen
  module Geometry
    # Talus autour de l'emprise : des rayons partent du pied du mur à z = 0, descendent selon
    # la pente choisie et s'arrêtent sous le terrain. Faces triangulées : le terrain est
    # quelconque et un quad entre deux rayons ne serait pas plan.
    class EmbankmentBuilder
      MATERIAL = 'earth'
      CORNER_RAYS = 3
      TOE_M = 0.05
      MARCH_PER_STEP = 4
      BISECTIONS = 16

      Ray = Struct.new(:origin, :tip, :reach, keyword_init: true)

      def self.call(footprint:, grid:, settings:, platform:)
        new(footprint, grid, settings, platform).call
      end

      def initialize(footprint, grid, settings, platform)
        @footprint = footprint
        @grid = grid
        @ratio = settings['embankment_ratio']
        @march = settings.dig('survey', 'step_m') / MARCH_PER_STEP
        @platform = platform
        @missing = []
        @unreached = []
      end

      # Result<{ nodes:, reach_m: }> ; toutes les façades sont parcourues pour tout signaler.
      def call
        rings = FACADE_ORDER.to_h { |id| [id, facade_rays(id)] }
        problems = diagnostics
        return Core::Result.fail(problems) unless problems.empty?

        nodes = FACADE_ORDER.each_with_index.filter_map do |id, index|
          facade_node(id, rings[id] + rings[FACADE_ORDER[(index + 1) % FACADE_ORDER.size]].first(1))
        end
        Core::Result.ok(nodes: nodes, reach_m: Core::Quant.q(rings.values.flatten.map(&:reach).max))
      end

      private

      def diagnostics
        out = []
        unless @missing.empty?
          out << Core::Diagnostic.error('E_SITE_SURVEY', '/site/survey', reason: 'missing_points', count: @missing.size,
                                                                          points: @missing.first(Core::SiteAssise::MAX_LISTED_POINTS))
        end
        @unreached.uniq.each { |id| out << Core::Diagnostic.error('E_SITE_TOE', '/site/embankment_ratio', reason: 'toe_not_found', id: id) }
        out
      end

      # Rayons de la façade, puis l'éventail de l'angle qui la termine.
      def facade_rays(id)
        facade = @footprint.facade(id)
        normal = [facade.normal[0], facade.normal[1]]
        rays = stations(facade).map { |u| ray(facade.point(u, 0.0), normal, id) }
        rays + corner_rays(facade, normal, id)
      end

      def corner_rays(facade, normal, id)
        corner = facade.point(facade.length_m, 0.0)
        following = [facade.tangent[0], facade.tangent[1]]
        (1..CORNER_RAYS).map do |i|
          angle = (Math::PI / 2.0) * i / (CORNER_RAYS + 1)
          direction = [(normal[0] * Math.cos(angle)) + (following[0] * Math.sin(angle)),
                       (normal[1] * Math.cos(angle)) + (following[1] * Math.sin(angle))]
          ray(corner, direction, id)
        end
      end

      def stations(facade)
        axis = facade.tangent[0].zero? ? @grid.ys : @grid.xs
        axis.select { |value| value >= -Core::Quant::EPSILON && value <= facade.length_m + Core::Quant::EPSILON }
      end

      def ray(origin, direction, id)
        return flat_ray(origin) unless clearance(origin, direction, 0.0).negative?

        toe = toe_distance(origin, direction, id)
        return flat_ray(origin) unless toe

        reach = toe + (TOE_M * @ratio)
        tip = Core::Quant.q3([origin[0] + (direction[0] * reach), origin[1] + (direction[1] * reach), -reach / @ratio])
        Ray.new(origin: origin, tip: tip, reach: reach)
      end

      def flat_ray(origin)
        Ray.new(origin: origin, tip: origin, reach: 0.0)
      end

      # Hauteur du terrain au-dessus de la surface du talus, à la distance s du mur.
      def clearance(origin, direction, distance)
        height = local_height(origin, direction, distance)
        height && (height + (distance / @ratio))
      end

      def local_height(origin, direction, distance)
        altitude = @grid.altitude_at(origin[0] + (direction[0] * distance), origin[1] + (direction[1] * distance))
        altitude && (altitude - @platform)
      end

      # Premier passage du terrain au-dessus du talus, affiné par dichotomie.
      def toe_distance(origin, direction, id)
        low = 0.0
        loop do
          high = low + @march
          value = clearance(origin, direction, high)
          return blocked(origin, direction, high, id) if value.nil?
          return refine(origin, direction, low, high) unless value.negative?

          low = high
        end
      end

      # Hors de la grille : le pied n'existe pas dans la marge. Dans la grille : un trou.
      def blocked(origin, direction, distance, id)
        x = origin[0] + (direction[0] * distance)
        y = origin[1] + (direction[1] * distance)
        if x.between?(@grid.xs.first, @grid.xs.last) && y.between?(@grid.ys.first, @grid.ys.last)
          @missing << [Core::Quant.q(x), Core::Quant.q(y)]
        else
          @unreached << id
        end
        nil
      end

      def refine(origin, direction, low, high)
        BISECTIONS.times do
          middle = (low + high) / 2.0
          value = clearance(origin, direction, middle)
          value.nil? || value.negative? ? low = middle : high = middle
        end
        high
      end

      def facade_node(id, chain)
        mesh = MeshBuilder.new('surface')
        faces = 0
        chain.each_cons(2) do |a, b|
          triangles(a, b).each do |triangle|
            mesh.add_face(triangle, MATERIAL)
            faces += 1
          end
        end
        faces.zero? ? nil : Node.leaf("site/embankment/#{id}", 'embankment', mesh.to_primitive)
      end

      # Deux triangles entre deux rayons voisins ; un rayon nul ou une origine commune en ôte un.
      def triangles(a, b)
        [[a.origin, a.tip, b.tip], [a.origin, b.tip, b.origin]].select { |points| points.uniq.size == 3 }
      end
    end
  end
end
