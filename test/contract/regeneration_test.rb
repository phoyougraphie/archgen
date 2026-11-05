# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter

# Contrat de la régénération avec doubles. La preuve native est H05.
class RegenerationTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp

  NEUTRAL = { 'schema_version' => 1, 'profile' => { 'id' => 'generic' }, 'name' => 'A', 'mode' => 'structural' }.freeze
  EDIT = { 'schema_version' => 1, 'footprint' => { 'width_m' => 14.0 } }.freeze

  def setup
    @uuids = %w[11111111-1111-4111-8111-111111111111 22222222-2222-4222-8222-222222222222 33333333-3333-4333-8333-333333333333]
  end

  def registry
    @registry ||= StyleRegistry.load(
      TestData.profiles, schema: TestData.schemas['profile'],
      config_validator: SchemaValidator.new(TestData.schemas['config']),
      capabilities: StyleRegistry::KNOWN_CAPABILITIES, materials: TestData.materials
    ).value
  end

  def service(**ports)
    @service ||= BuildingService.new(registry: registry, intake: TestData.intake, materials: TestData.materials, material_revision: 1,
                                     allow_internal: true, host: FakeSketchUp::Host, uuid: -> { @uuids.shift }, **ports)
  end

  def model
    @model ||= FakeSketchUp::ServiceModel.new
  end

  def a
    model.instances.first
  end

  def created
    @created ||= service.create(model: model, draft: NEUTRAL).value.tap { model.selection.replace([model.instances.first]) }
  end

  def regenerate(draft = EDIT, target: created.target)
    created
    service.regenerate(model: model, target: target, draft: draft)
  end

  def kinds_after_creation
    created
    model.operations.drop(2).map(&:first)
  end

  def meta(instance, key)
    instance.get_attribute('archgen.building', key)
  end

  def assert_stale(reason, result = regenerate)
    refute result.ok?, 'attendu un refus'
    assert_equal ['E_TARGET_STALE', reason], [result.errors.first.code, result.errors.first.params['reason']]
    assert_equal [], kinds_after_creation, 'aucune opération ne doit démarrer'
    assert_equal 1, model.definition_list.size, 'aucune définition ne doit être créée'
  end

  # --- Remplacement

  def test_success_is_one_operation_and_a_fresh_definition
    previous = created && a.definition
    result = regenerate
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal [[:start, 'ARCHGEN : régénérer', true], [:commit]], model.operations.drop(2)
    refute_same previous, a.definition
    assert_equal 2, model.definition_list.size
  end

  def test_previous_definition_is_never_modified
    created
    old = a.definition
    faces = old.entities.items.size
    attrs = old.attrs.dup
    regenerate
    assert_equal faces, old.entities.items.size
    assert_equal attrs, old.attrs
  end

  def test_revision_increments_and_config_is_replaced
    summary = regenerate.value
    assert_equal 2, summary.revision
    assert_equal 2, meta(a, 'revision')
    assert_equal 14.0, JSON.parse(meta(a, 'config_json'))['footprint']['width_m']
    assert_equal summary.plan_digest, meta(a, 'plan_digest')
  end

  def test_identity_placement_name_tag_and_third_party_attributes_are_kept
    created
    a.layer = :user_tag
    a.name = 'Nom utilisateur'
    a.set_attribute('autre.extension', 'cle', 'valeur')
    moved = FakeSketchUp::Transformation.new(FakeSketchUp::IDENTITY.dup.tap { |m| m[12] = 250.0 })
    a.transformation = moved
    pid = a.persistent_id
    regenerate
    assert_equal pid, a.persistent_id
    assert_equal moved.to_a, a.transformation.to_a
    assert_equal :user_tag, a.layer
    assert_equal 'Nom utilisateur', a.name
    assert_equal 'valeur', a.get_attribute('autre.extension', 'cle')
  end

  def test_config_name_does_not_rename_the_instance
    regenerate(EDIT.merge('name' => 'Nouveau libellé'))
    assert_equal 'A', a.name
    assert_equal 'Nouveau libellé', JSON.parse(meta(a, 'config_json'))['name']
  end

  def test_unique_root_keeps_its_uuid
    created
    uuid = meta(a, 'building_uuid')
    regenerate
    assert_equal uuid, meta(a, 'building_uuid')
  end

  def test_same_input_gives_new_definition_with_same_plan_digest
    digest = created.plan_digest
    summary = regenerate({ 'schema_version' => 1 }).value
    assert_equal digest, summary.plan_digest
    assert_equal 2, model.definition_list.size
  end

  def test_returned_target_allows_the_next_regeneration
    second = regenerate.value
    third = service.regenerate(model: model, target: second.target, draft: { 'schema_version' => 1, 'footprint' => { 'depth_m' => 10.0 } })
    assert third.ok?, third.errors.map(&:to_h).inspect
    assert_equal 3, third.value.revision
  end

  # --- Copies

  def test_copy_is_isolated_and_only_the_target_gets_a_new_uuid
    created
    original_uuid = meta(a, 'building_uuid')
    copy = model.copy_instance(a)
    copy_attrs = copy.attrs.dup
    shared = a.definition
    regenerate
    refute_equal original_uuid, meta(a, 'building_uuid')
    assert_equal original_uuid, meta(copy, 'building_uuid')
    assert_equal copy_attrs, copy.attrs
    assert_same shared, copy.definition
    refute_same shared, a.definition
  end

  def test_copy_can_be_regenerated_and_its_revision_increments
    created
    copy = model.copy_instance(a)
    regenerate
    model.selection.replace([copy])
    loaded = service.load_selection(model: model).value
    result = service.regenerate(model: model, target: loaded.target, draft: { 'schema_version' => 1, 'footprint' => { 'depth_m' => 11.0 } })
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal 2, meta(copy, 'revision')
    assert_equal 12.0, JSON.parse(meta(copy, 'config_json'))['footprint']['width_m'], 'la copie ne reçoit pas la largeur de A'
    assert_equal 14.0, JSON.parse(meta(a, 'config_json'))['footprint']['width_m']
  end

  def test_reading_a_shared_uuid_writes_nothing
    created
    copy = model.copy_instance(a)
    before = [a.attrs.dup, copy.attrs.dup]
    service.load_selection(model: model)
    model.selection.replace([copy])
    service.load_selection(model: model)
    assert_equal before, [a.attrs, copy.attrs]
  end

  # --- Changement de style

  def test_style_change_keeps_dimensions_and_replaces_style
    result = regenerate({ 'schema_version' => 1, 'profile' => { 'id' => 'brutalist', 'revision' => 1 } })
    assert result.ok?, result.errors.map(&:to_h).inspect
    data = JSON.parse(meta(a, 'config_json'))
    assert_equal({ 'id' => 'brutalist', 'revision' => 1 }, data['profile'])
    assert_equal 12.0, data['footprint']['width_m']
    assert_equal 'concrete', data['materials']['wall']
    assert_equal 'A', data['name']
  end

  # --- Sélection

  def test_load_selection_returns_config_and_target
    created
    loaded = service.load_selection(model: model)
    assert loaded.ok?
    assert_equal created.target.to_a, loaded.value.target.to_a
    assert_equal 'A', loaded.value.config.to_h['name']
  end

  def test_load_selection_needs_exactly_one_root
    created
    model.selection.clear
    assert_equal 'selection_not_single', service.load_selection(model: model).errors.first.params['reason']
    model.selection.replace([a, a])
    assert_equal 'selection_not_single', service.load_selection(model: model).errors.first.params['reason']
  end

  # --- Cible périmée : aucune écriture

  def test_invalid_target_object
    created
    assert_stale 'invalid_target', regenerate(target: 'forgé')
  end

  def test_deleted_target
    created
    target = created.target
    model.instances.clear
    result = service.regenerate(model: model, target: target, draft: EDIT)
    assert_equal 'target_not_found', result.errors.first.params['reason']
  end

  def test_selection_changed
    created
    model.selection.clear
    assert_stale 'selection_changed'
  end

  def test_other_entity_selected
    created
    copy = model.copy_instance(a)
    model.selection.replace([copy])
    assert_stale 'selection_changed'
  end

  def test_locked_target
    created
    a.locked = true
    assert_stale 'target_locked'
  end

  def test_nested_edit_context
    created
    model.active_path = [:group]
    assert_stale 'nested_edit_context'
  end

  def test_target_moved_into_another_definition
    created
    a.parent = :other_definition
    assert_stale 'not_at_model_root'
  end

  def test_definition_changed
    created
    target = created.target.dup.tap { |t| t.definition_id = -1 }
    assert_stale 'definition_changed', regenerate(target: target)
  end

  def test_revision_changed
    created
    target = created.target.dup.tap { |t| t.revision = 99 }
    assert_stale 'revision_changed', regenerate(target: target)
  end

  def test_config_changed
    created
    target = created.target.dup.tap { |t| t.config_digest = 'x' }
    assert_stale 'config_changed', regenerate(target: target)
  end

  def test_old_target_is_refused_after_a_regeneration
    target = created.target
    assert regenerate.ok?
    assert_equal 'definition_changed', service.regenerate(model: model, target: target, draft: EDIT).errors.first.params['reason']
  end

  # --- Transformations refusées, instruction explicite

  def with_matrix(index, value)
    created
    a.transformation = FakeSketchUp::Transformation.new(FakeSketchUp::IDENTITY.dup.tap { |m| m[index] = value })
  end

  def test_scale_refused
    with_matrix(0, 2.0)
    assert_stale 'non_rigid_transform'
  end

  def test_uniform_scale_stored_in_last_cell_refused
    with_matrix(15, 0.5)
    assert_stale 'non_rigid_transform'
  end

  def test_mirror_refused
    with_matrix(0, -1.0)
    assert_stale 'non_rigid_transform'
  end

  def test_singular_matrix_refused
    with_matrix(10, 0.0)
    assert_stale 'non_rigid_transform'
  end

  def test_rotation_and_translation_accepted
    created
    cos = Math.cos(0.5)
    sin = Math.sin(0.5)
    a.transformation = FakeSketchUp::Transformation.new([cos, sin, 0.0, 0.0, -sin, cos, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 300.0, -40.0, 12.0, 1.0])
    assert regenerate.ok?
  end

  # --- Rejet de la saisie : rien n'est écrit

  def test_invalid_draft_is_rejected_before_any_operation
    created
    before = a.attrs.dup
    result = regenerate({ 'schema_version' => 1, 'facade' => { 'window_width_m' => 3.0 } })
    assert_equal 'E_OPENING_CLEARANCE', result.errors.first.code
    assert_equal [], kinds_after_creation
    assert_equal before, a.attrs
  end

  # --- Pannes : abandon unique, aucune référence

  def test_writer_failure_aborts_once
    created
    model.writer_behaviour = { reject_faces: true }
    result = regenerate
    assert_nil result.value
    assert_equal 'write_failed', result.errors.first.params['reason']
    assert_equal %i[start abort], kinds_after_creation
  end

  def test_swap_altering_placement_aborts
    created
    a.swap_corrupts = true
    result = regenerate
    assert_equal 'write_failed', result.errors.first.params['reason']
    assert_match(/placement/, result.errors.first.params['detail'])
    assert_equal %i[start abort], kinds_after_creation
  end

  def test_refused_commit_returns_no_reference
    created
    model.commit_result = false
    result = regenerate
    assert_nil result.value
    assert_equal %i[start commit abort], kinds_after_creation
  end

  # --- Jetons

  def tokens
    @tokens ||= Archgen::UI::TargetTokens.new
  end

  def test_token_resolves_to_target_for_its_model_only
    token = tokens.issue(:cible, model: model)
    assert_equal :cible, tokens.resolve(token, model: model).value
    assert_equal 'other_model', tokens.resolve(token, model: FakeSketchUp::ServiceModel.new).errors.first.params['reason']
  end

  def test_forged_or_cleared_token_is_stale
    assert_equal 'unknown_token', tokens.resolve('forgé', model: model).errors.first.params['reason']
    assert_equal 'unknown_token', tokens.resolve(12, model: model).errors.first.params['reason']
    token = tokens.issue(:cible, model: model)
    tokens.clear
    assert_equal 'E_TARGET_STALE', tokens.resolve(token, model: model).errors.first.code
  end

  def test_token_is_opaque_and_store_is_bounded
    token = tokens.issue(:cible, model: model)
    assert_match(/\A\h{32}\z/, token)
    first = token
    64.times { tokens.issue(:autre, model: model) }
    refute tokens.resolve(first, model: model).ok?
  end
end
