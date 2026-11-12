# frozen_string_literal: true

module Archgen
  module Geometry
    # Trame structurelle et brise-soleil (docs/VOLUMES_MODERNES_CONTRACT.md, AG-093, ADR-48).
    module ModernSolver
      BAND_M = 0.30
      POST_M = 0.30
      GRID_D_M = [-0.10, 0.0].freeze
      SHADE_D_M = [-0.60, 0.0].freeze
      SHADE_GAP_M = 0.02
      SHADE_M = 0.08
      SHADE_WIDEN_M = 0.10
      FACADES = %w[front rear].freeze
      EPS = Core::Quant::EPSILON

      module_function

      # Bandeaux de plancher, poteaux aux limites de travée ; un poteau s'interrompt devant une baie.
      def structural_grid(footprint, levels, openings, config)
        material = config['materials']['wall']
        top = levels.last.top_z_m
        FACADES.flat_map do |side_id|
          facade = footprint.facade(side_id)
          own = openings.select { |o| o.facade_id == side_id }
          bands = levels.drop(1).map { |l| [l.base_z_m - (BAND_M / 2.0), l.base_z_m + (BAND_M / 2.0)] } + [[top - BAND_M, top]]
          nodes = bands.each_with_index.map do |(z0, z1), n|
            box(facade, "structure/#{side_id}/band/#{n}", 0.0, facade.length_m, z0, z1, GRID_D_M, material)
          end
          spans = levels.map { |l| [l.index.zero? ? 0.0 : l.base_z_m + (BAND_M / 2.0), l == levels.last ? top - BAND_M : levels[l.index + 1].base_z_m - (BAND_M / 2.0)] }
          posts(facade, config, side_id, own).each_with_index do |(u0, u1), p|
            spans.each_with_index do |(z0, z1), level|
              blocked = own.any? { |o| o.u_min_m < u1 - EPS && o.u_max_m > u0 + EPS && o.z_min_m < z1 - EPS && o.z_max_m > z0 + EPS }
              next if blocked || z1 - z0 < Core::Quant::MIN_EDGE_M

              nodes << box(facade, "structure/#{side_id}/post/#{p}/#{level}", u0, u1, z0, z1, GRID_D_M, material)
            end
          end
          nodes
        end
      end

      def posts(facade, config, side_id, own)
        f = config['facade']
        bays = side_id == 'front' ? f['front_bays'] : [own.map(&:bay_index).max.to_i + 1, 1].max
        start, pitch = FacadeSolver.frame(facade, f['margin_m'], bays, config['structure']['wall_m'])
        centres = (1...bays).map { |i| start + (i * pitch) }
        [[0.0, POST_M], [facade.length_m - POST_M, facade.length_m]] + centres.map { |c| [c - (POST_M / 2.0), c + (POST_M / 2.0)] }
      end
      private_class_method :posts

      # Casquette au-dessus de chaque fenêtre et de chaque bandeau de la façade avant.
      def sun_shades(footprint, openings, config)
        material = config['materials']['frames']
        facade = footprint.facade('front')
        openings.select { |o| o.facade_id == 'front' && %w[window ribbon].include?(o.kind) }.map do |o|
          z0 = o.z_max_m + SHADE_GAP_M
          box(facade, "sun_shade/#{o.level_index}/#{o.bay_index}", o.u_min_m - SHADE_WIDEN_M, o.u_max_m + SHADE_WIDEN_M, z0, z0 + SHADE_M, SHADE_D_M, material, 'sun_shade')
        end
      end

      AWNING = { depth: 1.50, drop: 0.50, thick: 0.02, valance: 0.25 }.freeze
      PERGOLA = { depth: 2.40, height: 2.60, post: 0.10, beam: 0.10, rafter: 0.06, rafter_h: 0.08, spacing: 0.60, post_spacing: 3.0, door_gap: 0.30 }.freeze

      # AG-098 : store banne au-dessus de chaque vitrine, ou pergola de marge à marge interrompue
      # devant la porte de l'immeuble. Façade avant, sous le bandeau.
      def shop_front(footprint, levels, openings, config)
        facade = footprint.facade('front')
        top = levels.first.top_z_m - 0.50
        front = openings.select { |o| o.facade_id == 'front' && o.level_index.zero? }
        return awnings(facade, front, top, config['materials']['awning']) if config['features']['shop_front'] == 'awning'

        pergola(facade, front, config)
      end

      def awnings(facade, front, top, material)
        a = AWNING
        front.select { |o| o.kind == 'shopfront' }.flat_map do |o|
          low = top - a[:drop]
          section = [[0.0, top], [0.0, top - a[:thick]], [-a[:depth], low - a[:thick]], [-a[:depth], low]]
          [Node.leaf("shop_front/awning/#{o.bay_index}", 'shop_front', extrude(facade, section, o.u_min_m, o.u_max_m, material)),
           box(facade, "shop_front/valance/#{o.bay_index}", o.u_min_m, o.u_max_m, low - a[:valance], low, [-a[:depth] - a[:thick], -a[:depth]], material, 'shop_front')]
        end
      end
      private_class_method :awnings

      def pergola(facade, front, config)
        p = PERGOLA
        material = config['materials']['frames']
        margin = config['facade']['margin_m']
        door = front.find { |o| %w[door porch].include?(o.kind) }
        spans = door ? [[margin, door.u_min_m - p[:door_gap]], [door.u_max_m + p[:door_gap], facade.length_m - margin]] : [[margin, facade.length_m - margin]]
        spans.select { |u0, u1| u1 - u0 >= 1.0 }.each_with_index.flat_map do |(u0, u1), s|
          base = "shop_front/pergola/#{s}"
          count = [((u1 - u0) / p[:post_spacing]).ceil, 1].max
          posts = (0..count).map { |k| u0 + ((u1 - u0 - p[:post]) * k / count) }
          nodes = posts.each_with_index.map do |u, k|
            box(facade, "#{base}/post/#{k}", u, u + p[:post], 0.0, p[:height] - p[:beam], [-p[:depth], -p[:depth] + p[:post]], material, 'shop_front')
          end
          nodes << box(facade, "#{base}/beam/front", u0, u1, p[:height] - p[:beam], p[:height], [-p[:depth], -p[:depth] + p[:beam]], material, 'shop_front')
          nodes << box(facade, "#{base}/beam/wall", u0, u1, p[:height] - p[:beam], p[:height], [-p[:beam], 0.0], material, 'shop_front')
          rafters = (((u1 - u0 - p[:rafter]) / p[:spacing]).floor + 1)
          rafters.times do |k|
            u = u0 + (k * p[:spacing])
            nodes << box(facade, "#{base}/rafter/#{k}", u, u + p[:rafter], p[:height], p[:height] + p[:rafter_h], [-p[:depth], 0.0], material, 'shop_front')
          end
          nodes
        end
      end
      private_class_method :pergola

      # Solide : section (d, z) balayée le long de la façade, de u0 à u1.
      def extrude(facade, section, u0, u1, material)
        q = ->(v) { Core::Quant.q(v) }
        a = section.map { |d, z| facade.point(q.call(u0), q.call(z), q.call(d)) }
        b = section.map { |d, z| facade.point(q.call(u1), q.call(z), q.call(d)) }
        mesh = MeshBuilder.new('solid')
        mesh.add_face(a, material)
        mesh.add_face(b.reverse, material)
        section.each_index do |i|
          j = (i + 1) % section.size
          mesh.add_face([b[i], b[j], a[j], a[i]], material)
        end
        mesh.to_primitive
      end
      private_class_method :extrude

      def box(facade, id, u0, u1, z0, z1, depth, material, category = 'structure')
        q = ->(v) { Core::Quant.q(v) }
        Node.leaf(id, category, Boxes.on_facade(facade, q.call(u0), q.call(u1), q.call(z0), q.call(z1), depth[0], depth[1], material))
      end
      private_class_method :box
    end
  end
end
