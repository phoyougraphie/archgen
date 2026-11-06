# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter

# Le pont du panneau de rue : Ruby valide tout, le panneau ne connaît pas le tracé.
class StreetControllerTest < Minitest::Test
  include Archgen::Adapters::SketchUp

  SETTINGS = { 'building' => { 'profile' => { 'id' => 'brutalist' }, 'mode' => 'shell', 'lod' => 0 }, 'parcel' => {}, 'layout' => { 'side' => 'left' } }.freeze

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def setup
    @model = FakeSketchUp::ServiceModel.new
    service = EnsembleService.new(registry: registry, intake: Archgen::Composition.intake, ensemble_intake: Archgen::Composition.ensemble_intake,
                                  materials: Archgen::Composition.materials.fetch('materials'), material_revision: 1, host: FakeSketchUp::Host)
    @session = Archgen::Core::TraceSession.new
    @controller = Archgen::UI::StreetController.new(service: service, session: @session, registry: registry, model_provider: -> { @model })
    @counter = 0
  end

  def call(action, payload = {}, id = nil)
    @counter += 1
    @controller.dispatch(JSON.generate('v' => 1, 'request_id' => id || "s#{@counter}", 'action' => action, 'payload' => payload))
  end

  def draw(*points, finish: true)
    @session.start(points[0][0], points[0][1], 0.0)
    points.drop(1).each { |p| @session.add(p) }
    @session.finish if finish
  end

  def preview(settings = SETTINGS)
    call('preview', 'settings' => settings)
  end

  def create(digest, settings = SETTINGS, id: nil)
    call('create', { 'settings' => settings, 'ensemble_digest' => digest }, id)
  end

  def starts
    @model.operations.count { |op| op.first == :start }
  end

  def test_init_gives_styles_and_defaults_only
    response = call('init')
    assert response['ok'], response.inspect
    assert_includes response['result']['profiles'].map { |p| p['id'] }, 'haussmann'
    assert_equal 'left', response['result']['side']
    assert_equal 12.0, response['result']['defaults']['parcel']['target_width_m']
  end

  def test_init_tells_a_late_page_about_the_tool
    assert_equal false, call('init')['result']['tool_active']
    @controller.tool_active = true
    assert_equal true, call('init')['result']['tool_active']
  end

  def test_preview_without_a_trace_says_so
    result = preview['result']
    assert_equal 'empty', result['trace']['state']
    refute result.key?('metrics')
    assert_empty @controller.overlay
  end

  def test_preview_while_drawing_is_shown_but_not_ready
    draw([5.0, 7.0], [65.0, 7.0], finish: false)
    result = preview['result']
    assert_equal 'drawing', result['trace']['state']
    assert_equal 5, result['metrics']['parcel_count']
  end

  def test_overlay_is_in_model_coordinates
    draw([5.0, 7.0], [65.0, 7.0])
    preview
    rings = @controller.overlay[:rings]
    assert_equal 5, rings.size
    assert_equal [5.0, 7.0], rings.first.first
    assert_equal [17.0, 7.0], rings.first[1]
    assert_equal [17.0, 16.0], rings.first[2]
  end

  def test_preview_writes_nothing
    draw([0.0, 0.0], [60.0, 0.0])
    preview
    assert_empty @model.operations
    assert_empty @model.instances
  end

  def test_side_comes_with_the_settings
    draw([0.0, 0.0], [60.0, 0.0])
    settings = SETTINGS.merge('layout' => { 'side' => 'both', 'street_width_m' => 14 })
    assert_equal 10, call('preview', 'settings' => settings)['result']['metrics']['parcel_count']
    assert_equal 'both', @session.side
    assert_equal(-7.0, @controller.overlay[:rings].map { |r| r.map(&:last).max }.min)
  end

  def test_refused_trace_keeps_its_state_and_explains
    draw([0.0, 0.0], [5.0, 0.0])
    response = preview
    assert response['ok']
    assert_equal 'ready', response['result']['trace']['state']
    assert response['result']['refused']
    assert_equal 'segment_short', response['result']['problems'].first['params']['reason']
    refute_nil response['result']['problems'].first['message']
    refute response['result'].key?('ensemble_digest')
  end

  def test_closed_trace_is_explained_and_not_creatable
    draw([0.0, 0.0], [40.0, 0.0], [40.0, 40.0], finish: false)
    @session.add([0.0, 40.0])
    @session.close
    result = preview['result']
    assert_equal 'access_unavailable', result['problems'].first['params']['reason']
    assert result['trace']['closed']
    assert @controller.overlay[:refused]
    assert_equal 12, @controller.overlay[:rings].size, 'les parcelles restent visibles'
  end

  def test_bad_settings_are_refused_with_their_path
    draw([0.0, 0.0], [60.0, 0.0])
    response = call('preview', 'settings' => SETTINGS.merge('parcel' => { 'depth_m' => 3 }))
    assert_equal '/parcel/depth_m', response['result']['problems'].first['path']
  end

  def test_state_is_what_the_tool_pushes
    draw([0.0, 0.0], [60.0, 0.0], finish: false)
    preview
    @session.finish
    update = @controller.state
    assert update['ok']
    assert_equal 'ready', update['result']['trace']['state']
    assert_equal 5, update['result']['metrics']['parcel_count']
  end

  # --- Créer

  def test_create_writes_once_and_clears_the_trace
    draw([5.0, 7.0], [65.0, 7.0])
    digest = preview['result']['ensemble_digest']
    response = create(digest)
    assert response['ok'], response.inspect
    assert_equal 1, starts
    assert_equal 5, response['result']['created']['metrics']['parcel_count']
    assert @session.empty?
    assert_empty @controller.overlay
    root = @model.instances.first
    assert_in_delta 5.0, root.transform.to_a[12] * 0.0254, 1e-9
    assert_equal [root], @model.selection.to_a
  end

  def test_replayed_create_writes_once
    draw([0.0, 0.0], [60.0, 0.0])
    digest = preview['result']['ensemble_digest']
    first = create(digest, id: 'une')
    second = create(digest, id: 'une')
    assert_equal first, second
    assert_equal 1, starts
  end

  def test_create_needs_a_finished_trace
    draw([0.0, 0.0], [60.0, 0.0], finish: false)
    digest = preview['result']['ensemble_digest']
    response = create(digest)
    assert_equal 'trace_not_ready', response['diagnostics'].first['params']['reason']
    assert_equal 0, starts
  end

  def test_create_refuses_what_was_not_shown
    draw([0.0, 0.0], [60.0, 0.0])
    digest = preview['result']['ensemble_digest']
    @session.clear
    draw([0.0, 0.0], [72.0, 0.0])
    response = create(digest)
    assert_equal 'E_CONFIRMATION_STALE', response['diagnostics'].first['code']
    assert_equal 'preview_changed', response['diagnostics'].first['params']['reason']
    assert_equal 0, starts
    assert_equal 2, @session.points.size, 'le tracé reste'
  end

  def test_create_refuses_settings_changed_after_the_preview
    draw([0.0, 0.0], [60.0, 0.0])
    digest = preview['result']['ensemble_digest']
    response = create(digest, SETTINGS.merge('parcel' => { 'depth_m' => 12 }))
    assert_equal 'preview_changed', response['diagnostics'].first['params']['reason']
    assert_equal 0, starts
  end

  def test_create_does_not_believe_a_refused_trace
    draw([0.0, 0.0], [5.0, 0.0])
    response = create('a' * 64)
    refute response['ok']
    assert_equal 'segment_short', response['diagnostics'].first['params']['reason']
    assert_equal 0, starts
  end

  def test_new_page_never_receives_an_old_answer
    draw([0.0, 0.0], [60.0, 0.0])
    first = create(preview['result']['ensemble_digest'], id: 's3')
    assert first['ok']
    call('init')
    draw([0.0, 0.0], [60.0, 0.0])
    second = create(preview['result']['ensemble_digest'], id: 's3')
    assert second['ok']
    assert_equal 2, starts
  end

  def test_clear_forgets_the_trace
    draw([0.0, 0.0], [60.0, 0.0])
    preview
    result = call('clear')['result']
    assert_equal 'empty', result['trace']['state']
    assert_empty @controller.overlay
  end

  def test_closing_and_changing_document_forget_the_trace
    draw([0.0, 0.0], [60.0, 0.0])
    preview
    @controller.document_changed
    assert @session.empty?
    assert_empty @controller.overlay
    draw([0.0, 0.0], [60.0, 0.0])
    preview
    @controller.close_session
    assert @session.empty?
  end

  # --- Enveloppe

  def test_the_panel_cannot_send_geometry
    draw([0.0, 0.0], [60.0, 0.0])
    response = call('preview', 'settings' => SETTINGS.merge('trace' => { 'points_m' => [[0, 0], [99, 0]], 'closed' => false }))
    assert_equal 60.0, response['result']['metrics']['facade_length_m'], 'le tracé de l’outil l’emporte'
    assert_equal 'invalid_envelope', call('preview', 'settings' => SETTINGS, 'points_m' => [])['diagnostics'].first['params']['reason']
  end

  def test_bad_envelopes_are_refused
    assert_equal 'unknown_action', call('delete')['diagnostics'].first['params']['reason']
    assert_equal 'invalid_envelope', call('preview', {})['diagnostics'].first['params']['reason']
    raw = JSON.generate('v' => 2, 'request_id' => 'r', 'action' => 'init', 'payload' => {})
    assert_equal 'unsupported_protocol', @controller.dispatch(raw)['diagnostics'].first['params']['reason']
    refute @controller.dispatch('{pas du json')['ok']
  end
end
