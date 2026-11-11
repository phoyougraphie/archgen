# frozen_string_literal: true

require_relative '../test_helper'

# U89 — Bâtiments d'une carte (docs/CARTOGRAPHIE_CONTRACT.md §3, AG-127).
class MapBuildingsTest < Minitest::Test
  include Archgen::Core

  def rotated(w, d, angle_deg, at: [0, 0])
    a = angle_deg * Math::PI / 180
    [[0, 0], [w, 0], [w, d], [0, d]].map { |x, y| [at[0] + (x * Math.cos(a)) - (y * Math.sin(a)), at[1] + (x * Math.sin(a)) + (y * Math.cos(a))] }
  end

  def building(id, ring, **tags)
    { 'id' => "way/#{id}", 'tags' => { 'building' => 'yes' }.merge(tags.transform_keys(&:to_s)), 'ring_m' => ring }
  end

  def convert(buildings, roads: [])
    result = MapBuildings.call({ 'ways' => [], 'buildings' => buildings }, style: 'haussmann', roads: roads)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def test_rotated_rectangle_is_found_exactly
    rect = MapBuildings.oriented_rectangle(rotated(12, 9, 30))
    assert_in_delta 1.0, rect[:fill], 1e-9
    assert_equal [9.0, 12.0], [rect[:width], rect[:height]].map { |s| s.round(6) }.sort
  end

  def test_an_l_shape_is_refused_below_eighty_five_percent
    ell = [[0, 0], [20, 0], [20, 8], [8, 8], [8, 20], [0, 20]]
    assert_operator MapBuildings.oriented_rectangle(ell)[:fill], :<, 0.85
    value = convert([building(1, ell)])
    assert_empty value['buildings']
    assert_equal({ 'not_rectangular' => 1 }, value['skipped'])
  end

  def test_levels_from_tags_then_height_then_default
    value = convert([building(1, rotated(10, 8, 0), 'building:levels' => '5'),
                     building(2, rotated(10, 8, 0, at: [30, 0]), height: '13 m'),
                     building(3, rotated(10, 8, 0, at: [60, 0])),
                     building(4, rotated(10, 8, 0, at: [90, 0]), 'building:levels' => '22')])
    assert_equal [5, 4, 3], value['buildings'].map { |b| b.dig('draft', 'levels', 'count') }
    assert_equal({ 'levels' => 1 }, value['skipped'])
  end

  def test_seed_is_stable_and_drafts_are_complete
    one = convert([building(77, rotated(10, 8, 15), name: 'Mairie')])['buildings'].first
    two = convert([building(77, rotated(10, 8, 15), name: 'Mairie')])['buildings'].first
    assert_equal one, two
    draft = one['draft']
    assert_equal 'Mairie', draft['name']
    assert_equal({ 'id' => 'haussmann' }, draft['profile'])
    assert draft['seed'].between?(0, 4_294_967_295)
    resolved = ConfigResolver.resolve(draft, registry: Archgen::Composition.registry.value, intake: Archgen::Composition.intake)
    assert resolved.ok?, resolved.errors.map(&:to_h).inspect
  end

  def test_front_faces_the_nearest_road_otherwise_the_longest_side
    ring = rotated(16, 10, 0, at: [0, 5])
    toward_road = convert([building(1, ring)], roads: [[[-10, 0], [30, 0]]])['buildings'].first
    assert_equal [0.0, 5.0], toward_road['origin_m']
    assert_equal [1.0, 0.0], toward_road['x_axis']
    assert_equal 16.0, toward_road.dig('draft', 'footprint', 'width_m')
    side_road = convert([building(1, ring)], roads: [[[20, -10], [20, 30]]])['buildings'].first
    assert_equal [0.0, 1.0], side_road['x_axis'], 'côté droit, face à la voie à x = 20'
    assert_equal [16.0, 5.0], side_road['origin_m']
    assert_equal 10.0, side_road.dig('draft', 'footprint', 'width_m')
    alone = convert([building(1, rotated(16, 10, 90))])['buildings'].first
    assert_equal 16.0, alone.dig('draft', 'footprint', 'width_m'), 'sans voie : le côté le plus long'
  end

  def test_overlaps_sizes_and_count
    value = convert([building(1, rotated(10, 8, 0)), building(2, rotated(10, 8, 0, at: [5, 0])),
                     building(3, rotated(10, 8, 0, at: [10, 0])), building(4, rotated(3, 3, 0, at: [40, 0]))])
    assert_equal %w[way/1 way/3], value['buildings'].map { |b| b['id'] }, 'mitoyen accepté, chevauchement écarté'
    assert_equal({ 'overlap' => 1, 'size' => 1 }, value['skipped'])
    many = (0..300).map { |i| building(i, rotated(5, 5, 0, at: [(i * 6.0) - 900, 0])) }
    kept = MapBuildings.call({ 'ways' => [], 'buildings' => many }, style: 'haussmann').value
    assert_equal 300, kept['buildings'].size
    assert_equal({ 'too_many' => 1 }, kept['skipped'])
    assert_equal 'way/300', (many.map { |b| b['id'] } - kept['buildings'].map { |b| b['id'] }).first, 'le plus loin du centre est écarté'
  end
end
