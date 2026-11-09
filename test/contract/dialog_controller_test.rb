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
    assert_equal %w[haussmann toulousain provencal_mas provencal_village breton_longere breton_bourg brutalist], result['profiles'].map { |p| p['id'] }
    result['profiles'].each do |profile|
      assert_equal registry.fetch(profile['id']).value.revision, profile['revision'], 'dernière révision seule (AG-064)'
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
    # Le jeton est tiré au hasard : il peut contenir les chiffres du PID par chance (vu une fois, « 1000 »).
    refute_includes JSON.generate(result.except('target_token')), created.persistent_id.to_s, 'le PID ne quitte pas Ruby'
    refute_equal created.persistent_id.to_s, result['target_token']
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

  # --- Générer

  def generated(fields = {})
    response = call('generate', { 'draft' => draft(name: 'G', **fields) }, request_id: 'g1')
    assert_equal true, response['ok'], response.inspect
    response['result']
  end

  def edit_draft(**fields)
    { 'schema_version' => 1 }.merge(fields.transform_keys(&:to_s))
  end

  def test_generate_creates_selects_and_gives_a_token
    result = generated
    assert_equal 1, model.instances.size
    assert_equal [model.instances.first], model.selection.to_a
    assert_equal 1, result['revision']
    assert_equal 'G', result['name']
    assert_match(/\A\h{32}\z/, result['target_token'])
    assert_equal 'G', result['config']['name']
  end

  def test_same_request_runs_once
    first = call('generate', { 'draft' => draft }, request_id: 'dbl')
    second = call('generate', { 'draft' => draft }, request_id: 'dbl')
    assert_equal first, second
    assert_equal 1, model.instances.size
    assert_equal 2, model.operations.size, 'une seule opération : start et commit'
  end

  def test_write_during_a_write_is_refused
    bridge = nil
    inner = nil
    reentrant = Object.new
    reentrant.define_singleton_method(:create) do |**|
      inner = bridge.dispatch(JSON.generate('v' => 1, 'request_id' => 'in', 'action' => 'generate', 'payload' => { 'draft' => {} }))
      Archgen::Core::Result.fail([Archgen::Core::Diagnostic.error('E_WRITE', '/model', reason: 'write_failed')])
    end
    bridge = Archgen::UI::DialogController.new(service: reentrant, registry: registry, materials: TestData.materials, model_provider: -> { model })
    bridge.dispatch(JSON.generate('v' => 1, 'request_id' => 'out', 'action' => 'generate', 'payload' => { 'draft' => {} }))
    assert_equal 'operation_in_progress', inner['diagnostics'].first['params']['reason']
  end

  def test_rejected_generate_writes_nothing
    response = call('generate', 'draft' => draft(facade: { 'window_width_m' => 3.0 }))
    assert_equal false, response['ok']
    assert_nothing_written
  end

  def test_generate_draft_must_be_an_object
    assert_refused call('generate', 'draft' => 'texte'), 'invalid_envelope'
    assert_refused call('generate'), 'invalid_envelope'
    assert_refused call('regenerate', 'draft' => 12), 'invalid_envelope'
    assert_nothing_written
  end

  # --- Régénérer et confirmation

  def edit_preview(token, draft_body)
    response = call('preview', 'draft' => draft_body, 'target_token' => token)
    assert_equal true, response['ok'], response.inspect
    response['result']['confirmation']
  end

  def regenerate(token, draft_body, confirmation)
    call('regenerate', { 'draft' => draft_body, 'target_token' => token, 'confirmation_token' => confirmation }, request_id: "m#{rand_id}")
  end

  def rand_id
    @rand_id = (@rand_id || 0) + 1
  end

  def test_creation_preview_has_no_confirmation
    assert_nil call('preview', 'draft' => draft)['result']['confirmation']
  end

  def test_edit_preview_gives_the_contract_warning_and_changes
    token = generated['target_token']
    confirmation = edit_preview(token, edit_draft(footprint: { 'width_m' => 14 }))
    assert_equal 120, confirmation['expires_in_s']
    assert_equal 'La géométrie générée de ce bâtiment sera remplacée. Placez les ajouts à conserver dans des groupes séparés.', confirmation['message']
    assert_equal [{ 'path' => '/footprint/width_m', 'label' => 'Largeur', 'from' => '12', 'to' => '14' }], confirmation['changes']
  end

  def test_style_change_summary_names_style_and_materials
    token = generated['target_token']
    confirmation = edit_preview(token, edit_draft(profile: { 'id' => 'brutalist', 'revision' => 1 }))
    labels = confirmation['changes'].to_h { |c| [c['label'], [c['from'], c['to']]] }
    assert_equal %w[Haussmannien Brutaliste], labels['Style']
    assert_equal ['Pierre calcaire', 'Béton brut'], labels['Matériau des murs']
    assert_equal %w[Mansarde Plat], labels['Type de toit']
    assert_equal 'Style', confirmation['changes'].first['label'], 'le style apparaît en premier'
  end

  def test_regenerate_writes_once_and_gives_a_new_token
    token = generated['target_token']
    body = edit_draft(footprint: { 'width_m' => 14 })
    response = regenerate(token, body, edit_preview(token, body)['token'])
    assert_equal true, response['ok'], response.inspect
    assert_equal 2, response['result']['revision']
    refute_equal token, response['result']['target_token']
    assert_equal 14.0, response['result']['config']['footprint']['width_m']
  end

  def test_confirmation_is_single_use
    token = generated['target_token']
    body = edit_draft(footprint: { 'width_m' => 14 })
    confirmation = edit_preview(token, body)['token']
    assert_equal true, regenerate(token, body, confirmation)['ok']
    before = model.operations.size
    replay = regenerate(token, body, confirmation)
    assert_refused replay, 'confirmation_unknown'
    assert_equal 'E_CONFIRMATION_STALE', replay['diagnostics'].first['code']
    assert_equal before, model.operations.size
  end

  def test_confirmation_is_refused_for_another_draft_and_burned
    token = generated['target_token']
    body = edit_draft(footprint: { 'width_m' => 14 })
    confirmation = edit_preview(token, body)['token']
    before = model.operations.size
    assert_refused regenerate(token, edit_draft(footprint: { 'width_m' => 15 }), confirmation), 'confirmation_mismatch'
    assert_refused regenerate(token, body, confirmation), 'confirmation_unknown'
    assert_equal before, model.operations.size
  end

  def test_name_is_part_of_the_confirmed_draft
    token = generated['target_token']
    confirmation = edit_preview(token, edit_draft(name: 'A'))['token']
    assert_refused regenerate(token, edit_draft(name: 'B'), confirmation), 'confirmation_mismatch'
  end

  def test_expired_confirmation_refused_without_writing
    now = 1000.0
    controller.confirmations.clock = -> { now }
    token = generated['target_token']
    body = edit_draft
    confirmation = edit_preview(token, body)['token']
    now += 121
    before = model.operations.size
    assert_refused regenerate(token, body, confirmation), 'confirmation_expired'
    assert_equal before, model.operations.size
  end

  def test_confirmation_valid_until_the_limit
    now = 1000.0
    controller.confirmations.clock = -> { now }
    token = generated['target_token']
    confirmation = edit_preview(token, edit_draft)['token']
    now += 119
    assert_equal true, regenerate(token, edit_draft, confirmation)['ok']
  end

  def test_new_preview_replaces_the_previous_confirmation
    token = generated['target_token']
    old = edit_preview(token, edit_draft)['token']
    fresh = edit_preview(token, edit_draft)['token']
    assert_refused regenerate(token, edit_draft, old), 'confirmation_unknown'
    assert_equal true, regenerate(token, edit_draft, fresh)['ok'], 'un faux jeton ne brûle pas la confirmation active'
  end

  def test_forged_confirmation_refused
    token = generated['target_token']
    edit_preview(token, edit_draft)
    assert_refused regenerate(token, edit_draft, 'forgé'), 'confirmation_unknown'
    assert_refused regenerate(token, edit_draft, nil), 'confirmation_unknown'
  end

  def test_other_document_refused_before_consuming
    token = generated['target_token']
    confirmation = edit_preview(token, edit_draft)['token']
    model.guid = 'autre-document'
    before = model.operations.size
    assert_refused regenerate(token, edit_draft, confirmation), 'other_model'
    assert_equal before, model.operations.size
  end

  def test_selection_changed_invalidates_confirmation
    token = generated['target_token']
    confirmation = edit_preview(token, edit_draft)['token']
    model.selection.clear
    assert_equal true, controller.selection_changed(model)
    assert_refused regenerate(token, edit_draft, confirmation), 'confirmation_unknown'
  end

  def test_selection_back_on_target_changes_nothing
    token = generated['target_token']
    confirmation = edit_preview(token, edit_draft)['token']
    assert_equal false, controller.selection_changed(model)
    assert_equal true, regenerate(token, edit_draft, confirmation)['ok']
  end

  def test_selection_ignored_without_edit_target
    model.selection.clear
    assert_equal false, controller.selection_changed(model)
  end

  def test_undo_redo_invalidate_confirmation
    token = generated['target_token']
    confirmation = edit_preview(token, edit_draft)['token']
    controller.invalidate
    assert_refused regenerate(token, edit_draft, confirmation), 'confirmation_unknown'
  end

  def test_document_change_clears_tokens
    token = generated['target_token']
    controller.invalidate(document_changed: true)
    assert_refused call('preview', 'draft' => edit_draft, 'target_token' => token), 'unknown_token'
  end

  def test_closing_the_session_forgets_everything
    token = generated['target_token']
    confirmation = edit_preview(token, edit_draft)['token']
    controller.close_session
    assert_refused regenerate(token, edit_draft, confirmation), 'unknown_token'
    assert_equal false, controller.selection_changed(model)
  end

  # Défaut trouvé par H14 : la page recompte depuis r1 après une réouverture ou un rechargement.
  def test_new_page_never_receives_an_old_answer
    first = call('generate', 'draft' => draft, request_id: 'r3')
    assert_equal true, first['ok'], first.inspect
    written = model.operations.size

    assert_equal first, call('generate', 'draft' => draft, request_id: 'r3'), 'même page : réponse rejouée'
    assert_equal written, model.operations.size, 'même page : pas de seconde écriture'

    call('init', request_id: 'r1')
    second = call('generate', 'draft' => draft, request_id: 'r3')
    assert_equal true, second['ok'], second.inspect
    assert_operator model.operations.size, :>, written, 'page neuve : écriture réelle'
    refute_equal first['result']['target_token'], second['result']['target_token']
  end

  def test_closing_the_panel_forgets_remembered_answers
    first = call('generate', 'draft' => draft, request_id: 'r3')
    written = model.operations.size
    controller.close_session
    second = call('generate', 'draft' => draft, request_id: 'r3')
    assert_operator model.operations.size, :>, written
    refute_equal first['result']['target_token'], second['result']['target_token']
  end

  def test_failed_write_consumes_the_confirmation
    token = generated['target_token']
    body = edit_draft(footprint: { 'width_m' => 14 })
    confirmation = edit_preview(token, body)['token']
    model.writer_behaviour = { reject_faces: true }
    response = regenerate(token, body, confirmation)
    assert_equal 'write_failed', response['diagnostics'].first['params']['reason']
    model.writer_behaviour = {}
    assert_refused regenerate(token, body, confirmation), 'confirmation_unknown'
  end

  def test_edit_style_change_requires_exact_revision
    created
    token = call('load_selection')['result']['target_token']
    response = call('preview', 'draft' => { 'schema_version' => 1, 'profile' => { 'id' => 'toulousain' } }, 'target_token' => token)
    assert_refused response, 'exact_revision_required'
  end
end
