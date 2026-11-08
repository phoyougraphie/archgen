# frozen_string_literal: true

require_relative '../test_helper'

# U34 : bandes d'eau et de berge, voie à eau horizontale (docs/EAU_CONTRACT.md, AG-051).
class RoadWaterTest < Minitest::Test
  include Archgen::Core

  OLD_PRESETS = %w[autoroute nationale campagne rural boulevard ville mixte tram fer verte pieton].freeze

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

  # Quai de 2 m, eau de 10 m (revanche 1, profondeur 2), berge de 4 m.
  def basin
    profile(band('quay', 2), band('water', 10, freeboard_m: 1, depth_m: 2), band('riverbank', 4))
  end

  def section(tree)
    result = profiles.profile(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    Archgen::Geometry::RoadSection.call(result.value, bands: bands, items: items)
  end

  def refused(tree, path, reason)
    result = profiles.profile(tree)
    refute result.ok?
    found = result.errors.find { |d| d.code == 'E_ROAD_BAND' && d.path == path && d.params['reason'] == reason }
    assert found, result.errors.map(&:to_h).inspect
    found
  end

  def road(profile, water: { 'mode' => 'flat' }, **rest)
    tree = { 'trace' => { 'points_m' => [[0, 0], [100, 0]], 'radii_m' => [] }, 'profile' => profile }
    tree['water'] = water if water
    tree.merge(rest.transform_keys(&:to_s))
  end

  def settings(tree)
    Archgen::Composition.road_intake.settings(tree)
  end

  def plan(tree)
    s = settings(tree)
    assert s.ok?, s.errors.map(&:to_h).inspect
    result = RoadEngine.call(s.value, bands: bands, items: items)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def water_error(tree, path, reason)
    result = settings(tree)
    refute result.ok?
    assert(result.errors.any? { |d| d.code == 'E_ROAD_WATER' && d.path == path && d.params['reason'] == reason }, result.errors.map(&:to_h).inspect)
  end

  # --- Coupe

  def test_bed_wall_and_bank_by_hand
    s = section(basin)
    rows = s['bands']
    assert_equal [[0.0, 0.0], [2.0, 0.0]], rows[0]['surface']
    # Contre le quai, le lit va jusqu'au pied du mur ; contre la berge, il remonte en 1 pour 2 sur 4 m.
    assert_equal [[2.0, -3.0], [8.0, -3.0], [12.0, -1.0]], rows[1]['surface']
    assert_equal [[12.0, -1.0], [16.0, 0.0]], rows[2]['surface']
    assert_equal [{ 'band' => 1, 'x0_m' => 2.0, 'x1_m' => 12.0, 'z_m' => -1.0 }], s['water']
    assert_equal [1.0, 2.0], rows[1].values_at('freeboard_m', 'depth_m')
    assert_empty s['curbs']
  end

  def test_two_banks_make_a_trapezoid_and_the_quay_wall_is_a_riser
    s = section(profile(band('riverbank', 3), band('water', 9, freeboard_m: 1.5, depth_m: 1), band('riverbank', 3)))
    assert_equal [[3.0, -1.5], [5.0, -2.5], [10.0, -2.5], [12.0, -1.5]], s['bands'][1]['surface']
    assert_equal [[0.0, 0.0], [3.0, -1.5]], s['bands'][0]['surface']
    line = Archgen::Geometry::RoadRibbons.cross_line(section(basin))
    wall = line.find { |a, b, _| a[0] == 2.0 && b[0] == 2.0 }
    assert_equal [[2.0, 0.0], [2.0, -3.0], 'road/quay'], wall
  end

  def test_item_on_a_bank_stands_on_its_slope
    s = section(preset('riviere'))
    tree = s['items'].find { |i| i['kind'] == 'tree' }
    assert_in_delta 4.5, tree['x_m'], 1e-9
    assert_in_delta(-0.6, tree['z_m'], 1e-9) # berge de 2 à 7 m, de 0 à −1,2 m
  end

  # --- Refus de la coupe

  def test_water_needs_a_quay_or_a_bank_on_each_side
    found = refused(profile(band('quay', 2), band('water', 10)), '/bands/1', 'water_unbounded')
    assert_equal 'right', found.params['side']
    refused(profile(band('sidewalk', 2), band('water', 10), band('quay', 2)), '/bands/1', 'water_unbounded')
    refused(profile(band('water', 10), band('quay', 2)), '/bands/0', 'water_unbounded')
  end

  def test_water_too_narrow_for_its_banks_first_step_beyond
    ok = profile(band('riverbank', 3), band('water', 8, depth_m: 2), band('riverbank', 3))
    assert profiles.profile(ok).ok?
    found = refused(profile(band('riverbank', 3), band('water', 7.999, depth_m: 2), band('riverbank', 3)), '/bands/1/width_m', 'water_too_narrow')
    assert_equal 8.0, found.params['min']
    assert profiles.profile(profile(band('quay', 2), band('water', 4, depth_m: 2), band('riverbank', 3))).ok?
  end

  def test_bank_belongs_to_one_water_and_is_not_steeper_than_one_for_one
    refused(profile(band('riverbank', 3), band('path', 2)), '/bands/0', 'bank_without_water')
    refused(profile(band('quay', 1), band('water', 10), band('riverbank', 3), band('water', 10), band('quay', 1)), '/bands/2', 'bank_without_water')
    assert profiles.profile(profile(band('quay', 1), band('water', 10, freeboard_m: 2), band('riverbank', 2))).ok?
    found = refused(profile(band('quay', 1), band('water', 10, freeboard_m: 2), band('riverbank', 1.999)), '/bands/2/width_m', 'bank_too_steep')
    assert_equal 2.0, found.params['min']
  end

  def test_band_settings_belong_to_water_and_stay_in_range
    refused(profile(band('lane', 3.5, freeboard_m: 1)), '/bands/0/freeboard_m', 'band_setting_unavailable')
    entry = bands['bands']['water']['settings']
    { 'freeboard_m' => entry['freeboard_m'], 'depth_m' => entry['depth_m'] }.each do |key, range|
      [range['min'], range['max']].each do |v|
        assert profiles.profile(profile(band('quay', 2), band('water', 40, key => v), band('quay', 2))).ok?, "#{key} #{v}"
      end
      [range['min'] - 0.001, range['max'] + 0.001].each do |v|
        refused(profile(band('quay', 2), band('water', 40, key => v), band('quay', 2)), "/bands/1/#{key}", 'setting_range')
      end
    end
  end

  def test_effective_profile_completes_water_only
    value = profiles.profile(profile(band('quay', 2), band('water', 10), band('quay', 2))).value
    assert_equal({ 'type' => 'water', 'width_m' => 10.0, 'depth_m' => 2.0, 'freeboard_m' => 1.0, 'items' => [] }, value['bands'][1])
    assert_equal %w[type width_m items], value['bands'][0].keys
  end

  # --- Réglage water et plan

  def test_water_setting_is_required_by_water_and_refused_without
    water_error(road(basin, water: nil), '/water', 'water_mode_missing')
    water_error(road(preset('ville')), '/water', 'water_without_band')
    water_error(road(basin, ground: {}), '/ground', 'water_ground_unavailable')
    result = settings(road(basin, water: { 'mode' => 'lake' }))
    assert_equal 'E_SCHEMA', result.errors.first.code
  end

  def test_effective_water_setting_takes_the_contract_defaults
    value = settings(road(basin, water: { 'mode' => 'canal', 'lock_drop_m' => 2.5 })).value['water']
    assert_equal({ 'mode' => 'canal', 'max_grade_percent' => 3.0, 'lock_drop_m' => 2.5, 'lock_length_m' => 40.0 }, value)
    assert_equal(-12.5, settings(road(basin, water: { 'mode' => 'flat', 'level_m' => -12.5 })).value['water']['level_m'])
  end

  def test_horizontal_water_plan_has_its_surface_apart
    p = plan(road(basin))
    nodes = p['nodes'][0]['children'].map { |n| n['id'] }
    assert_equal %w[road/surface road/water], nodes.first(2)
    water = p['nodes'][0]['children'][1]['primitive']
    assert_equal 1, water['faces'].size
    assert_equal ['road/water_surface'], water['faces'].map { |f| f['material'] }.uniq
    assert(water['vertices'].all? { |v| v[2] == -1.0 })
    assert_equal 1, p['metrics']['water_face_count']
    zs = p['nodes'][0]['children'][0]['primitive']['vertices'].map { |v| v[2] }
    assert_equal [-3.0, 0.0], zs.minmax
    assert_empty RoadPlanValidator.call(p)
  end

  def test_the_three_water_presets_draw_along_a_curve
    %w[canal riviere fleuve].each do |id|
      p = plan(road(preset(id), trace: { 'points_m' => [[0, 0], [300, 0], [300, 300]], 'radii_m' => [150] }))
      assert_operator p['metrics']['water_face_count'], :>, 10, id
      assert_empty RoadPlanValidator.call(p), id
    end
  end

  def test_existing_presets_keep_their_shape
    OLD_PRESETS.each do |id|
      value = profiles.profile(preset(id)).value
      assert(value['bands'].none? { |b| b.key?('freeboard_m') || b.key?('depth_m') }, id)
      p = plan(road(preset(id), water: nil))
      refute(p['nodes'][0]['children'].any? { |n| n['id'] == 'road/water' }, id)
      refute p['metrics'].key?('water_face_count'), id
    end
  end

  def test_water_is_refused_in_a_network
    roads = [{ 'id' => 'a', 'road' => road(basin) }]
    result = Archgen::Composition.road_network_intake.settings({ 'network_version' => 1, 'roads' => roads })
    refute result.ok?
    assert(result.errors.any? { |d| d.code == 'E_ROAD_WATER' && d.path == '/roads/0/road/profile' && d.params['reason'] == 'water_in_network' })
  end
end
