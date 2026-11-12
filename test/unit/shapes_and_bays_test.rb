# frozen_string_literal: true

require_relative '../test_helper'

# U99 : balcons d'angle, bow-windows, ailes en L, T et U (AG-137, AG-138 ; ADR-65, ADR-66).
class ShapesAndBaysTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def build(draft)
    config = ConfigResolver.resolve({ 'schema_version' => 1 }.merge(draft), registry: registry, intake: TestData.intake)
    return config unless config.ok?

    GeometryEngine.generate(config.value, materials: TestData.materials)
  end

  def nodes_of(nodes, out = [])
    nodes.each do |node|
      out << node
      nodes_of(node['children'], out)
    end
    out
  end

  def points(plan, prefix)
    nodes_of(plan['nodes']).select { |n| n['id'].start_with?(prefix) }.flat_map { |n| n.dig('primitive', 'vertices') || [] }
  end

  def reasons(result)
    result.errors.map { |d| d.params['reason'] }
  end

  # --- Balcons d'angle

  def test_wrapped_balconies_run_along_both_sides
    built = build('profile' => { 'id' => 'baule_front_de_mer' }, 'lod' => 1, 'levels' => { 'attic_setback_m' => 0 },
                  'facade' => { 'side_bays' => 2 }, 'features' => { 'balcony_wrap' => true })
    assert built.ok?, built.errors.map(&:to_h).inspect
    slab = points(built.value, 'balcony/3').reject { |v| v[2] > 20 }
    xs = slab.map(&:first)
    ys = slab.map { |v| v[1] }
    assert_in_delta(-1.8, xs.min, 1e-6)
    assert_in_delta 23.8, xs.max, 1e-6
    assert_operator ys.max, :>, 10, 'le balcon longe les côtés'
  end

  def test_wrap_falls_back_to_the_front_in_a_row
    tree = { 'seed' => 1, 'trace' => { 'points_m' => [[0, 0], [48, 0]], 'closed' => false },
             'building' => { 'profile' => { 'id' => 'baule_front_de_mer' }, 'lod' => 1, 'features' => { 'balcony_wrap' => true } } }
    settings = Archgen::Composition.ensemble_intake.settings(tree)
    result = EnsembleEngine.call(settings.value, registry: registry, intake: TestData.intake, materials: TestData.materials)
    assert result.ok?, result.errors.map(&:to_h).first(3).inspect
    assert(result.diagnostics.any? { |d| d.params['reason'] == 'balcony_wrap_in_row' })
  end

  # --- Bow-windows

  def test_bow_windows_stack_on_the_central_bay
    built = build('profile' => { 'id' => 'baule_villa' }, 'lod' => 1, 'levels' => { 'count' => 3 }, 'features' => { 'bow_window' => 'center' })
    assert built.ok?, built.errors.map(&:to_h).inspect
    ids = nodes_of(built.value['nodes']).map { |n| n['id'] }
    bows = ids.grep(%r{\Abow/\d+/\d+/front\z})
    assert_equal 2, bows.size, 'niveaux 1 et 2'
    assert_equal 1, ids.grep(%r{\Abow/.*/roof\z}).size, 'une seule dalle haute'
    front = points(built.value, 'bow/')
    assert_in_delta(-0.7, front.map { |v| v[1] }.min, 1e-6)
    ends = build('profile' => { 'id' => 'baule_villa' }, 'lod' => 1, 'features' => { 'bow_window' => 'ends' })
    assert ends.ok?, ends.errors.map(&:to_h).inspect
    assert_equal 2, nodes_of(ends.value['nodes']).map { |n| n['id'] }.grep(%r{\Abow/\d+/1/front\z}).size
  end

  def test_bow_window_refusals
    assert_includes reasons(build('profile' => { 'id' => 'baule_front_de_mer' }, 'lod' => 1, 'features' => { 'bow_window' => 'center' })), 'bow_window_with_balcony'
    assert_includes reasons(build('profile' => { 'id' => 'provencal_mas' }, 'lod' => 1, 'features' => { 'bow_window' => 'center' })), 'bow_window_with_shutters'
  end

  # --- Ailes

  def test_l_t_and_u_shapes
    { 'left' => [0.0, 5.0], 'right' => [7.0, 12.0], 'center' => [3.5, 8.5] }.each do |pos, (x0, x1)|
      built = build('profile' => { 'id' => 'maison_moderne' }, 'wing' => { 'position' => pos, 'width_m' => 5, 'depth_m' => 6 })
      assert built.ok?, "#{pos} : #{built.errors.map(&:to_h).inspect}"
      wing = points(built.value, "wing/#{pos}/wall")
      assert_in_delta x0, wing.map(&:first).min, 1e-6, pos
      assert_in_delta x1, wing.map(&:first).max, 1e-6, pos
      assert_in_delta 9.0, wing.map { |v| v[1] }.min, 1e-6, pos
      assert_in_delta 15.0, wing.map { |v| v[1] }.max, 1e-6, pos
    end
    u = build('profile' => { 'id' => 'baule_villa' }, 'lod' => 1, 'wing' => { 'position' => 'both', 'width_m' => 3.5, 'depth_m' => 5, 'levels' => 1 })
    assert u.ok?, u.errors.map(&:to_h).inspect
    ids = nodes_of(u.value['nodes']).map { |n| n['id'] }
    assert(ids.any? { |id| id.start_with?('wing/left/') } && ids.any? { |id| id.start_with?('wing/right/') })
    assert_equal u.value['metrics']['opening_count'], u.value['openings'].size
  end

  def test_none_removes_the_wing_and_the_bow_window
    config = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'maison_moderne' }, 'wing' => { 'position' => 'none', 'width_m' => 4, 'depth_m' => 5 },
                                      'features' => { 'bow_window' => 'none' } }, registry: registry, intake: TestData.intake)
    assert config.ok?, config.errors.map(&:to_h).inspect
    refute config.value.to_h.key?('wing')
    refute config.value.to_h['features'].key?('bow_window')
  end

  def test_wing_refusals_and_detached_street
    assert_includes reasons(build('profile' => { 'id' => 'maison_moderne' }, 'wing' => { 'position' => 'both', 'width_m' => 7, 'depth_m' => 6 })), 'wing_too_wide'
    tree = { 'seed' => 1, 'trace' => { 'points_m' => [[0, 0], [48, 0]], 'closed' => false },
             'building' => { 'profile' => { 'id' => 'maison_moderne' }, 'wing' => { 'position' => 'left', 'width_m' => 4, 'depth_m' => 5 } } }
    row = EnsembleEngine.call(Archgen::Composition.ensemble_intake.settings(tree).value, registry: registry, intake: TestData.intake, materials: TestData.materials)
    assert_includes reasons(row), 'wing_in_row'
    tree['parcel'] = { 'target_width_m' => 16, 'depth_m' => 25, 'bay_width_m' => 3, 'detached' => { 'side_gap_m' => 3, 'front_setback_m' => 5, 'building_depth_m' => 10 } }
    detached = EnsembleEngine.call(Archgen::Composition.ensemble_intake.settings(tree).value, registry: registry, intake: TestData.intake, materials: TestData.materials)
    assert detached.ok?, detached.errors.map(&:to_h).first(3).inspect
  end
end
