# frozen_string_literal: true

require_relative '../test_helper'

# U26 : rails et tram (docs/VOIRIE_CONTRACT.md, Rails) : écartement de 1,435 m en droite et en courbe,
# rails au ras de la chaussée en voie mixte et sur plateforme, voie sur traverses et ballast.
class RoadRailsTest < Minitest::Test
  include Archgen::Core

  GAUGE = 1.435
  TOL = 1e-5

  def intake
    @intake ||= Archgen::Composition.road_intake
  end

  def preset(id)
    Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def plan(points, radii, profile, **opts)
    settings = intake.settings({ 'trace' => { 'points_m' => points, 'radii_m' => radii }, 'profile' => profile })
    assert settings.ok?, settings.errors.map(&:to_h).inspect
    result = RoadEngine.call(settings.value, bands: Archgen::Composition.road_bands, items: Archgen::Composition.road_items, **opts)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def surface(plan)
    plan['nodes'][0]['children'].find { |c| c['id'] == 'road/surface' }['primitive']
  end

  def child(plan, id)
    plan['nodes'][0]['children'].find { |c| c['id'] == id }
  end

  def steel_faces(plan)
    s = surface(plan)
    s['faces'].select { |f| f['material'] == 'road/rail_steel' }.map { |f| f['indices'].map { |i| s['vertices'][i] } }
  end

  # --- Rails encastrés

  def test_mixed_street_rails_are_flush_and_at_standard_gauge_by_hand
    p = plan([[0, 0], [100, 0]], [], preset('mixte'))
    faces = steel_faces(p)
    assert_equal 4, faces.size
    assert(faces.flatten(1).all? { |v| v[2].zero? }, 'rails au niveau exact de la chaussée')
    # Voie de gauche : milieu à x = 4,65 dans la coupe, axe à 6,3 ; rails à y = 2,3675 et 0,9325, champignons de 7 cm.
    edges = faces.map { |f| f.map { |v| v[1] }.uniq.sort }.sort
    assert_equal [[-2.4025, -2.3325], [-0.9675, -0.8975], [0.8975, 0.9675], [2.3325, 2.4025]], edges
    centers = edges.map { |a, b| (a + b) / 2 }
    assert_in_delta GAUGE, centers[1] - centers[0], TOL
    assert_in_delta GAUGE, centers[3] - centers[2], TOL
  end

  def test_flush_rails_share_the_road_vertices_and_look_up
    p = plan([[0, 0], [100, 0]], [], preset('mixte'))
    s = surface(p)
    s['faces'].select { |f| f['material'] == 'road/rail_steel' }.each do |f|
      pts = f['indices'].map { |i| s['vertices'][i] }
      n = (pts[1][0] - pts[0][0]) * (pts[2][1] - pts[0][1]) - (pts[1][1] - pts[0][1]) * (pts[2][0] - pts[0][0])
      assert_operator n, :>, 0
    end
    # 17 points de coupe : trottoir (3 dont la bordure), contremarche, 4 bords de rails et le milieu de chaque voie, contremarche, trottoir (2).
    assert_equal p['metrics']['station_count'] * 17, s['vertices'].size
  end

  def test_tram_platform_rails_follow_a_curve_at_exact_gauge
    radius = 40.0
    p = plan([[0, 0], [100, 0], [100, 100]], [radius], preset('tram'))
    center = [100 - radius, radius]
    radii = steel_faces(p).flatten(1).select { |v| v[0] > center[0] + 1e-6 && v[1] > 1e-6 && v[1] < center[1] }
                          .map { |v| Math.hypot(v[0] - center[0], v[1] - center[1]).round(5) }.uniq.sort
    # Voie de gauche (milieu à 13,5 de la coupe de 22,8 m) : rails à R ± 0,7175 autour de 40 − (11,4 − 9,8).
    refute_empty radii
    assert_equal 8, radii.size
    track_left = radius - (11.4 - 9.8)
    track_right = radius - (11.4 - 13.0)
    expected = [track_left, track_right].flat_map { |c| [c - 0.7175, c + 0.7175] }.flat_map { |r| [r - 0.035, r + 0.035] }.map { |r| r.round(5) }.sort
    assert_equal expected, radii
  end

  # --- Voie sur ballast

  def test_ballast_track_rails_sleepers_by_hand
    p = plan([[0, 0], [100, 0]], [], preset('fer'))
    rails = child(p, 'road/linear')['children'].select { |n| n['id'].start_with?('rail/') }
    assert_equal 4, rails.size
    rails.each do |n|
      zs = n['primitive']['vertices'].map { |v| v[2] }.uniq.sort
      assert_equal [0.35, 0.52], zs
    end
    ys = rails.map { |n| n['primitive']['vertices'].map { |v| v[1] }.sum / n['primitive']['vertices'].size }.sort
    assert_in_delta GAUGE, ys[1] - ys[0], TOL
    assert_in_delta GAUGE, ys[3] - ys[2], TOL
    assert_in_delta 4.5, ys[2] - ys[0], TOL
    sleepers = child(p, 'road/sleepers')['children']
    # 0,30 m puis tous les 0,60 m jusqu'à 99,90 m : 167 par voie.
    assert_equal 334, sleepers.size
    assert_equal 334, p['metrics']['sleeper_count']
    first = sleepers.first['primitive']['matrix']
    assert_equal [0.3, 0.35], first.values_at(12, 14)
    top = p['definitions']['sleeper'].flat_map { |n| n['primitive']['vertices'] }.map { |v| v[2] }.max
    assert_in_delta 0.02, top, 1e-9
  end

  def test_ballast_rails_keep_their_gauge_around_a_curve
    radius = 30.0
    p = plan([[0, 0], [100, 0], [100, 100]], [radius], preset('fer'))
    center = [100 - radius, radius]
    child(p, 'road/linear')['children'].select { |n| n['id'].start_with?('rail/') }.each_slice(2) do |a, b|
      ra = arc_radii(a, center)
      rb = arc_radii(b, center)
      assert_in_delta GAUGE, ((ra.max + ra.min) / 2 - (rb.max + rb.min) / 2).abs, TOL
      assert_in_delta 0.07, ra.max - ra.min, TOL
    end
  end

  def test_tracks_survive_a_sharp_corner
    %w[fer tram mixte].each do |id|
      p = plan([[0, 0], [80, 0], [80, 80]], [0], preset(id))
      assert_empty RoadPlanValidator.call(p), id
    end
  end

  def test_sleeper_limit_and_first_step_beyond
    profile = preset('fer')
    assert plan([[0, 0], [100, 0]], [], profile, limits: { sleepers: 334 })
    settings = intake.settings({ 'trace' => { 'points_m' => [[0, 0], [100, 0]], 'radii_m' => [] }, 'profile' => profile }).value
    refused = RoadEngine.call(settings, bands: Archgen::Composition.road_bands, items: Archgen::Composition.road_items, limits: { sleepers: 333 })
    found = refused.errors.find { |d| d.params['reason'] == 'road_sleepers' }
    assert found
    assert_equal 334, found.params['value']
  end

  def test_sleepers_do_not_use_the_object_limit
    # 2 km de voie double : 6 666 traverses, au-delà des 5 000 objets mais sous les 20 000 traverses.
    p = plan([[0, 0], [1000, 0], [1000, 1000]], [200], preset('fer').merge('bands' => preset('fer')['bands'].map { |b| b.merge('items' => []) }))
    assert_operator p['metrics']['sleeper_count'], :>, Limits::ROAD_MAX_ITEMS
    assert_equal 0, p['metrics']['item_count'] - p['metrics']['sleeper_count']
  end

  def test_a_lane_has_no_rail
    p = plan([[0, 0], [100, 0]], [], preset('ville'))
    assert_empty steel_faces(p)
    assert_nil child(p, 'road/sleepers')
    assert_equal 0, p['metrics']['rail_count']
  end

  private

  def arc_radii(node, center)
    node['primitive']['vertices'].select { |v| v[0] > center[0] + 1e-6 && v[1] > 1e-6 && v[1] < center[1] - 1e-6 }
                                 .map { |v| Math.hypot(v[0] - center[0], v[1] - center[1]) }
  end
end
