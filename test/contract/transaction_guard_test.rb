# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter

# Garde de transaction et versions, avec doubles. La preuve native est H06-H07.
class TransactionGuardTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp

  NEUTRAL = { 'schema_version' => 1, 'profile' => { 'id' => 'generic' }, 'name' => 'A', 'mode' => 'structural' }.freeze
  EDIT = { 'schema_version' => 1, 'footprint' => { 'width_m' => 14.0 }, 'materials' => { 'roof' => 'zinc' } }.freeze
  Injected = Class.new(StandardError)
  Fatal = Class.new(Exception) # rubocop:disable Lint/InheritException

  def registry
    @registry ||= StyleRegistry.load(
      TestData.profiles, schema: TestData.schemas['profile'],
      config_validator: SchemaValidator.new(TestData.schemas['config']),
      capabilities: StyleRegistry::KNOWN_CAPABILITIES, materials: TestData.materials
    ).value
  end

  def service(**ports)
    BuildingService.new(registry: registry, intake: TestData.intake, materials: TestData.materials, material_revision: 1,
                        allow_internal: true, host: FakeSketchUp::Host, **ports)
  end

  def repository(&block)
    ComponentRepository.new(host: FakeSketchUp::Host).tap { |r| block.call(r) }
  end

  def model
    @model ||= FakeSketchUp::ServiceModel.new
  end

  def created
    @created ||= service.create(model: model, draft: NEUTRAL).value.tap { model.selection.replace([model.instances.first]) }
  end

  def a
    model.instances.first
  end

  def kinds
    created
    model.operations.drop(2).map(&:first)
  end

  def inventory
    [model.definition_list.size, model.instances.size, model.materials.count, model.layers.count,
     a.definition, a.attrs.dup, a.transformation.to_a]
  end

  # Une panne à l'endroit voulu du dépôt ou du writer.
  def regenerate_with(**ports)
    created
    @before = inventory
    service(**ports).regenerate(model: model, target: created.target, draft: EDIT)
  end

  def assert_restored(result, reason: 'write_failed')
    refute result.ok?
    assert_nil result.value
    assert_equal ['E_WRITE', reason], [result.errors.first.code, result.errors.first.params['reason']]
    assert_equal @before, inventory
    assert_equal %i[start abort], kinds
  end

  # --- Pannes aux points du contrat

  def test_failure_during_write_is_restored
    failing = Object.new
    def failing.write(*, **) = raise(Injected, 'milieu d’écriture')
    def failing.mark_definition(*, **) = nil
    assert_restored regenerate_with(writer: failing)
  end

  def test_failure_after_first_faces_is_restored
    created
    model.writer_behaviour = { reject_faces: true }
    @before = inventory
    assert_restored service.regenerate(model: model, target: created.target, draft: EDIT)
  end

  def test_failure_after_swap_is_restored
    faulty = repository do |r|
      r.define_singleton_method(:swap) do |instance, definition:|
        super(instance, definition: definition)
        raise Injected, 'après le remplacement'
      end
    end
    assert_restored regenerate_with(repository: faulty)
  end

  def test_failure_before_final_metadata_is_restored
    faulty = repository { |r| r.define_singleton_method(:write_metadata) { |*| raise Injected, 'avant métadonnées' } }
    assert_restored regenerate_with(repository: faulty)
  end

  def test_partial_metadata_write_is_restored
    faulty = repository do |r|
      r.define_singleton_method(:write_metadata) do |instance, metadata|
        instance.set_attribute(ComponentRepository::DICTIONARY, 'revision', metadata['revision'])
        raise Injected, 'écriture partielle'
      end
    end
    assert_restored regenerate_with(repository: faulty)
  end

  def test_failure_during_creation_leaves_nothing
    model.writer_behaviour = { reject_faces: true }
    result = service.create(model: model, draft: NEUTRAL)
    assert_equal 'write_failed', result.errors.first.params['reason']
    assert_equal 0, model.mutation_count
    assert_equal %i[start abort], model.operations.map(&:first)
  end

  def test_commit_refusal_is_restored
    created
    model.commit_result = false
    @before = inventory
    result = service.regenerate(model: model, target: created.target, draft: EDIT)
    assert_equal 'commit_failed', result.errors.first.params['reason']
    assert_equal @before, inventory
    assert_equal %i[start commit abort], kinds
  end

  # --- Le relevé révèle un abandon incomplet

  def test_incomplete_restore_is_reported_with_its_differences
    created
    model.abort_restores = false
    faulty = repository do |r|
      r.define_singleton_method(:write_metadata) { |*| raise Injected, 'panne' }
    end
    result = service(repository: faulty).regenerate(model: model, target: created.target, draft: EDIT)
    error = result.errors.first
    assert_equal 'restore_incomplete', error.params['reason']
    assert_equal 'write_failed', error.params['cause']
    assert_includes error.params['differences'], 'definitions'
    assert_includes error.params['differences'], 'target'
    assert_equal %i[start abort], kinds, 'aucune opération de réparation'
  end

  def test_refused_abort_is_not_verified_as_success
    created
    model.abort_result = false
    faulty = repository { |r| r.define_singleton_method(:write_metadata) { |*| raise Injected, 'panne' } }
    result = service(repository: faulty).regenerate(model: model, target: created.target, draft: EDIT)
    assert_equal 'abort_failed', result.errors.first.params['reason']
    assert_equal %i[start abort], kinds
  end

  def test_no_second_write_operation_masks_a_failure
    faulty = repository { |r| r.define_singleton_method(:swap) { |*, **| raise Injected, 'panne' } }
    regenerate_with(repository: faulty)
    assert_equal 1, kinds.count(:start)
  end

  # --- Garde

  def test_exception_outside_standard_error_closes_the_operation
    guard = TransactionGuard.new
    assert_raises(Fatal) { guard.run(model, 'test') { raise Fatal } }
    assert_equal %i[start abort], model.operations.map(&:first)
    assert guard.run(model, 'suite') { :ok }.ok?, 'la garde reste utilisable'
  end

  def test_nested_operation_is_refused
    guard = TransactionGuard.new
    inner = nil
    outer = guard.run(model, 'externe') { inner = guard.run(model, 'interne') { :jamais } }
    assert outer.ok?
    assert_equal 'operation_in_progress', inner.errors.first.params['reason']
    assert_equal %i[start commit], model.operations.map(&:first), 'une seule opération démarrée'
  end

  def test_value_returned_only_after_commit
    guard = TransactionGuard.new
    model.commit_result = false
    assert_nil guard.run(model, 'test') { :valeur }.value
    model.commit_result = true
    assert_equal :valeur, guard.run(model, 'test') { :valeur }.value
  end

  def test_exception_message_never_leaks_a_native_path
    guard = TransactionGuard.new
    result = guard.run(model, 'test') { raise IOError, 'C:/Users/secret/f.skp' }
    assert_equal 'IOError', result.errors.first.params['error']
    refute_includes result.errors.first.to_h.to_s, 'secret'
    detailed = guard.run(model, 'test') { raise WriteError, 'Face refusée : wall/front' }
    assert_equal 'Face refusée : wall/front', detailed.errors.first.params['detail']
  end

  # --- Versions

  def test_newer_engine_is_readable_but_not_regenerable
    created
    a.set_attribute('archgen.building', 'engine_version', '999')
    assert service.load_selection(model: model).ok?, 'consultable en diagnostic'
    target = service.load_selection(model: model).value.target
    @before = inventory
    result = service.regenerate(model: model, target: target, draft: EDIT)
    assert_equal ['E_VERSION', '/metadata/engine_version'], [result.errors.first.code, result.errors.first.path]
    assert_equal @before, inventory
    assert_equal [], kinds
  end

  def test_unreadable_engine_is_refused
    created
    a.set_attribute('archgen.building', 'engine_version', 'futur')
    assert_equal 'newer_engine', service.regenerate(model: model, target: created.target, draft: EDIT).errors.first.params['reason']
  end

  def test_newer_material_catalogue_is_refused
    created
    a.set_attribute('archgen.building', 'material_revision', 2)
    result = service.regenerate(model: model, target: created.target, draft: EDIT)
    assert_equal ['E_VERSION', '/metadata/material_revision'], [result.errors.first.code, result.errors.first.path]
    assert_equal [], kinds
  end

  def test_older_engine_can_be_regenerated_explicitly
    created
    a.set_attribute('archgen.building', 'engine_version', '0')
    result = service.regenerate(model: model, target: created.target, draft: EDIT)
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal Archgen::ENGINE_VERSION, a.get_attribute('archgen.building', 'engine_version')
  end
end
