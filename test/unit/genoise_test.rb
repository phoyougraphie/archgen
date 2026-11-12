# frozen_string_literal: true

require_relative '../test_helper'

# U51 : génoises (docs/STYLES_REGIONAUX_CONTRACT.md, AG-074, ADR-48).
class GenoiseTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def base
    TestData.intake.effective(TestData.building('rect-neutre-shell')).value
  end

  GABLE = { 'type' => 'gable', 'overhang_m' => 0.3, 'pitch_deg' => 22.0, 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0 }.freeze

  # Fixture neutre : 12 × 9 m, murs à 12,8 m, fenêtres hautes de 1,80 m à 0,85 m d'allège.
  def building(blocks = {})
    BuildingConfig.new(Merge.leaves(base, Merge.leaves({ 'lod' => 1, 'features' => { 'genoise' => true }, 'roof' => GABLE }, blocks)))
  end

  def generate(cfg)
    GeometryEngine.generate(cfg, materials: TestData.materials)
  end

  def plan(cfg)
    r = generate(cfg)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def rows(built)
    details = built['nodes'].first['children'].find { |n| n['id'] == 'details' }
    details ? details['children'].select { |n| n['category'] == 'genoise' } : []
  end

  def box(node)
    node['primitive']['vertices'].transpose.map(&:minmax)
  end

  def test_unticked_is_not_written_and_false_is_refused
    cfg = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'toulousain' }, 'features' => { 'genoise' => false } },
                                 registry: registry, intake: TestData.intake)
    refute cfg.value.to_h['features'].key?('genoise')
    assert_includes ConstraintValidator.call(Merge.leaves(base, 'features' => { 'genoise' => false })).map { |d| d.params['reason'] }, 'genoise_false_written'
  end

  def test_two_rows_front_and_rear_under_the_roof_skin
    built = plan(building)
    list = rows(built)
    assert_equal %w[genoise/front/0 genoise/rear/0 genoise/front/1 genoise/rear/1], list.map { |n| n['id'] }
    top = 12.8 - (Math.tan(22 * Math::PI / 180) * 0.16)
    (x0, x1), (y0, y1), (z0, z1) = box(list.first)
    assert_equal [0.0, 12.0], [x0, x1].map { |v| v.round(6) }
    assert_equal [-0.16, 0.0], [y0, y1].map { |v| v.round(6) }
    assert_in_delta top, z1, 1e-6
    assert_in_delta top - 0.10, z0, 1e-6
    (_, _), (ry0, ry1), = box(list[1])
    assert_equal [9.0, 9.16], [ry0, ry1].map { |v| v.round(6) }
    (_, _), (by0, _), (bz0, bz1) = box(list[2])
    assert_in_delta(-0.08, by0, 1e-6)
    assert_in_delta top - 0.20, bz0, 1e-6
    assert_in_delta top - 0.10, bz1, 1e-6
    assert_equal ['concrete'], list.flat_map { |n| n['primitive']['faces'].map { |f| f['material'] } }.uniq
  end

  def test_flat_and_mansard_roofs_warn_and_build_none
    flat = generate(building('roof' => { 'type' => 'flat', 'overhang_m' => 0.0, 'pitch_deg' => 0.0, 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0 }))
    assert flat.ok?
    assert_empty rows(flat.value)
    assert_includes flat.warnings.map { |d| d.params['reason'] }, 'genoise_roof'
    mansard = generate(building('roof' => { 'type' => 'mansard', 'overhang_m' => 0.15, 'pitch_deg' => 25.0, 'lower_pitch_deg' => 65.0, 'inset_m' => 0.9 }))
    assert_includes mansard.warnings.map { |d| d.params['reason'] }, 'genoise_roof'
  end

  def test_refusals
    with_cornice = generate(building('features' => { 'cornice' => true }))
    assert_includes with_cornice.errors.map { |d| d.params['reason'] }, 'genoise_with_cornice'
    tall = generate(building('facade' => { 'window_height_m' => 2.0 }))
    reasons = tall.errors.map { |d| [d.path, d.params['reason']] }.uniq
    assert_equal [['/features/genoise', 'genoise_head_margin']], reasons
  end

  def test_hip_and_lod_zero
    assert_equal 4, rows(plan(building('roof' => GABLE.merge('type' => 'hip')))).size
    assert_empty rows(plan(building('lod' => 0)))
  end

  def test_a_street_with_a_corner_takes_a_genoise
    tree = { 'seed' => 2, 'trace' => { 'points_m' => [[0, 0], [40, 0], [40, 30]], 'closed' => false },
             'building' => { 'profile' => { 'id' => 'toulousain' }, 'lod' => 1, 'features' => { 'genoise' => true, 'shutters' => false } } }
    settings = Archgen::Composition.ensemble_intake.settings(tree).value
    r = EnsembleEngine.call(settings, registry: registry, intake: TestData.intake, materials: TestData.materials)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value['definitions'].each_value { |built| assert_equal 4, rows(built).size }
  end
end
