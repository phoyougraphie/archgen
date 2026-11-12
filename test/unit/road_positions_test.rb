# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/road_net'

# U83 — Pose à des positions (docs/MOBILIER_CONTRACT.md §2, AG-121).
class RoadPositionsTest < Minitest::Test
  include Archgen::Core
  include RoadNet

  P = Archgen::Geometry::RoadItems::PREFIX

  def profile(items)
    { 'bands' => [{ 'type' => 'sidewalk', 'width_m' => 3.0, 'items' => items }, { 'type' => 'lane', 'width_m' => 3.5 }] }
  end

  def settings(items, points: [[0, 0], [100, 0]], radii: [])
    C.road_intake.settings({ 'trace' => { 'points_m' => points, 'radii_m' => radii }, 'profile' => profile(items) })
  end

  def compute(items, **trace)
    s = settings(items, **trace)
    return s unless s.ok?

    RoadEngine.call(s.value, bands: C.road_bands, items: C.road_items)
  end

  def plan(items, **trace)
    result = compute(items, **trace)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def instances(built, kind)
    found = []
    walk = lambda do |node|
      found << node if node.dig('primitive', 'type') == 'instance' && node['id'].start_with?("#{kind}/")
      node['children'].each(&walk)
    end
    built['nodes'].each(&walk)
    found
  end

  def at(node) = node['primitive']['matrix'].values_at(12, 13)

  def reasons(items)
    result = compute(items)
    result.errors.map { |e| e.params['reason'] }
  end

  def test_positions_are_exact_on_a_straight_road
    built = plan([{ 'kind' => 'sign', 'variant' => 'stop', 'positions_m' => [5, 42.5, 100] }])
    signs = instances(built, 'sign')
    assert_equal 3, signs.size
    xs = signs.map { |n| at(n)[0] }
    assert_equal [5.0, 42.5, 100.0], xs.map { |x| x.round(6) }
    assert_equal ["#{P}sign/stop/2300"], signs.map { |n| n['primitive']['definition_id'] }.uniq
    assert_equal 3, built['metrics']['item_count'] - built['metrics'].fetch('sleeper_count', 0)
  end

  def test_positions_follow_the_axis_on_an_arc
    built = plan([{ 'kind' => 'bench', 'positions_m' => [10, 60] }], points: [[0, 0], [50, 0], [50, 50]], radii: [20])
    axis = Archgen::Geometry::RoadAxis.call([[0, 0], [50, 0], [50, 50]], [20], left_m: 3.25, right_m: 3.25).value.map(&:point)
    benches = instances(built, 'bench')
    assert_equal 2, benches.size
    [10, 60].zip(benches).each do |s, node|
      i, t = Archgen::Geometry::RoadItems.locate(axis, s)
      on_axis = [axis[i][0] + ((axis[i + 1][0] - axis[i][0]) * t), axis[i][1] + ((axis[i + 1][1] - axis[i][1]) * t)]
      distance = Math.hypot(at(node)[0] - on_axis[0], at(node)[1] - on_axis[1])
      assert_in_delta 1.75, distance, 0.02, 'milieu du trottoir à 1,75 m de l’axe central, au droit de la position'
    end
  end

  def test_a_lamp_can_be_placed_at_positions
    built = plan([{ 'kind' => 'lamp', 'positions_m' => [30] }])
    assert_equal [30.0], instances(built, 'lamp').map { |n| at(n)[0].round(6) }
  end

  def test_refusals
    assert_includes reasons([{ 'kind' => 'bench', 'positions_m' => [120] }]), 'position_out_of_road'
    assert_includes reasons([{ 'kind' => 'bench', 'positions_m' => [10], 'spacing_m' => 20 }]), 'positions_with_spacing'
    assert_includes reasons([{ 'kind' => 'bus_stop' }]), 'positions_required'
    assert_includes reasons([{ 'kind' => 'sign', 'positions_m' => [20, 10] }]), 'positions_order'
    assert_includes reasons([{ 'kind' => 'low_wall', 'positions_m' => [10] }]), 'continuous_item'
  end

  def test_network_places_each_position_once_across_pieces
    item = { 'kind' => 'bench', 'positions_m' => [10, 45, 80] }
    prof = { 'bands' => [{ 'type' => 'sidewalk', 'width_m' => 3.0, 'items' => [item] }, { 'type' => 'lane', 'width_m' => 3.5 },
                         { 'type' => 'lane', 'width_m' => 3.5 }, { 'type' => 'sidewalk', 'width_m' => 3.0 }] }
    result = build(network(road('a', [[0, 0], [100, 0]], prof), road('b', [[50, -50], [50, 50]], 'ville')))
    assert result.ok?, result.errors.map(&:to_h).inspect
    benches = instances(result.value, 'bench')
    xs = benches.map { |n| at(n)[0].round(3) }.sort
    assert_includes xs, 10.0
    assert_includes xs, 80.0
    assert_equal xs.uniq, xs, 'jamais deux fois'
    far = build(network(road('a', [[0, 0], [100, 0]], prof.merge('bands' => [prof['bands'][0].merge('items' => [item.merge('positions_m' => [150])])] + prof['bands'][1..])),
                        road('b', [[50, -50], [50, 50]], 'ville')))
    assert_includes far.errors.map { |e| e.params['reason'] }, 'position_out_of_road'
  end
end
