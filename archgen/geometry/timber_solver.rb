# frozen_string_literal: true

module Archgen
  module Geometry
    # Pan de bois apparent (docs/PAN_DE_BOIS_CONTRACT.md, AG-083, ADR-48) : aux étages, sablières,
    # poteaux, huisseries et décharges posés sur le mur, de 0,04 m devant le nu jusqu'au nu. Le
    # rez-de-chaussée reste maçonné. Aucune pièce ne passe devant une baie.
    module TimberSolver
      RAIL_M = 0.20
      POST_M = 0.16
      JAMB_M = 0.12
      BRACE_M = 0.12
      MIN_PANEL_M = 0.50
      DEPTH_M = [-0.04, 0.0].freeze
      EPS = Core::Quant::EPSILON

      module_function

      def call(footprint:, levels:, openings:, config:, row:)
        return [] if levels.size < 2

        material = config['materials']['timber']
        footprint.facades.select { |f| %w[front rear].include?(f.id) || !row }.flat_map do |facade|
          facade_nodes(facade, levels, openings.select { |o| o.facade_id == facade.id && o.kind != 'porch' }, material)
        end
      end

      def facade_nodes(facade, levels, openings, material)
        length = facade.length_m
        top = levels.last.top_z_m
        base = "timber/#{facade.id}"
        nodes = levels.drop(1).map { |level| box(facade, "#{base}/#{level.index}/rail", 0.0, length, level.base_z_m, level.base_z_m + RAIL_M, material) }
        nodes << box(facade, "#{base}/top/rail", 0.0, length, top - RAIL_M, top, material)
        levels.drop(1).each_with_index do |level, i|
          upper = levels[i + 2]
          zb = level.base_z_m + RAIL_M
          zt = upper ? upper.base_z_m : top - RAIL_M
          nodes.concat(storey(facade, "#{base}/#{level.index}", openings.select { |o| o.level_index == level.index }.sort_by(&:u_min_m), zb, zt, material))
        end
        nodes
      end
      private_class_method :facade_nodes

      def storey(facade, base, openings, zb, zt, material)
        length = facade.length_m
        nodes = []
        jambs = openings.flat_map { |o| [[o.u_min_m - JAMB_M, o.u_min_m], [o.u_max_m, o.u_max_m + JAMB_M]] }
        openings.each_with_index do |o, n|
          jambs[2 * n, 2].each_with_index { |(u0, u1), side| nodes << box(facade, "#{base}/jamb/#{n}/#{side}", u0, u1, zb, zt, material) }
          if o.z_min_m - JAMB_M >= zb - EPS
            nodes << box(facade, "#{base}/sill/#{n}", o.u_min_m - JAMB_M, o.u_max_m + JAMB_M, o.z_min_m - JAMB_M, o.z_min_m, material)
          end
          if o.z_max_m + JAMB_M <= zt + EPS
            nodes << box(facade, "#{base}/head/#{n}", o.u_min_m - JAMB_M, o.u_max_m + JAMB_M, o.z_max_m, o.z_max_m + JAMB_M, material)
          end
        end
        centres = [POST_M / 2.0, length - (POST_M / 2.0)] + openings.each_cons(2).map { |a, b| (a.u_max_m + b.u_min_m) / 2.0 }
        posts = centres.map { |c| [c - (POST_M / 2.0), c + (POST_M / 2.0)] }.reject { |span| jambs.any? { |j| overlap?(span, j) } }
        posts.each_with_index { |(u0, u1), n| nodes << box(facade, "#{base}/post/#{n}", u0, u1, zb, zt, material) }
        members = (posts + jambs).sort
        members.each_cons(2).each_with_index do |(left, right), n|
          a = left[1]
          b = right[0]
          next if b - a < MIN_PANEL_M - EPS
          next if openings.any? { |o| o.u_min_m < b - EPS && o.u_max_m > a + EPS }

          nodes << brace(facade, "#{base}/brace/#{n}", a, b, zb, zt, n.even?, material)
        end
        nodes
      end
      private_class_method :storey

      def overlap?(a, b)
        a[0] < b[1] - EPS && a[1] > b[0] + EPS
      end
      private_class_method :overlap?

      def box(facade, id, u0, u1, z0, z1, material)
        q = ->(v) { Core::Quant.q(v) }
        Node.leaf(id, 'timber', Boxes.on_facade(facade, q.call(u0), q.call(u1), q.call(z0), q.call(z1), DEPTH_M[0], DEPTH_M[1], material))
      end
      private_class_method :box

      # Écharpe : parallélogramme dans le plan de façade, d'un coin bas à l'angle haut opposé.
      def brace(facade, id, a, b, zb, zt, rising, material)
        t = BRACE_M
        ring = if rising
                 [[a, zb], [a + t, zb], [b, zt], [b - t, zt]]
               else
                 [[b - t, zb], [b, zb], [a + t, zt], [a, zt]]
               end
        Node.leaf(id, 'timber', slab(facade, ring.map { |u, z| [Core::Quant.q(u), Core::Quant.q(z)] }, material))
      end
      private_class_method :brace

      # Solide fermé : face extérieure (devant le mur) dans le sens antihoraire vue du dehors.
      def slab(facade, ring, material)
        front = ring.map { |u, z| facade.point(u, z, DEPTH_M[0]) }
        back = ring.map { |u, z| facade.point(u, z, DEPTH_M[1]) }
        mesh = MeshBuilder.new('solid')
        mesh.add_face(front, material)
        mesh.add_face(back.reverse, material)
        ring.each_index do |i|
          j = (i + 1) % ring.size
          mesh.add_face([back[i], back[j], front[j], front[i]], material)
        end
        mesh.to_primitive
      end
      private_class_method :slab
    end
  end
end
