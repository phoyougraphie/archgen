# frozen_string_literal: true

require_relative '../test_helper'

# U47 : réglages propres d'une parcelle (docs/DETAILS_CONTRACT.md, AG-068, D-21).
class EnsembleParcelsTest < Minitest::Test
  include Archgen::Core

  STREET = [[0, 0], [60, 0]].freeze

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def settings(tree)
    result = Archgen::Composition.ensemble_intake.settings(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def tree(parcels = nil, points: STREET, closed: false, variety: nil, building: {})
    out = { 'seed' => 3, 'trace' => { 'points_m' => points, 'closed' => closed },
            'building' => { 'profile' => { 'id' => 'toulousain' }, 'lod' => 1 }.merge(building) }
    out['parcels'] = parcels if parcels
    out['variety'] = variety if variety
    out
  end

  def run_engine(value)
    EnsembleEngine.call(value, registry: registry, intake: TestData.intake, materials: TestData.materials)
  end

  def plan(value)
    r = run_engine(value)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def reasons(result)
    result.errors.map { |d| [d.code, d.path, d.params['reason']] }
  end

  def built(plan, id)
    placed = plan['parcels'].find { |p| p['id'] == id }
    plan['definitions'].fetch(placed['definition_id'])
  end

  def ids
    @ids ||= plan(settings(tree))['parcels'].map { |p| p['id'] }
  end

  def layout(value)
    r = EnsembleEngine.layout_for(value, registry: registry)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value['parcels']
  end

  # --- Format

  def test_bad_entries_are_refused_at_reading
    bad = Archgen::Composition.ensemble_intake.settings(tree({ 'front/0/1' => { 'levels' => 20 }, 'nope' => { 'levels' => 3 },
                                                             'left/0/2' => {}, 'left/0/3' => { 'roof' => 'hip' }, 'left/0/4' => { 'colour' => 'red' } }))
    refute bad.ok?
    found = bad.errors.map { |d| [d.path, d.params['reason']] }
    assert_includes found, ['/parcels/front/0/1/levels', 'maximum']
    assert_includes found, ['/parcels/nope', 'pattern']
    assert_includes found, ['/parcels/left/0/2', 'empty_parcel']
    assert(found.any? { |path, _| path == '/parcels/left/0/3/roof' })
    assert(found.any? { |path, _| path == '/parcels/left/0/4/colour' })
  end

  def test_an_ensemble_without_parcels_keeps_its_plan
    before = plan(settings(tree))
    assert_equal EnsembleEngine.digest(before), EnsembleEngine.digest(plan(settings(tree({}))))
  end

  def test_unknown_parcel_is_refused_with_its_id
    r = run_engine(settings(tree({ 'left/0/99' => { 'levels' => 3 } })))
    assert_includes reasons(r), ['E_STREET_PARCEL', '/parcels/left/0/99', 'unknown_parcel']
  end

  # --- Priorité

  def test_own_settings_win_over_the_street_and_the_others_do_not_move
    id = ids[1]
    base = plan(settings(tree))
    own = plan(settings(tree({ id => { 'levels' => 7, 'roof' => 'mansard', 'ground_floor' => 'shop', 'chimneys' => true } })))
    mine = built(own, id)
    assert_equal 7, mine['openings'].map { |o| o['level_index'] }.max + 1
    assert(mine['openings'].any? { |o| o['kind'] == 'shopfront' })
    assert(mine['nodes'].first['children'].any? { |n| n['id'] == 'roof' })
    (ids - [id]).each do |other|
      assert_equal built(base, other), built(own, other), other
      assert_equal base['parcels'].find { |p| p['id'] == other }['matrix'], own['parcels'].find { |p| p['id'] == other }['matrix']
    end
  end

  def test_own_settings_come_after_the_variety_draw_which_does_not_change
    variety = { 'levels' => { 'min' => 3, 'max' => 6 } }
    drawn = plan(settings(tree(variety: variety)))
    id = ids[2]
    own = plan(settings(tree({ id => { 'levels' => 12 } }, variety: variety)))
    assert_equal 12, built(own, id)['openings'].map { |o| o['level_index'] }.max + 1
    drawn['parcels'].zip(own['parcels']).each do |a, b|
      assert_equal a['variety'], b['variety'], 'le tirage reste celui de la rue'
      next if a['id'] == id

      assert_equal a['definition_id'], b['definition_id']
    end
  end

  def test_out_of_style_own_setting_is_warned_like_the_variety
    r = run_engine(settings(tree({ ids[0] => { 'roof' => 'flat' } })))
    assert r.ok?, r.errors.map(&:to_h).inspect
    assert(r.warnings.any? { |d| d.path.start_with?("/parcels/#{ids[0]}") }, r.warnings.map(&:to_h).inspect)
  end

  # --- Largeur (D-21, A)

  def test_wider_parcel_takes_from_the_next_one_and_the_rest_stays
    before = layout(settings(tree))
    id = before[1]['id']
    after = layout(settings(tree({ id => { 'width_m' => before[1]['width_m'] + 2.0 } })))
    assert_equal before.map { |p| p['id'] }, after.map { |p| p['id'] }
    assert_in_delta before[1]['width_m'] + 2.0, after[1]['width_m'], 1e-6
    assert_in_delta before[2]['width_m'] - 2.0, after[2]['width_m'], 1e-6
    assert_in_delta before[2]['origin_m'][0] + 2.0, after[2]['origin_m'][0], 1e-6
    (before.each_index.to_a - [1, 2]).each { |i| assert_equal before[i], after[i] }
  end

  def test_last_parcel_of_a_segment_takes_from_the_previous_one
    before = layout(settings(tree))
    last = before.rindex { |p| p['segment'] == before.first['segment'] && !p['corner'] }
    skip 'pas de dernière parcelle droite' unless last && last == before.size - 1
    after = layout(settings(tree({ before[last]['id'] => { 'width_m' => before[last]['width_m'] - 1.0 } })))
    assert_in_delta before[last - 1]['width_m'] + 1.0, after[last - 1]['width_m'], 1e-6
    assert_in_delta before[last]['origin_m'][0] + 1.0, after[last]['origin_m'][0], 1e-6
  end

  def test_width_refusals_are_localized
    before = layout(settings(tree))
    id = before[1]['id']
    narrow = run_engine(settings(tree({ id => { 'width_m' => before[1]['width_m'] + before[2]['width_m'] - 5.0 } })))
    assert_includes reasons(narrow), ['E_STREET_PARCEL', "/parcels/#{id}/width_m", 'neighbour_too_narrow']
    both = run_engine(settings(tree({ id => { 'width_m' => 10 }, before[2]['id'] => { 'width_m' => 10 } })))
    assert_includes reasons(both), ['E_STREET_PARCEL', "/parcels/#{id}/width_m", 'width_locked']
    corner = layout(settings(tree(points: [[0, 0], [40, 0], [40, 30]]))).find { |p| p['corner'] }
    r = run_engine(settings(tree({ corner['id'] => { 'width_m' => 9 } }, points: [[0, 0], [40, 0], [40, 30]])))
    assert_includes reasons(r), ['E_STREET_PARCEL', "/parcels/#{corner['id']}/width_m", 'width_locked']
  end
end
