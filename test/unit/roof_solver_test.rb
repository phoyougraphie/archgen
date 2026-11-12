# frozen_string_literal: true

require_relative '../test_helper'

# U08 : altitudes, pentes, débords, continuité et normales des quatre toits.
class RoofSolverTest < Minitest::Test
  include Archgen::Geometry

  MATERIALS = { 'wall' => 'limestone', 'roof' => 'zinc', 'frames' => 'painted_wood' }.freeze
  H = 12.8

  def roof(type, width: 12.0, depth: 9.0, overhang: 0.0, pitch: 0.0, lower: 0.0, inset: 0.0, top: H)
    footprint = FootprintSolver.call(width_m: width, depth_m: depth)
    spec = { 'type' => type, 'overhang_m' => overhang, 'pitch_deg' => pitch, 'lower_pitch_deg' => lower, 'inset_m' => inset }
    RoofSolver.call(footprint, top, spec, materials: MATERIALS)
  end

  def faces(plan, category = nil)
    Geo.find_nodes(plan.nodes, category || 'roof_face').map do |node|
      primitive = node['primitive']
      [node['id'], Geo.polygon(primitive, primitive['faces'].first), primitive['faces'].first['material']]
    end
  end

  def tan(degrees)
    Math.tan(degrees * Math::PI / 180.0)
  end

  def assert_all_upward(plan)
    faces(plan).each { |id, points, _| assert_operator Geo.unit_normal(points)[2], :>, 0.0, id }
  end

  def assert_planar(points)
    normal = Geo.unit_normal(points)
    points.each { |p| assert_in_delta 0.0, Geo.dot(normal, Geo.sub(p, points[0])), 5e-6 }
  end

  # --- Plat

  def test_flat_at_wall_top
    plan = roof('flat').value
    assert_equal H, plan.top_z_m
    id, points, material = faces(plan).first
    assert_equal 'roof/top', id
    assert_equal 'zinc', material
    assert_equal [H], points.map(&:last).uniq
    assert_all_upward(plan)
    assert_equal 1, faces(plan).size
  end

  def test_flat_overhang_widens_ring
    points = faces(roof('flat', overhang: 0.5).value).first[1]
    assert_equal [-0.5, 12.5], points.map(&:first).minmax
    assert_equal [-0.5, 9.5], points.map { |p| p[1] }.minmax
  end

  # --- Deux pans

  def test_gable_ridge_and_eaves
    plan = roof('gable', pitch: 30.0, overhang: 0.3).value
    expected_top = H + (tan(30) * 4.5)
    assert_in_delta expected_top, plan.top_z_m, 1e-5
    points = faces(plan).find { |id, _, _| id == 'roof/front' }[1]
    assert_in_delta H - (tan(30) * 0.3), points.map(&:last).min, 1e-5
    assert_equal [-0.3, 12.3], points.map(&:first).minmax
    assert_equal [-0.3, 4.5], points.map { |p| p[1] }.minmax
    assert_all_upward(plan)
    faces(plan).each { |_, pts, _| assert_planar(pts) }
  end

  def test_gable_slope_matches_pitch
    points = faces(roof('gable', pitch: 40.0).value).find { |id, _, _| id == 'roof/front' }[1]
    normal = Geo.unit_normal(points)
    assert_in_delta 40.0, Math.acos(normal[2]) * 180 / Math::PI, 1e-3
  end

  def test_gable_ends_are_triangles_outward_with_wall_material
    plan = roof('gable', pitch: 30.0, overhang: 0.3).value
    ends = faces(plan, 'gable_end')
    assert_equal %w[roof/gable/right roof/gable/left], ends.map(&:first)
    right = ends.first[1]
    left = ends.last[1]
    assert_equal 3, right.size
    assert_in_delta 1.0, Geo.unit_normal(right)[0], 1e-9
    assert_in_delta(-1.0, Geo.unit_normal(left)[0], 1e-9)
    assert_equal [12.0], right.map(&:first).uniq
    assert_equal [0.0], left.map(&:first).uniq
    assert_equal H, right.map(&:last).min, 'part de H, pas de la rive'
    assert_equal 'limestone', ends.first[2]
  end

  # --- Croupe

  def test_hip_square_has_one_apex_and_four_triangles
    plan = roof('hip', width: 10.0, depth: 10.0, pitch: 30.0).value
    list = faces(plan)
    assert_equal 4, list.size
    list.each { |_, points, _| assert_equal 3, points.size }
    assert_equal 1, list.map { |_, points, _| points.last }.uniq.size
    assert_in_delta H + (tan(30) * 5.0), plan.top_z_m, 1e-5
    assert_all_upward(plan)
  end

  def test_hip_wide_rectangle_has_ridge_along_x
    list = faces(roof('hip', pitch: 30.0).value)
    assert_equal [4, 3, 4, 3], list.map { |_, points, _| points.size }
    top = list.flat_map { |_, points, _| points }.max_by(&:last)[2]
    ridge = list.flat_map { |_, points, _| points }.select { |p| (p[2] - top).abs < 1e-6 }.uniq.sort
    assert_equal [[4.5, 4.5, top], [7.5, 4.5, top]], ridge
  end

  def test_hip_deep_rectangle_has_ridge_along_y
    list = faces(roof('hip', width: 9.0, depth: 12.0, pitch: 30.0).value)
    assert_equal [3, 4, 3, 4], list.map { |_, points, _| points.size }
    top = list.flat_map { |_, points, _| points }.max_by(&:last)[2]
    ridge = list.flat_map { |_, points, _| points }.select { |p| (p[2] - top).abs < 1e-6 }.uniq.sort
    assert_equal [[4.5, 4.5, top], [4.5, 7.5, top]], ridge
  end

  def test_hip_constant_slope_on_all_pans
    [[12.0, 9.0], [9.0, 12.0], [10.0, 10.0]].each do |w, d|
      faces(roof('hip', width: w, depth: d, pitch: 35.0, overhang: 0.4).value).each do |id, points, _|
        assert_in_delta 35.0, Math.acos(Geo.unit_normal(points)[2]) * 180 / Math::PI, 1e-3, id
        assert_planar(points)
      end
    end
  end

  def test_hip_eave_is_uniform_with_overhang
    points = faces(roof('hip', pitch: 30.0, overhang: 0.4).value).flat_map { |_, p, _| p }
    low = points.map(&:last).min
    assert_in_delta H - (tan(30) * 0.4), low, 1e-5
    points.select { |p| (p[2] - low).abs < 1e-9 }.each do |p|
      assert(p[0] == -0.4 || p[0] == 12.4)
      assert(p[1] == -0.4 || p[1] == 9.4)
    end
  end

  def test_nearly_square_hip_refused
    result = roof('hip', width: 10.001, depth: 10.0, pitch: 30.0)
    refute result.ok?
    assert_equal 'ridge_too_short', result.errors.first.params['reason']
    assert_equal 'E_ROOF_GEOMETRY', result.errors.first.code
  end

  # --- Mansarde

  def mansard(**kwargs)
    roof('mansard', pitch: 25.0, lower: 65.0, inset: 0.9, **kwargs).value
  end

  def test_mansard_total_altitude
    expected = H + (tan(65) * 0.9) + (tan(25) * ((9.0 / 2) - 0.9))
    assert_in_delta expected, mansard.top_z_m, 1e-5
  end

  def test_mansard_eave_and_ring
    plan = mansard(overhang: 0.15)
    lower = faces(plan).select { |id, _, _| id.start_with?('roof/lower/') }
    assert_equal 4, lower.size
    points = lower.flat_map { |_, p, _| p }
    assert_in_delta H - (tan(65) * 0.15), points.map(&:last).min, 1e-5
    assert_in_delta H + (tan(65) * 0.9), points.map(&:last).max, 1e-5
    assert_all_upward(plan)
    lower.each { |_, p, _| assert_planar(p) }
  end

  def test_mansard_junctions_share_vertices
    list = faces(mansard(overhang: 0.15))
    lower_top = list.select { |id, _, _| id.start_with?('roof/lower/') }.flat_map { |_, p, _| p.last(2) }.uniq.sort
    upper_low = list.select { |id, _, _| id.start_with?('roof/upper/') }.flat_map { |_, p, _| p }
    z = lower_top.first[2]
    upper_eave = upper_low.select { |p| (p[2] - z).abs < 1e-9 }.uniq.sort
    assert_equal lower_top, upper_eave
  end

  def test_mansard_upper_slope
    faces(mansard).select { |id, _, _| id.start_with?('roof/upper/') }.each do |id, points, _|
      assert_in_delta 25.0, Math.acos(Geo.unit_normal(points)[2]) * 180 / Math::PI, 1e-3, id
    end
  end

  def test_mansard_lower_slope
    faces(mansard).select { |id, _, _| id.start_with?('roof/lower/') }.each do |id, points, _|
      assert_in_delta 65.0, Math.acos(Geo.unit_normal(points)[2]) * 180 / Math::PI, 1e-3, id
    end
  end

  def test_mansard_square_crown_has_single_apex
    list = faces(roof('mansard', width: 10.0, depth: 10.0, pitch: 25.0, lower: 65.0, inset: 0.9).value)
    upper = list.select { |id, _, _| id.start_with?('roof/upper/') }
    assert_equal [3, 3, 3, 3], upper.map { |_, p, _| p.size }
  end

  # --- Rejets

  def test_eave_under_ground_rejected
    result = roof('mansard', pitch: 25.0, lower: 80.0, inset: 0.9, overhang: 1.0, top: 2.2)
    refute result.ok?
    assert_equal '/roof/overhang_m', result.errors.first.path
  end

  def test_invalid_inset_rejected_by_constraints
    data = TestData.intake.effective(TestData.building('haussmann-12x9')).value
    bad = Archgen::Core::Merge.leaves(data, 'footprint' => { 'depth_m' => 4.0 }, 'roof' => { 'inset_m' => 1.9 })
    assert_equal '/roof/inset_m', Archgen::Core::ConstraintValidator.call(bad).first.path
  end
end
