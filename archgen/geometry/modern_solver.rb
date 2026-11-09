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

      def box(facade, id, u0, u1, z0, z1, depth, material, category = 'structure')
        q = ->(v) { Core::Quant.q(v) }
        Node.leaf(id, category, Boxes.on_facade(facade, q.call(u0), q.call(u1), q.call(z0), q.call(z1), depth[0], depth[1], material))
      end
      private_class_method :box
    end
  end
end
