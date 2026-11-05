# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter

# Contrat du writer avec doubles : la preuve native reste la recette H02.
class GeometryWriterTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp

  def plan(name)
    config = BuildingConfig.new(TestData.intake.effective(TestData.building(name)).value)
    GeometryEngine.generate(config, materials: TestData.materials).value
  end

  def resources(model = FakeSketchUp::Model.new)
    Resources.new(model, catalog: TestData.materials, revision: 1, host: FakeSketchUp::Host)
  end

  def write(plan, entities: FakeSketchUp::Entities.new, res: resources)
    stats = GeometryWriter.new(host: FakeSketchUp::Host).write(plan, entities: entities, resources: res)
    [stats, entities]
  end

  def group(entities, name)
    entities.items.find { |g| g.is_a?(FakeSketchUp::Group) && g.name == name }
  end

  def wall(entities, id)
    group(group(entities, 'walls').entities, "wall/#{id}")
  end

  def test_face_and_group_counts_match_the_plan
    stats, = write(plan('rect-neutre-shell'))
    assert_equal 218, stats.face_count
    # walls + 4 murs + roof + 1 pan
    assert_equal 7, stats.group_count
    stats, = write(plan('rect-neutre-structural'))
    assert_equal 709, stats.face_count
    # walls + 4 murs + slabs + 3 dalles + roof + 1 pan
    assert_equal 11, stats.group_count
  end

  def test_metres_are_converted_to_inches_exactly_once
    _, entities = write(plan('rect-neutre-shell'))
    xs = wall(entities, 'front').entities.items.flat_map { |f| f.points.map(&:first) }
    assert_in_delta 12.0 / 0.0254, xs.max, 1e-6
    assert_in_delta 0.0, xs.min, 1e-9
  end

  def test_face_winding_is_preserved_when_host_agrees
    _, entities = write(plan('rect-neutre-shell'))
    wall(entities, 'front').entities.items.each do |face|
      assert_equal 0, face.reversals
      assert_operator face.normal.y, :<, 0.0
    end
  end

  def test_flipped_faces_are_reversed_after_the_build_block
    _, entities = write(plan('rect-neutre-shell'), entities: FakeSketchUp::Entities.new(flip_all: true))
    wall(entities, 'front').entities.items.each do |face|
      assert_equal 1, face.reversals
      assert_operator face.normal.y, :<, 0.0
    end
  end

  def test_each_piece_has_its_own_entities
    _, entities = write(plan('rect-neutre-structural'))
    assert_equal %w[wall/front wall/right wall/rear wall/left], group(entities, 'walls').entities.items.map(&:name)
    assert_equal %w[slab/1 slab/2 slab/3], group(entities, 'slabs').entities.items.map(&:name)
    assert_empty(group(entities, 'walls').entities.items.reject { |g| g.is_a?(FakeSketchUp::Group) })
  end

  def test_tags_on_top_containers_only
    _, entities = write(plan('rect-neutre-structural'))
    assert_equal 'ARCHGEN Murs', group(entities, 'walls').layer.name
    assert_equal 'ARCHGEN Dalles', group(entities, 'slabs').layer.name
    assert_equal 'ARCHGEN Toiture', group(entities, 'roof').layer.name
    assert_nil wall(entities, 'front').layer
    assert(wall(entities, 'front').entities.items.none? { |f| f.respond_to?(:layer) && f.layer })
  end

  def test_materials_follow_plan_roles
    _, entities = write(plan('rect-neutre-shell'))
    assert_equal ['ARCHGEN Enduit à la chaux'], wall(entities, 'front').entities.items.map { |f| f.material.name }.uniq
    pan = group(group(entities, 'roof').entities, 'roof/top').entities.items.first
    assert_equal 'ARCHGEN Béton brut', pan.material.name
  end

  # --- Arêtes de grille (ADR-15)

  def edges_of(entities, id)
    wall(entities, id).entities.edges
  end

  def test_shell_hides_only_edges_between_two_cells
    _, entities = write(plan('rect-neutre-shell'))
    edges = edges_of(entities, 'front')
    hidden, visible = edges.partition(&:hidden)
    assert(hidden.all? { |e| e.faces.size == 2 })
    assert(visible.all? { |e| e.faces.size == 1 }, 'contour et baies restent dessinés')
    refute_empty hidden
    refute_empty visible
  end

  def test_shell_hidden_edge_count_matches_cell_adjacencies
    built = plan('rect-neutre-shell')
    stats, entities = write(built)
    # Murs latéraux : 4 cellules empilées, donc 3 arêtes internes.
    assert_equal 3, edges_of(entities, 'right').count(&:hidden)
    total = %w[front right rear left].sum { |id| edges_of(entities, id).count(&:hidden) }
    assert_equal total, stats.hidden_edge_count
  end

  def test_structural_keeps_mitres_and_reveals_drawn
    _, entities = write(plan('rect-neutre-structural'))
    edges_of(entities, 'front').each do |edge|
      assert_equal 2, edge.faces.size, 'pièce fermée'
      normals = edge.faces.map { |f| Geo.unit_normal(f.points) }
      coplanar = Geo.dot(normals[0], normals[1]) > 0.999999
      assert_equal coplanar, edge.hidden
    end
    # Une arête de contour de baie reste visible : la baie se lit.
    assert(edges_of(entities, 'front').any? { |e| !e.hidden })
  end

  def test_coplanar_faces_of_different_materials_keep_their_edge
    surface = { 'type' => 'surface',
                'vertices' => [[0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 1.0, 0.0], [0.0, 1.0, 0.0], [2.0, 0.0, 0.0], [2.0, 1.0, 0.0]],
                'faces' => [{ 'indices' => [0, 1, 2, 3], 'material' => 'concrete' }, { 'indices' => [1, 4, 5, 2], 'material' => 'zinc' }] }
    custom = { 'units' => 'm', 'definitions' => {}, 'metrics' => { 'expanded_face_count' => 2 },
               'nodes' => [{ 'id' => 'building', 'category' => 'building', 'children' => [
                 { 'id' => 'p', 'category' => 'slab', 'children' => [], 'primitive' => surface }
               ] }] }
    stats, = write(custom)
    assert_equal 0, stats.hidden_edge_count
  end

  def test_hiding_edges_changes_neither_faces_nor_plan
    built = plan('rect-neutre-structural')
    before = GeometryEngine.plan_digest(built)
    stats, = write(built)
    assert_equal 709, stats.face_count
    assert_equal before, GeometryEngine.plan_digest(built)
  end

  # --- Échecs : levés, jamais masqués, pour l'abandon par le service

  def test_refused_face_raises
    error = assert_raises(WriteError) { write(plan('rect-neutre-shell'), entities: FakeSketchUp::Entities.new(reject_faces: true)) }
    assert_match(/Face refusée/, error.message)
  end

  def test_unexpected_face_count_raises
    error = assert_raises(WriteError) { write(plan('rect-neutre-shell'), entities: FakeSketchUp::Entities.new(extra_face: true)) }
    assert_match(/faces, \d+ attendues/, error.message)
  end

  def test_non_empty_destination_is_refused
    entities = FakeSketchUp::Entities.new
    entities.add_group
    assert_raises(WriteError) { write(plan('rect-neutre-shell'), entities: entities) }
  end

  def test_shared_definitions_are_refused_until_details_exist
    altered = JSON.parse(JSON.generate(plan('rect-neutre-shell')))
    altered['definitions'] = { 'frame' => [] }
    assert_raises(WriteError) { write(altered) }
  end

  def test_wrong_units_refused
    altered = JSON.parse(JSON.generate(plan('rect-neutre-shell')))
    altered['units'] = 'in'
    assert_raises(WriteError) { write(altered) }
  end

  def test_writer_never_opens_an_operation
    # Le double Model n'a pas start_operation ; le writer ne reçoit de toute façon pas le modèle.
    refute_respond_to FakeSketchUp::Model.new, :start_operation
    source = read_utf8('archgen', 'adapters', 'sketchup', 'geometry_writer.rb') + read_utf8('archgen', 'adapters', 'sketchup', 'resources.rb')
    refute_match(/\b(start_operation|commit_operation|abort_operation|active_layer|manifold\?)/, source.gsub(/#.*$/, ''))
  end

  # --- Ressources

  def test_resources_are_marked_and_reused
    model = FakeSketchUp::Model.new
    first = resources(model)
    material = first.material('concrete')
    assert_equal 'material', material.get_attribute('archgen.resource', 'kind')
    assert_equal [0xAA, 0xA9, 0xA4], [material.color.red, material.color.green, material.color.blue]
    assert_same material, resources(model).material('concrete')
    assert_equal 1, model.materials.count
    assert_equal [material], first.created
  end

  def test_user_material_with_same_name_stays_intact
    model = FakeSketchUp::Model.new
    user = model.materials.add('ARCHGEN Béton brut')
    user.color = FakeSketchUp::Color.new(255, 0, 0)
    ours = resources(model).material('concrete')
    refute_same user, ours
    assert_equal 'ARCHGEN Béton brut (2)', ours.name
    assert_equal 255, user.color.red
    assert_empty user.attrs
  end

  def test_user_tag_with_same_name_stays_intact
    model = FakeSketchUp::Model.new
    user = model.layers.add('ARCHGEN Murs')
    ours = resources(model).tag('walls')
    refute_same user, ours
    assert_equal 'ARCHGEN Murs (2)', ours.name
    assert_empty user.attrs
    assert_same ours, resources(model).tag('walls')
  end

  def test_altered_owned_material_is_not_reused
    model = FakeSketchUp::Model.new
    edited = resources(model).material('concrete')
    edited.color = FakeSketchUp::Color.new(1, 2, 3)
    fresh = resources(model).material('concrete')
    refute_same edited, fresh
    assert_equal [1, 2, 3], [edited.color.red, edited.color.green, edited.color.blue]
  end

  def test_other_revision_is_not_reused
    model = FakeSketchUp::Model.new
    old = resources(model).material('concrete')
    newer = Resources.new(model, catalog: TestData.materials, revision: 2, host: FakeSketchUp::Host).material('concrete')
    refute_same old, newer
  end

  def test_unknown_material_raises
    assert_raises(WriteError) { resources.material('unobtainium') }
  end

  def test_category_without_tag_stays_untagged
    assert_nil resources.tag('wall')
  end
end
