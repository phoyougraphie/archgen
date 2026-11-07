# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter
require File.expand_path('../../archgen/ui/messages', __dir__)
require File.expand_path('../../archgen/ui/network_controller', __dir__)

# Contrat du panneau de réseau (AG-048) : tracer des voies une à une, régler les carrefours nés tout
# seuls, créer puis modifier en une opération chacune, avec l'empreinte montrée.
class NetworkControllerTest < Minitest::Test
  include Archgen::Adapters::SketchUp

  def setup
    @model = FakeSketchUp::ServiceModel.new
    @session = Archgen::Core::TraceSession.new
    @controller = Archgen::UI::NetworkController.new(
      presets: Archgen::Composition.road_presets, catalog: Archgen::Composition.road_catalog,
      service: NetworkService.new(intake: Archgen::Composition.road_network_intake, bands: Archgen::Composition.road_bands,
                                  items: Archgen::Composition.road_items, materials: Archgen::Composition.road_catalog,
                                  material_revision: 1, host: FakeSketchUp::Host),
      session: @session, model_provider: -> { @model }
    )
    @counter = 0
  end

  def call(action, payload = {}, id = nil)
    @counter += 1
    @controller.dispatch(JSON.generate('v' => 1, 'request_id' => id || "r#{@counter}", 'action' => action, 'payload' => payload))
  end

  def draw(*points)
    @session.start(points[0][0], points[0][1], 1.0)
    points.drop(1).each { |p| @session.add(p) }
    @session.finish
  end

  # Deux voies qui se croisent, tracées en coordonnées du modèle (origine du réseau en 10, 20).
  def cross
    draw([10, 20], [110, 20])
    call('add_road', 'preset' => 'ville')
    draw([60, -30], [60, 70])
    call('add_road', 'preset' => 'boulevard')
  end

  def roots
    @model.instances.select { |i| i.get_attribute('archgen.network', 'network_version') }
  end

  def test_two_traced_roads_give_one_junction_and_a_plan_view
    cross
    r = call('preview')
    network = r['result']['network']
    assert network['ok'], network['diagnostics'].inspect
    assert_equal ['v1@50.0+v2@50.0'], network['junctions'].map { |j| j['id'] }
    assert_equal 2, network['metrics']['road_count']
    refute_empty network['plan']['faces']
    assert_equal %w[v1 v2], r['result']['state']['roads'].map { |x| x['id'] }
    assert_equal 2, @controller.overlay[:rings].size
    assert_empty @model.operations
  end

  def test_a_road_needs_a_finished_trace_and_a_known_preset
    refute call('add_road', 'preset' => 'ville')['ok']
    draw([0, 0], [50, 0])
    assert_equal 'enum', call('add_road', 'preset' => 'inconnu')['diagnostics'].first['params']['reason']
  end

  def test_junction_types_are_set_and_cleared
    cross
    r = call('set_junction', 'junction' => { 'id' => 'v1@50.0+v2@50.0', 'type' => 'roundabout', 'outer_radius_m' => 25 })
    assert_equal 'roundabout', r['result']['network']['junctions'].first['type']
    r = call('set_junction', 'junction' => { 'id' => 'v1@50.0+v2@50.0', 'type' => 'simple' })
    assert_empty r['result']['state']['junctions']
    assert_equal 'simple', r['result']['network']['junctions'].first['type']
  end

  def test_create_needs_the_shown_digest_and_is_one_operation
    cross
    digest = call('preview')['result']['network']['road_digest']
    stale = call('create', 'road_digest' => 'faux')
    assert_equal 'confirmation_mismatch', stale['diagnostics'].first['params']['reason']
    assert_empty roots
    r = call('create', { 'road_digest' => digest }, 'c1')
    assert r['ok'], r['diagnostics'].inspect
    assert_equal 1, roots.size
    assert_equal 1, @model.operations.count { |op| op.first == :start }
    assert_equal r, call('create', { 'road_digest' => digest }, 'c1'), 'requête rejouée : même réponse, aucune écriture'
    assert_equal 1, roots.size
    matrix = roots.first.transform.to_a
    assert_in_delta 10.0, matrix[12] * 0.0254, 1e-9
    assert_in_delta 20.0, matrix[13] * 0.0254, 1e-9
    assert_empty r['result']['state']['roads']
  end

  def test_edit_changes_a_junction_and_keeps_the_root
    cross
    call('create', 'road_digest' => call('preview')['result']['network']['road_digest'])
    root = roots.first
    @controller.mode = 'edit'
    loaded = call('load_selection')
    assert loaded['ok'], loaded['diagnostics'].inspect
    assert_equal 1, loaded['result']['revision']
    r = call('set_junction', 'junction' => { 'id' => 'v1@50.0+v2@50.0', 'type' => 'signals' })
    assert r['result']['network']['ok'], r['result']['network']['diagnostics'].inspect
    written = call('regenerate', 'road_digest' => r['result']['network']['road_digest'])
    assert written['ok'], written['diagnostics'].inspect
    assert_equal 2, written['result']['revision']
    assert_same root, roots.first
    assert_equal 'ARCHGEN : régénérer le réseau de voies', @model.operations.reverse.find { |op| op.first == :start }[1]
    assert_equal 'first_road_kept', call('remove_road', 'id' => 'v1')['diagnostics'].first['params']['reason']
    assert_equal 'add_road_in_edit', call('add_road', 'preset' => 'ville')['diagnostics'].first['params']['reason']
  end

  def test_removing_a_road_drops_its_junction_settings
    cross
    call('set_junction', 'junction' => { 'id' => 'v1@50.0+v2@50.0', 'type' => 'signals' })
    r = call('remove_road', 'id' => 'v2')
    assert_empty r['result']['state']['junctions']
    assert_equal ['v1'], r['result']['state']['roads'].map { |x| x['id'] }
  end

  def test_every_reason_has_a_message
    %w[add_road_in_edit too_many_roads unknown_road first_road_kept no_road not_a_network_root].each do |reason|
      assert Archgen::UI::Messages::REASONS.key?(reason), reason
    end
  end
end
