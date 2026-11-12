# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/road_net'
require File.expand_path('../../archgen/ui/messages', __dir__)

# U40 : arc et voûte (docs/PONT_CONTRACT.md ; AG-058). Même rivière et même rue qu'en U39 : portée 34 m,
# demi-portée 17 m.
class RoadBridgeFormsTest < Minitest::Test
  include Archgen::Core
  include RoadNet

  TOL = 1e-6
  F = Archgen::Geometry::RoadBridgeForms
  NODE = 'a@100.0+b@250.0'

  def river
    entry = road('a', [[0, 0], [200, 0]], 'riviere')
    entry['road']['water'] = { 'mode' => 'flat' }
    entry
  end

  def tree(**opts)
    network(river, road('b', [[100, -250], [100, 250]]), junctions: [{ 'id' => NODE }.merge(opts.transform_keys(&:to_s))])
  end

  def plan(t)
    r = build(t)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def solids(p)
    p['nodes'][0]['children'].find { |n| n['id'] == 'road/bridges' }['children']
  end

  def solid(p, name)
    solids(p).find { |n| n['id'] == "bridge/#{NODE}/#{name}" }['primitive']['vertices']
  end

  # Arc : tablier de 0,6 m, H = 0,02 + 4 + 0,6 = 4,62 ; sous-face 4,02 ; flèche voulue 34 / 5 = 6,8 m, plus
  # que la sous-face : les naissances sont au sol, la flèche vaut 4,02 m. Extrados z = 4,02 (1 − (a/17)²).
  def test_arch_shape_by_hand
    p = plan(tree(bridge_kind: 'arch'))
    assert_equal [4.62, 'arch'], p['junctions'].first.values_at('deck_m', 'bridge_kind')
    arch = solid(p, 'arch')
    assert_equal [0.0, 4.02], arch.map { |v| v[2].round(6) }.minmax
    crown = arch.select { |v| v[1].abs < TOL }.map { |v| v[2].round(6) }.uniq.sort
    assert_equal [3.02, 4.02], crown # anneau de 1 m à la clé
    # Montants à ± 5, ± 10, ± 15 m, de l'extrados en leur milieu à la sous-face.
    posts = solids(p).select { |n| n['id'].include?('/post/') }
    assert_equal 6, posts.size
    post = solid(p, 'post/1')
    assert_equal [(4.02 * (1 - ((15.0 / 17)**2))).round(6), 4.02], post.map { |v| v[2].round(6) }.minmax
    assert_empty RoadPlanValidator.call(p)
  end

  def test_shape_springs_above_ground_when_the_deck_is_high
    shape = F.shape('arch', 10.0, 9.0) # flèche 4 m, sous-face 9 m
    assert_in_delta 5.0, shape.spring, TOL
    assert_in_delta 4.0, shape.rise, TOL
    assert_in_delta 8.0, F.free_height(shape, 0.0), TOL
  end

  # Voûte : deux arches de (34 − 2) / 2 = 16 m et une pile de 2 m au milieu, dans l'eau (permise).
  def test_vault_arches_and_pier_by_hand
    shape = F.shape('vault', 17.0, 9.62)
    assert_equal [[-17.0, -1.0], [1.0, 17.0]], shape.openings
    assert_equal [[-1.0, 1.0]], shape.piers
    p = plan(tree(bridge_kind: 'vault', clearance_m: 9.6))
    assert_equal 10.42, p['junctions'].first['deck_m']
    names = solids(p).map { |n| n['id'].split('/', 3).last }
    assert_equal %w[pier/1 spandrel/1 spandrel/2], names.grep(/pier|spandrel/).sort
    assert_equal({ 'road/bridge_stone' => 12 }, solids(p).map { |n| n['primitive']['faces'].first['material'] }.tally)
    assert_empty RoadPlanValidator.call(p)
  end

  def test_vault_count_of_arches
    assert_equal 1, F.shape('vault', 10.0, 8.0).openings.size
    assert_equal 3, F.shape('vault', 25.0, 8.0).openings.size # 50 m : 3 arches de 14,67 m
  end

  # Gabarit : rien sous l'eau à moins de 2,5 m de la surface (−1,2 m) ; la voûte de 16 m demande une hauteur
  # libre de 9,58 m, que le refus annonce.
  def test_clearance_refusals_give_the_height_needed
    r = build(tree(bridge_kind: 'vault'))
    refute r.ok?
    assert_equal ['bridge_clearance', 3, 9.58], r.errors.first.params.values_at('reason', 'band_number', 'needed_m')
    street = network(road('a', [[0, 0], [400, 0]]), road('b', [[200, -250], [200, 250]]),
                     junctions: [{ 'id' => 'a@200.0+b@250.0', 'type' => 'bridge', 'over' => 'b', 'bridge_kind' => 'arch' }])
    r = build(street)
    assert_equal ['bridge_clearance', 2, 6.22], r.errors.first.params.values_at('reason', 'band_number', 'needed_m')
    street['junctions'][0]['clearance_m'] = 6.22
    assert build(street).ok?
    assert_match(/6,22 m/, Archgen::UI::Messages.text(r.errors.first))
  end

  def test_a_vault_pier_never_stands_on_a_track
    t = network(road('a', [[0, 0], [600, 0]], 'tram'), road('b', [[300, -300], [300, 300]]),
                junctions: [{ 'id' => 'a@300.0+b@300.0', 'type' => 'bridge', 'over' => 'b', 'bridge_kind' => 'vault', 'clearance_m' => 20 }])
    assert_equal ['pier_on_traffic', 4], build(t).errors.first.params.values_at('reason', 'band_number')
  end

  def test_the_beam_is_unchanged_by_the_forms
    p = plan(tree)
    assert_equal 'beam', p['junctions'].first['bridge_kind']
    assert_equal 9, solids(p).size
  end
end
