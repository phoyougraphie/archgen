# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/road_net'

# U84 — Arrêt de bus (docs/MOBILIER_CONTRACT.md §3, AG-122).
class BusStopTest < Minitest::Test
  include Archgen::Core
  include RoadNet

  def bands(stop_items, width: 3.0, next_band: 'lane')
    [{ 'type' => 'sidewalk', 'width_m' => width, 'items' => stop_items }, { 'type' => next_band, 'width_m' => 3.5 },
     { 'type' => 'lane', 'width_m' => 3.5 }]
  end

  def settings(list)
    C.road_intake.settings({ 'trace' => { 'points_m' => [[0, 0], [100, 0]], 'radii_m' => [] }, 'profile' => { 'bands' => list } })
  end

  def plan(list)
    s = settings(list)
    assert s.ok?, s.errors.map(&:to_h).inspect
    result = RoadEngine.call(s.value, bands: C.road_bands, items: C.road_items)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def section(list)
    Archgen::Geometry::RoadSection.call(settings(list).value['profile'], bands: C.road_bands, items: C.road_items)
  end

  def nodes(built, kind)
    found = []
    walk = ->(n) { found << n if n['id'].start_with?("#{kind}/") && n.dig('primitive', 'type') == 'instance'; n['children'].each(&walk) }
    built['nodes'].each(&walk)
    found
  end

  STOP = { 'kind' => 'bus_stop', 'positions_m' => [50] }.freeze

  def test_shelter_backs_onto_the_far_edge_and_opens_toward_the_lane
    cut = section(bands([STOP]))
    stop = cut['items'].find { |i| i['kind'] == 'bus_stop' }
    assert_equal 'right', stop['toward']
    assert_in_delta 1.0, stop['x_m'], 1e-9, 'fond à 0,30 m du bord gauche, 1,40 m de profondeur'
    built = plan(bands([STOP]))
    shelter = nodes(built, 'bus_stop').first
    definition = built['definitions'].fetch(shelter['primitive']['definition_id'])
    glass = definition.map { |n| n['primitive'] }.select { |p| p['faces'].first['material'] == 'road/item/glass' }
    back = glass.map { |p| p['vertices'].map { |v| v[1] }.max }.min
    assert_operator back, :<, 0, 'le fond vitré est du côté opposé à la chaussée'
  end

  def test_marking_lies_on_the_neighbouring_lane_only
    cut = section(bands([STOP]))
    marking = cut['items'].find { |i| i['kind'] == 'bus_marking' }
    lane = cut['bands'][1]
    assert_equal 1, marking['band']
    assert_in_delta lane['x0_m'] + 0.6, marking['x_m'], 1e-9
    built = plan(bands([STOP]))
    assert_equal 1, nodes(built, 'bus_marking').size
    zigzag = built['definitions'].fetch(nodes(built, 'bus_marking').first['primitive']['definition_id'])
    assert_equal 6, zigzag.size
    assert(zigzag.all? { |n| n['primitive']['faces'].first['material'] == 'road/item/yellow' })
    assert_nil section(bands([STOP], next_band: 'parking'))['items'].find { |i| i['kind'] == 'bus_marking' }, 'pas de marquage sur un stationnement'
  end

  def test_narrow_band_is_refused_but_the_mast_alone_fits
    errors = settings(bands([STOP], width: 1.5)).errors
    assert_equal ['bus_stop_band_too_narrow'], errors.map { |e| e.params['reason'] }
    assert settings(bands([STOP.merge('variant' => 'pole')], width: 1.5)).ok?
  end

  def test_tree_close_to_the_shelter_warns
    near = settings(bands([STOP, { 'kind' => 'tree', 'spacing_m' => 20 }]))
    assert near.ok?
    assert_includes near.warnings.map { |w| w.params['reason'] }, 'bus_stop_clearance'
    far = settings(bands([STOP, { 'kind' => 'tree', 'spacing_m' => 20, 'height_m' => 6 }].tap { |l| l[1]['spacing_m'] = 40 }))
    refute_includes far.warnings.map { |w| w.params['reason'] }, 'bus_stop_clearance'
  end
end
