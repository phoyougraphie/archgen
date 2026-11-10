# frozen_string_literal: true

require_relative '../test_helper'

# U88 — Voies d'une carte en réseaux (docs/CARTOGRAPHIE_CONTRACT.md §2, AG-126).
class MapRoadsTest < Minitest::Test
  include Archgen::Core
  C = Archgen::Composition

  def way(id, highway, points, **tags)
    { 'id' => "way/#{id}", 'tags' => { 'highway' => highway }.merge(tags.transform_keys(&:to_s)), 'points_m' => points }
  end

  def convert(ways)
    result = MapRoads.call({ 'ways' => ways, 'buildings' => [] }, presets: C.road_presets, road_intake: C.road_intake,
                                                                  bands: C.road_bands, items: C.road_items)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def roads(value) = value['networks'].flat_map { |n| n['roads'] }

  def test_types_follow_the_closed_table_and_unknown_or_levels_are_counted
    value = convert([way(1, 'residential', [[0, 0], [100, 0]]), way(2, 'cycleway', [[0, 50], [100, 50]]),
                     way(3, 'proposed', [[0, 90], [50, 90]]), way(4, 'primary', [[0, 120], [90, 120]], bridge: 'yes'),
                     way(5, 'footway', [[0, 150], [0.4, 150]])])
    names = roads(value).to_h { |r| [r['id'], r.dig('road', 'profile', 'name')] }
    assert_equal({ 'w1-1' => 'Rue de ville', 'w2-1' => C.road_presets['presets'].find { |p| p['id'] == 'verte' }.dig('profile', 'name') }, names)
    assert_equal({ 'highway_unknown' => 1, 'level' => 1, 'too_short' => 1 }, value['skipped'])
  end

  def test_simplification_drops_points_within_half_a_metre_and_keeps_corners
    wobble = (0..20).map { |i| [i * 5.0, i.odd? ? 0.3 : 0.0] } + [[100, 50]]
    points = MapRoads.simplify(wobble)
    assert_equal [[0.0, 0.0], [100.0, 0.0], [100, 50]], points
  end

  def test_long_ways_are_cut_into_roads_of_sixty_four_points_sharing_their_ends
    zigzag = (0..150).map { |i| [i * 10.0, i.even? ? 0.0 : 6.0] }
    pieces = MapRoads.chunks(zigzag)
    assert_equal [64, 64, 25], pieces.map(&:size)
    assert_equal pieces[0].last, pieces[1].first
    assert_equal zigzag.last, pieces.last.last
  end

  def test_radius_falls_back_until_the_trace_fits
    gentle = convert([way(1, 'residential', [[0, 0], [100, 0], [200, 30]])])
    assert_equal [10.0], roads(gentle).first.dig('road', 'trace', 'radii_m')
    hairpin = convert([way(2, 'motorway', [[0, 0], [60, 0], [0, 4]])])
    assert_equal({ 'trace_refused' => 1 }, hairpin['skipped'])
  end

  def test_connected_ways_make_one_network_and_big_ones_are_cut_at_twenty_four
    cross = convert([way(1, 'residential', [[0, 0], [50, 0], [100, 0]]), way(2, 'residential', [[50, -50], [50, 0], [50, 50]]),
                     way(3, 'residential', [[300, 0], [400, 0]])])
    assert_equal [%w[w1-1 w2-1], %w[w3-1]], cross['networks'].map { |n| n['roads'].map { |r| r['id'] } }
    grid = (0..29).map { |i| way(100 + i, 'service', [[i * 30.0, 0], [i * 30.0, 20], [(i + 1) * 30.0, 20]]) }
    big = convert(grid)
    assert_equal [24, 6], big['networks'].map { |n| n['roads'].size }
  end

  def test_an_imported_network_is_accepted_by_the_engine
    value = convert([way(1, 'residential', [[0, 0], [50, 0], [100, 0]]), way(2, 'residential', [[50, -50], [50, 0], [50, 50]])])
    tree = value['networks'].first
    settings = C.road_network_intake.settings(tree)
    assert settings.ok?, settings.errors.map(&:to_h).inspect
    plan = RoadNetworkEngine.call(settings.value, bands: C.road_bands, items: C.road_items)
    assert plan.ok?, plan.errors.map(&:to_h).inspect
    refute_empty plan.value['junctions']
  end

  def test_too_many_roads_is_refused_with_the_numbers
    many = (0..400).map { |i| way(i, 'service', [[i * 3.0, 0], [i * 3.0, 2]]) }
    result = MapRoads.call({ 'ways' => many, 'buildings' => [] }, presets: C.road_presets, road_intake: C.road_intake, bands: C.road_bands, items: C.road_items)
    assert_equal ['map_too_large', 401, 400], result.errors.first.params.values_at('reason', 'value', 'limit')
  end
end
