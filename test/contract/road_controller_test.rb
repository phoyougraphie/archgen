# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter

# Pont de l'éditeur de coupe (AG-038) : Ruby juge et dessine, le panneau compose. Aucun accès au modèle.
class RoadControllerTest < Minitest::Test
  def setup
    @controller = Archgen::UI::RoadController.new(
      intake: Archgen::Composition.road_profile_intake, bands: Archgen::Composition.road_bands,
      items: Archgen::Composition.road_items, presets: Archgen::Composition.road_presets
    )
    @counter = 0
  end

  def call(action, payload = {})
    @counter += 1
    @controller.dispatch(JSON.generate('v' => 1, 'request_id' => "r#{@counter}", 'action' => action, 'payload' => payload))
  end

  # AG-147 : chaque préréglage livré a une famille, une seule ; aucun ne tombe dans « Autres ».
  def test_every_preset_has_exactly_one_family
    r = call('init')
    families = r['result']['families']
    ids = r['result']['presets'].map { |p| p['id'] }
    assert_equal ids.sort, families.flat_map { |f| f['ids'] }.sort
    refute_includes families.map { |f| f['label'] }, Archgen::UI::RoadFamilies::OTHER
    assert_equal ['Ville', 'Route et campagne', 'Rail et tram', 'Piétons et vélos', 'Eau', 'Côte'], families.map { |f| f['label'] }
    assert_equal %w[ville boulevard mixte arret-bus], families.first['ids']
  end

  def test_an_unknown_preset_falls_into_others
    groups = Archgen::UI::RoadFamilies.group(%w[ville inconnu])
    assert_equal [['Ville', %w[ville]], ['Autres', %w[inconnu]]], groups.map { |g| g.values_at('label', 'ids') }
  end

  def test_init_gives_catalogues_presets_and_the_starting_profile
    r = call('init')
    assert r['ok']
    assert_equal 18, r['result']['presets'].size
    assert_equal 24, r['result']['bands'].size
    assert_equal 15, r['result']['items'].size
    assert_equal 'Rue de ville', r['result']['profile']['name']
    lane = r['result']['bands'].find { |b| b['type'] == 'lane' }
    assert_equal [2.5, 4.5, 'Voie de circulation'], lane.values_at('min_width_m', 'max_width_m', 'label')
    water = r['result']['bands'].find { |b| b['type'] == 'water' }
    assert_equal({ 'min' => 0.3, 'max' => 5, 'default' => 1 }, water['settings']['freeboard_m'])
    assert_equal({}, lane['settings'])
    tree = r['result']['items'].find { |i| i['kind'] == 'tree' }
    assert_equal 'Feuillu rond', tree['variants'].first['label']
    assert JSON.generate(r)
  end

  def test_preview_returns_the_effective_profile_and_its_section
    r = call('preview', 'profile' => { 'bands' => [{ 'type' => 'sidewalk', 'width_m' => 3, 'items' => [{ 'kind' => 'tree' }] }, { 'type' => 'lane', 'width_m' => 3.5 }] })
    assert r['ok'], r.inspect
    assert_equal 9.0, r['result']['profile']['bands'][0]['items'][0]['spacing_m']
    assert_in_delta 6.5, r['result']['section']['width_m'], 1e-9
    assert_equal 'W_ROAD_CLEARANCE', r['diagnostics'].first['code']
    assert_match(/bande 2/, r['diagnostics'].first['message'])
  end

  def test_a_refused_profile_has_messages_and_keeps_the_last_accepted_one
    call('preview', 'profile' => { 'name' => 'Ma rue', 'bands' => [{ 'type' => 'lane', 'width_m' => 3 }] })
    r = call('preview', 'profile' => { 'bands' => [{ 'type' => 'lane', 'width_m' => 9 }] })
    refute r['ok']
    assert_nil r['result']
    d = r['diagnostics'].first
    assert_equal ['E_ROAD_BAND', '/bands/0/width_m'], d.values_at('code', 'path')
    assert_equal 'Cette bande mesure 9 m : choisissez une largeur de 2,5 à 4,5 m.', d['message']
    assert_equal 'Ma rue', call('init')['result']['profile']['name']
  end

  def test_envelope_is_checked_before_anything
    assert_equal 'unknown_action', JSON.parse(JSON.generate(call('write')))['diagnostics'][0]['params']['reason']
    assert_equal 'invalid_envelope', call('preview', 'profile' => [])['diagnostics'][0]['params']['reason']
    assert_equal 'invalid_envelope', call('preview', 'profile' => {}, 'extra' => 1)['diagnostics'][0]['params']['reason']
    bad = @controller.dispatch(JSON.generate('v' => 2, 'request_id' => 'x', 'action' => 'init', 'payload' => {}))
    assert_equal 'unsupported_protocol', bad['diagnostics'][0]['params']['reason']
    garbage = @controller.dispatch('{"v":1,"v":1}')
    refute garbage['ok']
    long = @controller.dispatch(JSON.generate('v' => 1, 'request_id' => 'x' * 65, 'action' => 'init', 'payload' => {}))
    assert_nil long['request_id']
  end

  # Seul le service écrit, dans une opération : le contrôleur et le panneau ne touchent jamais à la géométrie.
  def test_the_panel_never_writes_the_model_itself
    source = read_utf8('archgen', 'ui', 'road_controller.rb') + read_utf8('archgen', 'ui', 'road_panel.rb')
    refute_match(/start_operation|commit_operation|\.entities|add_instance|add_group|set_attribute|erase/, source)
  end

  # Défaut vu en H19 : le panneau reçoit une chaîne JSON, il doit la décoder.
  def test_the_page_decodes_the_string_sent_by_ruby
    assert_includes read_utf8('archgen', 'ui', 'road_panel.rb'), 'archgenRoadReceive(#{literal(JSON.generate('
    assert_match(/window\.archgenRoadReceive = function \(json\) \{\n\s+var response = JSON\.parse\(json\);/, read_utf8('archgen', 'ui', 'road_panel.js'))
  end

  def test_static_page_fields_are_labelled
    html = read_utf8('archgen', 'ui', 'road_panel.html')
    ids = html.scan(/<(?:input|select)[^>]*\bid="([^"]+)"/).flatten
    labels = html.scan(/<label for="([^"]+)"/).flatten
    assert_equal %w[veh r-radius r-axis r-ground r-water r-grade r-drop r-chamber r-level add-type], ids
    assert_empty ids - labels
  end
