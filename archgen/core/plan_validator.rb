# frozen_string_literal: true

module Archgen
  module Core
    # Dernière barrière avant le writer : topologie, indices, limites et matériaux.
    # Ne fait confiance à aucun solveur : tout est recalculé depuis le plan.
    class PlanValidator
      PLANAR_TOLERANCE_M = 5e-6
      RIGID_TOLERANCE = 1e-5
      CATEGORIES = %w[building walls wall slabs slab roof roof_face gable_end details frame cornice balcony surround fascia chimney].freeze

      def self.call(plan, materials: nil)
        new(plan, materials).call
      end

      def initialize(plan, materials)
        @plan = plan
        @materials = materials
        @out = []
        @ids = {}
      end

      def call
        return @out unless header_ok?

        @plan['nodes'].each { |node| check_node(node, allow_instance: true) }
        @plan['definitions'].each do |id, nodes|
          problem(id, 'definition_not_array') unless nodes.is_a?(Array)
          @ids = {}
          nodes.each { |node| check_node(node, allow_instance: false) } if nodes.is_a?(Array)
        end
        check_metrics
        @out.sort_by(&:sort_key)
      end

      private

      def categories
        CATEGORIES
      end

      def problem(id, reason, **params)
        @out << Diagnostic.error('E_PLAN', '/plan', reason: reason, id: id.to_s, **params)
      end

      def header_ok?
        problem('plan', 'bad_header') unless @plan['schema_version'] == 1 && @plan['units'] == 'm'
        %w[nodes definitions openings metrics].each { |k| problem('plan', "missing_#{k}") unless @plan.key?(k) }
        return false unless @out.empty?

        tops = @plan['nodes']
        problem('plan', 'single_building_root') unless tops.size == 1 && tops.first['category'] == 'building'
        @out.empty?
      end

      def check_node(node, allow_instance:)
        id = node['id']
        problem(id, 'duplicate_node_id') if @ids.key?(id)
        @ids[id] = true
        problem(id, 'unknown_category', category: node['category']) unless categories.include?(node['category'])
        primitive = node['primitive']
        if primitive
          problem(id, 'primitive_with_children') unless node['children'].empty?
          check_primitive(id, primitive, allow_instance)
        end
        node['children'].each { |child| check_node(child, allow_instance: allow_instance) }
      end

      def check_primitive(id, primitive, allow_instance)
        case primitive['type']
        when 'surface' then check_mesh(id, primitive)
        when 'solid'
          check_solid(id, primitive) if check_mesh(id, primitive)
        when 'instance'
          problem(id, 'nested_instance') unless allow_instance
          check_instance(id, primitive)
        else problem(id, 'unknown_primitive', type: primitive['type'])
        end
      end

      # Retourne true si les faces sont exploitables pour une analyse topologique.
      def check_mesh(id, primitive)
        vertices = primitive['vertices']
        before = @out.size
        vertices.each { |v| check_vertex(id, v) }
        return false if @out.size > before

        primitive['faces'].each { |face| check_face(id, vertices, face) }
        check_edge_directions(id, primitive['faces'], primitive['type']) if @out.size == before
        @out.size == before
      end

      def check_vertex(id, vertex)
        valid = vertex.is_a?(Array) && vertex.size == 3 && vertex.all? { |c| c.is_a?(Float) && c.finite? }
        return problem(id, 'invalid_vertex') unless valid

        problem(id, 'unquantized_vertex') unless vertex == Quant.q3(vertex)
      end

      def check_face(id, vertices, face)
        indices = face['indices']
        unless indices.size.between?(3, 4) && indices.uniq.size == indices.size && indices.all? { |i| i.is_a?(Integer) && i.between?(0, vertices.size - 1) }
          return problem(id, 'invalid_indices')
        end

        check_material(id, face['material'])
        points = indices.map { |i| vertices[i] }
        check_edges(id, points)
        check_plane(id, points)
      end

      def check_material(id, material)
        return problem(id, 'missing_material') unless material.is_a?(String)
        return if @materials.nil? || @materials.key?(material)

        problem(id, 'unknown_material', material: material)
      end

      def check_edges(id, points)
        points.each_with_index do |p, i|
          length = distance(p, points[(i + 1) % points.size])
          problem(id, 'edge_too_short', length: length) if length < Quant::MIN_EDGE_M - Quant::EPSILON
        end
      end

      def check_plane(id, points)
        vector = newell(points)
        size = norm(vector)
        return problem(id, 'degenerate_face') if size < 1e-12

        unit = vector.map { |c| c / size }
        points.each do |p|
          offset = dot(unit, sub(p, points[0]))
          problem(id, 'non_planar_face', offset: offset) if offset.abs > PLANAR_TOLERANCE_M
        end
      end

      def check_edge_directions(id, faces, type)
        directed = Hash.new(0)
        each_edge(faces) { |a, b, _| directed[[a, b]] += 1 }
        return problem(id, 'inconsistent_orientation') if directed.values.any? { |count| count > 1 }
        return unless type == 'solid'

        directed.each_key do |(a, b)|
          next if directed.key?([b, a])

          problem(id, 'open_edge', a: a, b: b)
          break
        end
      end

      def each_edge(faces)
        faces.each_with_index do |face, f|
          indices = face['indices']
          indices.each_with_index { |a, i| yield(a, indices[(i + 1) % indices.size], f) }
        end
      end

      def check_solid(id, primitive)
        faces = primitive['faces']
        check_single_shell(id, faces)
        check_vertex_fans(id, faces)
        problem(id, 'non_positive_volume') unless signed_volume(primitive) > Quant::EPSILON
      end

      def check_single_shell(id, faces)
        reached = connected_from(0, faces.size, face_neighbours(faces))
        problem(id, 'disconnected_shell') unless reached.size == faces.size
      end

      def face_neighbours(faces)
        by_edge = Hash.new { |h, k| h[k] = [] }
        each_edge(faces) { |a, b, f| by_edge[[a, b].sort] << f }
        neighbours = Hash.new { |h, k| h[k] = [] }
        by_edge.each_value do |list|
          list.combination(2) do |x, y|
            neighbours[x] << y
            neighbours[y] << x
          end
        end
        neighbours
      end

      # À chaque sommet, les faces incidentes forment un seul éventail connexe.
      def check_vertex_fans(id, faces)
        around = Hash.new { |h, k| h[k] = [] }
        each_edge(faces) { |a, _b, f| around[a] << f }
        around.each do |vertex, list|
          links = Hash.new { |h, k| h[k] = [] }
          by_edge = Hash.new { |h, k| h[k] = [] }
          list.each do |f|
            indices = faces[f]['indices']
            position = indices.index(vertex)
            by_edge[[vertex, indices[(position + 1) % indices.size]].sort] << f
            by_edge[[vertex, indices[position - 1]].sort] << f
          end
          by_edge.each_value do |pair|
            pair.combination(2) do |x, y|
              links[x] << y
              links[y] << x
            end
          end
          next if connected_from(list.first, nil, links).size == list.size

          problem(id, 'split_vertex_fan', vertex: vertex)
          break
        end
      end

      def connected_from(start, _count, neighbours)
        seen = { start => true }
        stack = [start]
        until stack.empty?
          neighbours[stack.pop].each do |next_face|
            next if seen[next_face]

            seen[next_face] = true
            stack << next_face
          end
        end
        seen
      end

      def signed_volume(primitive)
        vertices = primitive['vertices']
        primitive['faces'].sum do |face|
          points = face['indices'].map { |i| vertices[i] }
          (1...(points.size - 1)).sum { |i| dot(points[0], cross(points[i], points[i + 1])) / 6.0 }
        end
      end

      def check_instance(id, primitive)
        problem(id, 'missing_definition', definition: primitive['definition_id']) unless @plan['definitions'].key?(primitive['definition_id'])
        matrix = primitive['matrix']
        unless matrix.is_a?(Array) && matrix.size == 16 && matrix.all? { |c| c.is_a?(Numeric) && c.finite? }
          return problem(id, 'invalid_matrix')
        end

        problem(id, 'non_rigid_matrix') unless rigid_direct?(matrix)
      end

      # Colonnes orthonormées, déterminant +1, dernière ligne (0,0,0,1).
      def rigid_direct?(m)
        x = m[0, 3]
        y = m[4, 3]
        z = m[8, 3]
        return false unless [m[3], m[7], m[11]].all? { |c| c.abs < RIGID_TOLERANCE } && (m[15] - 1.0).abs < RIGID_TOLERANCE
        return false unless [x, y, z].all? { |c| (norm(c) - 1.0).abs < RIGID_TOLERANCE }
        return false unless [dot(x, y), dot(y, z), dot(x, z)].all? { |c| c.abs < RIGID_TOLERANCE }

        (dot(cross(x, y), z) - 1.0).abs < RIGID_TOLERANCE
      end

      def check_metrics
        counted = count_faces
        declared = @plan['metrics']
        counted.each do |key, value|
          problem('metrics', 'metric_mismatch', metric: key, declared: declared[key], counted: value) unless declared[key] == value
        end
        @out.concat(Budget.check(declared))
      end

      def count_faces
        definition_faces = @plan['definitions'].transform_values { |nodes| nodes.sum { |n| node_faces(n) } }
        own = @plan['nodes'].sum { |n| node_faces(n) }
        instances = []
        @plan['nodes'].each { |n| collect_instances(n, instances) }
        {
          'unique_face_count' => own + definition_faces.values.sum,
          'expanded_face_count' => own + instances.sum { |id| definition_faces.fetch(id, 0) },
          'opening_count' => @plan['openings'].size,
          'detail_definition_count' => @plan['definitions'].size
        }
      end

      def node_faces(node)
        primitive = node['primitive']
        own = primitive && primitive['type'] != 'instance' ? primitive['faces'].size : 0
        own + node['children'].sum { |c| node_faces(c) }
      end

      def collect_instances(node, out)
        out << node['primitive']['definition_id'] if node.dig('primitive', 'type') == 'instance'
        node['children'].each { |c| collect_instances(c, out) }
      end

      def sub(a, b)
        [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
      end

      def dot(a, b)
        (a[0] * b[0]) + (a[1] * b[1]) + (a[2] * b[2])
      end

      def cross(a, b)
        [(a[1] * b[2]) - (a[2] * b[1]), (a[2] * b[0]) - (a[0] * b[2]), (a[0] * b[1]) - (a[1] * b[0])]
      end

      def norm(a)
        Math.sqrt(dot(a, a))
      end

      def distance(a, b)
        norm(sub(a, b))
      end

      def newell(points)
        total = [0.0, 0.0, 0.0]
        points.each_with_index do |p, i|
          q = points[(i + 1) % points.size]
          total[0] += (p[1] - q[1]) * (p[2] + q[2])
          total[1] += (p[2] - q[2]) * (p[0] + q[0])
          total[2] += (p[0] - q[0]) * (p[1] + q[1])
        end
        total
      end
    end
  end
end
