# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_terrain'

Archgen::Loader.load_adapter

# Contrat de l'écriture de l'assise, avec doubles. La preuve native est H13.
class SiteWriteTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp

  INCH = FakeTerrain::INCH
  NEUTRAL = { 'schema_version' => 1, 'profile' => { 'id' => 'generic' }, 'name' => 'A', 'mode' => 'shell' }.freeze
  SITE = 'archgen.site'
  BUILDING = 'archgen.building'
  Injected = Class.new(StandardError)

  def registry
    StyleRegistry.load(TestData.profiles, schema: TestData.schemas['profile'], config_validator: SchemaValidator.new(TestData.schemas['config']),
                                          capabilities: StyleRegistry::KNOWN_CAPABILITIES, materials: TestData.materials).value
  end

  def service(**ports)
    BuildingService.new(registry: registry, intake: TestData.intake, materials: TestData.materials, material_revision: 1,
                        allow_internal: true, host: FakeTerrain::Host, **ports)
  end

  # Sol à 8 % dans la direction du X du modèle ; la grille suit le bâtiment.
  def slope_answer(gradient = 0.08)
    lambda do |origin|
      x, y, = origin.to_a
      [FakeTerrain::Point.new(x, y, (100.0 + (gradient * x * INCH)) / INCH), [@terrain]]
    end
  end

  def setup
    @model = FakeTerrain::RayModel.new
    @terrain = FakeTerrain::Solid.new(777, @model)
    @model.solids << @terrain
    @service = service
    @created = @service.create(model: @model, draft: NEUTRAL)
    raise @created.errors.map(&:to_h).inspect unless @created.ok?

    @root = @created.value
    @instance = @model.instances.first
    @model.selection.replace([@terrain])
    @ref = @service.retain_terrain(model: @model).value
    @model.selection.replace([@instance])
    @model.ray_answer = slope_answer
  end

  def adapt(site = {}, **options)
    @service.adapt_to_site(model: @model, target: @root.target, terrain: @ref, site: site, **options)
  end

  def adapted(site = {})
    result = adapt(site)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result
  end

  def site_attr(key, instance = @instance)
    instance.get_attribute(SITE, key)
  end

  def kinds(from = @operations_before)
    @model.operations.drop(from || 2).map(&:first)
  end

  def snapshot
    [@model.definition_list.size, @model.instances.size, @model.materials.count, @model.layers.count, @instance.definition,
     @instance.attrs.dup, @instance.transformation.to_a]
  end

  def z_m(instance = @instance)
    instance.transformation.to_a[14] * INCH
  end

  def assert_refused(result, code, path = nil, reason = nil)
    refute result.ok?, 'attendu un refus'
    found = result.errors.find { |d| d.code == code && (path.nil? || d.path == path) }
    assert found, result.errors.map(&:to_h).inspect
    assert_equal reason, found.params['reason'] if reason
  end

  # --- Aperçu

  def test_preview_writes_nothing
    before = snapshot
    count = @model.operations.size
    preview = @service.preview_site(model: @model, target: @root.target, terrain: @ref, site: {})
    assert preview.ok?, preview.errors.map(&:to_h).inspect
    assert_equal count, @model.operations.size
    assert_equal before, snapshot
    assert_in_delta 100.96, preview.value.survey.assise['platform_z_m']
    assert_equal Archgen::Geometry::SitePlanner.digest(preview.value.site_plan), preview.value.site_digest
    assert(preview.diagnostics.any? { |d| d.code == 'W_SITE_DOOR_GAP' })
  end

  def test_preview_refusal_keeps_the_document
    before = snapshot
    assert_refused @service.preview_site(model: @model, target: @root.target, terrain: @ref, site: { 'evil' => 1 }), 'E_SCHEMA', '/site/evil'
    assert_equal before, snapshot
  end

  # --- Écriture

  def test_adapting_is_one_operation_with_its_own_name
    count = @model.operations.size
    adapted
    assert_equal [[:start, 'ARCHGEN : adapter au terrain', true], [:commit]], @model.operations.drop(count)
  end

  def test_root_keeps_identity_and_only_its_altitude_changes
    moved = FakeSketchUp::IDENTITY.dup
    moved[12] = 40.0
    moved[13] = 50.0
    @instance.transformation = FakeSketchUp::Transformation.new(moved)
    pid = @instance.persistent_id
    old_definition = @instance.definition
    faces = old_definition.entities.items.size
    adapted
    now = @instance.transformation.to_a
    assert_equal pid, @instance.persistent_id
    assert_equal [40.0, 50.0], now[12, 2]
    assert_equal moved.first(12), now.first(12)
    assert_in_delta 100.96 + (0.08 * 40.0 * INCH), z_m, 1e-4
    refute_same old_definition, @instance.definition, 'définition fraîche'
    assert_equal faces, old_definition.entities.items.size, 'ancienne définition intacte'
  end

  def test_revision_grows_and_building_data_stay
    plan_before = @instance.get_attribute(BUILDING, 'plan_digest')
    config_before = @instance.get_attribute(BUILDING, 'config_json')
    summary = adapted.value
    assert_equal 2, summary.revision
    assert_equal plan_before, @instance.get_attribute(BUILDING, 'plan_digest'), 'plan du bâtiment inchangé'
    assert_equal config_before, @instance.get_attribute(BUILDING, 'config_json')
    assert_in_delta 100.96, summary.site_metrics['platform_z_m']
  end

  def test_site_attributes_are_written_in_their_own_dictionary
    adapted
    assert_equal 1, site_attr('site_version')
    assert_equal 777, site_attr('terrain_pid')
    assert_match(/\A\h{64}\z/, site_attr('survey_digest'))
    assert_match(/\A\h{64}\z/, site_attr('site_digest'))
    assert_equal 'plinth', JSON.parse(site_attr('site_json'))['earthwork']
    assert_equal [0.0, 0.0, 1.0, 0.0], JSON.parse(site_attr('placement_json'))
  end

  def test_definition_holds_the_building_and_the_site
    adapted
    definition = @instance.definition
    groups = definition.entities.items.grep(FakeSketchUp::Group)
    assert_includes groups.map(&:name), 'site'
    assert_includes groups.map(&:name), 'walls'
    assert_equal 'ARCHGEN Terrassement', groups.find { |g| g.name == 'site' }.layer.name
  end

  def test_plinth_material_is_created_and_earth_only_with_a_talus
    adapted
    assert_nil @model.materials['ARCHGEN Terre']
    edit = @service.adapt_to_site(model: @model, target: @service.load_selection(model: @model).value.target, terrain: @ref, site: { 'earthwork' => 'embankment' })
    assert edit.ok?, edit.errors.map(&:to_h).inspect
    refute_nil @model.materials['ARCHGEN Terre']
  end

  def test_terrain_is_never_written
    adapted
    assert_empty @terrain.attrs
    @model.operations.each { |op| refute_equal :terrain, op.first }
  end

  def test_warnings_reach_the_caller
    assert(adapted.diagnostics.any? { |d| d.code == 'W_SITE_DOOR_GAP' })
  end

  # --- Refus avant toute opération

  def assert_no_operation
    count = @model.operations.size
    before = snapshot
    yield
    assert_equal count, @model.operations.size, 'aucune opération'
    assert_equal before, snapshot
  end

  def test_terrain_changed_since_the_preview_is_refused
    digest = @service.preview_site(model: @model, target: @root.target, terrain: @ref, site: {}).value.survey.survey_digest
    @model.ray_answer = slope_answer(0.09)
    assert_no_operation { assert_refused adapt({}, survey_digest: digest), 'E_TARGET_STALE', '/target', 'terrain_changed' }
  end

  def test_same_digest_is_accepted
    digest = @service.preview_site(model: @model, target: @root.target, terrain: @ref, site: {}).value.survey.survey_digest
    assert adapt({}, survey_digest: digest).ok?
  end

  def test_stale_target_settings_and_terrain_are_refused
    assert_no_operation { assert_refused adapt({ 'evil' => 1 }), 'E_SCHEMA', '/site/evil' }
    @model.selection.clear
    assert_no_operation { assert_refused adapt, 'E_TARGET_STALE', '/target', 'selection_changed' }
    @model.selection.replace([@instance])
    @terrain.hidden = true
    assert_no_operation { assert_refused adapt, 'E_SITE_TERRAIN', '/site/terrain', 'terrain_hidden' }
  end

  def test_buried_door_is_refused_before_writing
    assert_no_operation { assert_refused adapt({ 'platform' => { 'offset_m' => -2 } }), 'E_SITE_DOOR_BURIED', '/site/platform' }
  end

  def test_newer_engine_is_refused
    @instance.set_attribute(BUILDING, 'engine_version', '999')
    assert_no_operation { assert_refused adapt, 'E_VERSION', '/metadata/engine_version' }
  end

  # --- Pannes : abandon unique, rien de laissé

  def assert_restored(result)
    refute result.ok?
    assert_equal 'E_WRITE', result.errors.first.code
    assert_equal 'write_failed', result.errors.first.params['reason'], result.errors.map(&:to_h).inspect
    assert_equal @before, snapshot
    assert_equal %i[start abort], @model.operations.drop(@count).map(&:first)
    assert_nil site_attr('site_version')
  end

  def faulty(**ports)
    @before = snapshot
    @count = @model.operations.size
    service(**ports).adapt_to_site(model: @model, target: @root.target, terrain: @ref, site: {})
  end

  def test_failure_while_writing_the_site_is_restored
    writer = GeometryWriter.new(host: FakeTerrain::Host)
    writer.define_singleton_method(:write_site) { |*, **| raise Injected, 'panne pendant l’assise' }
    assert_restored faulty(writer: writer)
  end

  def repository_with(&block)
    ComponentRepository.new(host: FakeTerrain::Host).tap { |r| block.call(r) }
  end

  def test_failure_when_placing_the_root_is_restored
    assert_restored faulty(repository: repository_with { |r| r.define_singleton_method(:place_at_altitude) { |*| raise Injected, 'panne à la pose' } })
  end

  def test_failure_while_storing_the_site_is_restored
    assert_restored(faulty(repository: repository_with do |r|
      r.define_singleton_method(:write_site) do |instance, site|
        instance.set_attribute(ComponentRepository::SITE_DICTIONARY, 'site_version', site['site_version'])
        raise Injected, 'panne au milieu de l’assise'
      end
    end))
  end

  def test_incoherent_site_read_back_is_restored
    assert_restored(faulty(repository: repository_with { |r| r.define_singleton_method(:read_site) { |_instance| nil } }))
  end

  def test_placement_that_moves_x_is_a_failure
    repository = ComponentRepository.new(host: FakeTerrain::Host)
    instance = @instance
    instance.define_singleton_method(:transformation=) do |value|
      values = value.to_a.dup
      values[12] += 1.0
      super(FakeSketchUp::Transformation.new(values))
    end
    assert_raises(WriteError) { repository.place_at_altitude(instance, 5.0) }
  end

  # --- Annuler : le double rend l'état d'ouverture de l'opération

  def test_rollback_of_a_commit_failure_restores_altitude_and_attributes
    before = snapshot
    @model.commit_result = false
    result = adapt
    assert_equal 'commit_failed', result.errors.first.params['reason']
    assert_equal before, snapshot
  end

  # --- Régénérer garde l'assise

  def reload_target
    @service.load_selection(model: @model).value.target
  end

  def test_regenerating_keeps_the_site_and_follows_the_new_footprint
    adapted
    digest = site_attr('site_digest')
    result = @service.regenerate(model: @model, target: reload_target, draft: { 'schema_version' => 1, 'footprint' => { 'width_m' => 14.0 } })
    assert result.ok?, result.errors.map(&:to_h).inspect
    refute_equal digest, site_attr('site_digest'), 'nouvelle emprise, nouvelle assise'
    assert_equal 3, result.value.revision
    assert_in_delta 100.0 + (0.08 * 14.0), z_m, 1e-4
    assert_includes @instance.definition.entities.items.grep(FakeSketchUp::Group).map(&:name), 'site'
  end

  def test_regenerating_after_a_move_reads_the_new_place
    adapted
    moved = @instance.transformation.to_a.dup
    moved[12] = 100.0 / INCH
    @instance.transformation = FakeSketchUp::Transformation.new(moved)
    result = @service.regenerate(model: @model, target: reload_target, draft: { 'schema_version' => 1 })
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_in_delta 100.0 + (0.08 * 112.0), z_m, 1e-4
    assert_equal [100.0, 0.0, 1.0, 0.0], JSON.parse(site_attr('placement_json'))
  end

  def test_regenerating_when_the_terrain_is_gone_is_refused
    adapted
    target = reload_target
    @model.solids.clear
    count = @model.operations.size
    before = snapshot
    result = @service.regenerate(model: @model, target: target, draft: { 'schema_version' => 1 })
    assert_refused result, 'E_SITE_TERRAIN', '/site/terrain', 'terrain_missing'
    assert_equal count, @model.operations.size
    assert_equal before, snapshot
    refute_nil site_attr('site_version'), 'jamais de retrait silencieux'
  end

  def test_regenerating_without_a_site_is_unchanged
    count = @model.ray_count
    result = @service.regenerate(model: @model, target: @root.target, draft: { 'schema_version' => 1, 'footprint' => { 'width_m' => 14.0 } })
    assert result.ok?
    assert_equal count, @model.ray_count, 'aucun rayon sans assise'
    assert_nil site_attr('site_version')
    assert_equal 0.0, z_m
    assert_nil result.value.site_metrics
  end

  def test_copy_is_read_at_its_own_place_and_the_original_stays
    adapted
    copy = @model.copy_instance(@instance)
    moved = FakeSketchUp::IDENTITY.dup
    moved[12] = 200.0 / INCH
    copy.transformation = FakeSketchUp::Transformation.new(moved)
    original = [@instance.definition, @instance.attrs.dup, @instance.transformation.to_a]
    @model.selection.replace([copy])
    result = @service.regenerate(model: @model, target: @service.load_selection(model: @model).value.target, draft: { 'schema_version' => 1 })
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal original, [@instance.definition, @instance.attrs, @instance.transformation.to_a]
    assert_in_delta 100.0 + (0.08 * 212.0), z_m(copy), 1e-4
    refute_equal @instance.get_attribute(BUILDING, 'building_uuid'), copy.get_attribute(BUILDING, 'building_uuid')
  end

  # --- Retirer

  def test_removing_keeps_altitude_and_clears_the_dictionary
    adapted
    altitude = z_m
    count = @model.operations.size
    result = @service.remove_site(model: @model, target: reload_target)
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal [[:start, 'ARCHGEN : retirer l’assise', true], [:commit]], @model.operations.drop(count)
    assert_equal altitude, z_m
    assert_nil site_attr('site_version')
    refute_includes @instance.definition.entities.items.grep(FakeSketchUp::Group).map(&:name), 'site'
  end

  def test_removing_without_a_site_is_refused
    count = @model.operations.size
    assert_refused @service.remove_site(model: @model, target: @root.target), 'E_TARGET_STALE', '/target', 'site_absent'
    assert_equal count, @model.operations.size
  end

  def test_failed_removal_keeps_the_site
    adapted
    @model.commit_result = false
    result = @service.remove_site(model: @model, target: reload_target)
    refute result.ok?
    refute_nil site_attr('site_version')
  end

  # --- Lecture

  def test_status_of_a_building_without_a_site_is_nil
    result = @service.site_status(model: @model, target: @root.target)
    assert result.ok?
    assert_nil result.value
  end

  def test_status_reports_settings_and_movement
    adapted('earthwork' => 'embankment')
    target = reload_target
    status = @service.site_status(model: @model, target: target).value
    assert_equal 'embankment', status['settings']['earthwork']
    assert_equal 777, status['terrain_pid']
    assert_equal false, status['moved']
    moved = @instance.transformation.to_a.dup
    moved[13] = 50.0
    @instance.transformation = FakeSketchUp::Transformation.new(moved)
    assert_equal true, @service.site_status(model: @model, target: target).value['moved']
  end

  def test_altitude_alone_does_not_count_as_a_move
    adapted
    target = reload_target
    moved = @instance.transformation.to_a.dup
    moved[14] = 0.0
    @instance.transformation = FakeSketchUp::Transformation.new(moved)
    assert_equal false, @service.site_status(model: @model, target: target).value['moved']
  end

  # --- Attributs altérés

  def test_future_site_version_is_readable_but_not_writable
    adapted
    target = reload_target
    @instance.set_attribute(SITE, 'site_version', 2)
    assert @service.load_selection(model: @model).ok?, 'consultable'
    assert_no_operation { assert_refused @service.regenerate(model: @model, target: target, draft: { 'schema_version' => 1 }), 'E_VERSION', '/metadata/site/site_version' }
    assert_no_operation { assert_refused @service.remove_site(model: @model, target: target), 'E_VERSION', '/metadata/site/site_version' }
    assert_refused @service.site_status(model: @model, target: target), 'E_VERSION'
  end

  def test_tampered_site_fields_are_located
    adapted
    target = reload_target
    { 'site_json' => 12, 'survey_digest' => 'x', 'site_digest' => nil, 'terrain_pid' => 'abc', 'placement_json' => 3 }.each do |key, value|
      original = site_attr(key)
      @instance.set_attribute(SITE, key, value)
      assert_refused @service.regenerate(model: @model, target: target, draft: { 'schema_version' => 1 }), 'E_SCHEMA', "/metadata/site/#{key}", 'invalid_metadata'
      @instance.set_attribute(SITE, key, original)
    end
  end

  def test_tampered_settings_are_refused
    adapted
    target = reload_target
    @instance.set_attribute(SITE, 'site_json', '{"evil":1}')
    assert_refused @service.regenerate(model: @model, target: target, draft: { 'schema_version' => 1 }), 'E_SCHEMA', '/site/evil'
  end

  def test_every_new_reason_has_a_message
    %w[terrain_changed site_absent].each { |reason| assert Archgen::UI::Messages::REASONS.key?(reason), reason }
  end
end
