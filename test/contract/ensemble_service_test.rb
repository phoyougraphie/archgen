# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter

# Contrat de l'écriture d'un ensemble, avec doubles. La preuve native est H15.
class EnsembleServiceTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp

  DICTIONARY = 'archgen.ensemble'
  INCH = 0.0254
  Injected = Class.new(StandardError)
  TREE = {
    'trace' => { 'points_m' => [[0, 0], [48, 0], [48, 48]], 'closed' => false },
    'building' => { 'profile' => { 'id' => 'brutalist' } }
  }.freeze
  ORIGIN = [10.0, 20.0, 3.0].freeze

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def materials
    Archgen::Composition.materials.fetch('materials')
  end

  def service(**ports)
    EnsembleService.new(registry: registry, intake: Archgen::Composition.intake, ensemble_intake: Archgen::Composition.ensemble_intake,
                        materials: materials, material_revision: 1, host: FakeSketchUp::Host, **ports)
  end

  def setup
    @model = FakeSketchUp::ServiceModel.new
    @service = service
  end

  def create(tree = TREE, origin = ORIGIN)
    result = @service.create(model: @model, tree: tree, origin_m: origin)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def root
    @model.instances.find { |i| i.get_attribute(DICTIONARY, 'ensemble_version') }
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

  # --- Création

  def test_create_is_one_operation_and_one_root
    summary = create
    assert_equal 1, @model.operations.count { |op| op.first == :commit }
    assert_equal 1, starts
    assert_equal 1, @model.instances.size
    assert_equal 1, summary.revision
    assert_equal 'Ensemble ARCHGEN', root.name
    assert_equal summary.persistent_id, root.persistent_id
    assert_operator summary.metrics['parcel_count'], :>, 1
  end

  def test_operation_name
    create
    start = @model.operations.find { |op| op.first == :start }
    assert_equal 'ARCHGEN : créer un ensemble', start[1]
  end

  def test_root_is_placed_at_the_first_point
    create
    matrix = root.transform.to_a
    assert_in_delta ORIGIN[0], matrix[12] * INCH, 1e-9
    assert_in_delta ORIGIN[1], matrix[13] * INCH, 1e-9
    assert_in_delta ORIGIN[2], matrix[14] * INCH, 1e-9
  end

  def test_each_parcel_is_a_nested_instance
    summary = create
    nested = root.definition.entities.select { |e| e.is_a?(FakeSketchUp::Instance) }
    assert_equal summary.metrics['parcel_count'], nested.size
    assert_equal 'left/0/0', nested.first.name
    assert_equal summary.metrics['definition_count'], nested.map(&:definition).uniq.size
    assert_operator nested.size, :>, nested.map(&:definition).uniq.size, 'le partage du plan doit se retrouver'
  end

  def test_parcel_matrix_is_in_inches
    create
    nested = root.definition.entities.select { |e| e.is_a?(FakeSketchUp::Instance) }
    parcel = nested.find { |n| n.name == 'left/0/1' }
    assert_in_delta 12.0 / INCH, parcel.transform.to_a[12], 1e-6
  end

  def test_parcels_do_not_carry_building_attributes
    create
    root.definition.entities.select { |e| e.is_a?(FakeSketchUp::Instance) }.each do |parcel|
      assert_nil parcel.get_attribute('archgen.building', 'metadata_version')
      assert_nil parcel.get_attribute(DICTIONARY, 'ensemble_version')
    end
  end

  def test_metadata_is_complete_and_readable
    summary = create
    assert_equal 1, root.get_attribute(DICTIONARY, 'ensemble_version')
    assert_equal summary.ensemble_digest, root.get_attribute(DICTIONARY, 'ensemble_digest')
    assert_equal Archgen::ENGINE_VERSION, root.get_attribute(DICTIONARY, 'engine_version')
    stored = JSON.parse(root.get_attribute(DICTIONARY, 'ensemble_json'))
    assert_equal [[0.0, 0.0], [48.0, 0.0], [48.0, 48.0]], stored.dig('trace', 'points_m')
    select(root)
    loaded = @service.load_selection(model: @model)
    assert loaded.ok?, loaded.errors.map(&:to_h).inspect
    assert_equal 'brutalist', loaded.value.settings.dig('building', 'profile', 'id')
  end

  def test_stored_settings_give_the_same_digest
    summary = create
    select(root)
    loaded = @service.load_selection(model: @model).value
    again = @service.preview(tree: loaded.settings)
    assert_equal summary.ensemble_digest, again.value.ensemble_digest
  end

  def test_preview_touches_nothing
    before = snapshot
    result = @service.preview(tree: TREE)
    assert result.ok?
    assert_equal before, snapshot
    assert_empty @model.operations
  end

  def test_progress_reaches_the_status_bar
    FakeSketchUp::Host.statuses.clear
    summary = create
    assert_equal summary.metrics['definition_count'], FakeSketchUp::Host.statuses.count { |s| s.include?('bâtiment') }
    assert_equal '', FakeSketchUp::Host.statuses.last, 'la barre d’état ne garde pas un message périmé'
    assert_match(/bâtiment 1 sur/, FakeSketchUp::Host.statuses.first)
  end

  # --- Refus sans écriture

  def test_refused_trace_writes_nothing
    before = snapshot
    result = @service.create(model: @model, tree: TREE.merge('trace' => { 'points_m' => [[0, 0], [5, 0]], 'closed' => false }), origin_m: ORIGIN)
    assert_refused result, 'E_STREET_TRACE', 'segment_short'
    assert_equal before, snapshot
    assert_equal 0, starts
  end

  def test_closed_trace_with_a_porch_too_high_writes_nothing
    square = { 'trace' => { 'points_m' => [[0, 0], [40, 0], [40, 40], [0, 40]], 'closed' => true }, 'building' => { 'profile' => { 'id' => 'haussmann' } }, 'access' => { 'height_m' => 6 } }
    assert_refused @service.create(model: @model, tree: square, origin_m: ORIGIN), 'E_STREET_ACCESS', 'porch_too_high'
    assert_equal 0, starts
  end

  def test_closed_trace_with_a_form_is_written
    square = TREE.merge('trace' => { 'points_m' => [[0, 0], [40, 0], [40, 40], [0, 40]], 'closed' => true })
    summary = create(square)
    assert_equal 9, summary.metrics['parcel_count']
    assert_equal 3, summary.metrics['access_count']
    assert_equal 9, root.definition.entities.count { |e| e.is_a?(FakeSketchUp::Instance) }
  end

  def test_bad_origin_is_refused
    [nil, [1.0, 2.0], [1.0, 2.0, Float::NAN], [1, 'a', 3]].each do |origin|
      assert_refused @service.create(model: @model, tree: TREE, origin_m: origin), 'E_SCHEMA', 'invalid_origin'
    end
    assert_equal 0, starts
  end

  def test_nested_edit_context_is_refused
    @model.active_path = [Object.new]
    assert_refused @service.create(model: @model, tree: TREE, origin_m: ORIGIN), 'E_TARGET_STALE', 'nested_edit_context'
    assert_equal 0, starts
  end

  # --- Panne : le document revient à l'identique

  class FailingWriter
    def initialize(real, after:)
      @real = real
      @left = after
    end

    def write(*args, **options)
      raise Injected, 'panne' if @left.zero?

      @left -= 1
      @real.write(*args, **options)
    end

    def mark_definition(*args, **options)
      @real.mark_definition(*args, **options)
    end
  end

  def test_failure_on_a_later_building_leaves_no_trace
    before = snapshot
    writer = FailingWriter.new(GeometryWriter.new(host: FakeSketchUp::Host), after: 2)
    result = service(writer: writer).create(model: @model, tree: TREE, origin_m: ORIGIN)
    assert_refused result, 'E_WRITE', 'write_failed'
    assert_equal before, snapshot
    assert_equal 1, @model.operations.count { |op| op.first == :abort }
    assert_equal 0, @model.operations.count { |op| op.first == :commit }
  end

  # --- Régénération

  def regenerate(changes = {}, target: nil)
    select(root)
    target ||= @service.load_selection(model: @model).value.target
    @service.regenerate(model: @model, target: target, changes: changes)
  end

  def test_regenerate_keeps_root_and_placement
    create
    instance = root
    matrix = instance.transformation.to_a
    old = instance.definition
    result = regenerate({ 'parcel' => { 'depth_m' => 10 } })
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal 2, result.value.revision
    assert_same instance, root
    assert_equal matrix, instance.transformation.to_a
    refute_same old, instance.definition
    assert_equal 10.0, JSON.parse(instance.get_attribute(DICTIONARY, 'ensemble_json')).dig('parcel', 'depth_m')
    assert_equal 'ARCHGEN : régénérer l’ensemble', @model.operations.reverse.find { |op| op.first == :start }[1]
  end

  def test_regenerate_can_change_the_trace
    create
    result = regenerate({ 'trace' => { 'points_m' => [[0, 0], [36, 0]], 'closed' => false } })
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal 3, result.value.metrics['parcel_count']
  end

  def test_old_definition_stays_intact_for_a_copy
    create
    original = root
    copy = @model.copy_instance(original)
    old_definition = copy.definition
    count = old_definition.entities.count { true }
    select(original)
    target = @service.load_selection(model: @model).value.target
    assert @service.regenerate(model: @model, target: target, changes: { 'parcel' => { 'depth_m' => 10 } }).ok?
    assert_same old_definition, copy.definition
    assert_equal count, old_definition.entities.count { true }
    refute_same old_definition, original.definition
    assert_equal 9.0, JSON.parse(copy.get_attribute(DICTIONARY, 'ensemble_json')).dig('parcel', 'depth_m')
  end

  def test_refused_regeneration_changes_nothing
    create
    before = root.definition
    operations = starts
    result = regenerate({ 'parcel' => { 'depth_m' => 3 } })
    assert_refused result, 'E_SCHEMA', 'minimum'
    assert_same before, root.definition
    assert_equal operations, starts
  end

  def test_failed_regeneration_restores_everything
    create
    before = root.definition
    attrs = root.attrs.dup
    select(root)
    target = @service.load_selection(model: @model).value.target
    writer = FailingWriter.new(GeometryWriter.new(host: FakeSketchUp::Host), after: 0)
    result = service(writer: writer).regenerate(model: @model, target: target, changes: { 'parcel' => { 'depth_m' => 10 } })
    assert_refused result, 'E_WRITE', 'write_failed'
    assert_same before, root.definition
    assert_equal attrs, root.attrs
  end

  # --- Cible

  def target_after
    select(root)
    @service.load_selection(model: @model).value.target
  end

  def test_regenerate_rechecks_the_target
    create
    target = target_after
    select
    assert_refused @service.regenerate(model: @model, target: target), 'E_TARGET_STALE', 'selection_changed'
    assert_refused @service.regenerate(model: @model, target: :faux), 'E_TARGET_STALE', 'invalid_target'
    other = target.dup
    other.document_key = 'autre'
    select(root)
    assert_refused @service.regenerate(model: @model, target: other), 'E_TARGET_STALE', 'document_changed'
    other = target.dup
    other.revision = 9
    assert_refused @service.regenerate(model: @model, target: other), 'E_TARGET_STALE', 'revision_changed'
    other = target.dup
    other.definition_id = -1
    assert_refused @service.regenerate(model: @model, target: other), 'E_TARGET_STALE', 'definition_changed'
  end

  def test_locked_root_is_refused
    create
    target = target_after
    root.locked = true
    assert_refused @service.regenerate(model: @model, target: target), 'E_TARGET_STALE', 'target_locked'
  end

  def test_scaled_root_is_refused
    create
    target = target_after
    root.transformation = FakeSketchUp::Host.transformation([2.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0])
    assert_refused @service.regenerate(model: @model, target: target), 'E_TARGET_STALE', 'non_rigid_transform'
  end

  def test_future_versions_are_readable_but_not_writable
    create
    target = target_after
    root.set_attribute(DICTIONARY, 'engine_version', (Archgen::ENGINE_VERSION.to_i + 1).to_s)
    assert_refused @service.regenerate(model: @model, target: target), 'E_VERSION', 'newer_engine'
    root.set_attribute(DICTIONARY, 'engine_version', Archgen::ENGINE_VERSION)
    root.set_attribute(DICTIONARY, 'material_revision', 2)
    assert_refused @service.regenerate(model: @model, target: target), 'E_VERSION', 'newer_materials'
    root.set_attribute(DICTIONARY, 'material_revision', 1)
    root.set_attribute(DICTIONARY, 'ensemble_version', 2)
    select(root)
    assert_refused @service.load_selection(model: @model), 'E_VERSION', 'unsupported'
  end

  def test_altered_metadata_is_refused
    create
    root.set_attribute(DICTIONARY, 'ensemble_digest', 'court')
    select(root)
    found = assert_refused @service.load_selection(model: @model), 'E_SCHEMA', 'invalid_metadata'
    assert_equal '/metadata/ensemble_digest', found.path
  end

  def test_altered_settings_are_refused
    create
    root.set_attribute(DICTIONARY, 'ensemble_json', '{"trace":{}}')
    select(root)
    refute @service.load_selection(model: @model).ok?
  end

  def test_selection_must_be_a_single_ensemble_root
    create
    select
    assert_refused @service.load_selection(model: @model), 'E_TARGET_STALE', 'ensemble_selection_not_single'
    other = @model.add_instance(@model.add_definition('autre'), FakeSketchUp::Host.identity)
    select(other)
    assert_refused @service.load_selection(model: @model), 'E_TARGET_STALE', 'not_an_ensemble_root'
  end

  # --- Avec le bâtiment seul

  def building_service
    BuildingService.new(registry: registry, intake: Archgen::Composition.intake, materials: materials, material_revision: 1, host: FakeSketchUp::Host)
  end

  def test_a_lone_building_is_not_an_ensemble_and_vice_versa
    create
    select(root)
    assert_refused building_service.load_selection(model: @model), 'E_TARGET_STALE', 'not_an_archgen_root'
    built = building_service.create(model: @model, draft: { 'schema_version' => 1, 'profile' => { 'id' => 'brutalist' } })
    assert built.ok?, built.errors.map(&:to_h).inspect
    select(@model.instances.last)
    assert_refused @service.load_selection(model: @model), 'E_TARGET_STALE', 'not_an_ensemble_root'
  end
end
