# frozen_string_literal: true

require_relative '../test_helper'

# U20 : accès à la cour par interruption (docs/ENSEMBLE_CONTRACT.md, Accès à la cour).
class AccessPlannerTest < Minitest::Test
  include Archgen::Core

  Planner = Archgen::Geometry::AccessPlanner
  Planar = Archgen::Geometry::Planar
  SQUARE = [[0, 0], [40, 0], [40, 40], [0, 40]].freeze
  RANDOM_CASES = 100
  SUITE_SEED = 20_261_107

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def intake
    @intake ||= Archgen::Composition.intake
  end

  def settings(points = SQUARE, profile: 'brutalist', seed: 1, access: {}, parcel: {}, building: {})
    tree = { 'seed' => seed, 'trace' => { 'points_m' => points, 'closed' => true }, 'access' => access, 'parcel' => parcel,
             'building' => { 'profile' => { 'id' => profile } }.merge(building) }
    result = Archgen::Composition.ensemble_intake.settings(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def final(value = settings)
    result = EnsembleEngine.layout_for(value, registry: registry)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def engine(value = settings)
    EnsembleEngine.call(value, registry: registry, intake: intake, materials: Archgen::Composition.materials.fetch('materials'))
  end

  # --- Nombre d'accès

  def test_automatic_count_follows_the_perimeter
    assert_equal 1, Planner.access_count('auto', 79.999)
    assert_equal 2, Planner.access_count('auto', 80.0)
    assert_equal 2, Planner.access_count('auto', 159.999)
    assert_equal 3, Planner.access_count('auto', 160.0)
    assert_equal 2, Planner.access_count(2, 500.0)
  end

  # --- Carré de référence, calculé à la main

  def test_reference_square_gets_three_accesses_on_three_sides
    value = final
    assert_equal 3, value['accesses'].size
    assert_equal 3, value['metrics']['access_count']
    assert_equal 9, value['parcels'].size
    assert_equal 9, value['metrics']['parcel_count']
    assert_equal 3, value['accesses'].map { |a| a['segment'] }.uniq.size
    value['accesses'].each { |a| assert_equal 'gap', a['form'] }
  end

  def test_accesses_are_never_at_a_corner
    value = final
    value['accesses'].each { |a| assert_match(%r{\Aring/\d/1\z}, a['id']) }
    assert(value['parcels'].none? { |p| value['accesses'].any? { |a| a['id'] == p['id'] } }, 'la parcelle a disparu')
  end

  def test_neighbours_grow_equally_up_to_the_gap
    # Côté 40 : 12, 16, 12. Vide de 3,5 : chaque voisine gagne 6,25 m.
    value = final
    access = value['accesses'].first
    side = value['parcels'].select { |p| p['segment'] == access['segment'] }
    assert_equal 2, side.size
    side.each { |p| assert_equal 18.25, p['width_m'] }
    side.each { |p| assert_equal 9.25, p['rear_m'] }
  end

  def test_the_gap_has_the_exact_width
    value = final
    access = value['accesses'].first
    first, second = value['parcels'].select { |p| p['segment'] == access['segment'] }
    gap = Planar.length(Planar.sub(second['ring_m'][0], first['ring_m'][1]))
    assert_in_delta 3.5, gap, 1e-5
    rear = Planar.length(Planar.sub(second['ring_m'][3], first['ring_m'][2]))
    assert_in_delta 3.5, rear, 1e-5
  end

  def test_gap_width_follows_the_setting
    value = final(settings(access: { 'width_m' => 5.0 }))
    access = value['accesses'].first
    first, second = value['parcels'].select { |p| p['segment'] == access['segment'] }
    assert_in_delta 5.0, Planar.length(Planar.sub(second['ring_m'][0], first['ring_m'][1])), 1e-5
  end

  def test_the_fourth_side_stays_whole
    value = final
    free = (0..3).to_a - value['accesses'].map { |a| a['segment'] }
    assert_equal 1, free.size
    assert_equal [12.0, 16.0, 12.0], value['parcels'].select { |p| p['segment'] == free.first }.map { |p| p['width_m'] }
  end

  def test_extended_parcels_keep_their_mitre
    value = final
    access = value['accesses'].first
    first, second = value['parcels'].select { |p| p['segment'] == access['segment'] }
    assert_equal 9.0, first['delta_left_m']
    assert_equal 9.0, second['delta_right_m']
    assert_equal [[0.0, 0.0], [18.25, 0.0], [18.25, 9.0], [9.0, 9.0]], first['local_ring_m']
  end

  # --- Reproductibilité

  def test_same_seed_same_placement
    assert_equal final['accesses'], final['accesses']
  end

  def test_order_of_sides_follows_the_seed
    assert_equal 1, final(settings(access: { 'count' => 1 }))['accesses'].size
    sides = (1..24).map { |seed| final(settings(seed: seed, access: { 'count' => 1 }))['accesses'].first['segment'] }
    assert_equal [0, 1, 2, 3], sides.uniq.sort, 'toutes les graines ne donnent pas le même côté'
  end

  def test_explicit_count_is_honoured
    [1, 2, 3].each { |count| assert_equal count, final(settings(access: { 'count' => count }))['accesses'].size }
  end

  # --- Refus, sans réduire

  def test_an_impossible_count_is_refused
    # Carré de 20 m, D = 4 : δ = 4, deux parcelles d'angle de 10 m sur chaque côté, aucune candidate.
    tree = settings([[0, 0], [20, 0], [20, 20], [0, 20]], parcel: { 'depth_m' => 4 })
    result = EnsembleEngine.layout_for(tree, registry: registry)
    refute result.ok?
    found = result.errors.first
    assert_equal 'E_STREET_ACCESS', found.code
    assert_equal '/access/count', found.path
    assert_equal 'access_no_room', found.params['reason']
    assert_equal 0, found.params['placed']
  end

  def test_two_accesses_on_one_side_are_never_neighbours
    # Longs côtés de 150 m, petits côtés sans candidate : trois accès sur deux côtés.
    value = final(settings([[0, 0], [150, 0], [150, 22], [0, 22]], parcel: { 'depth_m' => 4 }, access: { 'count' => 3 }))
    by_side = value['accesses'].group_by { |a| a['segment'] }
    assert_equal 2, by_side.size
    pair = by_side.values.find { |list| list.size == 2 }
    refute_nil pair, by_side.inspect
    ranks = pair.map { |a| a['id'].split('/').last.to_i }
    assert_operator (ranks[0] - ranks[1]).abs, :>, 1, ranks.inspect
  end

  def test_access_narrower_than_the_parcel_only
    # Parcelle du milieu de 16 m : un accès de 6 m tient ; des parcelles de 6 m n'en accepteraient pas.
    tight = settings([[0, 0], [40, 0], [40, 40], [0, 40]], access: { 'width_m' => 6.0, 'count' => 1 }, parcel: { 'target_width_m' => 6 })
    value = EnsembleEngine.layout_for(tight, registry: registry)
    refute value.ok?, 'à 6 m de large, une parcelle droite de 6 m ne peut pas céder un vide de 6 m'
    assert_equal 'access_no_room', value.errors.first.params['reason']
  end

  def test_profile_without_a_form_cannot_close
    rules = { 'schema_version' => 1, 'access_forms' => { 'brutalist' => { '1' => 'gap' } } }
    result = EnsembleEngine.layout_for(settings(profile: 'haussmann'), registry: registry, rules: rules)
    refute result.ok?
    found = result.errors.first
    assert_equal 'E_STREET_ACCESS', found.code
    assert_equal 'access_form_unavailable', found.params['reason']
    assert_equal 'haussmann', found.params['id']
  end

  def test_unknown_form_in_the_catalog_is_refused
    rules = { 'schema_version' => 1, 'access_forms' => { 'brutalist' => { '1' => 'tunnel' } } }
    result = EnsembleEngine.layout_for(settings, registry: registry, rules: rules)
    assert_equal 'access_form_unavailable', result.errors.first.params['reason']
  end

  def test_catalog_is_read_by_exact_revision
    rules = { 'schema_version' => 1, 'access_forms' => { 'brutalist' => { '3' => 'gap' } } }
    result = EnsembleEngine.layout_for(settings, registry: registry, rules: rules)
    assert_equal 'access_form_unavailable', result.errors.first.params['reason']
  end

  def test_profile_is_required_to_close
    tree = { 'trace' => { 'points_m' => SQUARE, 'closed' => true } }
    value = Archgen::Composition.ensemble_intake.settings(tree).value
    result = EnsembleEngine.layout_for(value, registry: registry)
    assert_equal 'E_PROFILE_UNAVAILABLE', result.errors.first.code
    assert_equal '/building/profile', result.errors.first.path
  end

  # --- Plan complet

  def test_plan_of_the_reference_square
    result = engine
    assert result.ok?, result.errors.map(&:to_h).inspect
    plan = result.value
    assert_equal 9, plan['metrics']['parcel_count']
    assert_equal 3, plan['metrics']['access_count']
    assert_equal 160.0, plan['metrics']['facade_length_m']
    assert_equal 3, plan['accesses'].size
    assert_equal 9, plan['parcels'].size
    assert_equal EnsembleEngine.digest(plan), EnsembleEngine.digest(engine.value)
  end

  def test_neighbours_stay_complete_buildings
    value = settings(building: { 'mode' => 'structural', 'lod' => 1 })
    result = engine(value)
    assert result.ok?, result.errors.map(&:to_h).inspect
    side = final(value)['parcels'].find { |p| p['width_m'] == 18.25 }
    row = result.value['definitions'][result.value['parcels'].find { |p| p['id'] == side['id'] }['definition_id']]
    walls = row['nodes'].first['children'].find { |n| n['category'] == 'walls' }
    assert_equal 4, walls['children'].size
    assert_equal 6, ParcelBuilding.bays(18.25, 3.0, 1)
    assert_equal 18.25, row['metrics']['width_m']
  end

  def test_open_street_has_no_access
    tree = { 'trace' => { 'points_m' => [[0, 0], [60, 0]], 'closed' => false }, 'building' => { 'profile' => { 'id' => 'brutalist' } } }
    value = Archgen::Composition.ensemble_intake.settings(tree).value
    assert_empty EnsembleEngine.call(value, registry: registry, intake: intake).value['accesses']
    assert_equal 0, EnsembleEngine.layout_for(value, registry: registry).value['metrics'].fetch('access_count', 0)
  end

  # --- Contours pseudo-aléatoires

  def test_no_accepted_closed_form_lacks_an_access
    random = Random.new(SUITE_SEED)
    accepted = 0
    RANDOM_CASES.times do |index|
      value = settings(random_contour(random), seed: random.rand(1000), parcel: { 'depth_m' => 4.0 + (random.rand * 5.0), 'target_width_m' => 8.0 + (random.rand * 8.0) })
      result = EnsembleEngine.layout_for(value, registry: registry)
      message = "suite #{SUITE_SEED}, cas #{index}"
      unless result.ok?
        assert((result.errors.map(&:code) - %w[E_STREET_TRACE E_STREET_CORNER E_STREET_OVERLAP E_STREET_BUDGET E_STREET_ACCESS]).empty?, message)
        next
      end
      accepted += 1
      assert_operator result.value['accesses'].size, :>=, 1, message
      assert_equal result.value['accesses'].size, Planner.access_count('auto', result.value['metrics']['facade_length_m']), message
      assert_no_overlap(result.value['parcels'], message)
      assert_gaps(result.value, value, message)
    end
    assert_operator accepted, :>=, RANDOM_CASES / 4, 'la suite doit couvrir de vrais îlots'
  end

  private

  def random_contour(random)
    count = 3 + random.rand(4)
    raw = (0...count).map do |i|
      angle = (i + (random.rand * 0.6)) * 2 * Math::PI / count
      radius = 40.0 + (random.rand * 40.0)
      [radius * Math.cos(angle), radius * Math.sin(angle)]
    end
    raw.map { |x, y| [(x - raw[0][0]).round(3), (y - raw[0][1]).round(3)] }
  end

  def assert_no_overlap(parcels, message)
    parcels.combination(2).each do |a, b|
      assert_operator Planar.convex_distance(a['ring_m'], b['ring_m']), :>=, 0.0, message
    end
    parcels.each { |p| assert_operator Planar.signed_area(p['ring_m']), :>, 0.0, message }
  end

  def assert_gaps(layout, value, message)
    width = value.dig('access', 'width_m')
    layout['accesses'].each do |access|
      row = layout['parcels'].select { |p| p['segment'] == access['segment'] }
      gaps = row.each_cons(2).map { |a, b| Planar.length(Planar.sub(b['ring_m'][0], a['ring_m'][1])) }
      assert(gaps.any? { |gap| (gap - width).abs < 1e-4 }, "#{message} : #{gaps}")
    end
  end
end
