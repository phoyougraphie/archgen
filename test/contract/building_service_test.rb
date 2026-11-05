# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter

# Contrat du service avec doubles. La preuve native est H03-H04 : les doubles
# vérifient seulement qui appelle quoi, et dans quel ordre.
class BuildingServiceTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp

  UUID = '123e4567-e89b-42d3-a456-426614174000'
  NEUTRAL = { 'schema_version' => 1, 'profile' => { 'id' => 'generic' }, 'name' => 'Test', 'mode' => 'structural' }.freeze

  def registry
    @registry ||= StyleRegistry.load(
      TestData.profiles, schema: TestData.schemas['profile'],
      config_validator: SchemaValidator.new(TestData.schemas['config']),
      capabilities: StyleRegistry::KNOWN_CAPABILITIES, materials: TestData.materials
    ).value
  end

  def service(allow_internal: true, **ports)
    BuildingService.new(registry: registry, intake: TestData.intake, materials: TestData.materials, material_revision: 1,
                        allow_internal: allow_internal, host: FakeSketchUp::Host, uuid: -> { UUID }, **ports)
  end

  def model
    @model ||= FakeSketchUp::ServiceModel.new
  end

  def create(draft = NEUTRAL)
    service.create(model: model, draft: draft)
  end

  def kinds
    model.operations.map(&:first)
  end

  # --- Création

  def test_success_is_exactly_one_operation
    result = create
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal [[:start, 'ARCHGEN : créer', true], [:commit]], model.operations
  end

  def test_root_is_inserted_at_identity_with_config_name
    create
    instance = model.instances.first
    assert_equal :identity, instance.transform
    assert_equal 'Test', instance.name
    assert_equal 'ARCHGEN bâtiment', instance.definition.name
    assert_equal 'building', instance.definition.get_attribute('archgen.definition', 'kind')
  end

  def test_summary_is_returned_after_commit
    summary = create.value
    assert_equal 1000, summary.persistent_id
    assert_equal UUID, summary.building_uuid
    assert_equal 1, summary.revision
    assert_equal 709, summary.metrics['unique_face_count']
    assert_match(/\A\h{64}\z/, summary.plan_digest)
  end

  def test_metadata_fields_are_complete
    create
    metadata = ComponentRepository.new(host: FakeSketchUp::Host).read_metadata(model.instances.first)
    assert_equal ComponentRepository::KEYS.sort, metadata.keys.sort
    assert_equal 1, metadata['metadata_version']
    assert_equal 1, metadata['revision']
    assert_equal UUID, metadata['building_uuid']
    assert_equal Archgen::ENGINE_VERSION, metadata['engine_version']
    assert_equal 1, metadata['material_revision']
  end

  def test_config_lives_on_instance_not_on_definition
    create
    refute_nil model.instances.first.get_attribute('archgen.building', 'config_json')
    assert_nil model.instances.first.definition.get_attribute('archgen.definition', 'config_json')
  end

  def test_warnings_are_kept_on_success
    result = create('schema_version' => 1, 'profile' => { 'id' => 'haussmann' }, 'levels' => { 'count' => 4 })
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal ['W_HISTORICAL'], result.warnings.map(&:code)
  end

  def test_native_exception_message_is_not_exposed
    writer = Object.new
    writer.define_singleton_method(:write) { |*_, **_kw| raise IOError, 'C:/Users/secret/fichier' }
    result = service(writer: writer).create(model: model, draft: NEUTRAL)
    assert_equal 'IOError', result.errors.first.params['error']
    assert_nil result.errors.first.params['detail']
  end

  # --- Rejets : aucune écriture, aucune opération

  def assert_untouched
    assert_empty model.operations
    assert_equal 0, model.mutation_count
  end

  def test_invalid_json_touches_nothing
    result = create('{"schema_version":1,')
    assert_equal 'E_SCHEMA', result.errors.first.code
    assert_untouched
  end

  def test_opening_rejection_touches_nothing
    result = create(NEUTRAL.merge('facade' => { 'window_width_m' => 3.0 }))
    assert_equal 'E_OPENING_CLEARANCE', result.errors.first.code
    assert_untouched
  end

  def test_internal_profile_refused_outside_test_bench
    result = service(allow_internal: false).create(model: model, draft: NEUTRAL)
    assert_equal 'E_PROFILE_UNAVAILABLE', result.errors.first.code
    assert_untouched
  end

  def test_nested_edit_context_refused
    model.active_path = [:group]
    result = create
    assert_equal 'nested_edit_context', result.errors.first.params['reason']
    assert_untouched
  end

  def test_closed_model_refused
    model.valid = false
    assert_equal 'E_TARGET_STALE', create.errors.first.code
    assert_untouched
  end

  # --- Transaction : pannes

  def test_failed_start_neither_writes_nor_aborts
    model.start_result = false
    result = create
    assert_equal 'operation_not_started', result.errors.first.params['reason']
    assert_equal [:start], kinds
    assert_equal 0, model.mutation_count
  end

  def test_writer_failure_aborts_once_and_returns_no_reference
    model.writer_behaviour = { reject_faces: true }
    result = create
    assert_nil result.value
    assert_equal ['E_WRITE', 'write_failed'], [result.errors.first.code, result.errors.first.params['reason']]
    assert_equal %i[start abort], kinds
  end

  def test_insert_failure_aborts_once
    model.fail_insert = true
    assert_equal 'write_failed', create.errors.first.params['reason']
    assert_equal %i[start abort], kinds
  end

  def test_commit_false_aborts_once
    model.commit_result = false
    result = create
    assert_nil result.value
    assert_equal 'commit_failed', result.errors.first.params['reason']
    assert_equal %i[start commit abort], kinds
  end

  def test_refused_abort_is_a_blocking_incident
    model.writer_behaviour = { reject_faces: true }
    model.abort_result = false
    result = create
    assert_equal 'abort_failed', result.errors.first.params['reason']
    assert_equal 'write_failed', result.errors.first.params['cause']
    assert_equal %i[start abort], kinds, 'aucune seconde tentative ni opération de réparation'
  end

  def test_metadata_mismatch_aborts
    repository = ComponentRepository.new(host: FakeSketchUp::Host)
    repository.define_singleton_method(:read_metadata) { |_| {} }
    result = service(repository: repository).create(model: model, draft: NEUTRAL)
    assert_equal 'write_failed', result.errors.first.params['reason']
    assert_equal %i[start abort], kinds
  end

  # --- Relecture

  def loaded
    summary = create.value
    service.load_building(model: model, persistent_id: summary.persistent_id)
  end

  def test_round_trip_restores_exact_effective_config
    written = service.preview(draft: NEUTRAL).value.config
    result = loaded
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal written.to_h, result.value.config.to_h
    assert_equal written.config_digest, result.value.config.config_digest
    assert_kind_of Integer, result.value.config.to_h['seed']
    assert_kind_of Float, result.value.config.to_h['footprint']['width_m']
  end

  def test_reading_does_not_write_or_open_operation
    summary = create.value
    before = model.operations.dup
    attrs = model.instances.first.attrs.dup
    service.load_building(model: model, persistent_id: summary.persistent_id)
    assert_equal before, model.operations
    assert_equal attrs, model.instances.first.attrs
  end

  def set(key, value)
    model.instances.first.set_attribute('archgen.building', key, value)
  end

  def load_first
    service.load_building(model: model, persistent_id: model.instances.first.persistent_id)
  end

  def test_future_metadata_version_refused_without_mutation
    create
    set('metadata_version', 2)
    attrs = model.instances.first.attrs.dup
    result = load_first
    assert_equal ['E_VERSION', '/metadata/metadata_version'], [result.errors.first.code, result.errors.first.path]
    assert_equal attrs, model.instances.first.attrs
  end

  def test_future_config_version_refused
    create
    data = JSON.parse(model.instances.first.get_attribute('archgen.building', 'config_json'))
    set('config_json', JSON.generate(data.merge('schema_version' => 99)))
    assert_equal ['E_VERSION', '/schema_version'], [load_first.errors.first.code, load_first.errors.first.path]
  end

  def test_missing_profile_revision_refused
    create
    data = JSON.parse(model.instances.first.get_attribute('archgen.building', 'config_json'))
    set('config_json', JSON.generate(data.merge('profile' => { 'id' => 'generic', 'revision' => 9 })))
    assert_equal 'missing_revision', load_first.errors.first.params['reason']
  end

  def test_corrupted_config_is_a_diagnostic
    create
    set('config_json', '{"schema_version":1,')
    assert_equal 'E_SCHEMA', load_first.errors.first.code
    set('config_json', 'x' * 70_000)
    assert_equal 'too_large', load_first.errors.first.params['reason']
  end

  def test_each_invalid_metadata_field_is_located
    {
      'building_uuid' => 'pas-un-uuid', 'revision' => 0, 'config_json' => 12,
      'plan_digest' => 'abc', 'engine_version' => 1, 'material_revision' => 'x'
    }.each do |field, value|
      @model = nil
      create
      set(field, value)
      assert_equal ['E_SCHEMA', "/metadata/#{field}"], [load_first.errors.first.code, load_first.errors.first.path], field
    end
  end

  def test_unknown_or_foreign_target_is_stale
    assert_equal 'target_not_found', service.load_building(model: model, persistent_id: 1).errors.first.params['reason']
    summary = create.value
    instance = model.find_entity_by_persistent_id(summary.persistent_id)
    instance.attrs.clear
    assert_equal 'not_an_archgen_root', load_first.errors.first.params['reason']
  end

  def test_nested_instance_is_refused
    create
    model.instances.first.instance_variable_set(:@parent, :other_definition)
    assert_equal 'not_at_model_root', load_first.errors.first.params['reason']
  end

  # --- Aperçu

  def test_preview_writes_nothing
    result = service.preview(draft: NEUTRAL, model: model)
    assert result.ok?
    assert_untouched
    assert_equal 16, result.value.projection['front_elevation']['openings'].size
    assert_equal GeometryEngine.plan_digest(result.value.plan), result.value.plan_digest
  end

  def test_preview_and_create_share_the_same_plan
    preview = service.preview(draft: NEUTRAL).value
    assert_equal preview.plan_digest, create.value.plan_digest
  end

  # --- Composition réelle

  def test_real_composition_publishes_only_implemented_profiles
    registry = Archgen::Composition.registry
    assert registry.ok?, registry.errors.map(&:to_h).inspect
    assert_equal %w[brutalist], registry.value.active_profiles.map(&:id), 'les deux autres attendent AG-015'
  end
end
