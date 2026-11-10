# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/road_net'

# U85 — Panneaux (docs/MOBILIER_CONTRACT.md §4, AG-123).
class RoadSignsTest < Minitest::Test
  include Archgen::Core
  include RoadNet

  VARIANTS = %w[stop give_way prohibition limit mandatory information danger crossing].freeze

  def settings(items, band: 'sidewalk', at_right: false)
    sidewalk = { 'type' => band, 'width_m' => 3.0, 'items' => items }
    lane = { 'type' => 'lane', 'width_m' => 3.5 }
    list = at_right ? [lane, sidewalk] : [sidewalk, lane]
    C.road_intake.settings({ 'trace' => { 'points_m' => [[0, 0], [100, 0]], 'radii_m' => [] }, 'profile' => { 'bands' => list } })
  end

  def plan(items, **opts)
    s = settings(items, **opts)
    assert s.ok?, s.errors.map(&:to_h).inspect
    result = RoadEngine.call(s.value, bands: C.road_bands, items: C.road_items)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def signs(built)
    found = []
    walk = ->(n) { found << n if n['id'].start_with?('sign/') && n.dig('primitive', 'type') == 'instance'; n['children'].each(&walk) }
    built['nodes'].each(&walk)
    found
  end

  # Abscisse monde du centre de la plaque (les parties après le mât), par la matrice de l'instance.
  def plate_x(built, node)
    m = node['primitive']['matrix']
    parts = built['definitions'].fetch(node['primitive']['definition_id']).drop(1)
    xs = parts.flat_map { |p| p['primitive']['vertices'].map { |v| m[12] + (m[0] * v[0]) + (m[4] * v[1]) } }
    (xs.min + xs.max) / 2
  end

  def test_eight_plates_each_with_its_definition
    items = VARIANTS.each_with_index.map { |v, i| { 'kind' => 'sign', 'variant' => v, 'positions_m' => [10 + (10 * i)] } }
    built = plan(items.first(6))
    assert_equal 6, signs(built).map { |n| n['primitive']['definition_id'] }.uniq.size
    built = plan(items.last(2))
    assert_equal 2, signs(built).size
  end

  def test_forward_faces_those_who_follow_the_trace
    [false, true].each do |at_right|
      forward = plan([{ 'kind' => 'sign', 'variant' => 'stop', 'positions_m' => [50] }], at_right: at_right)
      node = signs(forward).first
      assert_operator plate_x(forward, node), :<, node['primitive']['matrix'][12], 'plaque avant le mât, vue en arrivant'
      backward = plan([{ 'kind' => 'sign', 'variant' => 'stop', 'positions_m' => [50], 'facing' => 'backward' }], at_right: at_right)
      node = signs(backward).first
      assert_operator plate_x(backward, node), :>, node['primitive']['matrix'][12], 'plaque tournée vers ceux qui remontent'
    end
  end

  def test_height_puts_the_plate_top_at_the_given_value
    built = plan([{ 'kind' => 'sign', 'variant' => 'danger', 'height_m' => 2.8, 'positions_m' => [20] }])
    parts = built['definitions'].fetch(signs(built).first['primitive']['definition_id'])
    top = parts.flat_map { |p| p['primitive']['vertices'].map { |v| v[2] } }.max
    assert_in_delta 2.8, top, 1e-6
  end

  def test_facing_belongs_to_signs_only
    reasons = settings([{ 'kind' => 'bench', 'facing' => 'backward' }]).errors.map { |e| e.params['reason'] }
    assert_includes reasons, 'facing_unavailable'
    refute settings([{ 'kind' => 'sign', 'positions_m' => [5], 'facing' => 'sideways' }]).ok?
    effective = settings([{ 'kind' => 'sign', 'positions_m' => [5] }]).value
    assert_equal 'forward', effective['profile']['bands'][0]['items'][0]['facing']
  end
end
