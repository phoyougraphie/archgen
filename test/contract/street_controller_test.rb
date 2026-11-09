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

  # --- Terrain d'un ensemble

  class SiteService
    attr_reader :adapted, :removed

    def initialize(inner)
      @inner = inner
      @removed = 0
    end

    def respond_to_missing?(*) = true

    def method_missing(name, ...)
      @inner.public_send(name, ...)
    end

    def retain_terrain(model:)
      model.selection.length == 1 ? Archgen::Core::Result.ok(:terrain) : Archgen::Core::Result.fail([Archgen::Core::Diagnostic.error('E_SITE_TERRAIN', '/site/terrain', reason: 'terrain_selection')])
    end

    def site_status(**) = Archgen::Core::Result.ok(@status)
    attr_writer :status

    def preview_site(**)
      warnings = (1..5).map { |i| Archgen::Core::Diagnostic.warning('W_SITE_DOOR_GAP', "/parcels/left/0/#{i}/site/platform", reason: 'door_gap', value: i * 0.3, id: 'door') }
      metrics = { 'platform_min_z_m' => 1.0, 'platform_max_z_m' => 2.0, 'max_step_m' => 0.5, 'fill_max_m' => 1.0, 'fill_volume_m3' => 3.0, 'cut_max_m' => 0.0, 'cut_volume_m3' => 0.0, 'survey_point_count' => 40, 'expanded_site_face_count' => 80 }
      Archgen::Core::Result.ok(Struct.new(:site_digest, :site_plan).new('d' * 64, { 'metrics' => metrics }), warnings)
    end

    def adapt_to_site(**options)
      @adapted = options
      Archgen::Core::Result.ok(Struct.new(:target, :revision).new(options[:target], 2))
    end

    def remove_site(target:, **)
      @removed += 1
      Archgen::Core::Result.ok(Struct.new(:target, :revision).new(target, 3))
    end
  end

  def site_controller
    inner = EnsembleService.new(registry: registry, intake: Archgen::Composition.intake, ensemble_intake: Archgen::Composition.ensemble_intake,
                                materials: Archgen::Composition.materials.fetch('materials'), material_revision: 1, host: FakeSketchUp::Host)
    created = inner.create(model: @model, tree: { 'trace' => { 'points_m' => [[0, 0], [48, 0]], 'closed' => false }, 'building' => { 'profile' => { 'id' => 'brutalist' } } }, origin_m: [0.0, 0.0, 0.0])
    raise created.errors.inspect unless created.ok?

    @root = @model.instances.last
    @site_service = SiteService.new(inner)
    @controller = Archgen::UI::StreetController.new(service: @site_service, session: @session, registry: registry, model_provider: -> { @model })
    @model.selection.replace([@root])
  end

  def test_init_gives_site_defaults_and_materials
    result = call('init')['result']
    assert_equal 'plinth', result['site_defaults']['earthwork']
    assert(result['site_materials'].any? { |m| m['id'] == 'concrete' })
  end

  def test_site_actions_need_a_loaded_ensemble
    assert_equal 'edit_not_loaded', call('site_preview', 'site' => {})['diagnostics'].first['params']['reason']
    assert_equal false, call('adapt_site', 'site' => {}, 'site_digest' => 'x')['ok']
    assert_equal false, call('remove_site')['ok']
  end

  def test_site_needs_a_retained_terrain
    site_controller
    call('load_selection')
    assert_equal 'terrain_not_retained', call('site_preview', 'site' => {})['diagnostics'].first['params']['reason']
  end

  def test_a_retained_terrain_survives_reloading_the_ensemble
    site_controller
    assert_equal true, call('retain_terrain')['result']['retained']
    assert_equal true, call('load_selection')['ok']
    assert_equal true, call('site_preview', 'site' => {})['ok']
  end

  def test_site_preview_shows_lines_and_merges_warnings
    site_controller
    call('retain_terrain')
    call('load_selection')
    response = call('site_preview', 'site' => {})
    assert_equal 'd' * 64, response['result']['site_digest']
    assert_includes response['result']['lines'].first, 'Plateformes'
    gaps = response['diagnostics'].select { |d| d['code'] == 'W_SITE_DOOR_GAP' }
    assert_equal 1, gaps.size
    assert_equal 5, gaps.first['params']['count']
    assert_includes gaps.first['message'], '5 parcelles'
  end

  def test_adapt_is_replayed_once_and_sends_the_digest
    site_controller
    call('retain_terrain')
    call('load_selection')
    call('adapt_site', { 'site' => {}, 'site_digest' => 'abc' }, 'same')
    first = @site_service.adapted
    call('adapt_site', { 'site' => {}, 'site_digest' => 'other' }, 'same')
    assert_equal 'abc', first[:site_digest]
    assert_same first, @site_service.adapted
  end

  def test_loaded_site_gives_its_terrain_without_retaining_again
    site_controller
    @site_service.status = { 'settings' => { 'x' => 1 }, 'terrain_pid' => 77, 'moved' => false }
    loaded = call('load_selection')
    assert_equal true, loaded['result']['site']['has_site']
    assert_equal true, call('site_preview', 'site' => {})['ok']
  end

  def test_remove_site_goes_through_mutations
    site_controller
    call('load_selection')
    call('remove_site', {}, 'r')
    call('remove_site', {}, 'r')
    assert_equal 1, @site_service.removed
  end

  def test_bad_site_payload_is_refused
    assert_equal 'invalid_envelope', call('site_preview', 'site' => 'x')['diagnostics'].first['params']['reason']
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

  def test_closed_trace_of_a_style_with_a_form_is_creatable
    draw([0.0, 0.0], [40.0, 0.0], [40.0, 40.0], finish: false)
    @session.add([0.0, 40.0])
    @session.close
    result = call('preview', 'settings' => SETTINGS.merge('access' => { 'count' => 2 }))['result']
    assert_equal 10, result['metrics']['parcel_count']
    assert_equal 2, result['metrics']['access_count']
    assert_equal 10, @controller.overlay[:rings].size, 'l’aperçu montre les vides'
    created = create(result['ensemble_digest'], SETTINGS.merge('access' => { 'count' => 2 }))
    assert created['ok'], created.inspect
    assert_equal 2, created['result']['created']['metrics']['access_count']
  end

  def test_access_settings_are_ignored_on_an_open_street
    draw([0.0, 0.0], [60.0, 0.0])
    result = call('preview', 'settings' => SETTINGS.merge('access' => { 'count' => 2 }))['result']
    assert_equal 5, result['metrics']['parcel_count']
  end

  def test_refused_porch_is_explained_and_not_creatable
    draw([0.0, 0.0], [40.0, 0.0], [40.0, 40.0], finish: false)
    @session.add([0.0, 40.0])
    @session.close
    result = call('preview', 'settings' => SETTINGS.merge('building' => { 'profile' => { 'id' => 'haussmann' } }, 'access' => { 'height_m' => 6 }))['result']
    assert_equal 'porch_too_high', result['problems'].first['params']['reason']
    assert result['trace']['closed']
    assert @controller.overlay[:refused]
    assert_operator @controller.overlay[:rings].size, :>=, 12, 'les parcelles et les passages restent visibles'
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

  # --- Modifier

  def created_root(*points, **options)
    draw(*points, **options)
    digest = preview['result']['ensemble_digest']
    assert create(digest)['ok']
    @model.instances.first
  end

  def edit_settings(extra = {})
    SETTINGS.merge(extra)
  end

  def test_load_selection_gives_settings_and_nothing_to_replace
    root = created_root([5.0, 7.0], [65.0, 7.0])
    @model.selection.replace([root])
    result = call('load_selection')['result']
    assert_equal 9.0, result['settings']['parcel']['depth_m']
    assert_equal 1, result['revision']
    assert_equal 5, result['metrics']['parcel_count']
    assert_equal false, result['changed']
  end

  def test_load_selection_refuses_anything_else
    @model.selection.replace([])
    assert_equal 'ensemble_selection_not_single', call('load_selection')['diagnostics'].first['params']['reason']
    assert_equal 'edit_not_loaded', call('edit_preview', 'settings' => SETTINGS)['diagnostics'].first['params']['reason']
  end

  def test_edit_preview_says_what_changed_without_writing
    root = created_root([5.0, 7.0], [65.0, 7.0])
    @model.selection.replace([root])
    call('load_selection')
    before = starts
    same = call('edit_preview', 'settings' => {})['result']
    assert_equal false, same['changed']
    changed = call('edit_preview', 'settings' => edit_settings('parcel' => { 'depth_m' => 12 }))['result']
    assert_equal true, changed['changed']
    assert_equal before, starts
  end

  def test_edit_preview_explains_a_refusal
    root = created_root([5.0, 7.0], [65.0, 7.0])
    @model.selection.replace([root])
    call('load_selection')
    result = call('edit_preview', 'settings' => edit_settings('parcel' => { 'depth_m' => 2 }))['result']
    assert result['refused']
    assert_equal '/parcel/depth_m', result['problems'].first['path']
  end

  def test_regenerate_replaces_and_keeps_the_trace
    root = created_root([5.0, 7.0], [65.0, 7.0])
    @model.selection.replace([root])
    call('load_selection')
    settings = edit_settings('parcel' => { 'depth_m' => 12 })
    digest = call('edit_preview', 'settings' => settings)['result']['ensemble_digest']
    old = root.definition
    response = call('regenerate', 'settings' => settings, 'ensemble_digest' => digest)
    assert response['ok'], response.inspect
    assert_equal 2, response['result']['revision']
    assert_equal false, response['result']['changed'], 'ce qui est écrit devient la référence'
    refute_same old, root.definition
    stored = JSON.parse(root.get_attribute('archgen.ensemble', 'ensemble_json'))
    assert_equal 12.0, stored['parcel']['depth_m']
    assert_equal [[0.0, 0.0], [60.0, 0.0]], stored['trace']['points_m']
  end

  def test_regenerate_refuses_what_was_not_shown
    root = created_root([5.0, 7.0], [65.0, 7.0])
    @model.selection.replace([root])
    call('load_selection')
    response = call('regenerate', 'settings' => edit_settings('parcel' => { 'depth_m' => 12 }), 'ensemble_digest' => 'a' * 64)
    assert_equal 'preview_changed', response['diagnostics'].first['params']['reason']
    assert_equal 1, root.get_attribute('archgen.ensemble', 'revision')
  end

  def test_regenerate_rechecks_the_selection
    root = created_root([5.0, 7.0], [65.0, 7.0])
    @model.selection.replace([root])
    call('load_selection')
    settings = edit_settings('parcel' => { 'depth_m' => 12 })
    digest = call('edit_preview', 'settings' => settings)['result']['ensemble_digest']
    @model.selection.replace([])
    response = call('regenerate', 'settings' => settings, 'ensemble_digest' => digest)
    assert_equal 'selection_changed', response['diagnostics'].first['params']['reason']
  end

  def test_street_width_is_only_kept_on_both_sides
    draw([0.0, 0.0], [60.0, 0.0])
    both = SETTINGS.merge('layout' => { 'side' => 'both', 'street_width_m' => 14 })
    digest = call('preview', 'settings' => both)['result']['ensemble_digest']
    assert create(digest, both)['ok']
    @model.selection.replace([@model.instances.first])
    call('load_selection')
    result = call('edit_preview', 'settings' => { 'layout' => { 'side' => 'left' } })['result']
    assert_equal 5, result['metrics']['parcel_count'], 'la largeur de rue enregistrée ne fait pas refuser'
  end

  def test_closed_settings_keep_their_access
    draw([0.0, 0.0], [40.0, 0.0], [40.0, 40.0], finish: false)
    @session.add([0.0, 40.0])
    @session.close
    settings = SETTINGS.merge('access' => { 'count' => 2 })
    digest = call('preview', 'settings' => settings)['result']['ensemble_digest']
    assert create(digest, settings)['ok']
    @model.selection.replace([@model.instances.first])
    loaded = call('load_selection')['result']
    assert_equal 2, loaded['settings']['access']['count']
    assert_equal 1, call('edit_preview', 'settings' => { 'access' => { 'count' => 1 } })['result']['metrics']['access_count']
  end

  # --- Rues variées (AG-063)

  VARIED = { 'levels' => { 'min' => 3, 'max' => 7 }, 'roofs' => %w[flat gable mansard] }.freeze

  def test_init_tells_each_style_its_roofs_and_levels
    profiles = call('init')['result']['profiles'].to_h { |p| [p['id'], p] }
    assert_equal %w[flat], profiles['brutalist']['roofs']
    assert_equal %w[mansard], profiles['haussmann']['roofs']
    assert_equal({ 'min' => 5, 'max' => 7 }, profiles['haussmann']['levels'])
    assert_equal %w[gable], profiles['toulousain']['roofs'], 'la croupe ne se propose pas en rangée'
    refute profiles['brutalist'].key?('levels')
  end

  def test_preview_announces_the_draw_and_a_new_seed_gives_another_street
    draw([0.0, 0.0], [72.0, 0.0])
    plain = preview['result']
    refute plain.key?('variety')
    assert_equal plain['ensemble_digest'], preview(SETTINGS.merge('variety' => nil))['result']['ensemble_digest'], 'case décochée : rien ne change'
    varied = preview(SETTINGS.merge('variety' => VARIED))['result']
    assert_equal 6, varied['variety']['levels'].values.sum
    assert_equal 6, varied['variety']['roofs'].values.sum
    other = preview(SETTINGS.merge('variety' => VARIED, 'seed' => 2))['result']
    refute_equal varied['ensemble_digest'], other['ensemble_digest']
  end

  def test_preview_explains_a_variety_refusal
    draw([0.0, 0.0], [72.0, 0.0])
    result = preview(SETTINGS.merge('variety' => { 'levels' => { 'min' => 6, 'max' => 3 } }))['result']
    assert result['refused']
    assert_equal '/variety/levels/min', result['problems'].first['path']
  end

  def test_edit_keeps_replaces_or_removes_the_variety
    draw([5.0, 7.0], [77.0, 7.0])
    varied = SETTINGS.merge('variety' => VARIED, 'seed' => 3)
    assert create(preview(varied)['result']['ensemble_digest'], varied)['ok']
    root = @model.instances.first
    @model.selection.replace([root])
    loaded = call('load_selection')['result']
    assert_equal VARIED['roofs'], loaded['settings']['variety']['roofs']
    assert_equal 3, loaded['settings']['seed']
    assert loaded['variety']
    kept = call('edit_preview', 'settings' => SETTINGS)['result']
    assert_equal false, kept['changed'], 'sans clé variety, la variété enregistrée reste'
    reseeded = call('edit_preview', 'settings' => SETTINGS.merge('seed' => 4))['result']
    assert_equal true, reseeded['changed']
    narrowed = SETTINGS.merge('variety' => { 'levels' => { 'min' => 4, 'max' => 4 }, 'roofs' => %w[gable] })
    result = call('edit_preview', 'settings' => narrowed)['result']
    assert_equal({ '4' => 6 }, result['variety']['levels'])
    assert_equal({ 'gable' => 6 }, result['variety']['roofs'], 'la liste remplace, elle ne fusionne pas')
    removed = SETTINGS.merge('variety' => nil)
    gone = call('edit_preview', 'settings' => removed)['result']
    refute gone.key?('variety')
    response = call('regenerate', 'settings' => removed, 'ensemble_digest' => gone['ensemble_digest'])
    assert response['ok'], response.inspect
    refute JSON.parse(root.get_attribute('archgen.ensemble', 'ensemble_json')).key?('variety')
  end

  # AG-064 : une rue fige la révision courante de son style ; une rue d'avant, sans révision, garde la 1.
  def test_a_street_keeps_the_revision_of_its_style
    root = created_root([5.0, 7.0], [65.0, 7.0])
    stored = -> { JSON.parse(root.get_attribute('archgen.ensemble', 'ensemble_json')).dig('building', 'profile') }
    assert_equal({ 'id' => 'brutalist', 'revision' => 2 }, stored.call)

    legacy = JSON.parse(root.get_attribute('archgen.ensemble', 'ensemble_json'))
    legacy['building']['profile'].delete('revision')
    root.set_attribute('archgen.ensemble', 'ensemble_json', JSON.generate(legacy))
    @model.selection.replace([root])
    loaded = call('load_selection')['result']
    assert_equal 1, loaded['settings'].dig('building', 'profile', 'revision')
    regenerate = lambda do |settings|
      digest = call('edit_preview', 'settings' => settings)['result']['ensemble_digest']
      response = call('regenerate', 'settings' => settings, 'ensemble_digest' => digest)
      assert response['ok'], response.inspect
      call('load_selection')
    end
    regenerate.call(SETTINGS.merge('seed' => 4))
    assert_equal({ 'id' => 'brutalist', 'revision' => 1 }, stored.call, 'même style : révision gardée')
    regenerate.call(Archgen::Core::Merge.leaves(SETTINGS, 'building' => { 'profile' => { 'id' => 'toulousain' } }))
    assert_equal({ 'id' => 'toulousain', 'revision' => 3 }, stored.call, 'autre style : sa révision courante')
  end

  def test_init_gives_the_details_each_style_ticks
    details = call('init')['result']['profiles'].to_h { |p| [p['id'], p['details']] }
    assert_equal({ 'revision' => 3, 'glazing' => true, 'chimneys' => false, 'muntins' => true, 'shutters' => false, 'dormers' => true, 'genoise' => false, 'stepped_gable' => false, 'cladding' => false, 'shop_height_m' => 4.5 },
                 details['haussmann'])
    assert_equal [true, false], details['toulousain'].values_at('shutters', 'dormers')
    assert_equal 4.0, details['toulousain']['shop_height_m']
  end

  def test_details_of_a_whole_street_are_kept_and_changed_on_edit
    root = created_root([5.0, 7.0], [65.0, 7.0])
    stored = -> { JSON.parse(root.get_attribute('archgen.ensemble', 'ensemble_json'))['building'] }
    @model.selection.replace([root])
    call('load_selection')
    regenerate = lambda do |settings|
      digest = call('edit_preview', 'settings' => settings)['result']['ensemble_digest']
      response = call('regenerate', 'settings' => settings, 'ensemble_digest' => digest)
      assert response['ok'], response.inspect
      call('load_selection')
    end
    regenerate.call(Archgen::Core::Merge.leaves(SETTINGS, 'building' => { 'ground_floor' => 'shop', 'features' => { 'chimneys' => true } }))
    assert_equal ['shop', true], [stored.call['ground_floor'], stored.call.dig('features', 'chimneys')]
    regenerate.call(SETTINGS.merge('seed' => 4))
    assert_equal 'shop', stored.call['ground_floor'], 'une case non envoyée garde la valeur de la rue'
    regenerate.call(Archgen::Core::Merge.leaves(SETTINGS, 'building' => { 'ground_floor' => 'dwelling' }))
    assert_equal 'dwelling', stored.call['ground_floor']
  end

  def test_changing_document_forgets_the_edit
    root = created_root([5.0, 7.0], [65.0, 7.0])
    @model.selection.replace([root])
    call('load_selection')
    @controller.document_changed
    assert_equal 'edit_not_loaded', call('edit_preview', 'settings' => {})['diagnostics'].first['params']['reason']
  end

  def test_mode_reaches_the_page
    assert_equal 'new', call('init')['result']['mode']
    @controller.mode = 'edit'
    assert_equal 'edit', call('init')['result']['mode']
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
