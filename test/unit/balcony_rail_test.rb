# frozen_string_literal: true

require_relative '../test_helper'

# U71 — Garde-corps des balcons (docs/TEINTES_ABORDS_CONTRACT.md, AG-106).
class BalconyRailTest < Minitest::Test
  include Archgen::Core

  def plan(rail = nil)
    base = TestData.intake.effective(TestData.building('rect-neutre-shell')).value
    features = { 'balcony' => true }
    features['balcony_rail'] = rail if rail
    result = GeometryEngine.generate(BuildingConfig.new(Merge.leaves(base, 'lod' => 1, 'features' => features, 'levels' => { 'count' => 5 })),
                                     materials: TestData.materials)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def balcony_nodes(built)
    Geo.find_nodes(built['nodes'], 'balcony')
  end

  def test_without_the_key_the_balcony_is_unchanged
    assert_equal %w[balcony/2], balcony_nodes(plan).map { |n| n['id'] }
  end

  def test_bars_rail_is_one_metre_high_on_the_three_free_sides
    built = plan('bars')
    nodes = balcony_nodes(built)
    rails = nodes.select { |n| n['id'].match?(%r{\Abalcony/2/rail/\d\z}) }
    assert_equal 3, rails.size
    slab = nodes.find { |n| n['id'] == 'balcony/2' }
    top = slab['primitive']['vertices'].map { |v| v[2] }.max
    rails.each { |r| assert_in_delta top + 1.0, r['primitive']['vertices'].map { |v| v[2] }.max, 1e-6 }
    bars = nodes.select { |n| n['primitive']['type'] == 'instance' }
    assert_operator bars.size, :>, 50
    assert_equal 1, bars.map { |n| n['primitive']['definition_id'] }.uniq.size, 'un barreau partagé'
    front = rails.find { |r| r['id'].end_with?('/1') }['primitive']['vertices'].map { |v| v[1] }.minmax
    assert_in_delta(-0.90, front[0], 1e-6)
    assert(bars.all? { |b| b['primitive']['matrix'][13].between?(-0.9, 0.0) })
  end

  def test_solid_rail_is_a_low_wall_of_the_wall_material
    built = plan('solid')
    rails = balcony_nodes(built).select { |n| n['id'].include?('/rail/') }
    assert_equal 3, rails.size
    wall = TestData.intake.effective(TestData.building('rect-neutre-shell')).value['materials']['wall']
    assert(rails.all? { |r| r['primitive']['faces'].all? { |f| f['material'] == wall } })
    assert(balcony_nodes(built).none? { |n| n['primitive']['type'] == 'instance' })
  end

  def test_none_is_not_written
    cfg = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'haussmann' }, 'features' => { 'balcony_rail' => 'none' } },
                                 registry: Archgen::Composition.registry.value, intake: TestData.intake)
    assert cfg.ok?, cfg.diagnostics.map(&:to_h).inspect
    refute cfg.value.to_h['features'].key?('balcony_rail')
  end
end
