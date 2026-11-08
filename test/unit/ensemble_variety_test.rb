# frozen_string_literal: true

require_relative '../test_helper'
require File.expand_path('../../archgen/ui/messages', __dir__)

# U42 : rues variées, tirage par parcelle (docs/RUE_VARIEE_CONTRACT.md ; AG-061, ADR-44).
class EnsembleVarietyTest < Minitest::Test
  # Défaut trouvé au vrai geste (AG-063) : un toit hors style n'était pas signalé, les avertissements
  # du bâtiment préparé se perdaient dans l'ensemble.
  def test_a_roof_outside_the_style_is_reported_per_parcel
    tree = { 'seed' => 2, 'trace' => { 'points_m' => [[0, 0], [72, 0]], 'closed' => false }, 'building' => { 'profile' => { 'id' => 'haussmann' } },
             'variety' => { 'levels' => { 'min' => 5, 'max' => 7 }, 'roofs' => %w[flat] } }
    settings = Archgen::Composition.ensemble_intake.settings(tree).value
    result = Archgen::Core::EnsembleEngine.call(settings, registry: Archgen::Composition.registry.value, intake: Archgen::Composition.intake,
                                                         materials: Archgen::Composition.materials.fetch('materials'))
    assert result.ok?
    roofs = result.diagnostics.select { |d| d.code == 'W_HISTORICAL' && d.path.end_with?('/roof/type') }
    assert_equal 6, roofs.size, result.diagnostics.map(&:to_h).inspect
  end

  include Archgen::Core

  STREET = [[0, 0], [72, 0]].freeze # six parcelles de 12 m
  R = DeterministicRandom

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def intake
    @intake ||= Archgen::Composition.intake
  end

  def tree(variety, profile: 'brutalist', building: {}, seed: 1, points: STREET, closed: false)
    { 'seed' => seed, 'trace' => { 'points_m' => points, 'closed' => closed },
      'building' => { 'profile' => { 'id' => profile } }.merge(building), 'variety' => variety }
  end

  def settings(*args, **kw)
    r = Archgen::Composition.ensemble_intake.settings(tree(*args, **kw))
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def engine(value)
    EnsembleEngine.call(value, registry: registry, intake: intake, materials: Archgen::Composition.materials.fetch('materials'))
  end

  def plan(value)
    r = engine(value)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def categories(definition)
    out = []
    walk = lambda do |n|
      out << n['category']
      n['children'].each(&walk)
    end
    definition['nodes'].each(&walk)
    out
  end

  VARIED = { 'levels' => { 'min' => 3, 'max' => 7 }, 'roofs' => %w[flat gable] }.freeze

  # Le tirage refait à la main : fenêtre [3 ; 7] puis ± 2 autour de la voisine précédente.
  def expected(seed, ids)
    previous = nil
    ids.map do |id|
      lo, hi = previous ? [[3, previous - 2].max, [7, previous + 2].min] : [3, 7]
      n = lo + (R.unit(seed, "parcel/#{id}/levels") * (hi - lo + 1)).floor
      previous = n
      { 'levels' => n, 'roof' => %w[flat gable][(R.unit(seed, "parcel/#{id}/roof") * 2).floor] }
    end
  end

  def test_draw_by_hand_and_applied_to_each_building
    p = plan(settings(VARIED))
    ids = p['parcels'].map { |x| x['id'] }
    assert_equal 6, ids.size
    assert_equal expected(1, ids), p['parcels'].map { |x| x['variety'] }
    # Le toit tiré est celui du bâtiment : un toit à deux pans a ses pignons, un toit plat n'en a pas.
    p['parcels'].each do |x|
      gables = categories(p['definitions'][x['definition_id']]).include?('gable_end')
      assert_equal x['variety']['roof'] == 'gable', gables, x['id']
    end
    levels = p['parcels'].map { |x| x['variety']['levels'] }
    assert(levels.each_cons(2).all? { |a, b| (a - b).abs <= 2 })
    tops = p['parcels'].map { |x| p['definitions'][x['definition_id']]['metrics']['wall_top_z_m'] }
    by_level = levels.zip(tops).group_by(&:first).transform_values { |pairs| pairs.map(&:last).uniq }
    assert(by_level.values.all? { |t| t.size == 1 }, 'même nombre de niveaux, même hauteur')
    assert_equal by_level.keys.sort.map { |k| by_level[k].first }, by_level.keys.sort.map { |k| by_level[k].first }.sort
    assert_equal({ 'levels' => levels.tally.sort.to_h.transform_keys(&:to_s), 'roofs' => p['parcels'].map { |x| x['variety']['roof'] }.tally.sort.to_h }, p['variety'])
  end

  def test_same_seed_same_street_other_seed_other_street
    a = plan(settings(VARIED))
    b = plan(settings(VARIED))
    assert_equal EnsembleEngine.digest(a), EnsembleEngine.digest(b)
    picks = (2..6).map { |seed| plan(settings(VARIED, seed: seed))['parcels'].map { |x| x['variety'] } }
    refute_equal 1, ([a['parcels'].map { |x| x['variety'] }] + picks).uniq.size
  end

  def test_neighbour_step_is_respected_on_a_long_street
    p = plan(settings({ 'levels' => { 'min' => 1, 'max' => 15, 'max_step' => 1 } }, points: [[0, 0], [240, 0]]))
    levels = p['parcels'].map { |x| x['variety']['levels'] }
    assert_equal 20, levels.size
    assert(levels.each_cons(2).all? { |a, b| (a - b).abs <= 1 }, levels.inspect)
    refute p['variety']['roofs'].any?
  end

  def test_a_street_without_variety_has_no_draw
    value = Archgen::Composition.ensemble_intake.settings('trace' => { 'points_m' => STREET, 'closed' => false }, 'building' => { 'profile' => { 'id' => 'brutalist' } }).value
    p = plan(value)
    refute p.key?('variety')
    refute(p['parcels'].any? { |x| x.key?('variety') })
  end

  def test_shape_refusals
    r = Archgen::Composition.ensemble_intake.settings(tree({ 'levels' => { 'min' => 6, 'max' => 4 } }))
    assert_equal ['E_STREET_VARIETY', '/variety/levels/min', 'variety_levels_order'], [r.errors.first.code, r.errors.first.path, r.errors.first.params['reason']]
    r = Archgen::Composition.ensemble_intake.settings(tree(VARIED, building: { 'levels' => { 'heights_m' => [3, 3, 3] } }))
    assert_equal 'variety_with_levels', r.errors.first.params['reason']
    r = engine(settings({ 'roofs' => %w[gable hip] }))
    assert_equal ['/variety/roofs', 'variety_hip_roof'], [r.errors.first.path, r.errors.first.params['reason']]
    assert_equal 2, settings({ 'levels' => { 'min' => 3, 'max' => 5 } })['variety']['levels']['max_step']
  end

  # Haussmannien en fidélité stricte : 5 à 7 niveaux, mansarde seulement.
  def test_style_rules_bound_the_draw
    strict = { 'fidelity' => 'strict' }
    r = engine(settings({ 'levels' => { 'min' => 3, 'max' => 7 } }, profile: 'haussmann', building: strict))
    found = r.errors.first
    assert_equal ['/variety/levels', 'variety_style_levels', 5, 7], [found.path, found.params['reason'], found.params['min'], found.params['max']]
    assert_match(/de 5 à 7 niveaux/, Archgen::UI::Messages.text(found))
    r = engine(settings({ 'roofs' => %w[mansard gable] }, profile: 'haussmann', building: strict))
    assert_equal ['/variety/roofs/1', 'variety_style_roof', 'mansard'], [r.errors.first.path, r.errors.first.params['reason'], r.errors.first.params['allowed']]
    assert plan(settings({ 'levels' => { 'min' => 5, 'max' => 7 }, 'roofs' => %w[mansard] }, profile: 'haussmann', building: strict))
  end
end
