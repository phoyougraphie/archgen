# frozen_string_literal: true

module Archgen
  module Geometry
    # Une façade : arête A→B de l'anneau, en repère local du bâtiment.
    # `start_factor` et `end_factor` : recul du joint intérieur par unité d'épaisseur, absents à angle droit.
    Facade = Struct.new(:id, :a, :tangent, :normal, :length_m, :start_factor, :end_factor, keyword_init: true) do
      # Point de mur = A + uT + zK − dN (contrat géométrique, Repères).
      def point(u, z, d = 0.0)
        [
          Core::Quant.q(a[0] + (u * tangent[0]) - (d * normal[0])),
          Core::Quant.q(a[1] + (u * tangent[1]) - (d * normal[1])),
          Core::Quant.q(z)
        ]
      end

      # Abscisses du mur côté intérieur, à l'épaisseur t : à angle droit, t et L − t.
      def inner_start(thickness)
        thickness * (start_factor || 1.0)
      end

      def inner_end(thickness)
        length_m - (thickness * (end_factor || 1.0))
      end
    end

    # `delta_left_m`, `delta_right_m` : reculs de l'arrière d'une parcelle d'angle, absents ailleurs.
    Footprint = Struct.new(:width_m, :depth_m, :ring, :facades, :delta_left_m, :delta_right_m, keyword_init: true) do
      def facade(id)
        facades.find { |f| f.id == id }
      end

      def trapezoid?
        !delta_left_m.nil?
      end

      # Abscisses des murs latéraux, prolongées au-delà de la façade et de l'arrière : le plan d'onglet.
      def left_x(y)
        delta_left_m.to_f * y / depth_m
      end

      def right_x(y)
        width_m - (delta_right_m.to_f * y / depth_m)
      end
    end

    Level = Struct.new(:index, :base_z_m, :top_z_m, :slab_bottom_z_m, keyword_init: true)
    Candidate = Struct.new(:facade_id, :level_index, :bay_index, :center_u_m, keyword_init: true)

    Opening = Struct.new(:id, :facade_id, :level_index, :bay_index, :kind, :u_min_m, :u_max_m, :z_min_m, :z_max_m, keyword_init: true) do
      def to_h
        { 'id' => id, 'facade_id' => facade_id, 'level_index' => level_index, 'bay_index' => bay_index, 'kind' => kind,
          'u_min_m' => u_min_m, 'u_max_m' => u_max_m, 'z_min_m' => z_min_m, 'z_max_m' => z_max_m }
      end

      def covers?(u, z)
        u > u_min_m && u < u_max_m && z > z_min_m && z < z_max_m
      end
    end

    # Construction des nœuds du plan, en données simples sérialisables.
    module Node
      CATEGORIES = %w[building walls wall slabs slab roof roof_face gable_end details frame cornice balcony surround fascia chimney shutter dormer genoise stepped_gable timber arch classical structure sun_shade].freeze

      module_function

      def group(id, category, children)
        { 'id' => id, 'category' => category, 'children' => children }
      end

      def leaf(id, category, primitive)
        { 'id' => id, 'category' => category, 'children' => [], 'primitive' => primitive }
      end
    end

    # Accumule sommets indexés (par position quantifiée) et faces d'une primitive.
    class MeshBuilder
      def initialize(type)
        @type = type
        @vertices = []
        @index = {}
        @faces = []
      end

      def add_face(points, material)
        indices = points.map { |p| vertex(p) }
        @faces << { 'indices' => indices, 'material' => material }
        self
      end

      def to_primitive
        { 'type' => @type, 'vertices' => @vertices, 'faces' => @faces }
      end

      private

      def vertex(point)
        quantized = Core::Quant.q3(point)
        @index[quantized] ||= begin
          @vertices << quantized
          @vertices.size - 1
        end
      end
    end

    # Ordre canonique des façades pour tous les tris.
    FACADE_ORDER = %w[front right rear left].freeze
  end
end
