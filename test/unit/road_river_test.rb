# frozen_string_literal: true

require_relative '../test_helper'

# U36 : rivière sur un terrain (docs/EAU_CONTRACT.md, AG-053). Rivière à berges de 32 m (eau de 18 m,
# revanche 1,2 m, profondeur 2 m) le long de x sur 100 m, terrain sans pente en travers :
# z = 20 − 0,02 s + bosse(s), bosse de h mètres centrée à 40 m, nulle au-delà de ± 10 m.
class RoadRiverTest < Minitest::Test
  include Archgen::Core

  C = Archgen::Composition
  G = Archgen::Geometry::RoadGround

  def preset(id)
    C.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def tree(water: { 'mode' => 'river' }, points: [[0, 0], [100, 0]], profile: 'riviere')
    { 'trace' => { 'points_m' => points, 'radii_m' => [] }, 'profile' => preset(profile), 'ground' => {}, 'water' => water }
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
    length = stations.each_cons(2).sum { |a, b| Math.hypot(b.point[0] - a.point[0], b.point[1] - a.point[1]) }
    axes = G.axes(length, width / 2, width / 2, G.settings(s['ground'])).value
    axes.merge('z_m' => axes['s_m'].map { |x| axes['u_m'].map { |u| terrain.call(x, u) } })
  end

  ENVELOPE = [[0, 20.0], [20, 19.6], [40, 19.6], [60, 18.8], [80, 18.4], [100, 18.0]].freeze

  def valley(bump)
    ->(s, _u) { 20 - (0.02 * s) + (bump * [0.0, 1 - ((s - 40).abs / 10.0)].max) }
  end

  def build(input, terrain)
    RoadEngine.call(settings(input), bands: C.road_bands, items: C.road_items, survey: survey(input, &terrain))
  end

  def plan(input, terrain)
    r = build(input, terrain)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def error(input, terrain)
    r = build(input, terrain)
    refute r.ok?
    r.errors.first
  end

  def water_vertices(plan)
    plan['nodes'][0]['children'].find { |n| n['id'] == 'road/water' }['primitive']['vertices']
  end

  # Points de pente 0, 20, …, 100 : 20 ; 19,6 ; 20,2 → 19,6 (enveloppe) ; 18,8 ; 18,4 ; 18. Pente de
  # 40 à 60 m : 0,8 / 20 = 4 %, au-delà de la borne de 3 % par défaut.
  def test_the_water_never_rises_over_a_bump
    p = plan(tree(water: { 'mode' => 'river', 'max_grade_percent' => 5 }), valley(1.0))
    m = p['metrics']
    assert_equal [2.0, 4.0, 20.0], m.values_at('water_drop_m', 'grade_max_percent', 'origin_z_m')
    vs = water_vertices(p).sort_by { |v| [v[0], v[1]] }
    by_x = vs.group_by { |v| v[0] }.transform_values { |list| list.map { |v| v[2] }.uniq }
    assert(by_x.values.all? { |zs| zs.size == 1 }, 'eau horizontale en travers')
    levels = by_x.sort.map { |_, zs| zs.first }
    assert_equal levels, levels.sort.reverse, 'eau jamais remontante'
    # Sans enveloppe, le point à 40 m serait à −1,0 m : l’eau y remonterait.
    assert_equal [-1.2, -1.6, -2.4, -2.8, -3.2], levels.uniq
    assert_empty RoadPlanValidator.call(p)
  end

  def test_the_river_grade_is_bounded_by_its_own_setting
    found = error(tree, valley(1.0))
    assert_equal ['E_ROAD_GRADE', '/water/max_grade_percent', 'grade_too_steep', 40.0, 3.0], [found.code, found.path, found.params['reason'], found.params['s_m'], found.params['limit']]
  end

  def test_a_trace_drawn_upstream_is_refused
    found = error(tree, ->(s, _u) { 18 + (0.02 * s) })
    assert_equal ['E_ROAD_WATER', '/trace', 'river_upstream', 2.0], [found.code, found.path, found.params['reason'], found.params['value']]
    assert build(tree, ->(s, _u) { 18 + (0.0099 * s) }).ok?, 'moins de 1 m de montée : accepté, l’enveloppe reste plate'
  end

  def test_digging_through_a_high_bump_is_bounded
    found = error(tree(water: { 'mode' => 'river', 'max_grade_percent' => 5 }), valley(4.0))
    assert_equal ['E_ROAD_EARTHWORK', 'earthwork_too_high', 40.0], [found.code, found.params['reason'], found.params['s_m']]
  end

  def test_banks_reach_the_terrain_and_items_follow_the_profile
    p = plan(tree(water: { 'mode' => 'river', 'max_grade_percent' => 5 }), valley(1.0))
    assert_operator p['metrics']['earthwork_face_count'], :>, 0
    tree_nodes = p['nodes'][0]['children'].find { |n| n['id'] == 'road/vegetation' }['children']
    tree_nodes.each do |n|
      x, _y, z = n['primitive']['matrix'].values_at(12, 13, 14)
      # Arbre sur la berge gauche, à mi-largeur : 0,6 m sous la base, base suivant l’enveloppe.
      assert_in_delta(G.z_at(ENVELOPE, x) - 20 - 0.6, z, 1e-6, "x #{x}")
    end
  end

  def test_flat_water_does_not_follow_a_terrain_yet
    r = C.road_intake.settings(tree(water: { 'mode' => 'flat' }))
    assert_equal ['/ground', 'water_ground_unavailable', 'flat'], [r.errors.first.path, r.errors.first.params['reason'], r.errors.first.params['mode']]
    # Un canal suit un terrain depuis AG-054, mais bordé de quais : pas cette rivière à berges.
    r = C.road_intake.settings(tree(water: { 'mode' => 'canal' }))
    assert_equal 'canal_needs_quays', r.errors.first.params['reason']
    refute C.road_intake.settings(tree(profile: 'plage', water: { 'mode' => 'flat' })).ok?
  end
end
