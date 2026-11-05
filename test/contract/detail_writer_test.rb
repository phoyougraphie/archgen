# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter

# Écriture des détails et cadres partagés, avec doubles. La preuve native est H08.
class DetailWriterTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp

  def plan(mode: 'shell', **blocks)
    base = TestData.intake.effective(TestData.building('rect-neutre-shell')).value
    config = BuildingConfig.new(Merge.leaves(base, { 'lod' => 1, 'mode' => mode }.merge(blocks.transform_keys(&:to_s))))
    result = GeometryEngine.generate(config, materials: TestData.materials)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def model
    @model ||= FakeSketchUp::ServiceModel.new
  end

  def resources
    Resources.new(model, catalog: TestData.materials, revision: 1, host: FakeSketchUp::Host)
  end

  def write(built, res: resources)
    entities = FakeSketchUp::Entities.new
    stats = GeometryWriter.new(host: FakeSketchUp::Host).write(built, entities: entities, resources: res)
    [stats, entities]
  end

  def details(entities)
    entities.items.find { |g| g.is_a?(FakeSketchUp::Group) && g.name == 'details' }
  end

  def frame_instances(entities)
    details(entities).entities.items.select { |i| i.is_a?(FakeSketchUp::Instance) }
  end

  def test_expanded_faces_are_counted_through_instances
    built = plan
    stats, = write(built)
    assert_equal built['metrics']['expanded_face_count'], stats.face_count
  end

  def test_one_definition_per_key_across_all_openings
    _, entities = write(plan)
    instances = frame_instances(entities)
    assert_equal 32, instances.size
    assert_equal 2, instances.map(&:definition).uniq.size
    assert_equal 2, model.definition_list.size
  end

  def test_each_definition_has_its_bars_in_their_own_entities
    _, entities = write(plan)
    door = frame_instances(entities).find { |i| i.name == 'frame/front/0/1' }.definition
    window = frame_instances(entities).find { |i| i.name == 'frame/front/0/0' }.definition
    assert_equal %w[bar/left bar/right bar/top], door.entities.items.map(&:name)
    assert_equal %w[bar/left bar/right bar/top bar/bottom], window.entities.items.map(&:name)
  end

  def test_translation_alone_is_converted_to_inches
    _, entities = write(plan)
    matrix = frame_instances(entities).find { |i| i.name == 'frame/front/1/0' }.transform.to_a
    assert_in_delta 1.35 / 0.0254, matrix[12], 1e-6
    assert_in_delta 4.05 / 0.0254, matrix[14], 1e-6
    assert_equal 1.0, matrix[0], 'la rotation reste sans unité'
    assert_equal 1.0, matrix[15]
  end

  def test_details_group_is_tagged_and_instances_are_not
    _, entities = write(plan)
    assert_equal 'ARCHGEN Détails', details(entities).layer.name
    assert(frame_instances(entities).all? { |i| i.layer.nil? })
  end

  def test_second_write_reuses_valid_definitions
    write(plan)
    created = model.definition_list.dup
    _, entities = write(plan)
    assert_equal created, model.definition_list
    assert_equal created.sort_by(&:object_id), frame_instances(entities).map(&:definition).uniq.sort_by(&:object_id)
  end

  def test_shell_and_structural_share_definitions
    write(plan)
    count = model.definition_list.size
    write(plan(mode: 'structural'))
    assert_equal count, model.definition_list.size, 'le recul vit dans la matrice'
  end

  def test_other_frame_size_creates_another_definition
    write(plan)
    count = model.definition_list.size
    write(plan(facade: { 'window_width_m' => 1.3 }))
    assert_equal count + 1, model.definition_list.size
  end

  def test_altered_definition_is_not_reused_and_stays_intact
    write(plan)
    altered = model.definition_list.first
    altered.entities.items.first.entities.items.pop
    faces = altered.entities.items.first.entities.items.size
    write(plan)
    assert_equal 3, model.definition_list.size
    assert_equal faces, altered.entities.items.first.entities.items.size
  end

  def test_user_definition_with_same_name_is_ignored
    user = model.add_definition('ARCHGEN frame window 1200000x1800000 painted_wood')
    write(plan)
    assert_empty user.entities.items
    assert_empty user.attrs
    assert_equal 3, model.definition_list.size
  end

  def test_other_engine_version_is_not_reused
    write(plan)
    model.definition_list.each { |d| d.set_attribute('archgen.resource', 'engine_version', '0') }
    write(plan)
    assert_equal 4, model.definition_list.size
  end

  def test_missing_definition_raises
    altered = JSON.parse(JSON.generate(plan))
    altered['definitions'] = {}
    assert_raises(WriteError) { write(altered) }
  end

  def test_face_refused_inside_definition_raises
    model.writer_behaviour = { reject_faces: true }
    entities = FakeSketchUp::Entities.new
    built = plan
    # Le premier mur passe (destination saine), la définition échoue.
    assert_raises(WriteError) do
      GeometryWriter.new(host: FakeSketchUp::Host).write(built, entities: entities, resources: resources)
    end
  end
end
