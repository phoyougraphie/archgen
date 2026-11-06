# frozen_string_literal: true

module Archgen
  module Geometry
    # Grille d'une façade : coupes U et Z quantifiées, cellules classées vide/plein.
    class FacadeGrid
      attr_reader :facade, :us, :zs

      def initialize(facade, us, zs, openings)
        @facade = facade
        @us = us
        @zs = zs
        @openings = openings
        @solid = classify
      end

      def self.build(facade, levels, openings, config)
        own = openings.select { |o| o.facade_id == facade.id }
        top = levels.last.top_z_m
        us = [0.0, facade.length_m] + own.flat_map { |o| [o.u_min_m, o.u_max_m] }
        zs = [0.0, top] + levels.map(&:base_z_m) + own.flat_map { |o| [o.z_min_m, o.z_max_m] }
        us = us.map { |v| Core::Quant.q(v) }.uniq.sort
        zs = zs.map { |v| Core::Quant.q(v) }.uniq.sort
        problems = cut_problems(us, facade, 'u', config) + cut_problems(zs, facade, 'z', config)
        return Core::Result.fail(problems) unless problems.empty?

        Core::Result.ok(new(facade, us, zs, own))
      end

      def self.cut_problems(cuts, facade, axis, config)
        cuts.each_cons(2).filter_map do |low, high|
          next unless high - low < Core::Quant::MIN_EDGE_M

          path = axis == 'z' ? '/facade/sill_m' : (config['facade']['jitter_m'].positive? ? '/facade/jitter_m' : '/facade/window_width_m')
          Core::Diagnostic.error('E_OPENING_CLEARANCE', path, reason: 'cuts_too_close', id: facade.id, axis: axis, low: low, high: high)
        end
      end
      private_class_method :cut_problems

      def columns
        us.size - 1
      end

      def rows
        zs.size - 1
      end

      def cell_count
        columns * rows
      end

      # Indices hors grille = absents, donc traités comme non pleins.
      def solid?(column, row)
        column.between?(0, columns - 1) && row.between?(0, rows - 1) && @solid[row][column]
      end

      private

      def classify
        Array.new(rows) do |row|
          mid_z = (zs[row] + zs[row + 1]) / 2.0
          Array.new(columns) do |column|
            mid_u = (us[column] + us[column + 1]) / 2.0
            @openings.none? { |o| o.covers?(mid_u, mid_z) }
          end
        end
      end
    end

    # Murs et dalles selon le mode, à partir de grilles partagées.
    module WallBuilder
      module_function

      def grids(footprint, levels, openings, config)
        problems = []
        built = footprint.facades.map do |facade|
          result = FacadeGrid.build(facade, levels, openings, config)
          problems.concat(result.errors)
          result.value
        end
        problems.empty? ? Core::Result.ok(built) : Core::Result.fail(problems)
      end

      def call(footprint, levels, grids, config)
        material = config['materials']['wall']
        structural = config['mode'] == 'structural'
        thickness = config['structure']['wall_m']
        walls = grids.map do |grid|
          primitive = structural ? solid_wall(grid, thickness, material) : surface_wall(grid, material)
          Node.leaf("wall/#{grid.facade.id}", 'wall', primitive)
        end
        nodes = [Node.group('walls', 'walls', walls)]
        nodes << Node.group('slabs', 'slabs', slabs(footprint, levels, config, material)) if structural && levels.size > 1
        nodes
      end

      def surface_wall(grid, material)
        mesh = MeshBuilder.new('surface')
        each_solid_cell(grid) { |c, r| mesh.add_face(outer_quad(grid, c, r), material) }
        mesh.to_primitive
      end
      private_class_method :surface_wall

      def solid_wall(grid, thickness, material)
        mesh = MeshBuilder.new('solid')
        each_solid_cell(grid) do |c, r|
          mesh.add_face(outer_quad(grid, c, r), material)
          mesh.add_face(inner_quad(grid, c, r, thickness), material)
          lateral_quads(grid, c, r, thickness).each { |quad| mesh.add_face(quad, material) }
        end
        mesh.to_primitive
      end
      private_class_method :solid_wall

      def each_solid_cell(grid)
        (0...grid.rows).each do |row|
          (0...grid.columns).each { |column| yield(column, row) if grid.solid?(column, row) }
        end
      end
      private_class_method :each_solid_cell

      def outer_quad(grid, c, r)
        f = grid.facade
        u0, u1, z0, z1 = bounds(grid, c, r)
        [f.point(u0, z0), f.point(u1, z0), f.point(u1, z1), f.point(u0, z1)]
      end
      private_class_method :outer_quad

      # Vu de l'intérieur : sens opposé à la face extérieure.
      def inner_quad(grid, c, r, t)
        u0, u1, z0, z1 = bounds(grid, c, r)
        [inner(grid, u0, z0, t), inner(grid, u0, z1, t), inner(grid, u1, z1, t), inner(grid, u1, z0, t)]
      end
      private_class_method :inner_quad

      # Une face latérale seulement si le voisin est absent ou vide : ferme la pièce
      # et produit onglets, jambages, linteau et appui. Le sens donne une normale
      # sortante en coordonnées (T, K, N), repère direct.
      def lateral_quads(grid, c, r, t)
        f = grid.facade
        u0, u1, z0, z1 = bounds(grid, c, r)
        quads = []
        unless grid.solid?(c - 1, r)
          quads << [inner(grid, u0, z0, t), f.point(u0, z0), f.point(u0, z1), inner(grid, u0, z1, t)]
        end
        unless grid.solid?(c + 1, r)
          quads << [inner(grid, u1, z0, t), inner(grid, u1, z1, t), f.point(u1, z1), f.point(u1, z0)]
        end
        unless grid.solid?(c, r - 1)
          quads << [inner(grid, u0, z0, t), inner(grid, u1, z0, t), f.point(u1, z0), f.point(u0, z0)]
        end
        unless grid.solid?(c, r + 1)
          quads << [inner(grid, u0, z1, t), f.point(u0, z1), f.point(u1, z1), inner(grid, u1, z1, t)]
        end
        quads
      end
      private_class_method :lateral_quads

      def bounds(grid, c, r)
        [grid.us[c], grid.us[c + 1], grid.zs[r], grid.zs[r + 1]]
      end
      private_class_method :bounds

      # À l'intérieur, u=0 et u=L suivent le joint (t et L−t à angle droit) ; les autres coupes gardent u.
      def inner(grid, u, z, t)
        mapped = if u.zero? then grid.facade.inner_start(t)
                 elsif u == grid.facade.length_m then grid.facade.inner_end(t)
                 else u
                 end
        grid.facade.point(mapped, z, t)
      end
      private_class_method :inner

      def slabs(footprint, levels, config, material)
        t = config['structure']['wall_m']
        return trapezoid_slabs(footprint, levels, t, material) if footprint.trapezoid?

        box = [t, footprint.width_m - t, t, footprint.depth_m - t]
        levels.drop(1).map do |level|
          Node.leaf("slab/#{level.index}", 'slab', Boxes.solid(*box, level.slab_bottom_z_m, level.base_z_m, material))
        end
      end
      private_class_method :slabs

      def trapezoid_slabs(footprint, levels, thickness, material)
        ring = footprint.facades.map { |facade| facade.point(facade.inner_start(thickness), 0.0, thickness).first(2) }
        levels.drop(1).map do |level|
          Node.leaf("slab/#{level.index}", 'slab', Boxes.prism(ring, level.slab_bottom_z_m, level.base_z_m, material))
        end
      end
      private_class_method :trapezoid_slabs
    end
  end
end