end

# Parcours du panneau de voirie avec le vrai service sur doubles (AG-042) : tracer, aperçu, créer,
# recharger, remplacer. La preuve native est H20.
class RoadControllerFlowTest < Minitest::Test
  include Archgen::Adapters::SketchUp

  def setup
    @model = FakeSketchUp::ServiceModel.new
    service = RoadService.new(intake: Archgen::Composition.road_intake, bands: Archgen::Composition.road_bands, items: Archgen::Composition.road_items,
                              materials: Archgen::Composition.road_catalog, material_revision: 1, host: FakeSketchUp::Host)
    @session = Archgen::Core::TraceSession.new
    @controller = Archgen::UI::RoadController.new(
      intake: Archgen::Composition.road_profile_intake, bands: Archgen::Composition.road_bands, items: Archgen::Composition.road_items,
      presets: Archgen::Composition.road_presets, service: service, session: @session, model_provider: -> { @model }
    )
    @counter = 0
  end

  def call(action, payload = {}, id = nil)
    @counter += 1
    @controller.dispatch(JSON.generate('v' => 1, 'request_id' => id || "r#{@counter}", 'action' => action, 'payload' => payload))
  end

  def profile
    Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == 'ville' }.fetch('profile')
  end

  def draw(*points)
    @session.start(points[0][0], points[0][1], 2.0)
    points.drop(1).each { |p| @session.add(p) }
    @session.finish
  end

  def preview(road = { 'radius_m' => 20, 'axis' => 'center' })
    call('preview', 'profile' => profile, 'road' => road)
  end

  def roots
    @model.instances.select { |i| i.get_attribute('archgen.road', 'road_version') }
  end

  def test_no_trace_no_road_and_nothing_written
    r = preview
    assert r['ok']
    assert_nil r['result']['road']
    assert_empty @model.operations
  end

  def test_a_finished_trace_gives_a_road_preview_and_an_outline
    draw([10, 20], [90, 20], [90, 80])
    r = preview
    road = r['result']['road']
    assert road['ok'], road.inspect
    assert_match(/\A\h{64}\z/, road['road_digest'])
    assert_operator road['metrics']['length_m'], :>, 100
    ring = @controller.overlay[:rings].first
    assert_in_delta 10.0, ring.first[0], 1e-6
    assert_in_delta 26.5, ring.first[1], 1e-6
    assert_empty @model.operations
  end

  def test_a_refused_road_does_not_refuse_the_section
    draw([0, 0], [80, 0], [80, 60])
    r = preview('radius_m' => 1, 'axis' => 'center')
    assert r['ok']
    road = r['result']['road']
    refute road['ok']
    assert_equal ['radius_too_small'], road['diagnostics'].map { |d| d['params']['reason'] }
    assert @controller.overlay[:refused]
  end

  def test_create_needs_the_shown_digest_then_writes_once
    draw([10, 20], [90, 20], [90, 80])
    digest = preview['result']['road']['road_digest']
    stale = call('create', 'profile' => profile, 'road' => { 'radius_m' => 25, 'axis' => 'center' }, 'road_digest' => digest)
    assert_equal 'confirmation_mismatch', stale['diagnostics'][0]['params']['reason']
    assert_empty roots
    created = call('create', { 'profile' => profile, 'road' => { 'radius_m' => 20, 'axis' => 'center' }, 'road_digest' => digest }, 'c1')
    assert created['ok'], created.inspect
    again = call('create', { 'profile' => profile, 'road' => { 'radius_m' => 20, 'axis' => 'center' }, 'road_digest' => digest }, 'c1')
    assert_equal created, again, 'un double clic ne crée pas deux voies'
    assert_equal 1, roots.size
    assert_equal 1, @model.operations.count { |op| op.first == :commit }
    assert_in_delta 10.0, roots.first.transform.to_a[12] * 0.0254, 1e-9
    assert_equal [roots.first], @model.selection.to_a
    assert @session.empty?, 'le tracé est oublié après création'
  end

  def test_create_without_a_finished_trace_is_refused
    r = call('create', 'profile' => profile, 'road' => {}, 'road_digest' => 'x' * 64)
    assert_equal 'trace_unfinished', r['diagnostics'][0]['params']['reason']
  end

  def test_edit_reloads_keeps_the_trace_and_replaces_in_one_operation
    draw([0, 0], [80, 0], [80, 60])
    digest = preview['result']['road']['road_digest']
    assert call('create', 'profile' => profile, 'road' => { 'radius_m' => 20, 'axis' => 'center' }, 'road_digest' => digest)['ok']
    @controller.mode = 'edit'
    loaded = call('load_selection')
    assert loaded['ok'], loaded.inspect
    assert_equal [20.0, 'center', 3, 1], loaded['result'].values_at('radius_m', 'axis', 'vertex_count', 'revision')
    mixte = Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == 'mixte' }.fetch('profile')
    shown = call('preview', 'profile' => mixte, 'road' => { 'axis' => 'center' })['result']['road']
    assert shown['ok'], shown.inspect
    done = call('regenerate', 'profile' => mixte, 'road' => { 'axis' => 'center' }, 'road_digest' => shown['road_digest'])
    assert done['ok'], done.inspect
    assert_equal 2, done['result']['revision']
    assert_equal 1, roots.size
    stored = JSON.parse(roots.first.get_attribute('archgen.road', 'road_json'))
    assert_equal 'Rue tram et voitures', stored.dig('profile', 'name')
    assert_equal [20.0], stored.dig('trace', 'radii_m')
  end

  # AG-056 : le régime de l'eau voyage avec la voie ; refus de la voie, pas de la coupe ; il est rechargé
  # et peut être ôté en modification avec la dernière bande d'eau.
  def test_a_canal_is_previewed_created_reloaded_and_turned_into_a_street
    canal = Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == 'canal' }.fetch('profile')
    draw([0, 0], [120, 0])
    missing = call('preview', 'profile' => canal, 'road' => { 'axis' => 'center' })
    assert missing['ok']
    refute missing['result']['road']['ok']
    assert_equal 'water_mode_missing', missing['result']['road']['diagnostics'].first['params']['reason']
    road = { 'axis' => 'center', 'water' => { 'mode' => 'canal', 'lock_drop_m' => 2.5 } }
    shown = call('preview', 'profile' => canal, 'road' => road)['result']['road']
    assert shown['ok'], shown.inspect
    assert_equal [], shown['locks']
    assert_match(/\A\h{64}\z/, shown['road_digest'])
    assert call('create', 'profile' => canal, 'road' => road, 'road_digest' => shown['road_digest'])['ok']
    @controller.mode = 'edit'
    loaded = call('load_selection')['result']
    assert_equal({ 'mode' => 'canal', 'max_grade_percent' => 3.0, 'lock_drop_m' => 2.5, 'lock_length_m' => 40.0 }, loaded['water'])
    street = call('preview', 'profile' => profile, 'road' => { 'axis' => 'center' })['result']['road']
    assert street['ok'], street.inspect
    done = call('regenerate', 'profile' => profile, 'road' => { 'axis' => 'center' }, 'road_digest' => street['road_digest'])
    assert done['ok'], done.inspect
    stored = JSON.parse(roots.first.get_attribute('archgen.road', 'road_json'))
    refute stored.key?('water')
  end

  def test_a_water_setting_that_is_not_an_object_refuses_the_road_not_the_section
    draw([0, 0], [120, 0])
    bad = call('preview', 'profile' => profile, 'road' => { 'axis' => 'center', 'water' => 'canal' })
    assert bad['ok']
    refute bad['result']['road']['ok']
    assert_equal ['E_SCHEMA', '/road/water'], bad['result']['road']['diagnostics'].first.values_at('code', 'path')
  end
end
