# frozen_string_literal: true

require_relative '../test_helper'

# U50 : lucarnes (docs/VOLETS_LUCARNES_CONTRACT.md, AG-072, ADR-47).
class DormersTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def base
    TestData.intake.effective(TestData.building('rect-neutre-shell')).value
  end

  GABLE = { 'type' => 'gable', 'overhang_m' => 0.3, 'pitch_deg' => 35.0, 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0 }.freeze
  MANSARD = { 'type' => 'mansard', 'overhang_m' => 0.15, 'pitch_deg' => 25.0, 'lower_pitch_deg' => 65.0, 'inset_m' => 0.9 }.freeze

  # Fixture neutre : 12 × 9 m, quatre travées, quatre niveaux de 3,2 m (murs à 12,8 m).
  def building(blocks = {})
    BuildingConfig.new(Merge.leaves(base, Merge.leaves({ 'lod' => 1, 'features' => { 'dormers' => true }, 'roof' => GABLE }, blocks)))
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
    built['nodes'].first['children'].find { |n| n['id'] == 'details' }['children']
  end

  def bodies(built)
    details(built).select { |n| n['category'] == 'dormer' }
  end

  def box(node)
    node['primitive']['vertices'].transpose.map(&:minmax)
  end

  def reasons(result)
    result.errors.map { |d| d.params['reason'] }.uniq
  end

  def test_unticked_is_not_written_and_a_written_false_is_refused
    cfg = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'haussmann' }, 'features' => { 'dormers' => false } },
                                 registry: registry, intake: TestData.intake)
    refute cfg.value.to_h['features'].key?('dormers')
    assert_includes ConstraintValidator.call(Merge.leaves(base, 'features' => { 'dormers' => false })).map { |d| d.params['reason'] }, 'dormers_false_written'
  end

  def test_one_dormer_per_front_bay_on_a_gable_buried_in_the_roof
    built = plan(building)
    list = bodies(built)
    assert_equal 4, list.size
    pitch = (12.0 - 1.2) / 4
    list.each_with_index do |node, bay|
      (x0, x1), (y0, y1), (z0, z1) = box(node)
      assert_in_delta 0.6 + ((bay + 0.5) * pitch), (x0 + x1) / 2, 1e-6, 'sur la trame'
      assert_in_delta 1.2 + 0.2, x1 - x0, 1e-6, 'fenêtre et deux jouées'
      assert_in_delta 0.15, y0, 1e-6
      assert_in_delta 12.8, z0, 1e-6
      roof_at_back = 12.8 + (Math.tan(35 * Math::PI / 180) * y1)
      assert_operator roof_at_back, :>=, z1, 'le faîte de la lucarne est sous la peau à son arrière'
      assert_operator y1, :<=, 4.5, 'avant le faîtage'
    end
    materials = list.first['primitive']['faces'].map { |f| f['material'] }.uniq.sort
    assert_equal %w[concrete lime_plaster], materials
  end

  def test_each_dormer_has_a_window_from_the_shared_frame
    built = plan(building('features' => { 'glazing' => true, 'muntins' => true }, 'materials' => { 'glass' => 'glass' }, 'facade' => { 'muntin_rows' => 2 }))
    frames = details(built).select { |n| n['id'].start_with?('frame/dormer/') }
    assert_equal 4, frames.size
    id = frames.first['primitive']['definition_id']
    assert_match %r{\Aframe/window/1200000x\d+/painted_wood/glazed/glass/muntins/2\z}, id
    height = id.split('/')[2].split('x').last.to_f / Quant::SCALE
    assert_operator height, :>=, 0.6
    assert_operator height, :<=, 1.4
    matrix = frames.first['primitive']['matrix']
    assert_in_delta 0.15, matrix[13], 1e-6, 'fenêtre dans le plan de la façade de lucarne'
    assert_operator matrix[14], :>=, 12.8 + 0.3 - 1e-6, 'allège au-dessus du haut des murs'
  end

  def test_mansard_dormers_sit_in_the_brisis
    list = bodies(plan(building('roof' => MANSARD)))
    assert_equal 4, list.size
    (_, _), (_, y1), = box(list.first)
    assert_operator y1, :<, 4.5
  end

  def test_flat_roof_warns_and_builds_none
    r = generate(building('roof' => { 'type' => 'flat', 'overhang_m' => 0.0, 'pitch_deg' => 0.0, 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0 }))
    assert r.ok?
    assert_empty bodies(r.value)
    assert_equal ['dormer_flat_roof'], r.warnings.map { |d| d.params['reason'] }
  end

  def test_hip_end_bays_are_skipped_and_said
    r = generate(building('roof' => GABLE.merge('type' => 'hip')))
    assert r.ok?, r.errors.map(&:to_h).inspect
    warning = r.warnings.find { |d| d.params['reason'] == 'dormer_skipped' }
    assert_equal 'hip', warning.params['why']
    assert_equal 4 - warning.params['ids'].size, bodies(r.value).size
  end

  def test_refusals_are_localized
    low = generate(building('roof' => GABLE.merge('pitch_deg' => 8.0)))
    assert_equal ['dormer_too_low'], reasons(low)
    crowded = generate(building('facade' => { 'front_bays' => 7, 'window_width_m' => 1.4, 'entry_bay' => 1 }))
    assert_includes reasons(crowded), 'dormer_no_room'
    assert(crowded.errors.all? { |d| d.path == '/features/dormers' })
  end

  def test_a_chimney_under_a_dormer_is_refused
    seed = (1..400).find do |s|
      generated = generate(building('seed' => s, 'roof' => GABLE.merge('pitch_deg' => 25.0), 'features' => { 'chimneys' => true }, 'facade' => { 'margin_m' => 0.2, 'front_bays' => 6, 'window_width_m' => 0.6, 'entry_bay' => 1 }))
      !generated.ok? && reasons(generated).include?('dormer_on_chimney')
    end
    assert seed, 'une souche contre un mur latéral sous la première lucarne'
  end

  def test_a_street_with_a_corner_keeps_dormers_inside_each_parcel
    tree = { 'seed' => 2, 'trace' => { 'points_m' => [[0, 0], [40, 0], [40, 30]], 'closed' => false },
             'building' => { 'profile' => { 'id' => 'haussmann' }, 'lod' => 1, 'features' => { 'dormers' => true } } }
    settings = Archgen::Composition.ensemble_intake.settings(tree).value
    r = EnsembleEngine.call(settings, registry: registry, intake: TestData.intake, materials: TestData.materials)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value['definitions'].each_value do |built|
      bodies(built).each do |node|
        (x0, x1), = box(node)
        assert_operator x0, :>, 0.0
        assert_operator x1, :<, built['metrics']['width_m']
      end
    end
  end

  def test_nothing_at_lod_zero_and_both_modes_valid
    assert_empty plan(building('lod' => 0))['definitions']
    %w[shell structural].each { |mode| assert_equal 4, bodies(plan(building('mode' => mode))).size }
  end
end
