# frozen_string_literal: true

require_relative '../test_helper'

# U90 — Terrain ASCII Grid (docs/CARTOGRAPHIE_CONTRACT.md §4, AG-128).
class MapTerrainTest < Minitest::Test
  include Archgen::Core
  L93 = MapTerrain::Lambert93
  RENNES = [48.11, -1.68].freeze

  # Grille de n × n cellules de `cell` m centrée sur l'origine, altitude = base + pente × (E − E0).
  def asc(origin, n: 51, cell: 1.0, base: 100.0, slope: 0.1, hole: nil, header: true)
    l = L93.call(*origin)
    x0 = l[:east] - (cell * n / 2.0)
    y0 = l[:north] - (cell * n / 2.0)
    rows = (0...n).map do |r|
      j = n - 1 - r
      (0...n).map do |i|
        next(-99_999) if hole && hole.include?([i, j])

        e = x0 + ((i + 0.5) * cell)
        format('%.3f', base + (slope * (e - l[:east])))
      end.join(' ')
    end
    head = header ? "ncols #{n}\nnrows #{n}\nxllcorner #{x0}\nyllcorner #{y0}\ncellsize #{cell}\nNODATA_value -99999\n" : ''
    head + rows.join("\n")
  end

  def build(text, origin = RENNES, **opts)
    MapTerrain.call(text, origin: origin, **opts)
  end

  def test_lambert93_origin_and_convergence
    o = L93.call(46.5, 3.0)
    assert_in_delta 700_000.0, o[:east], 0.001
    assert_in_delta 6_600_000.0, o[:north], 0.001
    assert_in_delta 0.0, o[:gamma], 1e-12
    assert_in_delta 0.99905, o[:k], 0.0001
    rennes = L93.call(*RENNES)
    assert_in_delta(-3.3958, rennes[:gamma] * 180 / Math::PI, 0.001, 'environ −3,4° à Rennes')
    assert rennes[:east].between?(340_000, 360_000) && rennes[:north].between?(6_780_000, 6_800_000), rennes.inspect
  end

  def test_mesh_is_centred_rotated_scaled_and_relative_to_the_origin
    result = build(asc(RENNES))
    assert result.ok?, result.errors.map(&:to_h).inspect
    m = result.value['metrics']
    assert_in_delta 100.0, m['z_origin_m'], 1e-6
    assert_equal 2.0, m['step_m']
    assert_equal 26 * 26, m['points']
    assert_equal 2 * 25 * 25, m['face_count']
    v = result.value['nodes'][0]['primitive']['vertices']
    near = v.min_by { |x, y, _| Math.hypot(x, y) }
    assert_operator Math.hypot(near[0], near[1]), :<, 1.5
    # La pente suit l'est du quadrillage, tourné de γ par rapport à l'est vrai.
    l = L93.call(*RENNES)
    v.each { |x, y, z| assert_in_delta 0.1 * l[:k] * ((x * Math.cos(l[:gamma])) + (y * Math.sin(l[:gamma]))), z, 0.01 }
  end

  def test_faces_point_up
    v = build(asc(RENNES, n: 5, cell: 2.0)).value['nodes'][0]['primitive']
    v['faces'].each do |f|
      a, b, c = f['indices'].map { |i| v['vertices'][i] }
      assert_operator ((b[0] - a[0]) * (c[1] - a[1])) - ((b[1] - a[1]) * (c[0] - a[0])), :>, 0
    end
  end

  def test_window_crops_to_the_map_extent_and_coarsens_large_files
    cropped = build(asc(RENNES, n: 201), extent: [[-10, -10], [10, 10]]).value['metrics']
    assert_operator cropped['points'], :<, 40 * 40, '60 m de fenêtre (20 m de marge) au pas de 2 m, et non 201 × 201'
    big = build(asc(RENNES, n: 801, base: 50, slope: 0)).value['metrics']
    assert_operator big['points'], :<=, 250 * 250
    assert_operator big['step_m'], :>, 2.0
  end

  def test_nodata_is_filled_below_one_percent_and_refused_above
    filled = build(asc(RENNES, n: 21, hole: [[3, 3], [10, 12]]))
    assert filled.ok?
    assert_equal 2, filled.value['metrics']['nodata_filled']
    many = (0..10).map { |i| [i, 0] }
    assert_equal 'terrain_nodata', build(asc(RENNES, n: 21, hole: many)).errors.first.params['reason']
  end

  def test_refusals
    assert_equal 'terrain_outside_map', build(asc(RENNES), [43.3, 5.4]).errors.first.params['reason']
    missing = build(asc(RENNES, header: false)).errors.first
    assert_equal %w[terrain_file header], [missing.params['reason'], missing.params['reason_detail']]
    short = build(asc(RENNES, n: 5).sub(/\S+\z/, '')).errors.first
    assert_equal 'values', short.params['reason_detail']
  end
end
