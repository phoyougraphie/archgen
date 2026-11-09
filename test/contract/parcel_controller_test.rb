# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter

# AG-069 : panneau de parcelle, « Personnaliser ce bâtiment ».
class ParcelControllerTest < Minitest::Test
  include Archgen::Adapters::SketchUp

  TREE = { 'seed' => 3, 'trace' => { 'points_m' => [[0, 0], [60, 0]], 'closed' => false },
           'building' => { 'profile' => { 'id' => 'toulousain' }, 'lod' => 0 } }.freeze

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def setup
    @model = FakeSketchUp::ServiceModel.new
    @service = EnsembleService.new(registry: registry, intake: Archgen::Composition.intake, ensemble_intake: Archgen::Composition.ensemble_intake,
                                   materials: Archgen::Composition.materials.fetch('materials'), material_revision: 1, host: FakeSketchUp::Host)
    created = @service.create(model: @model, tree: TREE, origin_m: [0.0, 0.0, 0.0])
    assert created.ok?, created.errors.map(&:to_h).inspect
    @root = @model.instances.first
    @model.selection.replace([@root])
    @controller = Archgen::UI::ParcelController.new(service: @service, registry: registry, intake: Archgen::Composition.intake, model_provider: -> { @model })
    @counter = 0
  end

  def call(action, payload = {}, id = nil)
    @counter += 1
    @controller.dispatch(JSON.generate('v' => 1, 'request_id' => id || "p#{@counter}", 'action' => action, 'payload' => payload))
  end

  def stored
    JSON.parse(@root.get_attribute('archgen.ensemble', 'ensemble_json'))
  end

  def parcel_ids
    Archgen::Core::EnsembleEngine.call(@service.preview(tree: TREE).value.settings, registry: registry, intake: Archgen::Composition.intake)
                                  .value['parcels'].map { |p| p['id'] }
  end

  def apply(own, id = nil)
    digest = call('preview', 'own' => own)['result']['ensemble_digest']
    call('apply', { 'own' => own, 'ensemble_digest' => digest }, id)
  end

  def test_init_gives_the_street_values_and_no_own_setting
    assert @controller.load(parcel_ids[1]).ok?
    result = call('init')['result']
    assert_equal parcel_ids[1], result['parcel_id']
    assert_equal({}, result['own'])
    assert_equal 0, result['custom_count']
    street = result['street']
    assert_equal %w[chimneys corner glazing ground_floor levels roof shop_height_m width_m], street.keys.sort
    assert_equal 'dwelling', street['ground_floor']
    assert_equal 4.0, street['shop_height_m']
  end

  def test_apply_writes_once_with_its_name_and_keeps_the_trace
    id = parcel_ids[1]
    @controller.load(id)
    before = @model.operations.count { |op| op.first == :start }
    response = apply({ 'levels' => 7, 'ground_floor' => 'shop', 'shop_height_m' => 4.5 })
    assert response['ok'], response.inspect
    starts = @model.operations.select { |op| op.first == :start }
    assert_equal before + 1, starts.size
    assert_equal 'ARCHGEN : personnaliser un bâtiment', starts.last[1]
    assert_equal({ 'levels' => 7, 'ground_floor' => 'shop', 'shop' => { 'height_m' => 4.5 } }, stored['parcels'][id])
    assert_equal TREE['trace'], stored['trace'].slice('points_m', 'closed').transform_values { |v| v.is_a?(Array) ? v.map { |p| p.map(&:to_i) } : v }
    assert_equal({ 'levels' => 7, 'ground_floor' => 'shop', 'shop_height_m' => 4.5 }, response['result']['own'])
    assert_equal 1, response['result']['custom_count']
  end

  def test_replayed_apply_writes_once
    @controller.load(parcel_ids[0])
    digest = call('preview', 'own' => { 'levels' => 5 })['result']['ensemble_digest']
    first = call('apply', { 'own' => { 'levels' => 5 }, 'ensemble_digest' => digest }, 'same')
    second = call('apply', { 'own' => { 'levels' => 5 }, 'ensemble_digest' => digest }, 'same')
    assert_equal first, second
    assert_equal 2, @model.operations.count { |op| op.first == :start }, 'création et une seule personnalisation'
  end

  def test_back_to_the_street_removes_the_entry_then_the_key
    id = parcel_ids[2]
    @controller.load(id)
    assert apply({ 'levels' => 6, 'roof' => 'flat' })['ok']
    assert apply({ 'levels' => 6 })['ok']
    assert_equal({ 'levels' => 6 }, stored['parcels'][id])
    assert apply({})['ok']
    refute stored.key?('parcels'), 'plus aucun réglage propre : la clé disparaît'
  end

  def test_refused_setting_writes_nothing
    id = parcel_ids[1]
    @controller.load(id)
    preview = call('preview', 'own' => { 'width_m' => 59 })
    assert preview['result']['refused']
    assert(preview['result']['problems'].any? { |p| p['params']['reason'] == 'neighbour_too_narrow' })
    count = @model.operations.size
    refused = call('apply', 'own' => { 'width_m' => 59 }, 'ensemble_digest' => 'x')
    refute refused['ok']
    assert_equal count, @model.operations.size
    refute stored.key?('parcels')
  end

  def test_stale_preview_is_refused
    @controller.load(parcel_ids[0])
    refute call('apply', 'own' => { 'levels' => 4 }, 'ensemble_digest' => 'old')['ok']
  end

  def test_unloaded_and_bad_requests_are_refused
    refute call('init')['ok']
    @controller.load(parcel_ids[0])
    assert_equal 'invalid_envelope', call('preview', 'own' => { 'colour' => 'red' })['diagnostics'].first['params']['reason']
    assert_equal 'unknown_action', call('erase')['diagnostics'].first['params']['reason']
  end
end
