# frozen_string_literal: true

require_relative '../test_helper'

# U100 : diversité des maisons de La Baule (AG-140 à AG-142 ; ADR-67). Palette tirée par la graine,
# encadrements d'une matière à eux, ailes sans baie derrière elles, parcelle d'angle laissée en jardin.
class BauleDiversityTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def resolve(draft)
    ConfigResolver.resolve({ 'schema_version' => 1 }.merge(draft), registry: registry, intake: TestData.intake)
  end

  def street(profile, detached: nil, points: [[0, 0], [96, 0]])
    tree = { 'seed' => 7, 'trace' => { 'points_m' => points, 'closed' => false }, 'building' => { 'profile' => { 'id' => profile }, 'lod' => 1 } }
    tree['parcel'] = { 'target_width_m' => 16, 'depth_m' => 22, 'bay_width_m' => 3, 'detached' => detached } if detached
    settings = Archgen::Composition.ensemble_intake.settings(tree)
    assert settings.ok?, settings.errors.map(&:to_h).inspect
    EnsembleEngine.call(settings.value, registry: registry, intake: TestData.intake, materials: TestData.materials)
  end

  def test_each_seed_draws_a_palette_variant
    picks = (1..40).map { |seed| resolve('profile' => { 'id' => 'baule_villa_toit' }, 'seed' => seed).value.to_h['materials'].slice('shutters', 'surrounds', 'wall') }
    assert_operator picks.uniq.size, :>=, 4, 'au moins quatre variantes sur quarante graines'
    assert_equal picks, (1..40).map { |seed| resolve('profile' => { 'id' => 'baule_villa_toit' }, 'seed' => seed).value.to_h['materials'].slice('shutters', 'surrounds', 'wall') }
    own = resolve('profile' => { 'id' => 'baule_villa_toit' }, 'seed' => 3, 'materials' => { 'shutters' => 'painted_wood_green' })
    assert_equal 'painted_wood_green', own.value.to_h['materials']['shutters'], 'un choix explicite passe avant la palette'
  end

  def test_a_variant_without_timber_drops_its_material
    configs = (1..60).map { |seed| resolve('profile' => { 'id' => 'baule_villa', 'revision' => 2 }, 'seed' => seed).value.to_h }
    plain = configs.find { |c| !c['features'].key?('timber_frame') }
    assert plain, 'une variante sans pan de bois'
    refute plain['materials'].key?('timber')
    assert_equal true, plain['features']['surrounds']
    assert(configs.any? { |c| c['features']['timber_frame'] })
  end

  def test_a_street_of_villas_mixes_colours_with_shared_definitions
    result = street('baule_maison_de_ville')
    assert result.ok?, result.errors.map(&:to_h).first(3).inspect
    plan = result.value
    assert_operator plan['metrics']['definition_count'], :>, 1, 'des maisons différentes'
    assert_operator plan['metrics']['definition_count'], :<, plan['metrics']['parcel_count'] + 1
  end

  def test_surrounds_take_their_own_material
    built = GeometryEngine.generate(resolve('profile' => { 'id' => 'baule_maison_de_ville' }, 'lod' => 1, 'materials' => { 'surrounds' => 'red_brick', 'wall' => 'granite' }).value,
                                    materials: TestData.materials)
    assert built.ok?, built.errors.map(&:to_h).inspect
    found = []
    walk = ->(nodes) { nodes.each { |n| found << n if n['category'] == 'surround'; walk.call(n['children']) } }
    walk.call(built.value['nodes'])
    refute_empty found
    assert(found.all? { |n| n['primitive']['faces'].all? { |f| f['material'] == 'red_brick' } })
  end

  def test_wings_leave_no_window_behind_them
    plan = GeometryEngine.generate(resolve('profile' => { 'id' => 'baule_villa', 'revision' => 1 }, 'lod' => 1, 'levels' => { 'count' => 3 },
                                           'wing' => { 'position' => 'both', 'width_m' => 3.5, 'depth_m' => 5, 'levels' => 2 }).value,
                                   materials: TestData.materials)
    assert plan.ok?, plan.errors.map(&:to_h).inspect
    openings = plan.value['openings']
    width = plan.value['metrics']['width_m']
    rear = openings.select { |o| o['facade_id'] == 'rear' && !o['id'].start_with?('wing/') }
    behind = rear.select { |o| o['u_max_m'] > width - 3.5 || o['u_min_m'] < 3.5 }
    assert_empty behind, 'pas de fenêtre du corps derrière une aile'
    assert_empty(openings.select { |o| o['id'].start_with?('wing/') && o['facade_id'] == 'rear' })
  end

  def test_a_narrow_corner_parcel_stays_a_garden
    result = street('baule_villa_toit', detached: { 'side_gap_m' => 4, 'front_setback_m' => 5, 'building_depth_m' => 9 }, points: [[0, 0], [60, 0], [60, 40]])
    assert result.ok?, result.errors.map(&:to_h).first(3).inspect
    assert(result.diagnostics.any? { |d| d.params['reason'] == 'detached_parcel_left_empty' })
  end
end
