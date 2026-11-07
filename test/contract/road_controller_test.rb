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

  def test_init_gives_catalogues_presets_and_the_starting_profile
    r = call('init')
    assert r['ok']
    assert_equal 11, r['result']['presets'].size
    assert_equal 16, r['result']['bands'].size
    assert_equal 7, r['result']['items'].size
    assert_equal 'Rue de ville', r['result']['profile']['name']
    lane = r['result']['bands'].find { |b| b['type'] == 'lane' }
    assert_equal [2.5, 4.5, 'Voie de circulation'], lane.values_at('min_width_m', 'max_width_m', 'label')
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

  def test_the_editor_never_reaches_the_model
    source = read_utf8('archgen', 'ui', 'road_controller.rb') + read_utf8('archgen', 'ui', 'road_panel.rb')
    refute_match(/active_model|start_operation|entities|Sketchup\./, source)
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
    assert_equal %w[veh add-type], ids
    assert_empty ids - labels
  end
end
