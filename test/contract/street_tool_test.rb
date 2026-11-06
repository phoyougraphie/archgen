# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter

# Contrat de l'outil de tracé, avec doubles : une écriture y est impossible, faute de modèle.
# La preuve native est H16.
class StreetToolTest < Minitest::Test
  Tool = Archgen::Adapters::SketchUp::StreetTool
  INCH = 0.0254
  Vec = Struct.new(:x, :y, :z)

  # Pixels = décimètres : (100, 200) vise le point (10 m, 20 m), au sol.
  class FakeInput
    attr_accessor :valid, :freedom, :altitude_in

    def initialize
      @valid = true
      @freedom = 2
      @altitude_in = 0.0
    end

    def pick(_view, x, y, *_rest)
      @x = x
      @y = y
    end

    def valid?
      @valid
    end

    def degrees_of_freedom
      @freedom
    end

    def position
      Vec.new(@x / 10.0 / INCH, @y / 10.0 / INCH, @altitude_in)
    end

    def tooltip
      'sol'
    end

    def display?
      false
    end
  end

  class FakeHost
    attr_reader :statuses, :input, :beeps
    attr_accessor :active_view

    def initialize
      @statuses = []
      @input = FakeInput.new
      @beeps = 0
    end

    def input_point
      @input
    end

    def point(x, y, z)
      Vec.new(x, y, z)
    end

    def plane_hit(_view, x, y, z)
      Vec.new(x / 10.0 / INCH, y / 10.0 / INCH, z)
    end

    def bounding_box(points)
      points
    end

    def parse_length_m(text)
      Float(text.tr(',', '.'), exception: false)
    end

    def format_length(inches)
      inches.to_s
    end

    def status(text)
      @statuses << text
    end

    def vcb(_label, _value); end

    def beep
      @beeps += 1
    end

    def color(*rgb)
      rgb
    end

    def gl_line_loop
      :loop
    end

    def gl_line_strip
      :strip
    end

    def gl_lines
      :lines
    end
  end

  class FakeView
    attr_accessor :tooltip, :line_width, :drawing_color
    attr_reader :invalidated, :drawn

    def initialize
      @invalidated = 0
      @drawn = []
    end

    def invalidate
      @invalidated += 1
    end

    def screen_coords(point)
      Vec.new(point.x * INCH * 10.0, point.y * INCH * 10.0, 0.0)
    end

    def draw(mode, points)
      @drawn << [mode, points, @drawing_color]
    end

    def draw_points(points, *_style)
      @drawn << [:points, points, @drawing_color]
    end
  end

  def setup
    @session = Archgen::Core::TraceSession.new
    @host = FakeHost.new
    @view = FakeView.new
    @changes = 0
    @rings = {}
    @tool = Tool.new(session: @session, on_change: -> { @changes += 1 }, overlay: -> { @rings }, host: @host)
    @host.active_view = @view
    @tool.activate
  end

  def click(x, y)
    @tool.onMouseMove(0, x, y, @view)
    @tool.onLButtonDown(0, x, y, @view)
  end

  def draw_street
    click(0, 0)
    click(400, 0)
    click(400, 400)
  end

  def test_clicks_place_points_in_meters
    draw_street
    assert_equal [[0.0, 0.0], [40.0, 0.0], [40.0, 40.0]], @session.points.map { |p| p.map { |c| c.round(6) } }
    assert_equal 3, @changes
  end

  def test_first_point_gives_the_plane
    @host.input.altitude_in = 3.0 / INCH
    click(100, 100)
    assert_in_delta 3.0, @session.z_m, 1e-9
  end

  def test_later_points_stay_in_the_plane_of_the_first
    @host.input.altitude_in = 3.0 / INCH
    click(0, 0)
    @host.input.altitude_in = 9.0 / INCH
    click(400, 0)
    assert_in_delta 3.0, @session.z_m, 1e-9
    assert_equal 2, @session.points.size
  end

  def test_click_outside_the_scene_does_nothing_at_first
    @host.input.valid = false
    @tool.onLButtonDown(0, 10, 10, @view)
    assert @session.empty?
  end

  def test_inferred_vertex_keeps_its_position
    click(0, 0)
    @host.input.freedom = 0
    click(123, 45)
    assert_in_delta 12.3, @session.points.last[0], 1e-6
  end

  def test_double_click_finishes_without_a_second_point
    click(0, 0)
    click(400, 0)
    @tool.onLButtonDown(0, 400, 0, @view)
    @tool.onLButtonDoubleClick(0, 400, 0, @view)
    assert_equal 'ready', @session.state
    assert_equal 2, @session.points.size
  end

  def test_escape_finishes_then_clears
    click(0, 0)
    click(400, 0)
    @tool.onCancel(0, @view)
    assert_equal 'ready', @session.state
    @tool.onCancel(0, @view)
    assert @session.empty?
  end

  def test_escape_with_one_point_forgets_it
    click(0, 0)
    @tool.onCancel(0, @view)
    assert @session.empty?
  end

  def test_click_after_a_finished_trace_starts_again
    click(0, 0)
    click(400, 0)
    @tool.onCancel(0, @view)
    click(100, 100)
    assert_equal 'drawing', @session.state
    assert_equal 1, @session.points.size
  end

  def test_clicking_near_the_first_point_closes
    draw_street
    click(5, 5)
    assert @session.closed?
    assert_equal 3, @session.points.size
  end

  def test_clicking_near_the_first_point_too_early_does_not_close
    click(0, 0)
    click(400, 0)
    click(5, 5)
    refute @session.closed?
  end

  def test_far_from_the_first_point_adds_a_point
    draw_street
    click(30, 30)
    refute @session.closed?
    assert_equal 4, @session.points.size
  end

  def test_typed_length_and_angle
    click(0, 0)
    @tool.onUserText('40;90', @view)
    assert_in_delta 40.0, @session.points.last[1], 1e-9
    assert_equal 2, @session.points.size
  end

  def test_typed_length_follows_the_mouse
    click(0, 0)
    @tool.onMouseMove(0, 0, 300, @view)
    @tool.onUserText('12,5', @view)
    assert_in_delta 12.5, @session.points.last[1], 1e-9
  end

  def test_bad_text_beeps_and_changes_nothing
    click(0, 0)
    @tool.onUserText('abc', @view)
    assert_equal 1, @session.points.size
    assert_equal 1, @host.beeps
    assert_match(/longueur/, @host.statuses.last)
  end

  def test_text_before_the_first_point_is_refused
    @tool.onUserText('10', @view)
    assert @session.empty?
    assert_equal 1, @host.beeps
  end

  def test_arrows_lock_axes
    click(0, 0)
    assert @tool.onKeyDown(Tool::KEY_RIGHT, 1, 0, @view)
    assert_equal 'red', @session.axis_lock
    assert @tool.onKeyDown(Tool::KEY_LEFT, 1, 0, @view)
    assert_equal 'green', @session.axis_lock
    click(30, 500)
    assert_in_delta 0.0, @session.points.last[0], 1e-9
    assert_in_delta 50.0, @session.points.last[1], 1e-9
  end

  def test_arrow_down_needs_a_previous_segment
    click(0, 0)
    assert @tool.onKeyDown(Tool::KEY_DOWN, 1, 0, @view)
    assert_nil @session.axis_lock
    assert_equal 1, @host.beeps
  end

  def test_ctrl_changes_side_and_notifies
    before = @changes
    assert @tool.onKeyDown(Tool::KEY_CTRL, 1, 0, @view)
    assert_equal 'right', @session.side
    assert_equal before + 1, @changes
  end

  def test_alt_toggles_right_angle
    @tool.onKeyDown(Tool::KEY_ALT, 1, 0, @view)
    assert @session.lock_90
    click(0, 0)
    click(400, 30)
    assert_in_delta 0.0, @session.points.last[1], 1e-9
  end

  def test_key_repeat_and_other_keys_are_left_alone
    refute @tool.onKeyDown(Tool::KEY_RIGHT, 2, 0, @view)
    refute @tool.onKeyDown(65, 1, 0, @view)
    assert_nil @session.axis_lock
  end

  def test_draw_shows_trace_and_parcels_without_a_model
    draw_street
    @rings = { rings: [[[0.0, 0.0], [12.0, 0.0], [12.0, 9.0], [0.0, 9.0]]] }
    @tool.draw(@view)
    modes = @view.drawn.map(&:first)
    assert_includes modes, :loop
    assert_includes modes, :strip
    assert_includes modes, :points
    assert_includes modes, :lines
  end

  def test_refused_parcels_change_color
    @rings = { rings: [[[0.0, 0.0], [12.0, 0.0], [12.0, 9.0], [0.0, 9.0]]], refused: true }
    @tool.draw(@view)
    assert_equal Tool::REFUSED_RGB, @view.drawn.find { |d| d.first == :loop }.last
  end

  def test_extents_cover_trace_and_parcels
    draw_street
    @rings = { rings: [[[0.0, 0.0], [100.0, 0.0], [100.0, 9.0], [0.0, 9.0]]] }
    points = @tool.getExtents
    assert_operator points.map(&:x).max * INCH, :>=, 100.0
  end

  def test_deactivation_is_reported
    told = 0
    tool = Tool.new(session: @session, on_change: -> {}, overlay: -> {}, host: @host, on_deactivate: -> { told += 1 })
    tool.deactivate(@view)
    assert_equal 1, told
  end

  def test_the_vcb_is_enabled
    assert @tool.enableVCB?
  end
end
