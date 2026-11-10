# frozen_string_literal: true

require 'json'

module Archgen
  module Adapters
    module Gltf
      # Écrit un glTF 2.0 binaire depuis un plan en mètres (ADR-54, docs/DECOR_JEU_CONTRACT.md §1).
      # Ruby pur : ni SketchUp, ni fichier, ni horloge. Les mêmes plans donnent les mêmes octets.
      class GlbWriter
        Stats = Struct.new(:triangle_count, :drawn_triangle_count, :vertex_count, :mesh_count, :material_count, :node_count, keyword_init: true) do
          def to_h
            super.transform_keys(&:to_s)
          end
        end

        # Erreur localisée : rendue par `Scene#to_glb` sous forme de diagnostic E_EXPORT.
        class ExportError < StandardError
          attr_reader :reason, :id

          def initialize(reason, id)
            @reason = reason
            @id = id
            super("#{reason} : #{id}")
          end
        end

        POSITION_DECIMALS = 4
        NORMAL_DECIMALS = 6
        FLOAT = 5126
        UNSIGNED_INT = 5125
        ARRAY_BUFFER = 34_962
        ELEMENT_ARRAY_BUFFER = 34_963
        TRIANGLES = 4
        DEFAULT_ROUGHNESS = 0.85
        DEFAULT_METALLIC = 0.0
        DOUBLE_SUFFIX = ' (double face)'
        IDENTITY = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0].freeze
        # SketchUp (x, y, z), Z vers le haut → glTF (x, z, −y), Y vers le haut.
        AXES = [[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, -1.0, 0.0]].freeze

        # Un bâtiment seul : un nœud racine nommé, le plan dessous.
        def self.building(plan, name:, materials:)
          scene = new(materials: materials)
          scene.add(name: name, nodes: plan['nodes'], definitions: plan['definitions'] || {})
          scene.to_glb
        rescue ExportError => e
          failure(e)
        end

        def self.failure(error)
          Core::Result.fail([Core::Diagnostic.error('E_EXPORT', '/export', reason: error.reason, id: error.id)])
        end

        # `materials` : catalogue fusionné (bâtiment et assise), teintes `id~L.n` comprises (ADR-51).
        def initialize(materials:)
          @catalog = materials
          @roots = []
          @nodes = []
          @meshes = []
          @materials = {}
          @accessors = []
          @views = []
          @binary = +''.b
          @definition_meshes = {}
          @triangles = 0
          @mesh_triangles = []
          @vertices = 0
        end

        # Lève ExportError, localisée, que l'appelant rend par `GlbWriter.failure`.
        # Ajoute un objet ARCHGEN sous un nœud racine ; `matrix` (colonnes, mètres, repère SketchUp) le place.
        def add(name:, nodes:, definitions:, matrix: nil)
          @definitions = definitions
          children = nodes.map { |node| convert(node) }
          @roots << push_node(node_hash(name, matrix: matrix, children: children))
        end

        # Ajoute à la racine de la scène un maillage fait de triangles (volume LOD2, collision `UCX_`).
        # `material` rend l'id de matière d'un triangle, ou nil pour un maillage sans matériau.
        def add_triangles(name:, triangles:, material: ->(_tri) {})
          vertices = triangles.flatten(1)
          faces = triangles.each_index.map { |i| { 'indices' => [3 * i, (3 * i) + 1, (3 * i) + 2], 'material' => material.call(triangles[i]) } }
          mesh = add_mesh(name, [[name, { 'type' => 'solid', 'vertices' => vertices, 'faces' => faces }, IDENTITY]])
          @roots << push_node(node_hash(name, mesh: mesh))
        end

        # Rend Result.ok({ 'bytes', 'stats' }) ou un diagnostic E_EXPORT localisé.
        def to_glb
          json = document
          Core::Result.ok({ 'bytes' => pack(json), 'stats' => stats })
        rescue ExportError => e
          self.class.failure(e)
        end

        # `triangle_count` compte le tampon (un maillage partagé une fois) ; `drawn_triangle_count`, l'affichage.
        def stats
          drawn = @nodes.sum { |node| node['mesh'] ? @mesh_triangles[node['mesh']] : 0 }
          Stats.new(triangle_count: @triangles, drawn_triangle_count: drawn, vertex_count: @vertices, mesh_count: @meshes.size,
                    material_count: @materials.size, node_count: @nodes.size)
        end

        private

        def convert(node)
          primitive = node['primitive']
          return convert_instance(node, primitive) if primitive && primitive['type'] == 'instance'

          if primitive
            unless %w[surface solid].include?(primitive['type'])
              raise ExportError.new('export_primitive', node['id'])
            end

            mesh = add_mesh(node['id'], [[node['id'], primitive, IDENTITY]])
            return push_node(node_hash(node['id'], mesh: mesh))
          end

          children = (node['children'] || []).map { |child| convert(child) }
          push_node(node_hash(node['id'], children: children))
        end

        # Une définition partagée devient un seul maillage, référencé par chaque instance.
        def convert_instance(node, primitive)
          id = primitive['definition_id']
          mesh = @definition_meshes[id] ||= begin
            parts = []
            flatten(definition(id, node['id']), IDENTITY, parts)
            add_mesh(id, parts)
          end
          push_node(node_hash(node['id'], mesh: mesh, matrix: primitive['matrix']))
        end

        def definition(id, owner)
          @definitions.fetch(id) { raise ExportError.new('export_definition', owner) }
        end

        def flatten(nodes, matrix, parts)
          nodes.each do |node|
            primitive = node['primitive']
            if primitive && primitive['type'] == 'instance'
              flatten(definition(primitive['definition_id'], node['id']), multiply(matrix, primitive['matrix']), parts)
            elsif primitive
              parts << [node['id'], primitive, matrix]
            else
              flatten(node['children'] || [], matrix, parts)
            end
          end
        end

        # Un primitif glTF par matière, dans l'ordre de première apparition.
        def add_mesh(name, parts)
          groups = {}
          parts.each do |owner, primitive, matrix|
            vertices = primitive['vertices'].map { |v| transform_point(matrix, v) }
            primitive['faces'].each do |face|
              points = face['indices'].map { |i| vertices.fetch(i) }
              triangles = Triangulator.call(points) || raise(ExportError.new('export_face', owner))
              normal = unit(Triangulator.newell(points)) || raise(ExportError.new('export_face', owner))
              key = [face['material'], primitive['type'] == 'surface']
              group = groups[key] ||= { positions: [], normals: [], uvs: [], indices: [], owner: owner }
              base = group[:positions].size
              points.each do |p|
                group[:positions] << axes(p).map { |c| c.round(POSITION_DECIMALS) + 0.0 }
                group[:normals] << axes(normal).map { |c| c.round(NORMAL_DECIMALS) + 0.0 }
                group[:uvs] << box_uv(p, normal).map { |c| c.round(POSITION_DECIMALS) + 0.0 }
              end
              triangles.each { |tri| group[:indices].concat(tri.map { |i| base + i }) }
            end
          end
          before = @triangles
          primitives = groups.map { |(material, double), group| write_primitive(material, double, group) }
          @mesh_triangles << (@triangles - before)
          @meshes << { 'name' => name, 'primitives' => primitives }
          @meshes.size - 1
        end

        def write_primitive(material, double, group)
          @triangles += group[:indices].size / 3
          @vertices += group[:positions].size
          position = accessor(group[:positions], 'VEC3', bounds: true)
          normal = accessor(group[:normals], 'VEC3')
          uv = accessor(group[:uvs], 'VEC2')
          indices = index_accessor(group[:indices])
          primitive = { 'attributes' => { 'NORMAL' => normal, 'POSITION' => position, 'TEXCOORD_0' => uv }, 'indices' => indices,
                        'mode' => TRIANGLES }
          primitive['material'] = material_index(material, double, group[:owner]) unless material.nil?
          primitive
        end

        # Un matériau glTF par matière et par face simple ou double (D-30) ; la double face prend un suffixe.
        def material_index(id, double, owner)
          key = [id, double]
          return @materials[key][:index] if @materials.key?(key)

          entry = Core::Tint.entry(@catalog, id) || raise(ExportError.new('export_material', owner))
          @materials[key] = { index: @materials.size, value: pbr(id, entry, double) }
          @materials[key][:index]
        end

        def pbr(id, entry, double)
          alpha = entry.fetch('alpha', 1.0).to_f
          color = entry.fetch('srgb').delete_prefix('#').scan(/../).map { |pair| linear(pair.to_i(16) / 255.0) }
          material = {
            'name' => double ? "#{id}#{DOUBLE_SUFFIX}" : id,
            'pbrMetallicRoughness' => {
              'baseColorFactor' => (color + [alpha]).map { |c| c.round(NORMAL_DECIMALS) + 0.0 },
              'metallicFactor' => entry.fetch('metallic', DEFAULT_METALLIC).to_f,
              'roughnessFactor' => entry.fetch('roughness', DEFAULT_ROUGHNESS).to_f
            }
          }
          material['alphaMode'] = 'BLEND' if alpha < 1.0
          material['doubleSided'] = true if double
          material
        end

        def linear(c)
          c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
        end

        # Projection cubique (D-29) : plan de l'axe dominant, 1 m = 1 unité, image à l'endroit vue de dehors.
        def box_uv(p, normal)
          axis = (0..2).max_by { |i| normal[i].abs }
          positive = normal[axis] >= 0
          case axis
          when 0 then [positive ? p[1] : -p[1], -p[2]]
          when 1 then [positive ? -p[0] : p[0], -p[2]]
          else [p[0], positive ? -p[1] : p[1]]
          end
        end

        def accessor(rows, type, bounds: false)
          data = rows.flatten.pack('e*')
          view = buffer_view(data, ARRAY_BUFFER)
          entry = { 'bufferView' => view, 'byteOffset' => 0, 'componentType' => FLOAT, 'count' => rows.size, 'type' => type }
          if bounds
            stored = data.unpack('e*').each_slice(3).to_a
            entry['min'] = (0..2).map { |i| stored.map { |r| r[i] }.min }
            entry['max'] = (0..2).map { |i| stored.map { |r| r[i] }.max }
          end
          @accessors << entry
          @accessors.size - 1
        end

        def index_accessor(indices)
          view = buffer_view(indices.pack('V*'), ELEMENT_ARRAY_BUFFER)
          @accessors << { 'bufferView' => view, 'byteOffset' => 0, 'componentType' => UNSIGNED_INT,
                          'count' => indices.size, 'type' => 'SCALAR' }
          @accessors.size - 1
        end

        def buffer_view(data, target)
          @binary << ("\0" * ((4 - (@binary.bytesize % 4)) % 4))
          offset = @binary.bytesize
          @binary << data
          @views << { 'buffer' => 0, 'byteLength' => data.bytesize, 'byteOffset' => offset, 'target' => target }
          @views.size - 1
        end

        def node_hash(name, mesh: nil, matrix: nil, children: nil)
          node = { 'name' => name.to_s }
          node['mesh'] = mesh if mesh
          node['matrix'] = gltf_matrix(matrix) if matrix && !identity?(matrix)
          node['children'] = children if children && !children.empty?
          node
        end

        def push_node(node)
          @nodes << node
          @nodes.size - 1
        end

        def document
          materials = @materials.values.sort_by { |m| m[:index] }.map { |m| m[:value] }
          doc = {
            'asset' => { 'generator' => "ARCHGEN #{Archgen::VERSION}", 'version' => '2.0' },
            'scene' => 0,
            'scenes' => [{ 'nodes' => @roots }],
            'nodes' => @nodes,
            'meshes' => @meshes,
            'materials' => materials,
            'accessors' => @accessors,
            'bufferViews' => @views,
            'buffers' => [{ 'byteLength' => padded(@binary).bytesize }]
          }
          JSON.generate(sorted(doc))
        end

        def pack(json)
          json_chunk = json.b + (' ' * ((4 - (json.bytesize % 4)) % 4))
          bin_chunk = padded(@binary)
          total = 12 + 8 + json_chunk.bytesize + 8 + bin_chunk.bytesize
          header = ['glTF', 2, total].pack('a4VV')
          header + [json_chunk.bytesize, 0x4E4F534A].pack('VV') + json_chunk +
            [bin_chunk.bytesize, 0x004E4942].pack('VV') + bin_chunk
        end

        def padded(binary)
          binary + ("\0" * ((4 - (binary.bytesize % 4)) % 4))
        end

        def sorted(value)
          case value
          when Hash then value.keys.sort.to_h { |k| [k, sorted(value[k])] }
          when Array then value.map { |v| sorted(v) }
          else value
          end
        end

        def axes(p)
          AXES.map { |row| (row[0] * p[0]) + (row[1] * p[1]) + (row[2] * p[2]) }
        end

        def unit(v)
          length = Math.sqrt(v.sum { |c| c * c })
          return nil if length < Triangulator::AREA_EPS

          v.map { |c| c / length }
        end

        # Matrices en colonnes (élément (r, c) à l'indice 4c + r), comme le plan et glTF.
        def transform_point(m, v)
          (0..2).map { |r| (m[r] * v[0]) + (m[4 + r] * v[1]) + (m[8 + r] * v[2]) + m[12 + r] }
        end

        def multiply(a, b)
          (0..15).map do |i|
            c = i / 4
            r = i % 4
            (0..3).sum { |k| a[(4 * k) + r] * b[(4 * c) + k] }
          end
        end

        # C · M · Cᵀ, C étant le changement d'axes : la pose reste rigide dans le repère glTF.
        def gltf_matrix(m)
          c = IDENTITY.dup
          AXES.each_with_index { |row, r| row.each_with_index { |value, k| c[(4 * k) + r] = value } }
          ct = (0..15).map { |i| c[(4 * (i % 4)) + (i / 4)] }
          multiply(multiply(c, m), ct).map { |value| value.round(NORMAL_DECIMALS) + 0.0 }
        end

        def identity?(m)
          m.each_with_index.all? { |value, i| (value - IDENTITY[i]).abs < 1e-12 }
        end
      end
    end
  end
end
