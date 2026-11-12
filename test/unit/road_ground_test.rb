# frozen_string_literal: true

require_relative '../test_helper'
require File.expand_path('../../archgen/ui/messages', __dir__)

# U32 : voie sur un terrain, étape 1 (docs/VOIRIE_CONTRACT.md, Terrain ; AG-049, ADR-38). Terrain
# plan z = 10 + 0,05 s + 0,1 u (u à gauche) sous une rue de ville de 13 m (chaussée ± 4 m, trottoirs
# à 0,14 m) : pente en long 5 %, déblai 0,51 m à gauche, remblai 0,79 m à droite, talus à 1,5.
class RoadGroundTest < Minitest::Test
  include Archgen::Core

  TOL = 1e-5
  C = Archgen::Composition
  G = Archgen::Geometry::RoadGround

  def preset(id)
    C.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def tree(points: [[0, 0], [100, 0]], radii: [], profile: 'ville', ground: {})
    t = { 'trace' => { 'points_m' => points, 'radii_m' => radii }, 'profile' => preset(profile) }
    ground ? t.merge('ground' => ground) : t
  end

  def settings(input)
    s = C.road_intake.settings(input)
    assert s.ok?, s.errors.map(&:to_h).inspect
    s.value
  end

  # Grille relevée sur une fonction z(s, u) ; `hole` : un nœud sans terrain.
  def survey(input, hole: nil, &terrain)
    s = settings(input)
    section = Archgen::Geometry::RoadSection.call(s['profile'], bands: C.road_bands, items: C.road_items)
    width = section['width_m']
    stations = Archgen::Geometry::RoadAxis.call(s['trace']['points_m'], s['trace']['radii_m'], left_m: width / 2, right_m: width / 2).value
    length = stations.each_cons(2).sum { |a, b| Math.hypot(b.point[0] - a.point[0], b.point[1] - a.point[1]) }
    axes = G.axes(length, width / 2, width / 2, G.settings(s['ground'])).value
    z = axes['s_m'].each_with_index.map do |x, i|
      # :axis20 : le nœud sous l'axe, à 20 m du départ.
      axes['u_m'].each_with_index.map { |u, j| hole == :axis20 && (x - 20).abs < 1e-6 && u.zero? ? nil : terrain.call(x, u) }
    end
    axes.merge('z_m' => z)
  end

  def build(input, grid)
    RoadEngine.call(settings(input), bands: C.road_bands, items: C.road_items, survey: grid)
  end

  def plan(input, grid)
    r = build(input, grid)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def reasons(input, grid)
    build(input, grid).errors.map { |d| d.params['reason'] }
  end

  def node(plan, id)
    plan['nodes'][0]['children'].find { |c| c['id'] == id }
  end

  PLANE = ->(s, u) { 10 + (0.05 * s) + (0.1 * u) }

  def test_a_road_without_ground_is_unchanged
    flat = RoadEngine.call(settings(tree(ground: nil)), bands: C.road_bands, items: C.road_items).value
    assert_nil node(flat, 'road/earthwork')
    refute flat['metrics'].key?('grade_max_percent')
    assert(flat['nodes'][0]['children'][0]['primitive']['vertices'].all? { |v| v[2] <= 0.14 + TOL })
  end

  def test_the_profile_and_the_slopes_by_hand
    input = tree
    p = plan(input, survey(input, &PLANE))
    m = p['metrics']
    assert_in_delta 5.0, m['grade_max_percent'], TOL
    assert_in_delta 10.0, m['origin_z_m'], TOL
    assert_in_delta 0.51, m['cut_max_m'], TOL
    assert_in_delta 0.79, m['fill_max_m'], TOL
    assert_in_delta 0.79 / ((1 / 1.5) - 0.1), m['earthwork_reach_m'], 1e-4
    # Chaussée à la cote du profil : z relatif = 0,05 s, stations tous les 20 m.
    surface = node(p, 'road/surface')['primitive']['vertices']
    lane = surface.select { |v| v[1].abs < 4 - TOL }
    assert(lane.all? { |v| (v[2] - (0.05 * v[0])).abs < TOL })
    assert_equal [0.0, 20.0, 40.0, 60.0, 80.0, 100.0], surface.map { |v| v[0].round(6) }.uniq.sort
  end

  def test_slope_feet_reach_the_terrain
    input = tree
    p = plan(input, survey(input, &PLANE))
    verts = node(p, 'road/earthwork')['primitive']['vertices']
    edges = verts.select { |v| (v[1].abs - 6.5).abs < TOL }
    feet = verts - edges
    refute_empty feet
    # Pied : sur le terrain, plus ou moins 0,05 m (déblai au-dessus, remblai en dessous), repère de la racine.
    feet.each do |v|
      ground = PLANE.call(v[0], v[1]) - 10
      assert_in_delta 0.05, (v[2] - ground).abs, 1e-4, v.inspect
    end
    faces = node(p, 'road/earthwork')['primitive']['faces']
    assert(faces.all? { |f| f['material'] == 'road/bank' })
  end

  def test_items_follow_the_profile
    input = tree
    p = plan(input, survey(input, &PLANE))
    lamps = []
    walk = lambda do |n|
      lamps << n['primitive']['matrix'] if n['primitive'] && n['primitive']['type'] == 'instance'
      n['children'].each(&walk)
    end
    p['nodes'].each(&walk)
    refute_empty lamps
    lamps.each { |m| assert_in_delta 0.14 + (0.05 * m[12]), m[14], 1e-4 }
  end

  def test_a_curve_follows_the_profile_without_breaking_the_plan
    input = tree(points: [[0, 0], [80, 0], [80, 60]], radii: [30])
    p = plan(input, survey(input) { |s, u| 5 + (0.03 * s) + (0.02 * u) })
    assert_operator p['metrics']['earthwork_face_count'], :>, 0
    assert_operator p['metrics']['grade_max_percent'], :<=, 3.0 + TOL
  end

  def test_refusals
    input = tree
    assert_equal ['grade_too_steep'], reasons(input, survey(input) { |s, u| (0.1 * s) + (0.01 * u) }).uniq
    rail = tree(profile: 'fer')
    assert_equal ['grade_too_steep'], reasons(rail, survey(rail) { |s, _u| 0.03 * s }).uniq
    assert_equal 2.5, build(rail, survey(rail) { |s, _u| 0.03 * s }).errors.first.params['limit']
    assert_equal ['earthwork_too_high'], reasons(input, survey(input) { |_s, u| u.abs > 5 ? 0 : 0.0 + (u > 6 ? 20 : 0) }.tap { |g| g['z_m'] = g['z_m'].map { |row| row.each_with_index.map { |z, j| g['u_m'][j] >= 6.5 ? z + 9 : z } } })
    assert_equal ['road_toe_not_found'], reasons(input, survey(input) { |_s, u| -0.7 * u.abs })
    assert_equal ['ground_missing'], reasons(input, survey(input, hole: :axis20, &PLANE))
    assert_equal ['survey_missing'], reasons(input, nil)
    grid = survey(input, &PLANE)
    grid['s_m'] = grid['s_m'].map { |v| v + 1 }
    assert_equal ['survey_axes'], reasons(input, grid)
    long = tree(points: [[0, 0], [1900, 0]], ground: { 'survey_step_m' => 1 })
    assert_equal ['ground_points'], reasons(long, nil)
    %w[survey_missing survey_axes ground_missing ground_points grade_too_steep earthwork_too_high road_toe_not_found].each do |r|
      assert Archgen::UI::Messages::REASONS.key?(r), r
    end
  end

  def test_ground_settings_are_closed_and_bounded
    refute C.road_intake.settings(tree(ground: { 'survey_step_m' => 0.5 })).ok?
    refute C.road_intake.settings(tree(ground: { 'autre' => 1 })).ok?
    s = settings(tree(ground: { 'slope_ratio' => 2 }))
    assert_equal({ 'survey_step_m' => 4.0, 'grade_step_m' => 20.0, 'max_grade_percent' => 8.0, 'slope_ratio' => 2.0 }, s['ground'])
  end
end
