# frozen_string_literal: true

require_relative '../test_helper'

# Logique pure du tracé : points, blocages, saisie (docs/ENSEMBLE_CONTRACT.md, Outil de tracé).
class TraceSessionTest < Minitest::Test
  Session = Archgen::Core::TraceSession

  def session(*points, z: 0.0)
    Session.new.tap do |s|
      next if points.empty?

      s.start(points[0][0], points[0][1], z)
      points.drop(1).each { |p| s.add(p) }
    end
  end

  def assert_point(expected, actual)
    assert_in_delta expected[0], actual[0], 1e-9
    assert_in_delta expected[1], actual[1], 1e-9
  end

  def test_starts_empty
    value = Session.new
    assert value.empty?
    assert_equal 'empty', value.state
    assert_equal 'left', value.side
  end

  def test_state_follows_the_gesture
    value = session([0.0, 0.0])
    assert_equal 'drawing', value.state
    value.add([10.0, 0.0])
    value.finish
    assert_equal 'ready', value.state
    assert value.finished?
    refute value.closed?
  end

  def test_a_point_on_the_last_one_is_ignored
    value = session([0.0, 0.0], [10.0, 0.0])
    refute value.add([10.0, 0.0005])
    assert value.add([10.0, 0.002])
    assert_equal 3, value.points.size
  end

  def test_finish_with_one_point_forgets_it
    value = session([0.0, 0.0])
    value.finish
    assert value.empty?
    refute value.finished?
  end

  def test_close_needs_three_points
    value = session([0.0, 0.0], [10.0, 0.0])
    refute value.close
    refute value.closed?
    value.add([10.0, 10.0])
    assert value.close
    assert value.closed?
    assert value.finished?
  end

  def test_points_are_relative_to_the_first
    value = session([5.0, 7.0], [45.0, 7.0], z: 3.0)
    assert_equal [[0.0, 0.0], [40.0, 0.0]], value.relative_points
    assert_equal [5.0, 7.0, 3.0], value.origin_m
    assert_equal({ 'points_m' => [[0.0, 0.0], [40.0, 0.0]], 'closed' => false }, value.trace)
  end

  def test_length_counts_the_closing_segment
    value = session([0.0, 0.0], [10.0, 0.0], [10.0, 10.0])
    assert_equal 20.0, value.length_m
    value.close
    assert_in_delta 20.0 + Math.hypot(10, 10), value.length_m, 1e-9
  end

  def test_side_cycles
    value = Session.new
    assert_equal %w[right both left], Array.new(3) { value.cycle_side }
  end

  def test_clear_keeps_side_and_right_angle
    value = session([0.0, 0.0], [10.0, 0.0])
    value.cycle_side
    value.toggle_90
    value.clear
    assert value.empty?
    assert_equal 'right', value.side
    assert value.lock_90
  end

  # --- Blocages

  def test_no_lock_leaves_the_target
    assert_equal [3.0, 4.0], session([0.0, 0.0]).constrain([3.0, 4.0])
  end

  def test_red_and_green_locks_follow_the_mouse_sense
    value = session([1.0, 1.0])
    value.toggle_lock('red')
    assert_point [6.0, 1.0], value.constrain([6.0, 3.0])
    assert_point [-2.0, 1.0], value.constrain([-2.0, 3.0])
    value.toggle_lock('green')
    assert_point [1.0, 5.0], value.constrain([3.0, 5.0])
    assert_point [1.0, -4.0], value.constrain([3.0, -4.0])
  end

  def test_same_arrow_unlocks
    value = session([0.0, 0.0])
    value.toggle_lock('red')
    assert_equal 'red', value.axis_lock
    value.toggle_lock('red')
    assert_nil value.axis_lock
  end

  def test_lock_falls_when_a_point_is_placed
    value = session([0.0, 0.0])
    value.toggle_lock('red')
    value.add([10.0, 0.0])
    assert_nil value.axis_lock
  end

  def test_previous_lock_needs_a_segment
    value = session([0.0, 0.0])
    refute value.toggle_lock('prev')
    assert_nil value.axis_lock
    value.add([10.0, 10.0])
    assert value.toggle_lock('prev')
  end

  def test_previous_lock_gives_square_or_straight
    value = session([0.0, 0.0], [10.0, 10.0])
    value.toggle_lock('prev')
    # Perpendiculaire au segment à 45°.
    assert_point [5.0, 15.0], value.constrain([5.0, 15.0])
    # Prolongement.
    assert_point [15.0, 15.0], value.constrain([16.0, 14.0])
  end

  def test_right_angle_lock_uses_the_axes_then_the_previous_segment
    value = Session.new
    value.toggle_90
    value.start(0.0, 0.0, 0.0)
    assert_point [10.0, 0.0], value.constrain([10.0, 2.0])
    value.add([10.0, 10.0])
    # Depuis (10, 10) vers (4, 15) : quart de tour à gauche du segment à 45°, longueur projetée 7,78.
    assert_point [4.5, 15.5], value.constrain([4.0, 15.0])
  end

  # --- Saisie

  def parse(text)
    Session.parse_typed(text, ->(v) { Float(v.tr(',', '.'), exception: false) })
  end

  def test_parse_length_and_angle
    assert_equal [12.5, nil], parse('12,5')
    assert_equal [12.5, 90.0], parse('12.5;90')
    assert_equal [10.0, -45.5], parse('10 ; -45,5')
  end

  def test_parse_refuses_the_rest
    assert_nil parse('')
    assert_nil parse('abc')
    assert_nil parse('-3')
    assert_nil parse('0')
    assert_nil parse('12;abc')
    assert_nil parse('12;90;3')
    assert_nil parse(';90')
  end

  def test_typed_with_an_angle_starts_from_the_red_axis
    value = session([1.0, 1.0])
    assert_point [1.0, 11.0], value.typed(10.0, 90.0, nil)
    assert_point [11.0, 1.0], value.typed(10.0, 0.0, nil)
  end

  def test_typed_without_angle_follows_the_mouse
    value = session([0.0, 0.0])
    assert_point [0.0, 10.0], value.typed(10.0, nil, [0.0, 3.0])
    assert_nil value.typed(10.0, nil, nil)
    assert_nil value.typed(10.0, nil, [0.0, 0.0])
  end
end
