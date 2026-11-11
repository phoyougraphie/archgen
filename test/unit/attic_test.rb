# frozen_string_literal: true

require_relative '../test_helper'

# U97 : attique en retrait et garde-corps vitré (AG-135, ADR-63). Le dernier niveau recule de
# `levels.attic_setback_m` depuis la façade avant ; un garde-corps borde la terrasse ; un plan validé.
class AtticTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def build(draft)
    config = ConfigResolver.resolve({ 'schema_version' => 1 }.merge(draft), registry: registry, intake: TestData.intake)
    return config unless config.ok?

    GeometryEngine.generate(config.value, materials: TestData.materials)
  end

  def ids(nodes, out = [])
    nodes.each do |node|
      out << node['id']
      ids(node['children'], out)
    end
    out
  end

  def vertices(nodes, prefix, out = [])
    nodes.each do |node|
      out.concat(node.dig('primitive', 'vertices') || []) if node['id'].start_with?(prefix)
      vertices(node['children'], prefix, out)
    end
    out
  end

  def test_attic_steps_back_with_a_terrace_rail
    base = { 'profile' => { 'id' => 'baule_front_de_mer' }, 'lod' => 1, 'levels' => { 'count' => 8 } }
    flat = build(base)
    attic = build(Merge.leaves(base, 'levels' => { 'attic_setback_m' => 2.5 }))
    assert attic.ok?, attic.errors.map(&:to_h).inspect
    plan = attic.value
    all = ids(plan['nodes'])
    assert_includes all, 'attic'
    assert(all.any? { |id| id.start_with?('attic/balcony/terrace/rail/') }, 'garde-corps de terrasse')
    walls = vertices(plan['nodes'], 'attic/wall')
    assert_operator walls.map { |v| v[1] }.min, :>=, 2.5 - 1e-6
    assert_operator walls.map { |v| v[2] }.min, :>, 7 * 2.7
    assert_in_delta flat.value['metrics']['wall_top_z_m'], plan['metrics']['wall_top_z_m'], 0.5
    assert_equal plan['metrics']['opening_count'], plan['openings'].size
  end

  def test_attic_refusals
    one = build('profile' => { 'id' => 'maison_moderne' }, 'levels' => { 'count' => 1, 'attic_setback_m' => 2 })
    assert_equal ['attic_single_level'], one.errors.map { |d| d.params['reason'] }
    deep = build('profile' => { 'id' => 'maison_moderne' }, 'levels' => { 'attic_setback_m' => 6 })
    assert_equal ['attic_too_deep'], deep.errors.map { |d| d.params['reason'] }
  end

  def test_an_attic_in_a_street
    tree = { 'seed' => 1, 'trace' => { 'points_m' => [[0, 0], [40, 0], [40, 30]], 'closed' => false },
             'building' => { 'profile' => { 'id' => 'baule_front_de_mer' }, 'lod' => 1, 'levels' => { 'attic_setback_m' => 2.0 } } }
    settings = Archgen::Composition.ensemble_intake.settings(tree)
    assert settings.ok?, settings.errors.map(&:to_h).inspect
    result = EnsembleEngine.call(settings.value, registry: registry, intake: TestData.intake, materials: TestData.materials)
    assert result.ok?, result.errors.map(&:to_h).first(3).inspect
  end

  def test_glass_rail_has_a_pane_under_the_handrail
    built = build('profile' => { 'id' => 'baule_front_de_mer' }, 'lod' => 1, 'features' => { 'balcony_rail' => 'glass' })
    assert built.ok?, built.errors.map(&:to_h).inspect
    all = ids(built.value['nodes'])
    assert(all.any? { |id| id.end_with?('/glass') })
    refute(all.any? { |id| id.include?('/bar/') })
  end
end
