# frozen_string_literal: true

require_relative '../test_helper'

# U35 : littoral, falaise, estran, dune, plage et mer à niveaux cumulés (docs/EAU_CONTRACT.md, AG-052).
class RoadCoastTest < Minitest::Test
  include Archgen::Core

  def profiles
    Archgen::Composition.road_profile_intake
  end

  def bands
    Archgen::Composition.road_bands
  end

  def items
    Archgen::Composition.road_items
  end

  def preset(id)
    Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def profile(*list)
    { 'road_profile_version' => 1, 'bands' => list }
  end

  def band(type, width, **extra)
    { 'type' => type, 'width_m' => width }.merge(extra.transform_keys(&:to_s))
  end

  def section(tree)
    result = profiles.profile(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    Archgen::Geometry::RoadSection.call(result.value, bands: bands, items: items)
  end

  def refused(tree, code, path, reason)
    result = profiles.profile(tree)
    refute result.ok?
    found = result.errors.find { |d| d.code == code && d.path == path && d.params['reason'] == reason }
    assert found, result.errors.map(&:to_h).inspect
    found
  end

  def road(profile, water: { 'mode' => 'flat' }, points: [[0, 0], [100, 0]], radii: [], **rest)
    tree = { 'trace' => { 'points_m' => points, 'radii_m' => radii }, 'profile' => profile }
    tree['water'] = water if water
    tree.merge(rest.transform_keys(&:to_s))
  end

  def build(tree)
    s = Archgen::Composition.road_intake.settings(tree)
    return s unless s.ok?

    RoadEngine.call(s.value, bands: bands, items: items)
  end

  def plan(tree)
    result = build(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  # --- Niveaux cumulés, à la main

  def test_cliff_coast_by_hand
    s = section(preset('falaises'))
    rows = s['bands']
    assert_equal [[9.0, 0.0], [15.0, -25.0]], rows[3]['surface']
    assert_equal [[15.0, -25.0], [35.0, -25.0]], rows[4]['surface']
    # Fond marin : du pied de l'estran à 3 m de profondeur sur 10 m, puis plat.
    assert_equal [[35.0, -25.0], [45.0, -28.0], [235.0, -28.0]], rows[5]['surface']
    assert_equal [{ 'band' => 5, 'x0_m' => 35.0, 'x1_m' => 235.0, 'z_m' => -25.0 }], s['water']
    assert_equal [0.0, 0.0, 0.0, 0.0, -25.0, -25.0], rows.map { |r| r['base_m'] }
  end

  def test_dune_coast_by_hand
    s = section(preset('dunes'))
    dune = s['bands'][1]['surface']
    assert_equal 9, dune.size
    assert_equal [2.5, 0.0], dune.first
    assert_equal [20.0, 6.0], dune[4]
    assert_equal [37.5, 0.0], dune.last
    assert_equal [[37.5, 0.0], [97.5, -1.8]], s['bands'][2]['surface']
    assert_equal(-1.8, s['water'].first['z_m'])
    assert_equal [[97.5, -1.8], [107.5, -4.8], [297.5, -4.8]], s['bands'][3]['surface']
    fence = s['items'].find { |i| i['band'] == 2 }
    assert_in_delta 67.5, fence['x_m'], 1e-9
    assert_in_delta(-0.9, fence['z_m'], 1e-9)
    assert_equal 2, s['items'].count { |i| i['band'] == 1 && i['kind'] == 'sand_fence' }
  end

  def test_promenade_wall_and_beach_by_hand
    s = section(preset('plage'))
    assert_equal [[8.0, 0.0], [58.0, -2.0]], s['bands'][2]['surface']
    assert_equal [{ 'band' => 3, 'x0_m' => 58.0, 'x1_m' => 258.0, 'z_m' => -2.0 }], s['water']
    wall = s['items'].find { |i| i['kind'] == 'low_wall' }
    assert_in_delta 0.14, wall['z_m'], 1e-9
    line = Archgen::Geometry::RoadRibbons.cross_line(s)
    assert_includes line, [[8.0, 0.14], [8.0, 0.0], 'road/sidewalk']
    assert_includes line, [[58.0, -2.0], [68.0, -5.0], 'road/sea'] # le fond prolonge la plage, sans marche
  end

  def test_sea_on_the_left_mirrors_the_levels
    s = section(profile(band('sea', 100), band('beach', 20, slope_percent: 5), band('path', 2)))
    assert_equal [[100.0, -1.0], [120.0, 0.0]], s['bands'][1]['surface']
    assert_equal [[0.0, -4.0], [90.0, -4.0], [100.0, -1.0]], s['bands'][0]['surface']
    assert_equal(-1.0, s['water'].first['z_m'])
    assert_equal [[120.0, 0.02], [122.0, 0.02]], s['bands'][2]['surface']
  end

  # --- Refus

  def test_sea_is_alone_and_at_one_end
    refused(profile(band('path', 2), band('sea', 100), band('path', 2)), 'E_ROAD_BAND', '/bands/1', 'sea_not_outer')
    refused(profile(band('sea', 100), band('beach', 20), band('sea', 100)), 'E_ROAD_BAND', '/bands/2', 'sea_not_outer')
    assert profiles.profile(profile(band('path', 2), band('sea', 20))).ok?
  end

  def test_cliff_and_beach_need_a_sea
    refused(profile(band('path', 2), band('cliff', 6)), 'E_ROAD_BAND', '/bands/1', 'coast_without_sea')
    refused(profile(band('beach', 20), band('path', 2)), 'E_ROAD_BAND', '/bands/0', 'coast_without_sea')
    assert profiles.profile(profile(band('path', 2), band('dune', 20))).ok?
  end

  def test_items_on_coast_bands
    found = refused(profile(band('sidewalk', 3, items: [{ 'kind' => 'sand_fence' }])), 'E_ROAD_ITEM', '/bands/0/items/0/kind', 'item_band_mismatch')
    assert_equal %w[dune beach], found.params['allowed']
    refused(profile(band('plant', 3, items: [{ 'kind' => 'low_wall' }])), 'E_ROAD_ITEM', '/bands/0/items/0/kind', 'item_band_mismatch')
    refused(profile(band('cliff', 6, items: [{ 'kind' => 'lamp' }]), band('sea', 50)), 'E_ROAD_ITEM', '/bands/0/items/0', 'band_accepts_no_items')
    refused(profile(band('path', 2), band('sea', 50, items: [{ 'kind' => 'tree' }])), 'E_ROAD_ITEM', '/bands/1/items/0', 'band_accepts_no_items')
    assert profiles.profile(profile(band('beach', 20, items: [{ 'kind' => 'low_wall' }, { 'kind' => 'sand_fence' }]), band('sea', 50))).ok?
  end

  def test_coast_settings_stay_in_range_and_on_their_band
    { 'cliff' => ['height_m', 5, 80], 'dune' => ['height_m', 1, 15], 'beach' => ['slope_percent', 1, 10] }.each do |type, (key, min, max)|
      wrap = ->(v) { profile(band(type, bands['bands'][type]['default_width_m'], key => v), band('sea', 50)) }
      [min, max].each { |v| assert profiles.profile(wrap.call(v)).ok?, "#{type} #{v}" }
      [min - 0.001, max + 0.001].each { |v| refused(wrap.call(v), 'E_ROAD_BAND', "/bands/0/#{key}", 'setting_range') }
    end
    refused(profile(band('lane', 3.5, height_m: 2)), 'E_ROAD_BAND', '/bands/0/height_m', 'band_setting_unavailable')
    refused(profile(band('dune', 20, slope_percent: 2)), 'E_ROAD_BAND', '/bands/0/slope_percent', 'band_setting_unavailable')
  end

  def test_sea_requires_a_single_level
    result = Archgen::Composition.road_intake.settings(road(preset('plage'), water: { 'mode' => 'river' }))
    found = result.errors.find { |d| d.params['reason'] == 'sea_needs_flat' }
    assert_equal ['E_ROAD_WATER', '/water/mode', 'river'], [found.code, found.path, found.params['value']]
    result = Archgen::Composition.road_intake.settings(road(preset('plage'), water: nil))
    assert_equal 'water_mode_missing', result.errors.first.params['reason']
  end

  # Depuis AG-057, une côte entre dans un réseau ; ses nœuds sont des ponts (U39).
  def test_sea_is_accepted_in_a_network
    roads = [{ 'id' => 'a', 'road' => road(preset('plage')) }]
    assert Archgen::Composition.road_network_intake.settings({ 'network_version' => 1, 'roads' => roads }).ok?
  end

  # --- Plan

  def test_cliff_coast_plan
    p = plan(road(preset('falaises')))
    water = p['nodes'][0]['children'].find { |n| n['id'] == 'road/water' }['primitive']
    assert(water['vertices'].all? { |v| v[2] == -25.0 })
    assert_equal [-28.0, 0.05], p['nodes'][0]['children'][0]['primitive']['vertices'].map { |v| v[2] }.minmax
    assert_empty RoadPlanValidator.call(p)
  end

  def test_dune_coast_plan_has_sand_fences_with_posts
    p = plan(road(preset('dunes')))
    furniture = p['nodes'][0]['children'].find { |n| n['id'] == 'road/furniture' }['children']
    assert_equal 3, furniture.count { |n| n['id'].start_with?('sand_fence/') }
    assert_equal 3 * 51, furniture.count { |n| n['id'].start_with?('post/') } # 0 à 100 m tous les 2 m
    assert_empty RoadPlanValidator.call(p)
  end

  def test_sea_on_the_concave_side_needs_a_large_radius
    left_turn = road(preset('falaises'), points: [[0, 0], [400, 0], [400, 400]], radii: [50], axis: 'left')
    assert build(left_turn).ok?, build(left_turn).errors.map(&:to_h).inspect
    right_turn = road(preset('falaises'), points: [[0, 0], [400, 0], [400, -400]], radii: [50], axis: 'left')
    error = build(right_turn).errors.find { |d| d.params['reason'] == 'radius_too_small' }
    assert_equal ['/trace/radii_m/0', 236.0], [error.path, error.params['min']]
    assert build(road(preset('falaises'), points: [[0, 0], [400, 0], [400, -400]], radii: [236], axis: 'left')).ok?
  end

  def test_the_three_coast_presets_draw_along_a_large_curve
    %w[falaises dunes plage].each do |id|
      p = plan(road(preset(id), points: [[0, 0], [700, 0], [700, 700]], radii: [350]))
      assert_operator p['metrics']['water_face_count'], :>, 10, id
      assert_empty RoadPlanValidator.call(p), id
    end
  end
end
