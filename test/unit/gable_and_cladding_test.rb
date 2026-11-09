# frozen_string_literal: true

require_relative '../test_helper'

# U54 : pignon à redents et bardage (docs/PIGNON_MONTAGNE_CONTRACT.md, AG-080, AG-081, ADR-48).
class GableAndCladdingTest < Minitest::Test
  include Archgen::Core

  CROSS = { 'type' => 'gable', 'overhang_m' => 0.0, 'pitch_deg' => 50.0, 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0, 'ridge' => 'perpendicular' }.freeze

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def base
    TestData.intake.effective(TestData.building('rect-neutre-shell')).value
  end

  # Fixture neutre : 12 × 9 m, quatre niveaux, murs à 12,8 m.
  def building(blocks = {})
    BuildingConfig.new(Merge.leaves(base, Merge.leaves({ 'lod' => 1, 'roof' => CROSS }, blocks)))
  end

  def generate(cfg)
    GeometryEngine.generate(cfg, materials: TestData.materials)
  end

  def plan(cfg)
    r = generate(cfg)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def details(built)
    node = built['nodes'].first['children'].find { |n| n['id'] == 'details' }
    node ? node['children'] : []
  end

  def box(node)
    node['primitive']['vertices'].transpose.map(&:minmax)
  end

  def reasons(data)
    ConstraintValidator.call(data, materials: TestData.materials).map { |d| d.params['reason'] }
  end

  # --- Pignon à redents

  def test_steps_rise_above_the_slope_and_cover_the_gable
    list = details(plan(building('features' => { 'stepped_gable' => true })))
    steps = list.select { |n| n['category'] == 'stepped_gable' }
    assert_equal 6, steps.size, 'cinq marches et un pinacle'
    slope = Math.tan(50 * Math::PI / 180)
    steps.first(5).each_with_index do |node, k|
      (x0, x1), (y0, y1), (_, z1) = box(node)
      assert_in_delta k * 1.2, x0, 1e-6
      assert_in_delta 12.0 - (k * 1.2), x1, 1e-6
      assert_in_delta 12.8 + (slope * (k + 1) * 1.2) + 0.30, z1, 1e-6
      assert_equal [-0.05, 0.25], [y0, y1].map { |v| v.round(6) }
    end
    assert_in_delta 0.40, box(steps.last)[2][1] - box(steps.last)[2][0], 1e-6
  end

  def test_stepped_gable_refusals_and_corner
    plain = Merge.leaves(base, 'features' => { 'stepped_gable' => true })
    assert_includes reasons(plain), 'stepped_gable_ridge'
    overhung = Merge.leaves(base, 'roof' => CROSS.merge('overhang_m' => 0.3), 'features' => { 'stepped_gable' => true })
    assert_includes reasons(overhung), 'stepped_gable_overhang'
    assert_includes reasons(Merge.leaves(base, 'features' => { 'stepped_gable' => false })), 'stepped_gable_false_written'
    tree = { 'seed' => 1, 'trace' => { 'points_m' => [[0, 0], [40, 0], [40, 30]], 'closed' => false },
             'building' => { 'profile' => { 'id' => 'toulousain' }, 'lod' => 1, 'roof' => { 'ridge' => 'perpendicular', 'overhang_m' => 0.0 },
                             'features' => { 'stepped_gable' => true, 'shutters' => false } } }
    r = EnsembleEngine.call(Archgen::Composition.ensemble_intake.settings(tree).value, registry: registry, intake: TestData.intake, materials: TestData.materials)
    assert r.ok?, r.errors.map(&:to_h).inspect
    assert(r.warnings.any? { |d| d.params['reason'] == 'stepped_gable_corner' })
  end

  # --- Bardage

  def clad(blocks = {})
    building(Merge.leaves({ 'features' => { 'cladding' => true, 'balcony' => true }, 'materials' => { 'cladding' => 'natural_wood' } }, blocks))
  end

  def test_top_level_gables_and_balconies_take_the_cladding
    built = plan(clad)
    walls = built['nodes'].first['children'].find { |n| n['id'] == 'walls' }['children']
    front = walls.find { |n| n['id'] == 'wall/front' }['primitive']
    by_material = front['faces'].group_by { |f| f['material'] }
    assert_equal %w[lime_plaster natural_wood], by_material.keys.sort
    by_material['natural_wood'].each do |face|
      assert(face['indices'].all? { |i| front['vertices'][i][2] >= 9.6 - 1e-6 }, 'bardage au dernier niveau seulement')
    end
    gable = built['nodes'].first['children'].find { |n| n['id'] == 'roof' }['children'].find { |n| n['id'] == 'roof/gable/front' }
    assert_equal ['natural_wood'], gable['primitive']['faces'].map { |f| f['material'] }
    balcony = details(built).find { |n| n['id'] == 'balcony/2' }
    assert_equal ['natural_wood'], balcony['primitive']['faces'].map { |f| f['material'] }.uniq
  end

  def test_cladding_in_both_modes_and_refusals
    %w[shell structural].each { |mode| plan(clad('mode' => mode)) }
    assert_includes reasons(Merge.leaves(base, 'features' => { 'cladding' => true })), 'cladding_material_required'
    assert_includes reasons(Merge.leaves(base, 'materials' => { 'cladding' => 'dark_wood' })), 'cladding_material_without_cladding'
    on = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'toulousain' }, 'features' => { 'cladding' => true } },
                                registry: registry, intake: TestData.intake).value.to_h
    assert_equal 'natural_wood', on['materials']['cladding']
  end
end
