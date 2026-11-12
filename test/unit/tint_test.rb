# frozen_string_literal: true

require_relative '../test_helper'

# U69 — Teintes (docs/TEINTES_ABORDS_CONTRACT.md, AG-104).
class TintTest < Minitest::Test
  include Archgen

  def config(tint, seed: 7)
    draft = Core::Merge.leaves(TestData.building('rect-neutre-shell'), 'seed' => seed, 'facade' => { 'tint' => tint })
    effective = TestData.intake.effective(draft)
    assert effective.ok?, effective.diagnostics.map(&:to_h).inspect
    Core::BuildingConfig.new(effective.value)
  end

  def generate(tint, seed: 7)
    result = Core::GeometryEngine.generate(config(tint, seed: seed), materials: TestData.materials)
    assert result.ok?, result.diagnostics.map(&:to_h).inspect
    result.value
  end

  def materials_of(plan)
    walk = ->(nodes) { nodes.flat_map { |n| (n.dig('primitive', 'faces') || []).map { |f| f['material'] } + walk.call(n['children']) } }
    (walk.call(plan['nodes']) + plan['definitions'].values.flat_map { |list| walk.call(list) }).uniq
  end

  def test_no_tint_keeps_catalog_materials_and_zero_is_not_written
    draft = { 'schema_version' => 1, 'profile' => { 'id' => 'haussmann' }, 'facade' => { 'tint' => 0 } }
    resolved = Core::ConfigResolver.resolve(draft, registry: Composition.registry.value, intake: TestData.intake)
    assert resolved.ok?, resolved.diagnostics.map(&:to_h).inspect
    refute resolved.value.to_h['facade'].key?('tint')
    plan = Core::GeometryEngine.generate(TestData.intake.effective(TestData.building('rect-neutre-shell')).value.then { |c| Core::BuildingConfig.new(c) }, materials: TestData.materials).value
    assert materials_of(plan).none? { |m| m.include?('~') }
  end

  def test_tint_draws_bounded_variants_from_the_seed
    plan = generate(2)
    tinted = materials_of(plan).grep(/~/)
    refute_empty tinted
    assert(tinted.all? { |m| m.match?(Core::Tint::PATTERN) })
    again = generate(2)
    assert_equal materials_of(plan), materials_of(again)
    other = (1..20).map { |seed| materials_of(generate(2, seed: seed)).grep(/~/).sort }
    assert_operator other.uniq.size, :>, 5, 'des seeds différentes donnent des teintes différentes'
  end

  def test_variant_color_comes_from_catalog_and_stays_close
    catalog = { 'stone' => { 'label' => 'Pierre', 'srgb' => '#c0b090' } }
    entry = Core::Tint.entry(catalog, 'stone~3.8')
    assert_equal 'Pierre (teinte 3.8)', entry['label']
    refute_equal '#c0b090', entry['srgb']
    base = [0xc0, 0xb0, 0x90]
    entry['srgb'].delete_prefix('#').scan(/../).map { |p| p.to_i(16) }.zip(base).each { |c, b| assert_in_delta b, c, 0.2 * b }
    assert_nil Core::Tint.entry(catalog, 'stone~4.1')
    assert_nil Core::Tint.entry(catalog, 'brick~1.1')
  end

  def test_door_differs_from_window_frames
    input = Core::Tint.apply(config(1).geometry_input)
    refute_equal input['materials']['frames'], input['materials']['door']
  end

  def test_neighbours_in_a_street_get_different_tints
    tree = { 'seed' => 3, 'trace' => { 'points_m' => [[0, 0], [48, 0]], 'closed' => false },
             'building' => { 'profile' => { 'id' => 'haussmann' }, 'lod' => 0, 'facade' => { 'tint' => 2 } } }
    settings = Composition.ensemble_intake.settings(tree)
    assert settings.ok?, settings.diagnostics.map(&:to_h).inspect
    result = Core::EnsembleEngine.call(settings.value, registry: Composition.registry.value, intake: Composition.intake,
                                                        materials: Composition.materials.fetch('materials'))
    assert result.ok?, result.diagnostics.map(&:to_h).inspect
    tints = result.value['definitions'].values.map { |plan| materials_of(plan).grep(/~/).sort }
    assert_operator tints.size, :>, 1, 'une définition par maison teintée'
    assert_operator tints.uniq.size, :>, 1
  end
end
