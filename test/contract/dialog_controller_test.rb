# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter

# Contrat du pont : Ruby valide toutes les entrées, indépendamment de JS.
class DialogControllerTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def model
    @model ||= FakeSketchUp::ServiceModel.new
  end

  def service
    @service ||= BuildingService.new(registry: registry, intake: TestData.intake, materials: TestData.materials,
                                     material_revision: 1, host: FakeSketchUp::Host)
  end

  def controller
    @controller ||= Archgen::UI::DialogController.new(service: service, registry: registry, materials: TestData.materials,
                                                      model_provider: -> { model })
  end

  # Ruby 3 range `'draft' => x` parmi les mots-clés : on sépare options et champs de payload.
  def call(action, payload = {}, **options)
    fields = options.select { |key, _| key.is_a?(String) }
    controller.dispatch(JSON.generate('v' => options.fetch(:version, 1), 'request_id' => options.fetch(:request_id, 'r1'),
                                      'action' => action, 'payload' => payload.merge(fields)))
  end

  def draft(**fields)
    { 'schema_version' => 1, 'profile' => { 'id' => 'haussmann', 'revision' => 1 } }.merge(fields.transform_keys(&:to_s))
  end

  def assert_refused(response, reason)
    assert_equal false, response['ok'], response.inspect
    assert_nil response['result']
    assert_equal reason, response['diagnostics'].first['params']['reason']
    assert_equal 'error', response['diagnostics'].first['severity']
  end

  def assert_nothing_written
    assert_empty model.operations
    assert_equal 0, model.mutation_count
  end

  # --- Enveloppe : tout est refusé proprement, sans exception

  def test_response_shape_echoes_request_id
    response = call('init', request_id: 'abc')
    assert_equal 1, response['v']
    assert_equal 'abc', response['request_id']
    assert_equal true, response['ok']
    assert_equal [], response['diagnostics']
    assert JSON.generate(response), 'toujours sérialisable'
  end

  def test_malformed_json_refused
    ['', '{', 'null', '[]', '"texte"', '12'].each do |raw|
      response = controller.dispatch(raw)
      assert_equal false, response['ok'], raw
    end
    assert_nothing_written
  end

  def test_non_string_input_refused
    assert_refused controller.dispatch(nil), 'not_a_string'
    assert_refused controller.dispatch({ 'v' => 1 }), 'not_a_string'
  end

  def test_oversized_request_refused
    huge = JSON.generate('v' => 1, 'request_id' => 'r', 'action' => 'preview', 'payload' => { 'draft' => { 'name' => 'x' * 70_000 } })
    assert_refused controller.dispatch(huge), 'too_large'
  end

  def test_duplicate_key_in_envelope_refused
    assert_refused controller.dispatch('{"v":1,"v":1,"request_id":"r","action":"init","payload":{}}'), 'duplicate_key'
  end

  def test_unknown_action_refused
    assert_refused call('eval'), 'unknown_action'
    assert_refused call('generate', 'draft' => draft), 'unknown_action'
    assert_refused call('__send__'), 'unknown_action'
    assert_nothing_written
  end

  def test_unknown_protocol_refused
    assert_refused call('init', version: 2), 'unsupported_protocol'
  end

  def test_extra_envelope_field_refused
    raw = JSON.generate('v' => 1, 'request_id' => 'r', 'action' => 'init', 'payload' => {}, 'admin' => true)
    assert_refused controller.dispatch(raw), 'invalid_envelope'
  end

  def test_extra_payload_field_refused
    assert_refused call('preview', 'draft' => draft, 'path' => 'C:/x'), 'invalid_envelope'
    assert_refused call('init', 'x' => 1), 'invalid_envelope'
  end

  def test_payload_must_be_an_object
    raw = JSON.generate('v' => 1, 'request_id' => 'r', 'action' => 'init', 'payload' => [])
    assert_refused controller.dispatch(raw), 'invalid_envelope'
  end

  def test_bad_request_id_is_never_echoed
    raw = JSON.generate('v' => 1, 'request_id' => 'x' * 65, 'action' => 'init', 'payload' => {})
    response = controller.dispatch(raw)
    assert_nil response['request_id']
    assert_equal false, response['ok']
    raw = JSON.generate('v' => 1, 'request_id' => 12, 'action' => 'init', 'payload' => {})
    assert_nil controller.dispatch(raw)['request_id']
  end

  def test_html_in_input_is_returned_as_data_only
    response = call('preview', 'draft' => draft(name: '<img src=x onerror=alert(1)>'))
    assert_equal true, response['ok']
    assert_equal '<img src=x onerror=alert(1)>', response['result']['config']['name']
  end

  def test_unexpected_exception_is_a_diagnostic_without_detail
    broken = Object.new
    def broken.preview(**) = raise(IOError, 'C:/Users/secret/f.skp')
    bridge = Archgen::UI::DialogController.new(service: broken, registry: registry, materials: TestData.materials, model_provider: -> { model })
    response = bridge.dispatch(JSON.generate('v' => 1, 'request_id' => 'r', 'action' => 'preview', 'payload' => { 'draft' => draft }))
    assert_refused response, 'internal_error'
    refute_includes JSON.generate(response), 'secret'
  end

  def test_repeated_requests_stay_independent
    20.times { |i| assert_equal "r#{i}", call('preview', { 'draft' => draft }, request_id: "r#{i}")['request_id'] }
    assert_nothing_written
  end

  # --- init

  def test_init_gives_ordered_profiles_catalogues_and_limits
    result = call('init')['result']
    assert_equal 'new', result['mode']
    assert_equal %w[haussmann toulousain brutalist], result['profiles'].map { |p| p['id'] }
    result['profiles'].each do |profile|
      assert_equal 1, profile['revision']
      refute_empty profile['label']
      refute_empty profile['signature']
    end
    assert_includes result['materials'].map { |m| m['id'] }, 'limestone'
    assert_equal 60.0, result['limits']['max_width_m']
  end

  def test_init_never_exposes_internal_profiles
    ids = call('init')['result']['profiles'].map { |p| p['id'] }
    refute_includes ids, 'generic'
    refute_includes ids, 'ordered_facade'
    assert_refused call('preview', 'draft' => { 'schema_version' => 1, 'profile' => { 'id' => 'generic' } }), 'not_selectable'
  end

  # --- Aperçu

  def test_preview_values_come_from_the_plan
    response = call('preview', 'draft' => draft(footprint: { 'width_m' => 14 }, lod: 1))
    assert_equal true, response['ok'], response.inspect
    result = response['result']
    assert_equal 14.0, result['metrics']['width_m']
    assert_equal 14.0, result['config']['footprint']['width_m']
    assert_equal 40, result['projection']['summary']['window_count'] + result['projection']['summary']['door_count']
    assert_match(/\A\h{64}\z/, result['plan_digest'])
    assert_equal 20, result['projection']['front_elevation']['openings'].size
  end

  def test_preview_writes_nothing
    call('preview', 'draft' => draft)
    call('preview', 'draft' => draft(mode: 'structural', lod: 1))
    call('preview', 'draft' => draft(facade: { 'window_width_m' => 3.0 }))
    assert_nothing_written
  end

  def test_projection_contains_no_markup
    response = call('preview', 'draft' => draft)
    refute_match(/<svg|<rect|<polygon/, JSON.generate(response['result']['projection']))
  end

  def test_rejection_carries_field_label_and_french_message
    response = call('preview', 'draft' => draft(facade: { 'window_width_m' => 3.0 }))
    diagnostic = response['diagnostics'].find { |d| d['severity'] == 'error' }
    assert_includes response['diagnostics'].map { |d| d['code'] }, 'W_HISTORICAL', 'l’avertissement de proportions reste visible'
    assert_equal '/facade/window_width_m', diagnostic['path']
    assert_equal 'Largeur de fenêtre', diagnostic['field']
    assert_equal 'Cette fenêtre ne tient pas dans la travée. Réduisez sa largeur ou le nombre de travées.', diagnostic['message']
  end

  def test_warning_does_not_block_and_is_explained
    response = call('preview', 'draft' => draft(levels: { 'count' => 4 }))
    assert_equal true, response['ok']
    assert_equal 'warning', response['diagnostics'].first['severity']
    assert_equal 'Ce style compte habituellement de 5 à 7 niveaux.', response['diagnostics'].first['message']
  end

  # --- Sélection et édition

  def created
    @created ||= service.create(model: model, draft: draft(name: 'A')).value.tap { model.selection.replace([model.instances.first]) }
  end

  def test_load_selection_gives_config_and_opaque_token
    created
    result = call('load_selection')['result']
    assert_equal 'A', result['config']['name']
    assert_equal 1, result['revision']
    assert_match(/\A\h{32}\z/, result['target_token'])
    refute_includes JSON.generate(result), created.persistent_id.to_s, 'le PID ne quitte pas Ruby'
  end

  def test_load_selection_without_selection_is_explained
    response = call('load_selection')
    assert_refused response, 'selection_not_single'
    assert_equal 'Sélectionnez un seul bâtiment ARCHGEN.', response['diagnostics'].first['message']
  end

  def test_edit_preview_starts_from_the_stored_config
    created
    token = call('load_selection')['result']['target_token']
    before = model.operations.size
    response = call('preview', 'draft' => { 'schema_version' => 1, 'footprint' => { 'depth_m' => 11 } }, 'target_token' => token)
    assert_equal true, response['ok'], response.inspect
    assert_equal 'A', response['result']['config']['name']
    assert_equal 11.0, response['result']['metrics']['depth_m']
    assert_equal before, model.operations.size
  end

  def test_forged_token_refused
    assert_refused call('preview', 'draft' => draft, 'target_token' => 'forgé'), 'unknown_token'
    assert_refused call('preview', 'draft' => draft, 'target_token' => 12), 'unknown_token'
  end

  def test_token_is_stale_after_document_change
    created
    token = call('load_selection')['result']['target_token']
    model.guid = 'autre-document'
    response = call('preview', 'draft' => { 'schema_version' => 1 }, 'target_token' => token)
    assert_refused response, 'other_model'
    assert_equal 'E_TARGET_STALE', response['diagnostics'].first['code']
  end

  def test_edit_preview_refused_when_selection_changed
    created
    token = call('load_selection')['result']['target_token']
    model.selection.clear
    response = call('preview', 'draft' => { 'schema_version' => 1 }, 'target_token' => token)
    assert_refused response, 'selection_changed'
    assert_equal 'Le bâtiment sélectionné a changé. Rechargez la sélection.', response['diagnostics'].first['message']
  end

  def test_edit_style_change_requires_exact_revision
    created
    token = call('load_selection')['result']['target_token']
    response = call('preview', 'draft' => { 'schema_version' => 1, 'profile' => { 'id' => 'toulousain' } }, 'target_token' => token)
    assert_refused response, 'exact_revision_required'
  end
end
