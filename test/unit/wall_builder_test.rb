# frozen_string_literal: true

require_relative '../test_helper'

# U06 et U07 : murs Shell et Structural, dalles et segments traversants.
class WallBuilderTest < Minitest::Test
  include Archgen::Geometry

  def config(name, **blocks)
    base = TestData.intake.effective(TestData.building(name)).value
    Archgen::Core::Merge.leaves(base, blocks.transform_keys(&:to_s))
  end

  def build(data)
    footprint = FootprintSolver.call(width_m: data['footprint']['width_m'], depth_m: data['footprint']['depth_m'])
    levels = FloorPlanner.call(data['levels'], slab_m: data['structure']['slab_m'])
    candidates = FacadeSolver.call(footprint, levels, data['facade']).value
    openings = OpeningSolver.call(candidates, data, footprint: footprint, levels: levels).value
    grids = WallBuilder.grids(footprint, levels, openings, data).value
    { footprint: footprint, openings: openings, grids: grids, nodes: WallBuilder.call(footprint, levels, grids, data) }
  end

  def wall(built, id)
    Geo.find_node(built[:nodes], "wall/#{id}")['primitive']
  end

  # --- Grille

  def test_grid_counts_match_contract
    grids = build(config('rect-neutre-shell'))[:grids]
    assert_equal [143, 4, 108, 4], grids.map(&:cell_count)
  end

  def test_cuts_closer_than_two_millimetres_refused
    data = config('rect-neutre-shell', facade: { 'door_width_m' => 1.199 })
    footprint = FootprintSolver.call(width_m: 12.0, depth_m: 9.0)
    levels = FloorPlanner.call(data['levels'], slab_m: 0.2)
    candidates = FacadeSolver.call(footprint, levels, data['facade']).value
    openings = OpeningSolver.call(candidates, data, footprint: footprint, levels: levels).value
    result = WallBuilder.grids(footprint, levels, openings, data)
    refute result.ok?
    assert_equal 'cuts_too_close', result.errors.first.params['reason']
    assert_equal '/facade/window_width_m', result.errors.first.path
  end

  # --- U06 Shell

  def test_shell_areas
    built = build(config('rect-neutre-shell'))
    assert_in_delta 119.00, Geo.total_area(wall(built, 'front')), 1e-5
    assert_in_delta 119.04, Geo.total_area(wall(built, 'rear')), 1e-5
    assert_in_delta 115.2, Geo.total_area(wall(built, 'right')), 1e-5
    assert_in_delta 115.2, Geo.total_area(wall(built, 'left')), 1e-5
  end

  def test_shell_is_surface_with_outward_normals_and_no_slab
    built = build(config('rect-neutre-shell'))
    assert_empty Geo.find_nodes(built[:nodes], 'slab')
    built[:footprint].facades.each do |facade|
      primitive = wall(built, facade.id)
      assert_equal 'surface', primitive['type']
      primitive['faces'].each do |face|
        normal = Geo.unit_normal(Geo.polygon(primitive, face))
        assert_in_delta 1.0, Geo.dot(normal, [facade.normal[0], facade.normal[1], 0.0]), 1e-9
      end
    end
  end

  def test_shell_face_count
    built = build(config('rect-neutre-shell'))
    assert_equal 217, built[:grids].map { |g| wall(built, g.facade.id)['faces'].size }.sum
  end

  def through_segment(facade, u, z, thickness)
    [facade.point(u, z, -0.05), facade.point(u, z, thickness + 0.05)]
  end

  def assert_openings_clear(built, thickness)
    built[:openings].each do |opening|
      facade = built[:footprint].facade(opening.facade_id)
      u = (opening.u_min_m + opening.u_max_m) / 2.0
      z = (opening.z_min_m + opening.z_max_m) / 2.0
      a, b = through_segment(facade, u, z, thickness)
      refute Geo.primitive_hit?(wall(built, facade.id), a, b), "#{opening.id} bouché"
    end
  end

  def test_shell_no_face_in_opening_axis
    assert_openings_clear(build(config('rect-neutre-shell')), 0.24)
  end

  def test_shell_witness_segment_in_solid_cell_hits
    built = build(config('rect-neutre-shell'))
    a, b = through_segment(built[:footprint].facade('front'), 0.5, 1.0, 0.24)
    assert Geo.primitive_hit?(wall(built, 'front'), a, b)
  end

  def test_door_has_no_threshold
    built = build(config('rect-neutre-shell'))
    door = built[:openings].find { |o| o.kind == 'door' }
    facade = built[:footprint].facade('front')
    a, b = through_segment(facade, (door.u_min_m + door.u_max_m) / 2.0, 0.001, 0.24)
    refute Geo.primitive_hit?(wall(built, 'front'), a, b)
  end

  # --- U07 Structural

  def structural
    @structural ||= build(config('rect-neutre-structural'))
  end

  def test_each_wall_piece_has_positive_volume
    assert_in_delta 27.82272, Geo.signed_volume(wall(structural, 'front')), 1e-5
    %w[front right rear left].each do |id|
      assert_operator Geo.signed_volume(wall(structural, id)), :>, 0.0, id
      assert_equal 'solid', wall(structural, id)['type']
    end
  end

  def test_rear_and_side_volumes_analytically
    mean_long = (12.0 + 11.52) / 2.0
    mean_short = (9.0 + 8.52) / 2.0
    assert_in_delta ((mean_long * 12.8) - (16 * 2.16)) * 0.24, Geo.signed_volume(wall(structural, 'rear')), 1e-5
    assert_in_delta mean_short * 12.8 * 0.24, Geo.signed_volume(wall(structural, 'right')), 1e-5
  end

  def test_three_slabs_with_expected_volume_and_bounds
    slabs = Geo.find_nodes(structural[:nodes], 'slab')
    assert_equal %w[slab/1 slab/2 slab/3], slabs.map { |n| n['id'] }
    slabs.each { |s| assert_in_delta 19.63008, Geo.signed_volume(s['primitive']), 1e-5 }
    xs = slabs.first['primitive']['vertices'].map(&:first).uniq.sort
    assert_equal [0.24, 11.76], xs
    assert_equal [3.0, 3.2], slabs.first['primitive']['vertices'].map(&:last).uniq.sort
  end

  def test_structural_face_count_without_roof
    walls = %w[front right rear left].sum { |id| wall(structural, id)['faces'].size }
    slabs = Geo.find_nodes(structural[:nodes], 'slab').sum { |n| n['primitive']['faces'].size }
    assert_equal 708, walls + slabs
  end

  def test_each_wall_is_closed_with_opposite_edges
    %w[front right rear left].each do |id|
      incidences = Hash.new(0)
      wall(structural, id)['faces'].each do |face|
        face['indices'].each_with_index do |v, i|
          incidences[[v, face['indices'][(i + 1) % face['indices'].size]]] += 1
        end
      end
      incidences.each do |(a, b), count|
        assert_equal 1, count, "arête dupliquée #{a}-#{b} sur #{id}"
        assert_equal 1, incidences[[b, a]], "arête ouverte #{a}-#{b} sur #{id}"
      end
    end
  end

  def test_outward_lateral_faces_at_mitres
    primitive = wall(structural, 'front')
    mitre = primitive['faces'].map { |f| Geo.polygon(primitive, f) }.select { |p| p.map(&:first).minmax == [0.0, 0.24] && p.map { |q| q[1] }.minmax == [0.0, 0.24] }
    refute_empty mitre
    mitre.each do |points|
      n = Geo.unit_normal(points)
      assert_in_delta(-Math.sqrt(0.5), n[0], 1e-6)
      assert_in_delta Math.sqrt(0.5), n[1], 1e-6
    end
  end

  def test_mitres_share_interface_without_volume_overlap
    front = wall(structural, 'front')['vertices'].select { |v| v[0] <= 0.24 && v[1] <= 0.24 }
    left = wall(structural, 'left')['vertices'].select { |v| v[0] <= 0.24 && v[1] <= 0.24 }
    assert_includes front, [0.0, 0.0, 0.0]
    assert_includes left, [0.0, 0.0, 0.0]
    assert_includes front, [0.24, 0.24, 0.0]
    assert_includes left, [0.24, 0.24, 0.0]
    # Le coin ne contient que la diagonale commune : aucun volume ne la franchit.
    (front + left).each { |v| assert_in_delta v[0], v[1], 1e-6, v.inspect }
  end

  def test_structural_segments_clear_both_skins
    assert_openings_clear(structural, 0.24)
  end

  def test_structural_witness_hits_both_skins
    a, b = through_segment(structural[:footprint].facade('front'), 0.6, 1.0, 0.24)
    hits = wall(structural, 'front')['faces'].count { |f| Geo.segment_hits?(a, b, Geo.polygon(wall(structural, 'front'), f)) }
    assert_equal 2, hits
  end

  def test_no_wall_threshold_under_door_in_structural
    primitive = wall(structural, 'front')
    door = structural[:openings].find { |o| o.kind == 'door' }
    bottom = primitive['faces'].map { |f| Geo.polygon(primitive, f) }.select do |points|
      points.all? { |p| p[2].zero? } && points.all? { |p| p[0] > door.u_min_m && p[0] < door.u_max_m }
    end
    assert_empty bottom
  end

  def test_shell_and_structural_share_openings_and_grid
    shell = build(config('rect-neutre-shell'))
    assert_equal shell[:openings].map(&:to_h), structural[:openings].map(&:to_h)
    assert_equal shell[:grids].map(&:us), structural[:grids].map(&:us)
    assert_equal shell[:grids].map(&:zs), structural[:grids].map(&:zs)
  end

  def test_single_level_has_no_slab
    built = build(config('rect-neutre-structural', levels: { 'count' => 1 }, facade: { 'entry_bay' => 0 }))
    assert_empty Geo.find_nodes(built[:nodes], 'slab')
  end
end
