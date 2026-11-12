# frozen_string_literal: true

require_relative '../test_helper'

# U92 — Rues à plat du mode simple (ADR-58, docs/CARTOGRAPHIE_CONTRACT.md §6).
class MapStreetsTest < Minitest::Test
  include Archgen::Core

  def way(id, highway, points, **tags)
    { 'id' => "way/#{id}", 'tags' => { 'highway' => highway }.merge(tags.transform_keys(&:to_s)), 'points_m' => points }
  end

  def streets(ways)
    result = MapStreets.call({ 'ways' => ways, 'buildings' => [] })
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def faces(node)
    p = node['primitive']
    p['faces'].map { |f| f['indices'].map { |i| p['vertices'][i] } }
  end

  def test_width_material_and_level_follow_the_type
    value = streets([way(1, 'residential', [[0, 0], [100, 0]]), way(2, 'footway', [[0, 20], [50, 20]]), way(3, 'primary', [[0, 40], [80, 40]])])
    residential, footway, primary = value['nodes']
    ys = faces(residential).flatten(1).map { |p| p[1] }
    assert_equal [-3.0, 3.0], ys.minmax.map { |y| y.round(6) }
    assert_equal 'road/sidewalk', footway['primitive']['faces'][0]['material']
    z = ->(n) { n['primitive']['vertices'][0][2] }
    assert_operator z.call(primary), :>, z.call(residential), 'la plus importante au-dessus'
    assert_operator z.call(residential), :>, z.call(footway)
  end

  def test_every_face_is_flat_convex_and_faces_up_even_on_sharp_turns
    zigzag = [[0, 0], [30, 0], [2, 3], [40, 8], [41, 40], [0, 41], [3, 0.5]]
    value = streets([way(1, 'primary', zigzag), way(2, 'residential', (0..40).map { |i| [i * 3.0, Math.sin(i / 2.0) * 6] })])
    value['nodes'].each do |node|
      faces(node).each do |pts|
        assert_operator MapBuildings.polygon_area(pts.map { |p| p[0, 2] }), :>, 0, node['id']
        assert_equal 1, pts.map { |p| p[2] }.uniq.size
        next unless pts.size == 4

        assert MapStreets.convex?(pts.map { |p| p[0, 2] }), node['id']
      end
    end
  end

  def test_unknown_tunnels_and_short_ways_are_counted_not_refused
    value = streets([way(1, 'proposed', [[0, 0], [10, 0]]), way(2, 'residential', [[0, 0], [10, 0]], tunnel: 'yes'),
                     way(3, 'service', [[0, 0], [0.2, 0]]), way(4, 'residential', [[0, 0], [10, 0]], bridge: 'yes')])
    assert_equal 1, value['street_count'], 'un pont reste une rue à plat'
    assert_equal({ 'highway_unknown' => 1, 'too_short' => 1, 'tunnel' => 1 }, value['skipped'])
  end
end
