# frozen_string_literal: true

require_relative '../test_helper'

# U23, coupe dessinée : bords, surfaces, bordures, rails, éléments (docs/VOIRIE_CONTRACT.md).
class RoadSectionTest < Minitest::Test
  Section = Archgen::Geometry::RoadSection
  TOL = 1e-9

  def intake
    @intake ||= Archgen::Composition.road_profile_intake
  end

  def preset(id)
    Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def section(tree)
    result = intake.profile(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    Section.call(result.value, bands: Archgen::Composition.road_bands, items: Archgen::Composition.road_items)
  end

  def test_city_street_edges_and_curbs_by_hand
    s = section(preset('ville'))
    assert_in_delta 13.0, s['width_m'], TOL
    assert_equal [[0, 2.5], [2.5, 4.5], [4.5, 7.5], [7.5, 10.5], [10.5, 13]], s['bands'].map { |b| [b['x0_m'], b['x1_m']] }
    assert_equal [[2.5, 0, 'left', 0.0, 0.14], [10.5, 4, 'right', 0.0, 0.14]],
                 s['curbs'].map { |c| [c['x_m'], c['band'], c['side'], c['z_low_m'], c['z_high_m']] }
    assert(s['curbs'].all? { |c| c['width_m'] == 0.16 })
  end

  def test_a_small_step_has_no_curb_and_a_twelve_centimetre_step_has_one
    assert_empty section('bands' => [{ 'type' => 'cycle', 'width_m' => 2 }, { 'type' => 'lane', 'width_m' => 3 }])['curbs']
    assert_empty section('bands' => [{ 'type' => 'tram', 'width_m' => 3.2 }, { 'type' => 'lane', 'width_m' => 3 }])['curbs']
    curbs = section('bands' => [{ 'type' => 'sidewalk', 'width_m' => 2 }, { 'type' => 'cycle', 'width_m' => 2 }])['curbs']
    assert_equal 1, curbs.size
    assert_in_delta 0.12, curbs[0]['z_high_m'] - curbs[0]['z_low_m'], 1e-9
  end

  def test_ditch_is_a_trapezoid_with_a_thirty_percent_floor
    ditch = section('bands' => [{ 'type' => 'verge', 'width_m' => 1 }, { 'type' => 'ditch', 'width_m' => 1.5 }])['bands'][1]
    assert_equal [[1.0, 0.0], [1.525, -0.6], [1.975, -0.6], [2.5, 0.0]], ditch['surface']
  end

  def test_banks_rise_away_from_the_middle
    s = section(preset('autoroute'))
    first = s['bands'].first['surface']
    last = s['bands'].last['surface']
    assert_equal [[0.0, 1.2], [3.0, 0.0]], first
    assert_in_delta 1.2, last[1][1], TOL
    assert_in_delta 0.0, last[0][1], TOL
  end

  def test_rails_are_centred_at_standard_gauge
    s = section(preset('fer'))
    rails = s['rails']
    assert_equal 4, rails.size
    assert_in_delta 5.25 - 0.7175, rails[0]['x_m'], 1e-6
    assert_in_delta 5.25 + 0.7175, rails[1]['x_m'], 1e-6
    assert_in_delta 0.52, rails[0]['z_m'], 1e-9
    mixed = section(preset('mixte'))['rails']
    assert(mixed.all? { |r| r['kind'] == 'embedded' && r['z_m'].zero? })
  end

  def test_items_are_spread_across_their_band_with_counts_per_hundred_metres
    s = section(preset('ville'))
    lamp, bollard = s['items']
    assert_equal ['lamp', 1.25, 0.14, 'right', 5], lamp.values_at('kind', 'x_m', 'z_m', 'toward', 'count_per_100m')
    assert_equal ['bollard', 11.75, 'left', 40], bollard.values_at('kind', 'x_m', 'toward', 'count_per_100m')
    two = section(preset('mixte'))['items'].first(2)
    assert_equal [1.0, 2.0], two.map { |i| i['x_m'] }
  end

  def test_count_rule_of_the_contract
    assert_equal 11, Section.count_over(9) # 4,5 puis tous les 9 m : 4,5 à 94,5
    assert_equal 1, Section.count_over(200) # 100 m tout juste
    assert_equal 1, Section.count_over(150)
    assert_equal 0, Section.count_over(201)
    assert_equal 100, Section.count_over(1)
  end

  def test_tree_crown_comes_from_the_catalogue
    tree = section(preset('boulevard'))['items'].first
    assert_in_delta 0.34 * 12, tree['crown_radius_m'], 1e-6
    assert_in_delta 0.32 * 12, tree['crown_base_m'], 1e-6
    assert_in_delta 0.14, tree['z_m'], TOL
  end

  def test_continuous_items_have_no_count
    hedge = section(preset('campagne'))['items'].first
    assert_equal 'continuous', hedge['repeat']
    refute hedge.key?('count_per_100m')
  end

  def test_mirror_gives_the_mirrored_section
    profile = preset('boulevard')
    mirrored = profile.merge('bands' => profile['bands'].reverse)
    a = section(profile)
    b = section(mirrored)
    w = a['width_m']
    xs = ->(s) { s['items'].map { |i| i['x_m'].round(6) }.sort }
    assert_equal xs.call(a), xs.call(b).map { |x| (w - x).round(6) }.sort
    assert_equal a['curbs'].map { |c| c['x_m'] }.sort, b['curbs'].map { |c| (w - c['x_m']).round(6) }.sort
  end

  def test_every_preset_gives_a_section_whose_surface_is_continuous
    Archgen::Composition.road_presets.fetch('presets').each do |p|
      s = section(p['profile'])
      s['bands'].each_cons(2) { |a, b| assert_in_delta a['x1_m'], b['x0_m'], TOL, p['id'] }
      assert_in_delta s['width_m'], s['bands'].last['x1_m'], 1e-6, p['id']
      assert_equal s, section(p['profile']), "#{p['id']} déterministe"
    end
  end
end
