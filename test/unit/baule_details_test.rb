# frozen_string_literal: true

require_relative '../test_helper'

# U101 : détails des maisons de La Baule (AG-143, ADR-68) : bandeaux, lucarnes passantes, tourelle,
# balconnets, bow-window de rez-de-chaussée.
class BauleDetailsTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def build(draft)
    config = ConfigResolver.resolve({ 'schema_version' => 1, 'lod' => 1 }.merge(draft), registry: registry, intake: TestData.intake)
    return config unless config.ok?

    GeometryEngine.generate(config.value, materials: TestData.materials)
  end

  def nodes(plan, out = [])
    plan.each do |n|
      out << n
      nodes(n['children'], out)
    end
    out
  end

  def ids(result)
    assert result.ok?, result.errors.map(&:to_h).inspect
    nodes(result.value['nodes']).map { |n| n['id'] }
  end

  def reasons(result)
    result.errors.map { |d| d.params['reason'] }
  end

  def town
    { 'profile' => { 'id' => 'baule_maison_de_ville' }, 'seed' => 1, 'materials' => { 'wall' => 'granite', 'surrounds' => 'red_brick' } }
  end

  def test_string_courses_at_each_floor_and_eave_in_brick
    result = build(Merge.leaves(town, 'features' => { 'string_courses' => true }))
    bands = nodes(result.value['nodes']).select { |n| n['id'].start_with?('band/') }
    assert_equal 4 * 2, bands.size, 'quatre façades, un plancher et l’égout'
    assert(bands.all? { |n| n['primitive']['faces'].all? { |f| f['material'] == 'red_brick' } })
    assert_includes reasons(build('profile' => { 'id' => 'baule_villa', 'revision' => 1 }, 'features' => { 'string_courses' => true })), 'string_courses_with_timber'
  end

  def test_wall_dormers_stand_in_the_facade_plane
    plain = build(Merge.leaves(town, 'features' => { 'wall_dormers' => false }))
    wall = build(Merge.leaves(town, 'features' => { 'wall_dormers' => true }))
    front = ->(r) { nodes(r.value['nodes']).select { |n| n['category'] == 'dormer' }.flat_map { |n| n['primitive']['vertices'] }.map { |v| v[1] }.min }
    assert_in_delta 0.15, front.call(plain), 1e-6
    assert_in_delta 0.0, front.call(wall), 1e-6
  end

  def test_turret_on_the_front_left_corner_above_the_eave
    result = build('profile' => { 'id' => 'baule_villa_toit' }, 'seed' => 1, 'features' => { 'turret' => true })
    all = ids(result)
    assert_includes all, 'turret/body'
    assert_includes all, 'turret/spire'
    spire = nodes(result.value['nodes']).find { |n| n['id'] == 'turret/spire' }['primitive']['vertices']
    assert_operator spire.map(&:last).max, :>, result.value['metrics']['wall_top_z_m'] + 2.9
    narrow = build('profile' => { 'id' => 'baule_villa_toit' }, 'seed' => 1, 'facade' => { 'front_bays' => 4 }, 'footprint' => { 'width_m' => 7 }, 'features' => { 'turret' => true })
    assert_includes reasons(narrow), 'turret_over_opening'
  end

  def test_balconettes_in_front_of_upper_windows
    result = build(Merge.leaves(town, 'levels' => { 'count' => 3 }, 'features' => { 'balconettes' => true }))
    slabs = ids(result).grep(%r{\Abalconette/\d+/\d+/slab\z})
    assert_equal 4, slabs.size, 'deux fenêtres sur deux étages'
    assert_includes reasons(build('profile' => { 'id' => 'baule_front_de_mer' }, 'features' => { 'balconettes' => true })), 'balconettes_with_balcony'
  end

  def test_ground_floor_bow_window
    result = build('profile' => { 'id' => 'maison_moderne' }, 'features' => { 'bow_window' => 'ground' })
    bows = ids(result).grep(%r{\Abow/\d+/0/front\z})
    assert_equal 1, bows.size
    # Avec des bandeaux, le cordon du plancher s'interrompt au droit du bow-window.
    banded = build('profile' => { 'id' => 'maison_moderne' }, 'features' => { 'bow_window' => 'ground', 'string_courses' => true })
    assert_equal 2, ids(banded).grep(%r{\Aband/front/0(/\d+)?\z}).size
  end
end
