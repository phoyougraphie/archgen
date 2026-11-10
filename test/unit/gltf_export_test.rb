# frozen_string_literal: true

require_relative '../test_helper'

Archgen::Loader.load_export

# U78 — Triangulation et écriture glTF (docs/DECOR_JEU_CONTRACT.md §1, AG-115).
class GltfExportTest < Minitest::Test
  include Archgen::Core
  Tri = Archgen::Adapters::Gltf::Triangulator
  Writer = Archgen::Adapters::Gltf::GlbWriter

  def plan(**blocks)
    base = TestData.intake.effective(TestData.building('rect-neutre-shell')).value
    result = GeometryEngine.generate(BuildingConfig.new(Merge.leaves(base, blocks.transform_keys(&:to_s))), materials: TestData.materials)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def railed
    @railed ||= plan(lod: 1, features: { 'balcony' => true, 'balcony_rail' => 'bars' }, levels: { 'count' => 5 })
  end

  def all_nodes(built)
    nodes = []
    Geo.walk(built['nodes']) { |node| nodes << node }
    nodes
  end

  def export(built)
    result = Writer.building(built, name: 'maison')
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def parse(bytes)
    magic, version, length = bytes[0, 12].unpack('a4VV')
    json_length, json_type = bytes[12, 8].unpack('VV')
    json = JSON.parse(bytes[20, json_length])
    bin_length, bin_type = bytes[20 + json_length, 8].unpack('VV')
    { magic: magic, version: version, length: length, json_type: json_type, bin_type: bin_type,
      bin_length: bin_length, json: json, bin: bytes[28 + json_length, bin_length] }
  end

  def area_sign(points, tri, normal)
    a, b, c = tri.map { |i| points[i] }
    u = b.zip(a).map { |p, q| p - q }
    v = c.zip(a).map { |p, q| p - q }
    cross = [(u[1] * v[2]) - (u[2] * v[1]), (u[2] * v[0]) - (u[0] * v[2]), (u[0] * v[1]) - (u[1] * v[0])]
    cross.zip(normal).sum { |p, q| p * q }
  end

  def test_concave_face_gives_n_minus_two_triangles_with_the_same_normal
    l_shape = [[0, 0, 0], [4, 0, 0], [4, 1, 0], [1, 1, 0], [1, 3, 0], [0, 3, 0]]
    tris = Tri.call(l_shape)
    assert_equal 4, tris.size
    assert(tris.all? { |t| area_sign(l_shape, t, [0, 0, 1]) > 0 })
    assert_in_delta 6.0, tris.sum { |t| area_sign(l_shape, t, [0, 0, 1]) / 2.0 }, 1e-9
    wall = [[0, 0, 0], [0, 0, 3], [0, 2, 3], [0, 2, 0]] # normale −x
    assert(Tri.call(wall).all? { |t| area_sign(wall, t, [-1, 0, 0]) > 0 })
  end

  def test_aligned_vertex_keeps_the_count_and_degenerate_face_is_refused
    assert_equal 3, Tri.call([[0, 0, 0], [1, 0, 0], [2, 0, 0], [2, 2, 0], [0, 2, 0]]).size
    assert_nil Tri.call([[0, 0, 0], [1, 0, 0], [2, 0, 0]])
  end

  def test_glb_is_valid_and_byte_identical
    built = plan
    first = export(built)
    second = export(JSON.parse(JSON.generate(built)))
    assert_equal first['bytes'], second['bytes']
    glb = parse(first['bytes'])
    assert_equal ['glTF', 2, first['bytes'].bytesize], [glb[:magic], glb[:version], glb[:length]]
    assert_equal [0x4E4F534A, 0x004E4942], [glb[:json_type], glb[:bin_type]]
    assert_equal 0, glb[:bin_length] % 4
    assert_equal glb[:bin_length], glb[:json]['buffers'][0]['byteLength']
    assert_equal '2.0', glb[:json]['asset']['version']
    assert_equal 'maison', glb[:json]['nodes'][glb[:json]['scenes'][0]['nodes'][0]]['name']
  end

  def test_triangle_count_and_axes
    built = plan
    out = export(built)
    expected = all_nodes(built).sum do |node|
      node['primitive'] ? node['primitive']['faces'].sum { |f| f['indices'].size - 2 } : 0
    end
    assert_equal expected, out['stats'].triangle_count
    assert_equal expected, out['stats'].drawn_triangle_count
    json = parse(out['bytes'])[:json]
    positions = json['meshes'].flat_map { |m| m['primitives'].map { |p| json['accessors'][p['attributes']['POSITION']] } }
    top = positions.map { |a| a['max'][1] }.max
    assert_in_delta built['metrics']['roof_top_z_m'], top, 1e-4, 'Y vers le haut'
    assert_in_delta(-built['metrics']['depth_m'], positions.map { |a| a['min'][2] }.min, 1e-4, 'y SketchUp vers −z')
    assert_operator positions.map { |a| a['min'][1] }.min, :>=, -1e-4
  end

  def test_shared_definition_is_one_mesh_reused_by_every_instance
    out = export(railed)
    json = parse(out['bytes'])[:json]
    bars = json['nodes'].select { |n| n['name'].include?('/bar/') && n['mesh'] }
    assert_operator bars.size, :>, 50
    assert_equal 1, bars.map { |n| n['mesh'] }.uniq.size
    assert(bars.all? { |n| n['matrix'] })
    assert_operator out['stats'].drawn_triangle_count, :>, out['stats'].triangle_count
    bar = bars.first
    translation = bar['matrix'][12, 3]
    source = all_nodes(railed).find { |n| n['id'] == bar['name'] }['primitive']['matrix']
    assert_in_delta source[12], translation[0], 1e-6
    assert_in_delta source[14], translation[1], 1e-6
    assert_in_delta(-source[13], translation[2], 1e-6)
  end

  def test_degenerate_face_is_refused_with_its_piece
    built = JSON.parse(JSON.generate(plan))
    leaf = all_nodes(built).find { |n| n['primitive'] && n['primitive']['type'] != 'instance' }
    leaf['primitive']['vertices'] = leaf['primitive']['vertices'].map { |v| [v[0], 0.0, 0.0] }
    result = Writer.building(built, name: 'maison')
    refute result.ok?
    error = result.errors.first
    assert_equal ['E_EXPORT', 'export_face', leaf['id']], [error.code, error.params['reason'], error.params['id']]
  end
end
