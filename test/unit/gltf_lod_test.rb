# frozen_string_literal: true

require_relative '../test_helper'

Archgen::Loader.load_export

# U80 — Niveaux de détail et collisions de l'export glTF (docs/DECOR_JEU_CONTRACT.md §3, AG-117).
class GltfLodTest < Minitest::Test
  include Archgen::Core
  Gltf = Archgen::Adapters::Gltf

  def config(name, **blocks)
    BuildingConfig.new(Merge.leaves(TestData.intake.effective(TestData.building(name)).value, blocks.transform_keys(&:to_s)))
  end

  def plan(cfg)
    result = GeometryEngine.generate(cfg, materials: TestData.materials)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def lods(cfg)
    lod1 = Gltf::LodSet.lod1_plan(cfg, TestData.materials)
    assert lod1.ok?
    result = Gltf::LodSet.building(name: 'maison', plan: plan(cfg), lod1: lod1.value, materials: TestData.materials)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result
  end

  def json(file)
    bytes = file['bytes']
    JSON.parse(bytes[20, bytes[12, 4].unpack1('V')])
  end

  def convex?(triangles)
    points = triangles.flatten(1).uniq
    triangles.all? do |a, b, c|
      u = b.zip(a).map { |p, q| p - q }
      v = c.zip(a).map { |p, q| p - q }
      n = [(u[1] * v[2]) - (u[2] * v[1]), (u[2] * v[0]) - (u[0] * v[2]), (u[0] * v[1]) - (u[1] * v[0])]
      points.all? { |p| n.zip(p.zip(a).map { |x, y| x - y }).sum { |i, j| i * j } <= 1e-6 }
    end
  end

  def test_three_files_with_decreasing_triangles
    result = lods(config('haussmann-12x9'))
    assert_equal %w[LOD0 LOD1 LOD2], result.value.map { |f| f['suffix'] }
    counts = result.value.map { |f| f['stats'].drawn_triangle_count }
    assert counts.each_cons(2).all? { |a, b| b < a }, counts.inspect
    assert_empty result.warnings
    lod1 = json(result.value[1])
    refute(lod1['nodes'].any? { |n| n['name'].start_with?('frame/') }, 'LOD1 sans détails')
  end

  def test_lod2_is_the_convex_envelope_of_walls_and_roof
    cfg = config('toulousain')
    built = plan(cfg)
    volume = Gltf::Volumes.call(built)
    assert convex?(volume['triangles'])
    zs = volume['triangles'].flatten(1).map { |p| p[2] }
    assert_in_delta built['metrics']['roof_top_z_m'], zs.max, 1e-4
    assert_in_delta 0.0, zs.min, 1e-4
    lod2 = json(lods(cfg).value.last)
    names = lod2['materials'].map { |m| m['name'] }
    assert_equal 2, names.size, 'une matière de mur et une de toit'
    assert_equal ['maison'], lod2['scenes'][0]['nodes'].map { |i| lod2['nodes'][i]['name'] }
  end

  def test_collision_is_a_convex_ucx_node_without_material_in_lod0
    lod0 = json(lods(config('haussmann-12x9')).value.first)
    roots = lod0['scenes'][0]['nodes'].map { |i| lod0['nodes'][i] }
    assert_equal %w[maison UCX_maison_00], roots.map { |n| n['name'] }
    collision = lod0['meshes'][roots.last['mesh']]
    assert(collision['primitives'].none? { |p| p.key?('material') })
  end

  def test_building_already_at_lod_zero_skips_lod1_with_a_warning
    cfg = config('rect-neutre-shell')
    assert_nil Gltf::LodSet.lod1_plan(cfg, TestData.materials).value
    result = lods(cfg)
    assert_equal %w[LOD0 LOD2], result.value.map { |f| f['suffix'] }
    assert_equal ['lod1_skipped'], result.warnings.map { |w| w.params['reason'] }
  end

  def test_hull_of_a_cube_is_closed_outward_and_flat_input_is_nil
    cube = [0, 1].product([0, 1], [0, 1]).map { |p| p.map(&:to_f) } + [[0.5, 0.5, 0.5], [0.5, 0.0, 0.5]]
    triangles = Gltf::ConvexHull.call(cube)
    assert convex?(triangles)
    volume = triangles.sum do |a, b, c|
      ((a[0] * ((b[1] * c[2]) - (b[2] * c[1]))) - (a[1] * ((b[0] * c[2]) - (b[2] * c[0]))) + (a[2] * ((b[0] * c[1]) - (b[1] * c[0])))) / 6.0
    end
    assert_in_delta 1.0, volume, 1e-9, 'volume positif : normales vers l’extérieur'
    refute_includes triangles.flatten(1), [0.5, 0.5, 0.5]
    assert_nil Gltf::ConvexHull.call([[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0]])
  end
end
