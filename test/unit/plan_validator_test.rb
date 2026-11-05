# frozen_string_literal: true

require_relative '../test_helper'

# U09 : le validateur refuse chaque défaut de topologie et de référence.
class PlanValidatorTest < Minitest::Test
  include Archgen::Core

  CUBE_VERTICES = [
    [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [1.0, 1.0, 0.0], [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0], [1.0, 0.0, 1.0], [1.0, 1.0, 1.0], [0.0, 1.0, 1.0]
  ].freeze
  CUBE_FACES = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]].freeze

  def cube_primitive
    { 'type' => 'solid', 'vertices' => CUBE_VERTICES.map(&:dup),
      'faces' => CUBE_FACES.map { |f| { 'indices' => f.dup, 'material' => 'concrete' } } }
  end

  def plan_with(primitive, id: 'p', category: 'slab', definitions: {}, metrics: {})
    faces = primitive['type'] == 'instance' ? 0 : primitive['faces'].size
    {
      'schema_version' => 1, 'engine_version' => '1', 'units' => 'm',
      'nodes' => [{ 'id' => 'building', 'category' => 'building', 'children' => [{ 'id' => id, 'category' => category, 'children' => [], 'primitive' => primitive }] }],
      'definitions' => definitions, 'openings' => [],
      'metrics' => { 'width_m' => 1.0, 'depth_m' => 1.0, 'wall_top_z_m' => 1.0, 'roof_top_z_m' => 1.0, 'opening_count' => 0,
                     'unique_face_count' => faces, 'expanded_face_count' => faces, 'wall_cell_count' => 0, 'detail_definition_count' => definitions.size }.merge(metrics)
    }
  end

  def problems(plan)
    PlanValidator.call(plan, materials: TestData.materials)
  end

  def assert_reason(reason, plan)
    found = problems(plan)
    assert(found.any? { |d| d.params['reason'] == reason }, "attendu #{reason}, reçu #{found.map(&:to_h)}")
  end

  def test_valid_cube_passes
    assert_empty problems(plan_with(cube_primitive))
  end

  def test_open_edge_refused
    primitive = cube_primitive
    primitive['faces'].pop
    assert_reason 'open_edge', plan_with(primitive)
  end

  def test_inconsistent_orientation_refused
    primitive = cube_primitive
    primitive['faces'][0]['indices'].reverse!
    assert_reason 'inconsistent_orientation', plan_with(primitive)
  end

  def test_inverted_solid_has_non_positive_volume
    primitive = cube_primitive
    primitive['faces'].each { |f| f['indices'].reverse! }
    assert_reason 'non_positive_volume', plan_with(primitive)
  end

  def test_non_planar_face_refused
    primitive = cube_primitive
    primitive['vertices'][6] = [1.0, 1.0, 1.1]
    assert_reason 'non_planar_face', plan_with(primitive)
  end

  def test_split_vertex_fan_refused
    # Deux cubes qui ne se touchent que par un sommet partagé : éventail scindé.
    primitive = { 'type' => 'solid', 'vertices' => [], 'faces' => [] }
    add_cube = lambda do |offset|
      index = {}
      CUBE_FACES.each do |face|
        indices = face.map do |v|
          point = CUBE_VERTICES[v].map { |c| Quant.q(c + offset) }
          index[point] ||= begin
            found = primitive['vertices'].index(point)
            found || begin
              primitive['vertices'] << point
              primitive['vertices'].size - 1
            end
          end
        end
        primitive['faces'] << { 'indices' => indices, 'material' => 'concrete' }
      end
    end
    add_cube.call(0.0)
    add_cube.call(1.0)
    assert_reason 'split_vertex_fan', plan_with(primitive)
  end

  def test_disconnected_shell_refused
    primitive = cube_primitive
    far = CUBE_VERTICES.map { |v| v.map { |c| c + 5.0 } }
    primitive['vertices'] += far
    primitive['faces'] += CUBE_FACES.map { |f| { 'indices' => f.map { |i| i + 8 }, 'material' => 'concrete' } }
    assert_reason 'disconnected_shell', plan_with(primitive)
  end

  def test_invalid_index_refused
    primitive = cube_primitive
    primitive['faces'][0]['indices'][0] = 99
    assert_reason 'invalid_indices', plan_with(primitive)
  end

  def test_duplicate_index_in_face_refused
    primitive = cube_primitive
    primitive['faces'][0]['indices'] = [0, 0, 1]
    assert_reason 'invalid_indices', plan_with(primitive)
  end

  def test_short_edge_refused
    surface = { 'type' => 'surface', 'vertices' => [[0.0, 0.0, 0.0], [0.001, 0.0, 0.0], [0.001, 1.0, 0.0], [0.0, 1.0, 0.0]],
                'faces' => [{ 'indices' => [0, 1, 2, 3], 'material' => 'concrete' }] }
    assert_reason 'edge_too_short', plan_with(surface)
  end

  def test_unquantized_vertex_refused
    primitive = cube_primitive
    primitive['vertices'][0] = [0.00000012, 0.0, 0.0]
    assert_reason 'unquantized_vertex', plan_with(primitive)
  end

  def test_unknown_material_refused
    primitive = cube_primitive
    primitive['faces'][0]['material'] = 'unobtainium'
    assert_reason 'unknown_material', plan_with(primitive)
  end

  def test_duplicate_node_id_refused
    plan = plan_with(cube_primitive)
    plan['nodes'].first['children'] << plan['nodes'].first['children'].first
    assert_reason 'duplicate_node_id', plan
  end

  def test_unknown_category_refused
    assert_reason 'unknown_category', plan_with(cube_primitive, category: 'tower')
  end

  def test_primitive_with_children_refused
    plan = plan_with(cube_primitive)
    plan['nodes'].first['children'].first['children'] = [{ 'id' => 'c', 'category' => 'slab', 'children' => [] }]
    assert_reason 'primitive_with_children', plan
  end

  def test_single_building_root_required
    plan = plan_with(cube_primitive)
    plan['nodes'] << plan['nodes'].first
    assert_reason 'single_building_root', plan
  end

  def test_bad_header_refused
    assert_reason 'bad_header', plan_with(cube_primitive).merge('units' => 'in')
  end

  def test_metric_mismatch_refused
    assert_reason 'metric_mismatch', plan_with(cube_primitive, metrics: { 'unique_face_count' => 5 })
  end

  # --- Instances

  IDENTITY = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 2.0, 3.0, 4.0, 1.0].freeze

  def instance_plan(matrix, definition_id: 'def')
    definitions = { 'def' => [{ 'id' => 'piece', 'category' => 'frame', 'children' => [], 'primitive' => cube_primitive }] }
    plan_with({ 'type' => 'instance', 'definition_id' => definition_id, 'matrix' => matrix }, category: 'frame', definitions: definitions,
              metrics: { 'unique_face_count' => 6, 'expanded_face_count' => 6 })
  end

  def test_valid_instance_counts_expanded_faces
    assert_empty problems(instance_plan(IDENTITY))
  end

  def test_missing_definition_refused
    assert_reason 'missing_definition', instance_plan(IDENTITY, definition_id: 'nope')
  end

  def test_scaled_or_mirrored_matrix_refused
    scaled = IDENTITY.dup
    scaled[0] = 2.0
    assert_reason 'non_rigid_matrix', instance_plan(scaled)
    mirrored = IDENTITY.dup
    mirrored[0] = -1.0
    assert_reason 'non_rigid_matrix', instance_plan(mirrored)
  end

  def test_malformed_matrix_refused
    assert_reason 'invalid_matrix', instance_plan([1.0] * 15)
  end

  def test_nested_instance_in_definition_refused
    nested = { 'def' => [{ 'id' => 'i', 'category' => 'frame', 'children' => [], 'primitive' => { 'type' => 'instance', 'definition_id' => 'def', 'matrix' => IDENTITY } }] }
    assert_reason 'nested_instance', plan_with(cube_primitive, definitions: nested)
  end
end
