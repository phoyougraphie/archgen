# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_terrain'

Archgen::Loader.load_adapter

# Le pont de la section Terrain : Ruby valide tout, indépendamment du panneau. La preuve native est H14.
class DialogSiteTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp

  INCH = FakeTerrain::INCH
  DRAFT = { 'schema_version' => 1, 'profile' => { 'id' => 'haussmann', 'revision' => 1 } }.freeze

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def setup
    @model = FakeTerrain::RayModel.new
    @terrain = FakeTerrain::Solid.new(777, @model)
    @model.solids << @terrain
    @model.ray_answer = lambda do |origin|
      x, y, = origin.to_a
      [FakeTerrain::Point.new(x, y, (100.0 + (0.08 * x * INCH)) / INCH), [@terrain]]
    end
    service = BuildingService.new(registry: registry, intake: TestData.intake, materials: TestData.materials, material_revision: 1, host: FakeTerrain::Host)
    @controller = Archgen::UI::DialogController.new(service: service, registry: registry, materials: TestData.materials, model_provider: -> { @model })
    @counter = 0
    created = call('generate', 'draft' => DRAFT)
    assert created['ok'], created.inspect
    @target = created['result']['target_token']
    @instance = @model.instances.first
  end

  def call(action, payload = {})
    @counter += 1
    @controller.dispatch(JSON.generate('v' => 1, 'request_id' => "r#{@counter}", 'action' => action, 'payload' => payload))
  end

  def retain
    @model.selection.replace([@terrain])
    token = call('retain_terrain')['result']['terrain_token']
    @model.selection.replace([@instance])
    token
  end

  def survey(terrain = retain, site = {})
    payload = { 'site' => site, 'target_token' => @target }
    payload['terrain_token'] = terrain if terrain
    call('site_preview', payload)
  end

  def adapt(terrain = retain, site = {})
    preview = survey(terrain, site)
    assert preview['ok'], preview.inspect
    payload = { 'site' => site, 'target_token' => @target, 'confirmation_token' => preview['result']['confirmation']['token'] }
    payload['terrain_token'] = terrain if terrain
    written = call('adapt_site', payload)
    assert written['ok'], written.inspect
    @target = written['result']['target_token']
    written
  end

  def writes
    @model.operations.count { |op| op.first == :start }
  end

  def assert_refused(response, reason)
    assert_equal false, response['ok'], response.inspect
    assert_nil response['result']
    assert_equal reason, response['diagnostics'].first['params']['reason']
  end

  # --- Enveloppe

  def test_init_gives_the_site_defaults
    site = call('init')['result']['site']
    assert_equal 'high', site['platform']['policy']
    assert_equal 'plinth', site['earthwork']
  end

  def test_extra_or_missing_fields_are_refused
    assert_refused call('retain_terrain', 'x' => 1), 'invalid_envelope'
    assert_refused call('site_preview', 'target_token' => @target), 'invalid_envelope'
    assert_refused call('site_preview', 'site' => [], 'target_token' => @target), 'invalid_envelope'
    assert_refused call('site_preview', 'site' => {}, 'target_token' => @target, 'path' => 'C:/x'), 'invalid_envelope'
    assert_refused call('adapt_site', 'target_token' => @target, 'confirmation_token' => 'x'), 'invalid_envelope'
  end

  # --- Retenir

  def test_retaining_gives_an_opaque_token
    token = retain
    assert_match(/\A\h{32}\z/, token)
    refute_includes token, '777'
    assert_empty @terrain.attrs
  end

  def test_retaining_a_building_is_refused_with_a_message
    @model.selection.replace([@instance])
    response = call('retain_terrain')
    assert_refused response, 'terrain_is_building'
    assert_equal 'Un bâtiment ARCHGEN ne peut pas servir de terrain.', response['diagnostics'].first['message']
  end

  def test_selecting_the_terrain_keeps_the_building_token_usable_after_coming_back
    token = retain
    assert survey(token)['ok']
  end

  # --- État

  def test_status_without_a_site
    assert_equal({ 'has_site' => false }, call('site_status', 'target_token' => @target)['result'])
  end

  def test_status_with_a_site
    adapt
    result = call('site_status', 'target_token' => @target)['result']
    assert_equal true, result['has_site']
    assert_equal false, result['moved']
    assert_equal 'plinth', result['settings']['earthwork']
    refute result.key?('terrain_pid'), 'le PID ne sort pas de Ruby'
  end

  def test_forged_tokens_are_refused
    assert_refused call('site_status', 'target_token' => 'forge'), 'unknown_token'
    assert_refused survey('forge'), 'terrain_not_retained'
    [12, [], {}, ''].each { |bad| assert_equal false, call('site_status', 'target_token' => bad)['ok'] }
  end

  # --- Relever

  def test_survey_gives_values_and_a_confirmation_without_writing
    count = writes
    result = survey['result']
    assert_equal count, writes
    assert_in_delta 100.96, result['metrics']['platform_z_m'], 1e-3
    assert_includes result['lines'].first, 'Altitude de la plateforme : 100,96 m'
    assert_match(/\A\h{32}\z/, result['confirmation']['token'])
    assert_includes result['confirmation']['message'], 'Le terrain n’est pas modifié'
    assert_equal 120, result['confirmation']['expires_in_s']
  end

  def test_survey_reports_warnings_with_french_messages
    response = survey
    warning = response['diagnostics'].find { |d| d['code'] == 'W_SITE_DOOR_GAP' }
    refute_nil warning
    assert_includes warning['message'], 'aucun escalier'
  end

  def test_survey_without_a_terrain_is_explained
    response = survey(nil)
    assert_refused response, 'terrain_not_retained'
    assert_includes response['diagnostics'].first['message'], 'Retenir ce terrain'
  end

  def test_refused_settings_are_located_for_the_field
    response = survey(retain, 'platform' => { 'offset_m' => 5 })
    assert_equal '/site/platform/offset_m', response['diagnostics'].first['path']
    assert_equal 'Décalage de plateforme', response['diagnostics'].first['field']
  end

  def test_talus_lines_give_the_reach
    result = survey(retain, 'earthwork' => 'embankment')['result']
    assert(result['lines'].any? { |line| line.start_with?('Emprise du talus') })
  end

  # --- Adapter

  def test_adapting_writes_once_and_gives_a_new_token
    before = @target
    count = writes
    written = adapt
    assert_equal count + 1, writes
    assert_equal 2, written['result']['revision']
    refute_equal before, written['result']['target_token']
    assert_in_delta 100.96, written['result']['site_metrics']['platform_z_m'], 1e-3
    refute_nil written['result']['config']
  end

  def test_confirmation_is_required_single_use_and_bound
    token = retain
    confirmation = survey(token)['result']['confirmation']['token']
    count = writes
    base = { 'site' => {}, 'target_token' => @target, 'terrain_token' => token }
    assert_refused call('adapt_site', base.merge('confirmation_token' => 'forge')), 'confirmation_unknown'
    assert_equal count, writes
    other = call('adapt_site', base.merge('site' => { 'earthwork' => 'embankment' }, 'confirmation_token' => confirmation))
    assert_refused other, 'confirmation_mismatch'
    assert_equal count, writes
    assert_refused call('adapt_site', base.merge('confirmation_token' => confirmation)), 'confirmation_unknown'
    assert_equal count, writes
  end

  def test_expired_confirmation_is_refused
    token = retain
    confirmation = survey(token)['result']['confirmation']['token']
    @controller.site_confirmations.clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) + 121 }
    count = writes
    assert_refused call('adapt_site', 'site' => {}, 'target_token' => @target, 'terrain_token' => token, 'confirmation_token' => confirmation), 'confirmation_expired'
    assert_equal count, writes
  end

  def test_terrain_changed_since_the_survey_is_refused
    token = retain
    confirmation = survey(token)['result']['confirmation']['token']
    @model.ray_answer = lambda do |origin|
      x, y, = origin.to_a
      [FakeTerrain::Point.new(x, y, 101.0 / INCH), [@terrain]]
    end
    count = writes
    assert_refused call('adapt_site', 'site' => {}, 'target_token' => @target, 'terrain_token' => token, 'confirmation_token' => confirmation), 'terrain_changed'
    assert_equal count, writes
  end

  def test_replayed_request_writes_once
    token = retain
    confirmation = survey(token)['result']['confirmation']['token']
    raw = JSON.generate('v' => 1, 'request_id' => 'une', 'action' => 'adapt_site',
                        'payload' => { 'site' => {}, 'target_token' => @target, 'terrain_token' => token, 'confirmation_token' => confirmation })
    count = writes
    first = @controller.dispatch(raw)
    assert first['ok'], first.inspect
    assert_equal first, @controller.dispatch(raw)
    assert_equal count + 1, writes
  end

  def test_a_failed_write_does_not_expose_a_path
    token = retain
    confirmation = survey(token)['result']['confirmation']['token']
    @model.fail_insert = true
    @model.commit_result = false
    response = call('adapt_site', 'site' => {}, 'target_token' => @target, 'terrain_token' => token, 'confirmation_token' => confirmation)
    assert_equal false, response['ok']
    refute_match(/[A-Z]:[\\\/]/, JSON.generate(response))
  end

  # --- Les deux confirmations ne se gênent pas

  def test_site_and_building_confirmations_are_independent
    token = retain
    building = call('preview', 'draft' => DRAFT, 'target_token' => @target)['result']['confirmation']['token']
    survey(token)
    written = call('regenerate', 'draft' => DRAFT, 'target_token' => @target, 'confirmation_token' => building)
    assert written['ok'], written.inspect
  end

  def test_undo_redo_and_selection_invalidate_the_site_confirmation
    token = retain
    confirmation = survey(token)['result']['confirmation']['token']
    @controller.invalidate
    assert_refused call('adapt_site', 'site' => {}, 'target_token' => @target, 'terrain_token' => token, 'confirmation_token' => confirmation), 'confirmation_unknown'
    confirmation = survey(token)['result']['confirmation']['token']
    @model.selection.replace([@terrain])
    @controller.selection_changed(@model)
    @model.selection.replace([@instance])
    assert_refused call('adapt_site', 'site' => {}, 'target_token' => @target, 'terrain_token' => token, 'confirmation_token' => confirmation), 'confirmation_unknown'
  end

  def test_changing_document_forgets_the_retained_terrain
    token = retain
    @controller.invalidate(document_changed: true)
    @target = call('load_selection')['result']['target_token']
    assert_refused survey(token), 'terrain_not_retained'
  end

  def test_closing_the_session_forgets_the_terrain
    token = retain
    @controller.close_session
    assert_equal false, call('site_preview', 'site' => {}, 'target_token' => @target, 'terrain_token' => token)['ok']
  end

  # --- Une racine adaptée garde son terrain

  def test_survey_again_without_retaining
    adapt
    response = survey(nil)
    assert response['ok'], response.inspect
  end

  def test_building_warning_mentions_the_kept_site
    message = call('preview', 'draft' => DRAFT, 'target_token' => @target)['result']['confirmation']['message']
    assert_equal Archgen::UI::Messages::REPLACE_WARNING, message
    adapt
    message = call('preview', 'draft' => DRAFT, 'target_token' => @target)['result']['confirmation']['message']
    assert_includes message, Archgen::UI::Messages::REPLACE_WARNING
    assert_includes message, Archgen::UI::Messages::SITE_KEPT_WARNING
  end

  # --- Retirer

  def test_removing_needs_a_site_and_a_confirmation
    assert_refused call('site_remove_preview', 'target_token' => @target), 'site_absent'
    adapt
    count = writes
    assert_refused call('remove_site', 'target_token' => @target, 'confirmation_token' => 'forge'), 'confirmation_unknown'
    assert_equal count, writes
    confirmation = call('site_remove_preview', 'target_token' => @target)['result']['confirmation']
    assert_includes confirmation['message'], 'Son altitude ne change pas'
    written = call('remove_site', 'target_token' => @target, 'confirmation_token' => confirmation['token'])
    assert written['ok'], written.inspect
    assert_equal count + 1, writes
    assert_nil written['result']['site_metrics']
    assert_equal false, call('site_status', 'target_token' => written['result']['target_token'])['result']['has_site']
  end
end
