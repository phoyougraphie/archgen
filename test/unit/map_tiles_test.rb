# frozen_string_literal: true

require_relative '../test_helper'
Archgen::Loader.load_adapter

# U93 — Fond de plan : tuiles et pose à l'échelle (ADR-59, docs/CARTOGRAPHIE_CONTRACT.md §7).
class MapTilesTest < Minitest::Test
  include Archgen::Core
  T = MapTiles
  LAT = 44.017545
  LON = 1.353766

  def test_a_point_falls_inside_its_tile
    [16, 18, 19].each do |z|
      x, y = T.tile_of(LAT, LON, z)
      north, west = T.corner(x, y, z)
      south, east = T.corner(x + 1, y + 1, z)
      assert LAT.between?(south, north) && LON.between?(west, east), "z#{z}"
    end
  end

  def test_tiles_are_square_at_the_ground_scale_and_touch_each_other
    projection = MapProjection.new(LAT, LON)
    tiles = T.tiles(LAT, LON, 400, 18)
    size = T.tile_size_m(LAT, 18)
    assert_in_delta 110.0, size, 1.0
    placed = tiles.map { |t| T.placement(t, projection) }
    placed.each do |p|
      assert_in_delta size, p['width_m'], size * 0.005
      assert_in_delta p['width_m'], p['height_m'], size * 0.005
    end
    a, b = placed.first(2)
    assert_in_delta a['origin_m'][0] + a['width_m'], b['origin_m'][0], 0.01, 'voisines bord à bord'
    xs = placed.map { |p| p['origin_m'][0] }
    ys = placed.map { |p| p['origin_m'][1] }
    assert_operator xs.min, :<=, -200
    assert_operator xs.max + size, :>=, 200
    assert_operator ys.min, :<=, -200
    assert_operator ys.max + size, :>=, 200
  end

  def test_zoom_is_lowered_to_keep_the_tile_count
    assert_equal 19, T.zoom_for(LAT, LON, 400, wanted: 19, max_tiles: 100)
    z = T.zoom_for(LAT, LON, 1500, wanted: 19, max_tiles: 100)
    assert_operator z, :<, 19
    assert_operator T.tiles(LAT, LON, 1500, z).size, :<=, 100
  end

  def test_plan_gives_two_layers_with_fixed_hosts
    plan = Archgen::Adapters::SketchUp::BaseMap.plan(LAT, LON, 400)
    assert_equal %w[map photo], plan.keys
    map = plan['map']['tiles'].first
    assert_match %r{\Ahttps://tile\.openstreetmap\.org/18/\d+/\d+\.png\z}, map['url']
    photo = plan['photo']['tiles'].first
    assert photo['url'].start_with?('https://data.geopf.fr/wmts?')
    assert_includes photo['url'], 'LAYER=ORTHOIMAGERY.ORTHOPHOTOS'
    assert_equal 'ARCHGEN Fond photo', plan['photo']['label']
    assert(plan.values.all? { |l| l['tiles'].size <= 100 })
    assert_equal 'size', Archgen::Adapters::SketchUp::BaseMap.size_problem(5000).params['reason_detail']
  end
end
