# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter

# Contrat de l'écriture d'une voie (AG-042), avec doubles. La preuve native est H20.
class RoadServiceTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp

  DICTIONARY = 'archgen.road'
  Injected = Class.new(StandardError)
  ORIGIN = [10.0, 20.0, 3.0].freeze

  def preset(id)
    Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def tree(profile = preset('ville'), points: [[0, 0], [80, 0], [80, 60]], radii: [20])
    { 'trace' => { 'points_m' => points, 'radii_m' => radii }, 'profile' => profile }
  end

  def service(**ports)
    RoadService.new(intake: Archgen::Composition.road_intake, bands: Archgen::Composition.road_bands, items: Archgen::Composition.road_items,
                    materials: Archgen::Composition.road_catalog, material_revision: 1, host: FakeSketchUp::Host, **ports)
  end

  def setup
    @model = FakeSketchUp::ServiceModel.new
    @service = service
  end

  def create(input = tree, origin = ORIGIN)
    result = @service.create(model: @model, tree: input, origin_m: origin)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def root
    @model.instances.find { |i| i.get_attribute(DICTIONARY, 'road_version') }
  end

  def select(*entities)
    @model.selection.replace(entities)
  end

  def snapshot
    [@model.definition_list.size, @model.instances.size, @model.materials.count, @model.layers.count]
  end

  def starts
    @model.operations.count { |op| op.first == :start }
  end

  def assert_refused(result, code, reason = nil)
    refute result.ok?, 'attendu un refus'
    found = result.errors.find { |d| d.code == code }
    assert found, result.errors.map(&:to_h).inspect
    assert_equal reason, found.params['reason'] if reason
    found
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

  # --- Création

  def test_create_is_one_named_operation_and_one_root
    summary = create
    assert_equal 1, starts
    assert_equal 1, @model.operations.count { |op| op.first == :commit }
    assert_equal 'ARCHGEN : créer une voie', @model.operations.find { |op| op.first == :start }[1]
    assert_equal 1, @model.instances.size
    assert_equal 'Voie ARCHGEN', root.name
    assert_equal summary.persistent_id, root.persistent_id
    assert_equal 1, summary.revision
  end

  def test_root_is_placed_at_the_first_point_in_inches
    create
    matrix = root.transform.to_a
    ORIGIN.each_with_index { |c, i| assert_in_delta c, matrix[12 + i] * 0.0254, 1e-9 }
  end

  def test_metadata_is_complete_and_reproduces_the_digest
    summary = create
    meta = RoadRepository::KEYS.to_h { |k| [k, root.get_attribute(DICTIONARY, k)] }
    assert(meta.values.none?(&:nil?), meta.inspect)
    assert_equal summary.road_digest, meta['road_digest']
    assert_equal summary.road_digest, @service.preview(tree: meta['road_json']).value.road_digest
  end

  def test_each_family_is_written_under_its_tag
    create(tree(preset('boulevard'), points: [[0, 0], [120, 0]], radii: []))
    groups = root.definition.entities.to_a.select { |e| e.respond_to?(:layer) && e.respond_to?(:name) }
    by_name = groups.to_h { |g| [g.name, g.layer&.name] }
    assert_equal 'ARCHGEN Voirie chaussée et trottoirs', by_name['road/surface']
    assert_equal 'ARCHGEN Voirie végétation', by_name['road/vegetation']
    assert_equal 'ARCHGEN Voirie éclairage', by_name['road/lighting']
  end

  def test_every_material_of_every_preset_is_in_the_catalog
    catalog = Archgen::Composition.road_catalog
    Archgen::Composition.road_presets.fetch('presets').each do |p|
      plan = @service.preview(tree: tree(p['profile'], points: [[0, 0], [60, 0], [60, 60]], radii: [40])).value.plan
      used = []
      walk = lambda do |node|
        node['primitive']['faces'].each { |f| used << f['material'] } if node['primitive'] && node['primitive']['faces']
        node['children'].each { |c| walk.call(c) }
      end
      plan['nodes'].each { |n| walk.call(n) }
      plan['definitions'].each_value { |nodes| nodes.each { |n| walk.call(n) } }
      assert_empty used.uniq - catalog.keys, p['id']
    end
  end

  def test_preview_touches_nothing
    before = snapshot
    assert @service.preview(tree: tree).ok?
    assert_equal before, snapshot
    assert_empty @model.operations
  end

  def test_refused_road_writes_nothing
    before = snapshot
    assert_refused @service.create(model: @model, tree: tree(radii: [1]), origin_m: ORIGIN), 'E_ROAD_TRACE', 'radius_too_small'
    assert_equal before, snapshot
    assert_empty @model.operations
  end

  def test_bad_origin_and_nested_context_are_refused
    assert_refused @service.create(model: @model, tree: tree, origin_m: [0, 0]), 'E_SCHEMA', 'invalid_origin'
    @model.active_path = [:groupe]
    assert_refused @service.create(model: @model, tree: tree, origin_m: ORIGIN), 'E_TARGET_STALE', 'nested_edit_context'
    assert_empty @model.operations
  end

  def test_a_write_failure_leaves_no_trace
    before = snapshot
    result = service(writer: FailingWriter.new(GeometryWriter.new(host: FakeSketchUp::Host))).create(model: @model, tree: tree, origin_m: ORIGIN)
    assert_refused result, 'E_WRITE', 'write_failed'
    assert_equal before, snapshot
    assert_equal 1, @model.operations.count { |op| op.first == :abort }
    assert_equal 0, @model.operations.count { |op| op.first == :commit }
  end

  # --- Régénération

  def target_after
    select(root)
    @service.load_selection(model: @model).value.target
  end

  def test_regenerate_changes_the_section_and_keeps_root_and_trace
    create
    instance = root
    matrix = instance.transformation.to_a
    old = instance.definition
    result = @service.regenerate(model: @model, target: target_after, changes: { 'profile' => preset('mixte') })
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal 2, result.value.revision
    assert_same instance, root
    assert_equal matrix, instance.transformation.to_a
    refute_same old, instance.definition
    stored = JSON.parse(instance.get_attribute(DICTIONARY, 'road_json'))
    assert_equal 'Rue tram et voitures', stored.dig('profile', 'name')
    assert_equal [[0.0, 0.0], [80.0, 0.0], [80.0, 60.0]], stored.dig('trace', 'points_m')
    assert_equal 'ARCHGEN : régénérer la voie', @model.operations.reverse.find { |op| op.first == :start }[1]
  end

  def test_regenerate_can_change_radii_and_axis
    create
    result = @service.regenerate(model: @model, target: target_after, changes: { 'trace' => { 'radii_m' => [40] }, 'axis' => 'left' })
    assert result.ok?, result.errors.map(&:to_h).inspect
    stored = JSON.parse(root.get_attribute(DICTIONARY, 'road_json'))
    assert_equal [[40.0], 'left'], [stored.dig('trace', 'radii_m'), stored['axis']]
  end

  def test_a_copy_keeps_its_own_definition
    create
    original = root
    copy = @model.copy_instance(original)
    old_definition = copy.definition
    count = old_definition.entities.count { true }
    select(original)
    target = @service.load_selection(model: @model).value.target
    assert @service.regenerate(model: @model, target: target, changes: { 'profile' => preset('mixte') }).ok?
    assert_same old_definition, copy.definition
    assert_equal count, old_definition.entities.count { true }
    refute_same old_definition, original.definition
  end

  def test_refused_or_failed_regeneration_changes_nothing
    create
    before = root.definition
    attrs = root.attrs.dup
    operations = starts
    assert_refused @service.regenerate(model: @model, target: target_after, changes: { 'trace' => { 'radii_m' => [1] } }), 'E_ROAD_TRACE'
    assert_equal operations, starts
    failing = service(writer: FailingWriter.new(GeometryWriter.new(host: FakeSketchUp::Host)))
    assert_refused failing.regenerate(model: @model, target: target_after, changes: { 'profile' => preset('mixte') }), 'E_WRITE', 'write_failed'
    assert_same before, root.definition
    assert_equal attrs, root.attrs
  end

  def test_regenerate_rechecks_the_target
    create
    target = target_after
    select
    assert_refused @service.regenerate(model: @model, target: target), 'E_TARGET_STALE', 'selection_changed'
    assert_refused @service.regenerate(model: @model, target: :faux), 'E_TARGET_STALE', 'invalid_target'
    select(root)
    other = target.dup
    other.revision = 9
    assert_refused @service.regenerate(model: @model, target: other), 'E_TARGET_STALE', 'revision_changed'
    root.locked = true
    assert_refused @service.regenerate(model: @model, target: target), 'E_TARGET_STALE', 'target_locked'
  end

  def test_future_versions_are_readable_but_not_writable
    create
    target = target_after
    root.set_attribute(DICTIONARY, 'road_engine_version', (Archgen::ROAD_ENGINE_VERSION.to_i + 1).to_s)
    assert_refused @service.regenerate(model: @model, target: target), 'E_VERSION', 'newer_engine'
    root.set_attribute(DICTIONARY, 'road_engine_version', Archgen::ROAD_ENGINE_VERSION)
    root.set_attribute(DICTIONARY, 'road_version', 2)
    select(root)
    assert_refused @service.load_selection(model: @model), 'E_VERSION', 'unsupported_road'
  end

  def test_altered_metadata_and_foreign_roots_are_refused
    create
    root.set_attribute(DICTIONARY, 'road_digest', 'court')
    select(root)
    assert_equal '/metadata/road_digest', assert_refused(@service.load_selection(model: @model), 'E_SCHEMA', 'invalid_metadata').path
    other = @model.add_instance(@model.add_definition('autre'), FakeSketchUp::Host.identity)
    select(other)
    assert_refused @service.load_selection(model: @model), 'E_TARGET_STALE', 'not_a_road_root'
    select
    assert_refused @service.load_selection(model: @model), 'E_TARGET_STALE', 'road_selection_not_single'
  end
end
