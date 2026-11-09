# frozen_string_literal: true

require_relative '../test_helper'

# U46 : cheminées (docs/DETAILS_CONTRACT.md, AG-066, ADR-45).
class ChimneyTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def base
    TestData.intake.effective(TestData.building('rect-neutre-shell')).value
  end

  # Fixture neutre : 12 × 9 m, quatre niveaux de 3,2 m, murs de 0,24 m, toit plat.
  def building(blocks = {})
    BuildingConfig.new(Merge.leaves(base, { 'lod' => 1, 'features' => { 'chimneys' => true } }.merge(blocks)))
  end

  def plan(cfg)
    r = GeometryEngine.generate(cfg, materials: TestData.materials)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def stacks(built)
    details = built['nodes'].first['children'].find { |n| n['id'] == 'details' }
    details ? details['children'].select { |n| n['category'] == 'chimney' } : []
  end

  def box(node)
    node['primitive']['vertices'].transpose.map(&:minmax)
  end

  def bodies(built)
    stacks(built).reject { |n| n['id'].end_with?('/cap') }
  end

  def seed_with(count)
    (1..200).find { |s| (DeterministicRandom.unit(s, 'chimneys') < 0.5 ? 1 : 2) == count }
  end

  GABLE = { 'type' => 'gable', 'overhang_m' => 0.3, 'pitch_deg' => 35.0, 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0 }.freeze

  def test_unticked_is_not_written_and_a_written_false_is_refused
    cfg = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'haussmann' }, 'features' => { 'chimneys' => false } },
                                 registry: registry, intake: TestData.intake)
    refute cfg.value.to_h['features'].key?('chimneys')
    found = ConstraintValidator.call(Merge.leaves(base, 'features' => { 'chimneys' => false })).map { |d| d.params['reason'] }
    assert_includes found, 'chimneys_false_written'
  end

  def test_gable_stacks_lean_on_the_side_walls_and_rise_above_the_ridge
    built = plan(building('seed' => seed_with(2), 'roof' => GABLE))
    two = bodies(built)
    assert_equal 2, two.size
    ridge = built['metrics']['roof_top_z_m']
    (lx, _), (ly0, ly1), (lz0, lz1) = box(two.first)
    (_, rx1), = box(two.last)
    assert_in_delta 0.24 + 0.10, lx, 1e-6
    assert_in_delta 12.0 - 0.34, rx1, 1e-6
    assert_in_delta 4.5, (ly0 + ly1) / 2, 1e-6, 'centrée sur le faîtage'
    assert_in_delta 0.45, ly1 - ly0, 1e-6
    assert_in_delta 4 * 3.2, lz0, 1e-6, 'part du haut des murs'
    cap = stacks(built).find { |n| n['id'] == 'chimney/0/cap' }
    assert_in_delta ridge + 0.60, box(cap)[2][1], 1e-6
    assert_in_delta lx - 0.05, box(cap)[0][0], 1e-6
    assert_in_delta lz1, box(cap)[2][0], 1e-6
    assert_equal ['lime_plaster'], two.first['primitive']['faces'].map { |f| f['material'] }.uniq
  end

  def test_count_is_drawn_from_the_seed_and_is_stable
    one = plan(building('seed' => seed_with(1), 'roof' => GABLE))
    assert_equal 1, bodies(one).size
    assert_equal one, plan(building('seed' => seed_with(1), 'roof' => GABLE))
  end

  def test_flat_roof_stack_rises_one_metre
    built = plan(building('seed' => seed_with(2)))
    assert_in_delta built['metrics']['roof_top_z_m'] + 1.0, stacks(built).map { |n| box(n)[2][1] }.max, 1e-6
  end

  def test_hip_and_mansard_stacks_sit_on_the_ridge_ends
    hip = plan(building('seed' => seed_with(2), 'roof' => GABLE.merge('type' => 'hip')))
    centres = bodies(hip).map { |n| box(n)[0].sum / 2 }
    assert_equal [4.5, 7.5], centres.map { |v| v.round(6) }, 'faîtage de x = 4,5 à 7,5 sur 12 × 9'
    square = plan(building('seed' => seed_with(2), 'footprint' => { 'width_m' => 9 }, 'roof' => GABLE.merge('type' => 'hip')))
    assert_equal 1, bodies(square).size, 'un carré n’a qu’un sommet'
    mansard = { 'type' => 'mansard', 'overhang_m' => 0.15, 'pitch_deg' => 25.0, 'lower_pitch_deg' => 65.0, 'inset_m' => 0.9 }
    assert_equal 2, bodies(plan(building('seed' => seed_with(2), 'roof' => mansard))).size
  end

  def test_nothing_at_lod_zero_and_plans_stay_valid_in_both_modes
    assert_empty stacks(plan(building('lod' => 0)))
    %w[shell structural].each { |mode| refute_empty stacks(plan(building('mode' => mode, 'seed' => seed_with(2), 'roof' => GABLE))) }
  end

  def street(features = { 'chimneys' => true }, roof = 'gable')
    tree = { 'seed' => 5, 'trace' => { 'points_m' => [[0, 0], [60, 0], [60, 30]], 'closed' => false },
             'building' => { 'profile' => { 'id' => 'toulousain' }, 'lod' => 1, 'features' => features, 'roof' => { 'type' => roof } } }
    settings = Archgen::Composition.ensemble_intake.settings(tree).value
    r = EnsembleEngine.call(settings, registry: registry, intake: TestData.intake, materials: TestData.materials)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def test_street_stacks_stay_inside_each_parcel_and_follow_each_seed
    value = street
    plans = value['definitions'].values
    plans.each do |built|
      bodies(built).each do |n|
        (x0, x1), = box(n)
        assert_operator x0, :>, 0.0
        assert_operator x1, :<, built['metrics']['width_m']
      end
    end
    counts = plans.map { |b| bodies(b).size }
    assert_includes counts, 1
    assert_includes counts, 2
    assert_operator value['definitions'].size, :>=, value['parcels'].size - 1, 'la seed rend chaque parcelle propre'
  end
end
