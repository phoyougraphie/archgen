# frozen_string_literal: true

require_relative '../test_helper'

# U38 : fleuve et côte à un seul niveau sur un terrain (docs/EAU_CONTRACT.md, AG-055).
class RoadFlatWaterTest < Minitest::Test
  include Archgen::Core

  C = Archgen::Composition
  G = Archgen::Geometry::RoadGround

  def preset(id)
    C.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def tree(profile, water: {})
    { 'trace' => { 'points_m' => [[0, 0], [100, 0]], 'radii_m' => [] }, 'profile' => preset(profile), 'ground' => {},
      'water' => { 'mode' => 'flat' }.merge(water) }
  end

  def settings(input)
    s = C.road_intake.settings(input)
    assert s.ok?, s.errors.map(&:to_h).inspect
    s.value
  end

  def survey(input, &terrain)
    s = settings(input)
    width = Archgen::Geometry::RoadSection.call(s['profile'], bands: C.road_bands, items: C.road_items)['width_m']
    stations = Archgen::Geometry::RoadAxis.call(s['trace']['points_m'], [], left_m: width / 2, right_m: width / 2).value
    axes = G.axes(100.0, width / 2, width / 2, G.settings(s['ground'])).value
    axes.merge('z_m' => axes['s_m'].map { |x| axes['u_m'].map { |u| terrain.call(x, u) } })
  end

  def build(input, terrain)
    RoadEngine.call(settings(input), bands: C.road_bands, items: C.road_items, survey: survey(input, &terrain))
  end

  def plan(input, terrain)
    r = build(input, terrain)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  GENTLE = ->(s, _u) { 10 - (0.01 * s) }
  FLAT = ->(_s, _u) { 5.0 }

  # Moyennes sous l'eau 10 ; 9,8 ; … ; 9 : le fleuve se pose au plus bas, 9 m, sur toute sa longueur.
  def test_river_at_the_lowest_grade_point
    p = plan(tree('fleuve'), GENTLE)
    m = p['metrics']
    assert_equal [9.0, 0.0, 0.0], m.values_at('origin_z_m', 'water_drop_m', 'grade_max_percent')
    assert_in_delta 1.0, m['cut_max_m'], 1e-6 # quai à 9 m sous un terrain à 10 m, au départ ; le lit ne compte pas
    water = p['nodes'][0]['children'].find { |n| n['id'] == 'road/water' }['primitive']['vertices']
    assert_equal [-3.0], water.map { |v| v[2] }.uniq
    assert_empty RoadPlanValidator.call(p)
  end

  def test_level_given_by_the_user
    p = plan(tree('fleuve', water: { 'level_m' => 9.5 }), GENTLE)
    assert_equal 9.5, p['metrics']['origin_z_m']
  end

  def test_a_terrain_too_steep_for_one_level_is_refused
    r = build(tree('fleuve'), ->(s, _u) { 10 - (0.1 * s) })
    refute r.ok?
    assert_equal %w[E_ROAD_EARTHWORK earthwork_too_high], [r.errors.first.code, r.errors.first.params['reason']]
  end

  # Plage et promenade, mer à droite : pas de talus côté mer, l'entaille s'arrête au bord de la mer.
  def test_sea_side_has_no_slope_and_the_cut_stops_at_the_sea_edge
    p = plan(tree('plage', water: { 'level_m' => 5 }), FLAT)
    half = p['metrics']['width_m'] / 2
    right = p['ground']['outline_m'].select { |_x, y| y.negative? }
    assert(right.all? { |_x, y| (y + half).abs < 1e-6 }, right.inspect)
    left = p['ground']['outline_m'].select { |_x, y| y.positive? }
    assert(left.all? { |_x, y| y >= half - 1e-6 })
    assert_equal 0.0, p['metrics']['origin_z_m'] - 5.0
    assert_empty RoadPlanValidator.call(p)
  end

  def test_a_cliff_coast_cuts_a_flat_terrain_without_earthwork_refusal
    p = plan(tree('falaises', water: { 'level_m' => 5 }), FLAT)
    sea = p['nodes'][0]['children'].find { |n| n['id'] == 'road/water' }['primitive']['vertices']
    assert_equal [-25.0], sea.map { |v| v[2] }.uniq
    assert_operator p['metrics']['earthwork_face_count'], :>, 0
  end

  def test_sea_on_the_left_leaves_the_left_side_open
    profile = { 'road_profile_version' => 1, 'bands' => [{ 'type' => 'sea', 'width_m' => 50 }, { 'type' => 'beach', 'width_m' => 20 }, { 'type' => 'path', 'width_m' => 3 }] }
    input = tree('plage', water: { 'level_m' => 5 }).merge('profile' => profile)
    p = plan(input, FLAT)
    left = p['ground']['outline_m'].select { |_x, y| y.positive? }
    assert(left.all? { |_x, y| (y - 36.5).abs < 1e-6 }, left.inspect)
  end
end
