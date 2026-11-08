# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'
require_relative '../support/road_net'

Archgen::Loader.load_adapter

# Contrat de l'écriture d'un réseau de voies (AG-048), avec doubles. La preuve native est H21.
class NetworkServiceTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp

  DICTIONARY = 'archgen.network'
  ORIGIN = [10.0, 20.0, 0.0].freeze
  Injected = Class.new(StandardError)

  def x(type = nil, **opts)
    roads = [RoadNet.road('a', [[0, 0], [100, 0]]), RoadNet.road('b', [[50, -50], [50, 50]])]
    junctions = type ? [{ 'id' => 'a@50.0+b@50.0', 'type' => type }.merge(opts.transform_keys(&:to_s))] : nil
    RoadNet.network(*roads, junctions: junctions)
  end

  def service(**ports)
    NetworkService.new(intake: Archgen::Composition.road_network_intake, bands: Archgen::Composition.road_bands,
                       items: Archgen::Composition.road_items, materials: Archgen::Composition.road_catalog,
                       material_revision: 1, host: FakeSketchUp::Host, **ports)
  end

  def setup
    @model = FakeSketchUp::ServiceModel.new
    @service = service
  end

  def create(tree = x)
    result = @service.create(model: @model, tree: tree, origin_m: ORIGIN)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def root
    @model.instances.find { |i| i.get_attribute(DICTIONARY, 'network_version') }
  end

  def target
    @model.selection.replace([root])
    @service.load_selection(model: @model).value.target
  end

  def snapshot
    [@model.definition_list.size, @model.instances.size, @model.materials.count, @model.layers.count]
  end

  def starts
    @model.operations.count { |op| op.first == :start }
  end

  class FailingWriter
    def initialize(real)
      @real = real
    end

    def write(*)
      raise Injected, 'panne'
    end

    def mark_definition(*args, **options)
      @real.mark_definition(*args, **options)
    end
  end

  def test_create_is_one_named_operation_and_one_root
    summary = create
    assert_equal 1, starts
    assert_equal 'ARCHGEN : créer un réseau de voies', @model.operations.find { |op| op.first == :start }[1]
    assert_equal 'Réseau ARCHGEN', root.name
    assert_equal 1, summary.revision
    assert_equal 1, summary.metrics['junction_count']
    assert_equal 'network', root.definition.get_attribute('archgen.definition', 'kind')
  end

  def test_each_junction_type_is_written_and_reread
    [nil, 'signals', 'roundabout'].each do |type|
      model = FakeSketchUp::ServiceModel.new
      written = @service.create(model: model, tree: x(type), origin_m: ORIGIN)
      assert written.ok?, written.errors.map(&:to_h).inspect
      instance = model.instances.first
      stored = instance.get_attribute(DICTIONARY, 'network_json')
      again = @service.preview(tree: stored)
      assert again.ok?, again.errors.map(&:to_h).inspect
      assert_equal written.value.road_digest, again.value.road_digest, type.inspect
    end
  end

  # AG-057 : un pont sur une rivière s'écrit en une opération, avec ses ouvrages et l'eau dans leurs
  # groupes, puis se relit à l'identique.
  def test_a_bridge_over_a_river_is_written_and_reread
    river = RoadNet.road('a', [[0, 0], [200, 0]], 'riviere')
    river['road']['water'] = { 'mode' => 'flat' }
    tree = RoadNet.network(river, RoadNet.road('b', [[100, -200], [100, 200]]))
    summary = create(tree)
    assert_equal 1, starts
    assert_equal 1, summary.metrics['bridge_count']
    names = root.definition.entities.to_a.select { |e| e.respond_to?(:name) }.map(&:name)
    assert_includes names, 'road/bridges'
    assert_includes names, 'road/water'
    again = @service.preview(tree: root.get_attribute(DICTIONARY, 'network_json'))
    assert_equal summary.road_digest, again.value.road_digest
  end

  def test_stored_settings_keep_the_network_frame
    create
    stored = JSON.parse(root.get_attribute(DICTIONARY, 'network_json'))
    assert_equal [[50.0, -50.0], [50.0, 50.0]], stored['roads'][1]['road']['trace']['points_m']
    assert_equal [[0.0, 0.0], [100.0, 0.0]], stored['roads'][0]['road']['trace']['points_m']
  end

  def test_refused_network_writes_nothing
    before = snapshot
    refused = @service.create(model: @model, tree: x('roundabout', outer_radius_m: 60), origin_m: ORIGIN)
    refute refused.ok?
    assert_equal before, snapshot
    assert_empty @model.operations
  end

  def test_a_write_failure_leaves_no_trace
    before = snapshot
    failing = service(writer: FailingWriter.new(GeometryWriter.new(host: FakeSketchUp::Host)))
    refute failing.create(model: @model, tree: x, origin_m: ORIGIN).ok?
    assert_equal before, snapshot
    assert_equal 0, @model.operations.count { |op| op.first == :commit }
  end

  def test_regenerate_changes_a_junction_type_in_one_operation
    create
    instance = root
    old = instance.definition
    result = @service.regenerate(model: @model, target: target, changes: { 'junctions' => [{ 'id' => 'a@50.0+b@50.0', 'type' => 'roundabout' }] })
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal 2, result.value.revision
    assert_same instance, root
    refute_same old, instance.definition
    assert_equal 'ARCHGEN : régénérer le réseau de voies', @model.operations.reverse.find { |op| op.first == :start }[1]
    stored = JSON.parse(instance.get_attribute(DICTIONARY, 'network_json'))
    assert_equal 'roundabout', stored['junctions'].first['type']
  end

  def test_refused_regeneration_and_stale_target_change_nothing
    create
    t = target
    attrs = root.attrs.dup
    operations = starts
    bad = { 'junctions' => [{ 'id' => 'a@50.0+b@50.0', 'type' => 'roundabout', 'outer_radius_m' => 60 }] }
    refute @service.regenerate(model: @model, target: t, changes: bad).ok?
    @model.selection.replace([])
    refute @service.regenerate(model: @model, target: t, changes: {}).ok?
    assert_equal operations, starts
    assert_equal attrs, root.attrs
  end

  def test_a_road_root_is_not_a_network
    road = RoadService.new(intake: Archgen::Composition.road_intake, bands: Archgen::Composition.road_bands, items: Archgen::Composition.road_items,
                           materials: Archgen::Composition.road_catalog, material_revision: 1, host: FakeSketchUp::Host)
    single = RoadNet.road('a', [[0, 0], [100, 0]])['road']
    assert road.create(model: @model, tree: single, origin_m: ORIGIN).ok?
    @model.selection.replace([@model.instances.first])
    refused = @service.load_selection(model: @model)
    assert_equal 'not_a_network_root', refused.errors.first.params['reason']
  end
end
