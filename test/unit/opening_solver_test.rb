# frozen_string_literal: true

require_relative '../test_helper'

# U05 : travées, porte, jitter et dégagements.
class OpeningSolverTest < Minitest::Test
  include Archgen::Geometry

  def config(**blocks)
    base = TestData.intake.effective(TestData.building('rect-neutre-shell')).value
    Archgen::Core::Merge.leaves(base, blocks.transform_keys(&:to_s))
  end

  def solve(data)
    footprint = FootprintSolver.call(width_m: data['footprint']['width_m'], depth_m: data['footprint']['depth_m'])
    levels = FloorPlanner.call(data['levels'], slab_m: data['structure']['slab_m'])
    candidates = FacadeSolver.call(footprint, levels, data['facade'])
    return candidates unless candidates.ok?

    OpeningSolver.call(candidates.value, data, footprint: footprint, levels: levels)
  end

  def assert_refused(data, path, reason)
    result = solve(data)
    refute result.ok?, 'attendu un refus'
    assert(result.errors.any? { |d| d.code == 'E_OPENING_CLEARANCE' && d.path == path && d.params['reason'] == reason },
           "attendu #{path} #{reason}, reçu #{result.errors.map(&:to_h)}")
  end

  def test_pitch_and_front_centers
    footprint = FootprintSolver.call(width_m: 12.0, depth_m: 9.0)
    levels = FloorPlanner.call(config['levels'], slab_m: 0.2)
    candidates = FacadeSolver.call(footprint, levels, config['facade']).value
    centers = candidates.select { |c| c.facade_id == 'front' && c.level_index.zero? }.map(&:center_u_m)
    [1.95, 4.65, 7.35, 10.05].zip(centers) { |want, got| assert_in_delta want, got, 1e-9 }
  end

  def test_thirty_one_windows_and_one_door_none_on_sides
    openings = solve(config).value
    assert_equal 32, openings.size
    assert_equal 1, openings.count { |o| o.kind == 'door' }
    assert_equal 31, openings.count { |o| o.kind == 'window' }
    assert_empty(openings.select { |o| %w[right left].include?(o.facade_id) })
    assert_equal 'opening/front/0/1', openings.find { |o| o.kind == 'door' }.id
  end

  def test_door_replaces_window_and_starts_at_ground
    door = solve(config).value.find { |o| o.kind == 'door' }
    assert_equal 0.0, door.z_min_m
    assert_equal 2.2, door.z_max_m
    assert_equal [4.15, 5.15], [door.u_min_m, door.u_max_m]
  end

  def test_window_rectangles_relative_to_level
    openings = solve(config).value
    first = openings.find { |o| o.id == 'opening/front/1/0' }
    assert_equal [1.35, 2.55, 4.05, 5.85], [first.u_min_m, first.u_max_m, first.z_min_m, first.z_max_m]
  end

  def test_sorted_by_facade_level_bay
    ids = solve(config('facade' => { 'side_bays' => 1 })).value.map { |o| [o.facade_id, o.level_index, o.bay_index] }
    assert_equal ids.sort_by { |f, l, b| [FACADE_ORDER.index(f), l, b] }, ids
  end

  def test_side_bays_open_right_and_left
    openings = solve(config(facade: { 'side_bays' => 2 })).value
    assert_equal 8, openings.count { |o| o.facade_id == 'right' }
    assert_equal 8, openings.count { |o| o.facade_id == 'left' }
  end

  # --- Jitter

  def test_jitter_moves_windows_not_door_and_is_bounded
    data = config(facade: { 'jitter_m' => 0.05 })
    moved = solve(data).value
    still = solve(config).value
    pairs = moved.zip(still)
    refute(pairs.all? { |a, b| a.u_min_m == b.u_min_m })
    pairs.each do |a, b|
      assert_equal a.id, b.id
      assert_equal(b.u_min_m, a.u_min_m, a.id) if a.kind == 'door'
      assert_operator (a.u_min_m - b.u_min_m).abs, :<=, 0.05 + 1e-6
      assert_in_delta b.u_max_m - b.u_min_m, a.u_max_m - a.u_min_m, 2e-6
    end
  end

  def test_jitter_uses_semantic_key_and_formula
    data = config(facade: { 'jitter_m' => 0.05 })
    opening = solve(data).value.find { |o| o.id == 'opening/rear/3/3' }
    draw = Archgen::Core::DeterministicRandom.unit(42, 'opening/rear/3/3/u')
    expected = 10.05 + (0.05 * ((2 * draw) - 1)) - 0.6
    assert_in_delta expected, opening.u_min_m, 1e-6
  end

  def test_jitter_changes_with_seed_and_is_stable
    a = solve(config(facade: { 'jitter_m' => 0.05 })).value.map(&:u_min_m)
    b = solve(config(facade: { 'jitter_m' => 0.05 })).value.map(&:u_min_m)
    c = solve(config(facade: { 'jitter_m' => 0.05 }, seed: 7)).value.map(&:u_min_m)
    assert_equal a, b
    refute_equal a, c
  end

  # --- Rejets

  def test_margin_at_or_above_half_length_refused
    assert_refused config(facade: { 'margin_m' => 6.0 }), '/facade/margin_m', 'margin_exceeds_half_length'
    assert_refused config(facade: { 'margin_m' => 7.0 }), '/facade/margin_m', 'margin_exceeds_half_length'
  end

  def test_zero_side_bays_ignores_margin
    assert solve(config(footprint: { 'depth_m' => 4.0 }, facade: { 'margin_m' => 2.5, 'front_bays' => 1, 'entry_bay' => 0, 'window_width_m' => 1.0, 'door_width_m' => 1.0 })).ok?
  end

  def test_window_too_wide_for_bay_refused
    assert_refused config(facade: { 'window_width_m' => 2.65 }), '/facade/window_width_m', 'opening_spacing'
    assert solve(config(facade: { 'window_width_m' => 2.6 })).ok?, 'exactement 0,10 m de dégagement'
  end

  def test_facade_end_clearance_is_wall_plus_ten_cm
    # Bord à 0,2 + (2,7−2)/2 − … : marge 0,6, largeur 2,6 ⇒ u_min = 0,65 ; mur 0,56 ⇒ limite 0,66.
    assert_refused config(facade: { 'window_width_m' => 2.6 }, structure: { 'wall_m' => 0.56 }), '/facade/window_width_m', 'facade_end'
    assert solve(config(facade: { 'window_width_m' => 2.6 }, structure: { 'wall_m' => 0.55 })).ok?
  end

  def test_top_clearance_intermediate_level_counts_slab
    # sill 0,85 + h = top − slab − 0,10 = 3,2 − 0,2 − 0,1 ⇒ h = 2,05 ; au-delà, refus.
    assert solve(config(facade: { 'window_height_m' => 2.05 })).ok?
    assert_refused config(facade: { 'window_height_m' => 2.06 }), '/facade/window_height_m', 'level_top'
  end

  def test_top_clearance_last_level_has_no_slab
    single = { levels: { 'count' => 1 }, facade: { 'window_height_m' => 2.25, 'entry_bay' => 0 } }
    assert solve(config(**single)).ok?
    assert_refused config(levels: { 'count' => 1 }, facade: { 'window_height_m' => 2.26 }), '/facade/window_height_m', 'level_top'
  end

  def test_door_too_tall_refused
    assert_refused config(facade: { 'door_height_m' => 2.95 }), '/facade/door_height_m', 'level_top'
  end

  def test_door_collision_with_neighbour_window_refused
    # Porte de 4 m centrée à 4,65 : [2,65 ; 6,65]. Fenêtre voisine jusqu'à 2,60 : 0,05 m.
    assert_refused config(facade: { 'door_width_m' => 4.0, 'window_width_m' => 1.3 }), '/facade/door_width_m', 'opening_spacing'
    assert solve(config(facade: { 'door_width_m' => 4.0, 'window_width_m' => 1.2 })).ok?, 'exactement 0,10 m'
  end

  def test_cumulated_jitter_refused
    # Baies à 2,6 sur 2,7 : seul 0,1 de marge, tout jitter peut réduire l'écart.
    data = config(facade: { 'window_width_m' => 2.6, 'jitter_m' => 0.3 })
    result = solve(data)
    refute result.ok?
    assert(result.errors.any? { |d| d.path == '/facade/jitter_m' && d.params['reason'] == 'opening_spacing' }, result.errors.map(&:to_h).inspect)
  end

  def test_rejection_happens_without_retry_or_adjustment
    a = solve(config(facade: { 'window_width_m' => 2.65 })).errors.map(&:to_h)
    b = solve(config(facade: { 'window_width_m' => 2.65 })).errors.map(&:to_h)
    assert_equal a, b
  end

  def test_traversal_independence_of_jitter
    data = config(facade: { 'jitter_m' => 0.04, 'side_bays' => 2 })
    footprint = FootprintSolver.call(width_m: 12.0, depth_m: 9.0)
    levels = FloorPlanner.call(data['levels'], slab_m: 0.2)
    candidates = FacadeSolver.call(footprint, levels, data['facade']).value
    forward = OpeningSolver.call(candidates, data, footprint: footprint, levels: levels).value.map(&:to_h)
    backward = OpeningSolver.call(candidates.reverse, data, footprint: footprint, levels: levels).value.map(&:to_h)
    assert_equal forward, backward
  end
end
