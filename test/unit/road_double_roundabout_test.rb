# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/road_net'
require File.expand_path('../../archgen/ui/messages', __dir__)

# U30 : double giratoire (ADR-37, docs/VOIRIE_CONTRACT.md, Carrefours ; AG-046). Deux nœuds voisins
# sur une même voie deviennent deux anneaux ; le bout de voie entre eux est la liaison, sans îlot
# séparateur. Rue de ville, anneaux de 15 m : la liaison perd 2 × √(21² − 10²) = 36,93 m.
class RoadDoubleRoundaboutTest < Minitest::Test
  include Archgen::Core
  include RoadNet

  TOL = 1e-5
  ENTRY = Math.sqrt((21**2) - (10**2))

  def roads(gap)
    [road('a', [[0, 0], [200, 0]]), road('b', [[60, -60], [60, 60]]), road('c', [[60 + gap, 0], [60 + gap, 60]])]
  end

  def ids(roads)
    plan(network(*roads))['junctions'].map { |j| j['id'] }
  end

  def double(roads, **rest)
    first, second = ids(roads)
    network(*roads, junctions: [{ 'id' => second, 'type' => 'double_roundabout', 'pair' => first }.merge(rest.transform_keys(&:to_s))])
  end

  def plan(tree)
    result = build(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def reasons(tree)
    build(tree).errors.map { |d| d.params['reason'] }.uniq
  end

  def test_two_neighbours_become_two_rings_and_a_link
    p = plan(double(roads(70), outer_radius_m: 15))
    a, b = p['junctions']
    assert_equal %w[double_roundabout double_roundabout], [a['type'], b['type']]
    assert_equal [b['id'], a['id']], [a['pair'], b['pair']]
    assert_in_delta 70 - (2 * ENTRY), a['link_m'], TOL
    assert_equal a['link_m'], b['link_m']
    assert_equal [15.0, 15.0], [a['outer_radius_m'], b['outer_radius_m']]
    # Branche de liaison : arrondis d'entrée seulement ; les autres : îlot séparateur, coupe de 25 m.
    assert_in_delta ENTRY, a['cuts_m'].min, TOL
    assert_equal 1, a['cuts_m'].count { |c| (c - ENTRY).abs < TOL }
    assert_equal 1, b['cuts_m'].count { |c| (c - ENTRY).abs < TOL }
    assert(b['cuts_m'].reject { |c| (c - ENTRY).abs < TOL }.all? { |c| (c - 25).abs < TOL })
    # Îlots séparateurs : 5 branches hors liaison, deux triangles chacun.
    assert_equal 10, surface(p)['faces'].count { |f| f['material'] == 'road/median' }
  end

  def test_sealed
    rs = roads(70)
    p = plan(double(rs))
    strips = rs.map { |r| strip(r['road']['trace']['points_m'].first, r['road']['trace']['points_m'].last, r['road']['profile']) }
    box = [20, -45, 170, 50]
    p['junctions'].each do |j|
      holes = coverage_defects(p, strips, box, step: 0.53, disc: [j['point_m'], 15])
      assert_empty holes, "#{j['id']} #{holes.first(3)}"
    end
    assert_equal [0, 0], edge_defects(p, strips)
    assert_empty misfacing_walls(p, box)
  end

  def test_same_input_same_split
    a = plan(double(roads(70)))
    assert_equal RoadEngine.digest(a), RoadEngine.digest(plan(double(roads(70))))
    swapped = roads(70).reverse
    swapped = [swapped.last] + swapped.first(2) # la première voie part toujours de l'origine
    b = plan(double(swapped))
    keys = %w[id type pair link_m cuts_m]
    assert_equal a['junctions'].map { |j| j.slice(*keys) }, b['junctions'].map { |j| j.slice(*keys) }
  end

  def test_link_too_short_and_first_accepted
    limit = (2 * ENTRY) + 5
    assert plan(double(roads((limit + 0.02).round(2))))
    errors = build(double(roads((limit - 0.03).round(2)))).errors
    assert_equal ['link_too_short'], errors.map { |d| d.params['reason'] }
    assert_equal 5.0, errors.first.params['limit']
    assert_operator errors.first.params['value'], :<, 5
    # Plus court que les deux coupes : toujours la liaison qui parle, pas les nœuds trop proches.
    assert_equal ['link_too_short'], reasons(double(roads(30)))
  end

  def test_pairing_refusals
    rs = roads(70)
    first, second = ids(rs)
    assert_equal ['pair_missing'], reasons(network(*rs, junctions: [{ 'id' => second, 'type' => 'double_roundabout' }]))
    assert_equal ['unknown_pair'], reasons(network(*rs, junctions: [{ 'id' => second, 'type' => 'double_roundabout', 'pair' => 'nulle@part' }]))
    assert_equal ['unknown_pair'], reasons(network(*rs, junctions: [{ 'id' => second, 'type' => 'double_roundabout', 'pair' => second }]))
    set_twice = [{ 'id' => second, 'type' => 'double_roundabout', 'pair' => first }, { 'id' => first, 'type' => 'roundabout' }]
    assert_equal ['pair_already_set'], reasons(network(*rs, junctions: set_twice))
    three = [road('a', [[0, 0], [300, 0]]), road('b', [[60, -60], [60, 60]]), road('c', [[140, -60], [140, 60]]), road('d', [[220, -60], [220, 60]])]
    js = ids(three)
    far = { 'id' => js.find { |i| i.include?('220') }, 'type' => 'double_roundabout', 'pair' => js.find { |i| i.include?('a@60') } }
    assert_equal ['not_neighbours'], reasons(network(*three, junctions: [far]))
    %w[pair_missing unknown_pair pair_already_set not_neighbours link_too_short].each { |r| assert Archgen::UI::Messages::REASONS.key?(r), r }
  end
end
