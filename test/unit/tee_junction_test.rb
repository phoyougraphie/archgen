# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/road_net'

# U67 : carrefours en T plus tolérants (docs/CARREFOURS_DALLE_CONTRACT.md, AG-101).
class TeeJunctionTest < Minitest::Test
  include RoadNet

  def plan(tree)
    result = build(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def test_an_end_on_the_carriageway_makes_a_t_on_the_axis
    p = plan(network(road('a', [[0, 0], [100, 0]]), road('b', [[50, 5], [50, 50]])))
    assert_equal [['a@50.0+b@0.0', 3]], p['junctions'].map { |j| [j['id'], j['arms']] }
  end

  def test_a_slight_overshoot_makes_a_t_not_a_cross
    p = plan(network(road('a', [[0, 0], [100, 0]]), road('b', [[50, -5], [50, 50]])))
    assert_equal [['a@50.0+b@0.0', 3]], p['junctions'].map { |j| [j['id'], j['arms']] }
  end

  def test_a_real_crossing_stays_a_cross_and_roads_apart_stay_apart
    assert_equal 4, plan(network(road('a', [[0, 0], [100, 0]]), road('b', [[50, -30], [50, 50]])))['junctions'].first['arms']
    assert_empty plan(network(road('a', [[0, 0], [100, 0]]), road('b', [[50, 20], [50, 60]])))['junctions']
  end
end
