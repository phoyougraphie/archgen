# frozen_string_literal: true

require_relative '../test_helper'

# U66 : dalle de rez-de-chaussée et seuils (docs/CARREFOURS_DALLE_CONTRACT.md, AG-100, ADR-50).
class GroundSlabTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def base
    TestData.intake.effective(TestData.building('rect-neutre-shell')).value
  end

  def plan(blocks = {})
    r = GeometryEngine.generate(BuildingConfig.new(Merge.leaves(base, blocks)), materials: TestData.materials)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def walls(built)
    built['nodes'].first['children'].find { |n| n['id'] == 'walls' }['children']
  end

  def box(node)
    node['primitive']['vertices'].transpose.map(&:minmax)
  end

  def test_shell_gets_a_floor_face_and_a_threshold_under_the_door
    built = plan('structure' => { 'ground_slab' => true })
    slab = walls(built).find { |n| n['id'] == 'wall/ground_slab' }
    assert_equal [[0.0, 12.0], [0.0, 9.0], [0.0, 0.0]], box(slab)
    door = built['openings'].find { |o| o['kind'] == 'door' }
    step = box(walls(built).find { |n| n['id'] == 'wall/threshold/front' })
    assert_equal [door['u_min_m'], door['u_max_m']], step[0]
    assert_equal [-0.2, 0.05], step[1].map { |v| v.round(6) }
    assert_equal [0.0, 0.03], step[2]
  end

  def test_structural_slab_below_zero_and_threshold_through_the_wall
    built = plan('mode' => 'structural', 'structure' => { 'ground_slab' => true })
    assert_equal [-0.2, 0.0], box(walls(built).find { |n| n['id'] == 'wall/ground_slab' })[2]
    assert_in_delta 0.24, box(walls(built).find { |n| n['id'] == 'wall/threshold/front' })[1][1], 1e-6
  end

  def test_absent_means_no_change_and_false_is_not_written
    assert(walls(plan).none? { |n| n['id'].start_with?('wall/ground_slab', 'wall/threshold') })
    assert_empty(walls(plan('structure' => { 'ground_slab' => true }, 'features' => { 'pilotis' => true })).select { |n| n['id'] == 'wall/ground_slab' })
    cfg = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'brutalist' }, 'structure' => { 'ground_slab' => false } },
                                 registry: registry, intake: TestData.intake).value.to_h
    refute cfg['structure'].key?('ground_slab')
  end
end
