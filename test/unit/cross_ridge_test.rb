# frozen_string_literal: true

require_relative '../test_helper'

# U53 : faîtage perpendiculaire à la rue (docs/PIGNON_MONTAGNE_CONTRACT.md, AG-079, ADR-48).
class CrossRidgeTest < Minitest::Test
  include Archgen::Core

  CROSS = { 'type' => 'gable', 'overhang_m' => 0.3, 'pitch_deg' => 45.0, 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0, 'ridge' => 'perpendicular' }.freeze

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def base
    TestData.intake.effective(TestData.building('rect-neutre-shell')).value
  end

  # Fixture neutre : 12 × 9 m, murs à 12,8 m.
  def building(blocks = {})
    BuildingConfig.new(Merge.leaves(base, Merge.leaves({ 'roof' => CROSS }, blocks)))
  end

  def generate(cfg)
    GeometryEngine.generate(cfg, materials: TestData.materials)
  end

  def plan(cfg)
    r = generate(cfg)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def roof_nodes(built)
    built['nodes'].first['children'].find { |n| n['id'] == 'roof' }['children']
  end

  def box(node)
    node['primitive']['vertices'].transpose.map(&:minmax)
  end

  def resolve(draft)
    ConfigResolver.resolve({ 'schema_version' => 1 }.merge(draft), registry: registry, intake: TestData.intake)
  end

  def test_resolution_writes_only_a_perpendicular_ridge_on_a_gable
    on = resolve('profile' => { 'id' => 'toulousain' }, 'roof' => { 'ridge' => 'perpendicular' }).value.to_h
    assert_equal 'perpendicular', on['roof']['ridge']
    off = resolve('profile' => { 'id' => 'toulousain' }, 'roof' => { 'ridge' => 'parallel' }).value.to_h
    refute off['roof'].key?('ridge')
    refused = resolve('profile' => { 'id' => 'toulousain' }, 'roof' => { 'type' => 'hip', 'ridge' => 'perpendicular' })
    assert_equal [['/roof/ridge', 'ridge_axis_roof']], refused.errors.map { |d| [d.path, d.params['reason']] }
    stored = Merge.leaves(base, 'roof' => { 'ridge' => 'perpendicular' })
    assert_includes ConstraintValidator.call(stored).map { |d| d.params['reason'] }, 'ridge_axis_roof'
  end

  def test_gables_face_the_street_and_the_ridge_runs_front_to_back
    built = plan(building)
    ids = roof_nodes(built).map { |n| n['id'] }
    assert_equal %w[roof/left roof/right roof/gable/front roof/gable/rear], ids
    front = box(roof_nodes(built).find { |n| n['id'] == 'roof/gable/front' })
    assert_equal [0.0, 0.0], front[1]
    assert_in_delta 12.8 + 6.0, built['metrics']['roof_top_z_m'], 1e-6, 'faîtage à mi-largeur, pente 45°'
    left = box(roof_nodes(built).find { |n| n['id'] == 'roof/left' })
    assert_equal [-0.3, 9.3], left[1].map { |v| v.round(6) }
    assert_in_delta(-0.3, left[0][0], 1e-6)
  end

  def test_parallel_buildings_keep_their_plan
    plain = Merge.leaves(base, 'roof' => CROSS.reject { |k, _| k == 'ridge' })
    assert_equal %w[roof/front roof/rear roof/gable/right roof/gable/left], roof_nodes(plan(BuildingConfig.new(plain))).map { |n| n['id'] }
  end

  def test_chimneys_sit_on_the_ridge_and_dormers_and_genoise_are_said
    built = generate(building('lod' => 1, 'seed' => 7, 'features' => { 'chimneys' => true, 'dormers' => true, 'genoise' => true }))
    assert built.ok?, built.errors.map(&:to_h).inspect
    details = built.value['nodes'].first['children'].find { |n| n['id'] == 'details' }['children']
    stacks = details.select { |n| n['category'] == 'chimney' && !n['id'].end_with?('/cap') }
    refute_empty stacks
    stacks.each { |n| assert_in_delta 6.0, box(n)[0].sum / 2, 1e-6 }
    assert_empty(details.select { |n| %w[dormer genoise].include?(n['category']) })
    assert_equal %w[dormer_ridge genoise_roof], built.warnings.map { |d| d.params['reason'] }.sort
  end

  def street(points)
    tree = { 'seed' => 1, 'trace' => { 'points_m' => points, 'closed' => false },
             'building' => { 'profile' => { 'id' => 'toulousain' }, 'roof' => { 'ridge' => 'perpendicular', 'overhang_m' => 0.3 } } }
    settings = Archgen::Composition.ensemble_intake.settings(tree).value
    EnsembleEngine.call(settings, registry: registry, intake: TestData.intake, materials: TestData.materials)
  end

  def test_a_row_has_no_side_overhang
    r = street([[0, 0], [36, 0]])
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value['definitions'].each_value do |built|
      left = box(roof_nodes(built).find { |n| n['id'] == 'roof/left' })
      assert_in_delta 0.0, left[0][0], 1e-6, 'égout au droit du mur mitoyen'
      assert_in_delta(-0.3, left[1][0], 1e-6, 'débord avant gardé')
    end
  end

  def test_a_corner_parcel_keeps_a_parallel_ridge_and_says_so
    r = street([[0, 0], [40, 0], [40, 30]])
    assert r.ok?, r.errors.map(&:to_h).inspect
    assert(r.warnings.any? { |d| d.params['reason'] == 'ridge_corner' })
    kinds = r.value['definitions'].values.map { |built| roof_nodes(built).map { |n| n['id'] }.include?('roof/left') }
    assert_includes kinds, true
    assert_includes kinds, false
  end
end
