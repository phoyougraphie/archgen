# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/road_net'
require File.expand_path('../../archgen/ui/messages', __dir__)

# U39 : pont à poutre (docs/PONT_CONTRACT.md ; AG-057). Rivière à berges de 32 m le long de x, rue de
# ville de 13 m le long de x = 100, à angle droit : pont d'office, portée 16 + 1 de chaque côté = 34 m,
# point le plus haut de la rivière 0,02 m (chemin), hauteur libre 4 m, tablier de 1,2 m : H = 5,22 m ;
# rampes à 5 % de 104,4 m.
class RoadBridgeTest < Minitest::Test
  include Archgen::Core
  include RoadNet

  TOL = 1e-5

  def river(id = 'a', points = [[0, 0], [200, 0]], profile = 'riviere')
    entry = road(id, points, profile)
    entry['road']['water'] = { 'mode' => 'flat' }
    entry
  end

  def street(points = [[100, -200], [100, 200]], id = 'b', profile = 'ville')
    road(id, points, profile)
  end

  def node_id(tree)
    C.road_network_intake.settings(tree).then do |s|
      roads = s.value['roads'].each_with_index.map { |e, i| RoadNetworkEngine.road(e, i, C.road_bands, C.road_items).value }
      Archgen::Geometry::RoadNetwork.detect(roads).first.id
    end
  end

  def with_junction(tree, **opts)
    tree.merge('junctions' => [{ 'id' => node_id(tree) }.merge(opts.transform_keys(&:to_s))])
  end

  def plan(tree)
    r = build(tree)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def reason(tree)
    r = build(tree)
    refute r.ok?, 'refus attendu'
    r.errors.first.params['reason']
  end

  def group(plan, id)
    plan['nodes'][0]['children'].find { |n| n['id'] == id }
  end

  def walk(plan, prefix)
    out = []
    w = lambda do |n|
      out << n if n['id'].start_with?(prefix)
      n['children'].each(&w)
    end
    plan['nodes'].each(&w)
    out
  end

  def river_bridge
    plan(network(river, street))
  end

  def test_a_bridge_is_born_over_water_by_hand
    p = river_bridge
    j = p['junctions'].first
    assert_equal ['bridge', 'beam', 'b', 34.0, 5.22, 104.4, 4.0], j.values_at('type', 'bridge_kind', 'over', 'span_m', 'deck_m', 'ramp_m', 'clearance_m')
    assert_equal [1, 0], p['metrics'].values_at('bridge_count', 'crossing_count')
    assert_empty RoadPlanValidator.call(p)
  end

  def test_the_street_rises_on_ramps_and_crosses_on_the_deck
    p = river_bridge
    axis = surface(p)['vertices'].select { |v| (v[0] - 100).abs < 3.9 && v[1].abs <= 200 }
    expected = lambda do |y|
      d = y.abs
      d <= 17 ? 5.22 : (d >= 121.4 ? 0.0 : 5.22 * (121.4 - d) / 104.4)
    end
    refute_empty axis
    axis.each { |v| assert_in_delta expected.call(v[1]), v[2], TOL, v.inspect }
    assert(axis.any? { |v| (v[1] - 17).abs < TOL } && axis.any? { |v| (v[1] + 121.4).abs < TOL })
  end

  def test_the_river_stays_whole_under_the_deck
    p = river_bridge
    water = group(p, 'road/water')['primitive']['vertices']
    assert_equal [-1.2], water.map { |v| v[2] }.uniq
    assert_in_delta 0.0, water.map(&:first).min, TOL
    assert_in_delta 200.0, water.map(&:first).max, TOL
    trees = walk(p, 'tree/').map { |n| n['primitive']['matrix'][12] }
    refute_empty trees
    assert(trees.none? { |x| x > 92.5 && x < 107.5 }, 'pas d’arbre de berge sous le tablier')
  end

  def test_slab_abutments_and_parapets
    p = river_bridge
    solids = group(p, 'road/bridges')['children']
    names = solids.map { |n| n['id'].split('/', 3).last }
    assert_equal %w[slab abutment/1 abutment/2 parapet/left/deck parapet/left/ramp1 parapet/left/ramp2 parapet/right/deck parapet/right/ramp1 parapet/right/ramp2].sort, names.sort
    slab = solids.find { |n| n['id'].end_with?('/slab') }['primitive']['vertices']
    assert_equal [4.02, 5.2], slab.map { |v| v[2].round(6) }.minmax
    assert_equal [-17.2, 17.2], slab.map { |v| (v[1]).round(6) }.minmax
    abutment = solids.find { |n| n['id'].end_with?('/abutment/1') }['primitive']['vertices']
    assert_equal 0.0, abutment.map { |v| v[2] }.min
    assert_equal({ 'road/bridge' => 3, 'road/item/steel' => 6 }, solids.map { |n| n['primitive']['faces'].first['material'] }.tally)
  end

  def test_a_railway_is_bridged_on_request_with_its_own_clearance
    rail = road('a', [[0, 0], [200, 0]], 'fer')
    p = plan(with_junction(network(rail, street([[100, -250], [100, 250]])), type: 'bridge'))
    j = p['junctions'].first
    # Dessus des rails 0,52 m + 5,5 m + 1,2 m.
    assert_equal ['b', 7.22, 5.5], j.values_at('over', 'deck_m', 'clearance_m')
    assert_equal 4, walk(p, 'rail/').size
  end

  def test_between_two_streets_the_carried_road_must_be_named
    tree = network(road('a', [[0, 0], [400, 0]]), street([[200, -200], [200, 200]]))
    assert_equal 'bridge_over_missing', reason(with_junction(tree, type: 'bridge'))
    p = plan(with_junction(tree, type: 'bridge', over: 'a', clearance_m: 5))
    # Trottoir de la rue franchie à 0,14 m + 5 m + 1,2 m.
    assert_equal ['a', 6.34], p['junctions'].first.values_at('over', 'deck_m')
    assert_equal 'bridge_over_unknown', reason(with_junction(tree, type: 'bridge', over: 'zz'))
  end

  def test_refusals_on_water
    assert_equal 'water_crossing', reason(with_junction(network(river, street), type: 'signals'))
    assert_equal 'water_confluence', reason(network(river, street([[100, 0], [100, 200]])))
    assert_equal 'water_confluence', reason(network(river, river('c', [[100, -100], [100, 100]])))
    assert_equal 'bridge_over_unknown', reason(with_junction(network(river, street), over: 'a'))
  end

  def test_angle_span_and_settings_refusals
    assert_equal 'bridge_angle', reason(network(river, street([[100 - 346.41, -200], [100 + 346.41, 200]])))
    fleuve = river('a', [[0, 0], [400, 0]], 'fleuve')
    r = build(network(fleuve, street([[200, -300], [200, 300]])))
    assert_equal ['bridge_span_too_long', 146.0, 40.0], r.errors.first.params.values_at('reason', 'value', 'limit')
    streets = network(road('a', [[0, 0], [100, 0]]), street([[50, -60], [50, 60]]))
    assert_equal 'bridge_setting_unavailable', reason(with_junction(streets, clearance_m: 6))
  end

  def test_a_lone_river_in_a_network_draws_its_water
    p = plan(network(river))
    assert_operator group(p, 'road/water')['primitive']['faces'].size, :>, 0
    refute p['metrics'].key?('bridge_count')
  end
end
