# frozen_string_literal: true

require_relative '../test_helper'

# U04 : anneau, normales, niveaux.
class FootprintTest < Minitest::Test
  include Archgen::Geometry

  def footprint
    FootprintSolver.call(width_m: 12.0, depth_m: 9.0)
  end

  def levels(hash = { 'count' => 4, 'height_m' => 3.2, 'heights_m' => [] })
    FloorPlanner.call(hash, slab_m: 0.2)
  end

  def test_ring_is_counter_clockwise
    ring = footprint.ring
    assert_equal [[0.0, 0.0], [12.0, 0.0], [12.0, 9.0], [0.0, 9.0]], ring
    area = ring.each_with_index.sum { |p, i| q = ring[(i + 1) % 4]; (p[0] * q[1]) - (q[0] * p[1]) } / 2.0
    assert_in_delta 108.0, area, 1e-9
  end

  def test_facade_names_and_normals
    expected = { 'front' => [0.0, -1.0], 'right' => [1.0, 0.0], 'rear' => [0.0, 1.0], 'left' => [-1.0, 0.0] }
    assert_equal expected.keys, footprint.facades.map(&:id)
    footprint.facades.each { |f| assert_equal expected[f.id], f.normal, f.id }
  end

  def test_normal_is_tangent_cross_vertical
    footprint.facades.each do |f|
      n = Geo.cross([f.tangent[0], f.tangent[1], 0.0], [0.0, 0.0, 1.0])
      assert_equal [n[0] + 0.0, n[1] + 0.0], f.normal, f.id
    end
  end

  def test_wall_point_formula
    front = footprint.facade('front')
    assert_equal [2.0, 0.24, 3.0], front.point(2.0, 3.0, 0.24), 'd vers l’intérieur, −N = +Y'
    right = footprint.facade('right')
    assert_equal [11.76, 2.0, 3.0], right.point(2.0, 3.0, 0.24)
    rear = footprint.facade('rear')
    assert_equal [10.0, 8.76, 3.0], rear.point(2.0, 3.0, 0.24)
    left = footprint.facade('left')
    assert_equal [0.24, 7.0, 3.0], left.point(2.0, 3.0, 0.24)
  end

  def test_uniform_levels_quantized
    assert_equal [0.0, 3.2, 6.4, 9.6], levels.map(&:base_z_m)
    assert_equal 12.8, levels.last.top_z_m
  end

  def test_three_slab_bands_and_none_at_ground
    bands = levels.map(&:slab_bottom_z_m)
    assert_nil bands.first
    assert_equal [3.0, 6.2, 9.4], bands.drop(1)
  end

  def test_variable_heights_replace_uniform_height
    custom = levels('count' => 3, 'height_m' => 3.2, 'heights_m' => [4.0, 3.0, 2.5])
    assert_equal [0.0, 4.0, 7.0], custom.map(&:base_z_m)
    assert_equal 9.5, custom.last.top_z_m
  end

  def test_overflow_rejected_before_any_geometry
    too_wide = TestData.building('rect-neutre-shell').merge('footprint' => { 'width_m' => 60.5, 'depth_m' => 9 })
    assert_equal '/footprint/width_m', TestData.intake.effective(too_wide).errors.first.path
    data = TestData.intake.effective(TestData.building('rect-neutre-shell')).value
    tall = Archgen::Core::Merge.leaves(data, 'levels' => { 'count' => 15, 'height_m' => 4.1 })
    assert_equal 'E_BUDGET', Archgen::Core::ConstraintValidator.call(tall).first.code
  end
end
