# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/road_net'
require File.expand_path('../../archgen/ui/messages', __dir__)

# U33 : passage à niveau (docs/VOIRIE_CONTRACT.md, Carrefours ; AG-050). Voie ferrée double (emprise
# 15 m, rails à 0,52 m) croisée à angle droit par une rue de ville (13 m) : platelage à 0,515 m,
# rampes de 12,875 m à 4 %, demi-platelage de 8 m ; la voie ferrée reste entière.
class RoadCrossingTest < Minitest::Test
  include Archgen::Core
  include RoadNet

  TOL = 1e-5
  RAIL = RoadNet.road('a', [[0, 0], [100, 0]], 'fer')

  def crossing(road_b, **opts)
    roads = [RAIL, road_b]
    id = build(network(*roads)).errors.first.path.split('/').last
    network(*roads, junctions: [{ 'id' => id, 'type' => 'level_crossing' }.merge(opts.transform_keys(&:to_s))])
  end

  def plan(tree)
    r = build(tree)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def reasons(tree)
    build(tree).errors.map { |d| d.params['reason'] }.uniq
  end

  def nodes(plan, prefix)
    out = []
    walk = lambda do |n|
      out << n if n['id'].start_with?(prefix)
      n['children'].each(&walk)
    end
    plan['nodes'].each(&walk)
    out
  end

  def straight
    plan(crossing(road('b', [[50, -60], [50, 60]])))
  end

  def test_deck_and_ramps_by_hand
    p = straight
    j = p['junctions'].first
    assert_equal ['level_crossing', 0.515, 12.875], j.values_at('type', 'deck_m', 'ramp_m')
    assert_equal 1, p['metrics']['crossing_count']
    # Chaussée de la rue (à moins de 3,9 m de x = 50, cote de bande 0) : 0,515 sur ± 8 m, rampe jusqu'à
    # ± 20,875 m, 0 au-delà.
    axis = surface(p)['vertices'].select { |v| (v[0] - 50).abs < 3.9 && v[1].abs <= 60 }
    expected = lambda do |y|
      d = y.abs
      d <= 8 ? 0.515 : (d >= 20.875 ? 0.0 : 0.515 * (20.875 - d) / 12.875)
    end
    refute_empty axis
    axis.each { |v| assert_in_delta expected.call(v[1]), v[2], TOL, v.inspect }
    assert(axis.any? { |v| (v[1] - 8).abs < TOL } && axis.any? { |v| (v[1] - 20.875).abs < TOL })
  end

  def test_the_railway_stays_whole_and_rails_rise_above_the_deck
    p = straight
    rails = nodes(p, 'rail/')
    assert_equal 4, rails.size
    rails.each do |r|
      xs = r['primitive']['vertices'].map(&:first)
      assert_in_delta 0.0, xs.min, TOL
      assert_in_delta 100.0, xs.max, TOL
      assert_in_delta 0.52, r['primitive']['vertices'].map { |v| v[2] }.max, TOL
    end
    sleepers = nodes(p, 'sleeper/').map { |n| n['primitive']['matrix'][12] }
    assert(sleepers.any? { |x| (x - 50).abs < 1 }, 'traverses sous le platelage')
  end

  def test_other_railway_items_stop_at_the_road
    p = straight
    fences = nodes(p, 'fence/')
    refute_empty fences
    fences.each do |f|
      xs = f['primitive']['vertices'].map(&:first)
      assert(xs.max <= 50 - 7.5 + TOL || xs.min >= 50 + 7.5 - TOL, xs.minmax.inspect)
    end
    poles = nodes(p, 'pole/').map { |n| n['primitive']['matrix'][12] }
    assert(poles.none? { |x| (x - 50).abs < 7.5 - TOL })
  end

  # Vu en recette : un lampadaire de la rue se dressait entre les rails. Rien de la rue sur le platelage.
  def test_no_road_item_stands_on_the_deck
    p = straight
    lamps = nodes(p, 'lamp/').map { |n| n['primitive']['matrix'].values_at(12, 13) }
    refute_empty lamps
    assert(lamps.select { |x, _| (x - 50).abs < 7 }.none? { |_, y| y.abs < 8 - TOL }, lamps.inspect)
    bollards = nodes(p, 'bollard/').map { |n| n['primitive']['matrix'].values_at(12, 13) }
    assert(bollards.select { |x, _| (x - 50).abs < 7 }.none? { |_, y| y.abs < 8 - TOL })
  end

  # Croix de Saint-André : deux lames inclinées à ±45°, aucune lame horizontale ni verticale.
  def test_the_crossing_sign_is_an_x
    shape = Archgen::Geometry::RoadItemShapes.definition('crossing_light', 'standard', 3.2)
    white = shape.map { |n| n['primitive'] }.select { |prim| prim['faces'].all? { |f| f['material'] == 'road/item/white' } }
    assert_equal 2, white.size
    white.each do |prim|
      ys = prim['vertices'].map { |v| v[1] }
      zs = prim['vertices'].map { |v| v[2] }
      assert_in_delta ys.max - ys.min, zs.max - zs.min, 1e-6, 'lame à 45°'
    end
  end

  def test_skirts_and_signs
    p = straight
    s = surface(p)
    # Murets : faces de bordure aux bords de l'emprise de la rue (x = 50 ± 6,5), du sol au-dessus de 0,5 m.
    walls = s['faces'].select do |f|
      pts = f['indices'].map { |i| s['vertices'][i] }
      f['material'] == 'road/curb' && pts.all? { |v| ((v[0] - 50).abs - 6.5).abs < TOL } && pts.map { |v| v[2] }.min.abs < TOL && pts.map { |v| v[2] }.max > 0.5
    end
    assert_equal 4, walls.size
    signs = nodes(p, 'signal/')
    assert_equal 2, signs.count { |n| n['id'].include?('crossing_light') }
    assert_equal 2, signs.count { |n| n['id'].include?('crossing_gate') }
    light = signs.find { |n| n['id'].include?('crossing_light') && n['primitive']['matrix'][13].positive? }
    m = light['primitive']['matrix']
    # Feu à 3 m avant le platelage (8 + 3 = 11 m), à droite de ceux qui arrivent, sur la rampe.
    assert_in_delta 11.0, m[13], TOL
    assert_in_delta 0.14 + (0.515 * (20.875 - 11) / 12.875), m[14], TOL
    assert p['definitions'].key?('road1/crossing_light/standard/3200')
  end

  def test_an_oblique_crossing_widens_the_deck
    p = plan(crossing(road('b', [[0, -60], [100, 60]])))
    j = p['junctions'].first
    sin = 120 / Math.hypot(100, 120)
    cot = 100 / 120.0
    assert_in_delta (7.5 / sin) + (6.5 * cot) + 0.5 + 12.875, j['cuts_m'].max, TOL
  end

  def test_refusals
    assert_equal ['rails_at_junction'], reasons(network(RAIL, road('b', [[50, -60], [50, 60]])))
    plain = [road('a', [[0, 0], [100, 0]]), road('b', [[50, -60], [50, 60]])]
    assert_equal ['crossing_roads'], reasons(network(*plain, junctions: [{ 'id' => 'a@50.0+b@60.0', 'type' => 'level_crossing' }]))
    assert_equal ['crossing_through'], reasons(crossing(road('b', [[50, 0], [50, 60]])))
    assert_equal ['crossing_angle'], reasons(crossing(road('b', [[0, -30], [100, 30]])))
    assert_equal ['arm_too_short'], reasons(crossing(road('b', [[50, -15], [50, 60]])))
    assert_equal ['E_SCHEMA'], build(crossing(road('b', [[50, -60], [50, 60]]), ramp_grade_percent: 9)).errors.map(&:code).uniq
    %w[crossing_roads crossing_through crossing_angle].each { |r| assert Archgen::UI::Messages::REASONS.key?(r), r }
  end

  def test_a_steeper_ramp_is_shorter
    p = plan(crossing(road('b', [[50, -60], [50, 60]]), ramp_grade_percent: 8))
    assert_in_delta 0.515 / 0.08, p['junctions'].first['ramp_m'], TOL
  end
end
