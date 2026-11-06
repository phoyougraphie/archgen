# frozen_string_literal: true

require_relative '../test_helper'

# U19 : plan d'ensemble (docs/ENSEMBLE_CONTRACT.md, Plan d'ensemble).
class EnsembleEngineTest < Minitest::Test
  include Archgen::Core

  PROFILES = %w[haussmann toulousain brutalist].freeze
  ELBOW = [[0, 0], [48, 0], [48, 48]].freeze
  STREET = [[0, 0], [60, 0]].freeze

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def intake
    @intake ||= Archgen::Composition.intake
  end

  def materials
    Archgen::Composition.materials.fetch('materials')
  end

  def settings(points = STREET, profile: 'brutalist', closed: false, layout: nil, building: {}, parcel: {}, seed: 1)
    tree = { 'seed' => seed, 'trace' => { 'points_m' => points, 'closed' => closed }, 'parcel' => parcel,
             'building' => { 'profile' => { 'id' => profile } }.merge(building) }
    tree['layout'] = layout if layout
    result = Archgen::Composition.ensemble_intake.settings(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def engine(value, **options, &block)
    EnsembleEngine.call(value, registry: registry, intake: intake, materials: materials, **options, &block)
  end

  def plan(value = settings, **options)
    result = engine(value, **options)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def layout_parcels(value)
    Archgen::Geometry::ParcelLayout.call(value).value['parcels']
  end

  # --- Plan

  def test_shape_of_the_plan
    value = plan
    assert_equal 1, value['schema_version']
    assert_equal 'm', value['units']
    assert_equal Archgen::ENGINE_VERSION, value['engine_version']
    assert_equal [], value['accesses']
    assert value.frozen?
    assert_equal %w[left/0/0 left/0/1 left/0/2 left/0/3 left/0/4], value['parcels'].map { |p| p['id'] }
    assert_equal 5, value['metrics']['parcel_count']
    assert_equal 60.0, value['metrics']['facade_length_m']
    assert_equal 0, value['metrics']['access_count']
  end

  def test_identical_straight_parcels_share_one_definition
    value = plan
    assert_equal 1, value['definitions'].size
    assert_equal 1, value['parcels'].map { |p| p['definition_id'] }.uniq.size
    only = value['definitions'].values.first
    assert_equal only['metrics']['unique_face_count'], value['metrics']['unique_face_count']
    assert_equal only['metrics']['expanded_face_count'] * 5, value['metrics']['expanded_face_count']
  end

  def test_corner_parcels_get_their_own_definitions
    value = plan(settings(ELBOW))
    corners = layout_parcels(settings(ELBOW)).select { |p| p['corner'] }
    assert_equal 2, corners.size
    ids = value['parcels'].to_h { |p| [p['id'], p['definition_id']] }
    refute_equal ids[corners[0]['id']], ids[corners[1]['id']], 'reculs de côtés opposés'
    straight = value['parcels'].reject { |p| corners.any? { |c| c['id'] == p['id'] } }.map { |p| p['definition_id'] }.uniq
    assert_equal 1, straight.size
    assert_equal 3, value['definitions'].size
  end

  def test_rear_bays_keep_definitions_apart
    ready = lambda do |rear|
      config = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'brutalist' } }, registry: registry, intake: intake).value
      ParcelBuilding::Prepared.new(config: config, row: { rear_bays: rear, delta_left_m: 0.0, delta_right_m: 0.0 }, warnings: [])
    end
    assert_equal ParcelBuilding.share_key(ready.call(3)), ParcelBuilding.share_key(ready.call(3))
    refute_equal ParcelBuilding.share_key(ready.call(3)), ParcelBuilding.share_key(ready.call(2))
  end

  def test_share_key_ignores_name_and_seed_unless_jitter_matters
    build = lambda do |request|
      config = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'brutalist' } }.merge(request), registry: registry, intake: intake).value
      ParcelBuilding::Prepared.new(config: config, row: { rear_bays: 1, delta_left_m: 0.0, delta_right_m: 0.0 }, warnings: [])
    end
    assert_equal ParcelBuilding.share_key(build.call('seed' => 1, 'name' => 'A')), ParcelBuilding.share_key(build.call('seed' => 2, 'name' => 'B'))
    jitter = { 'facade' => { 'jitter_m' => 0.02 } }
    refute_equal ParcelBuilding.share_key(build.call(jitter.merge('seed' => 1))), ParcelBuilding.share_key(build.call(jitter.merge('seed' => 2)))
  end

  def test_shared_definition_equals_what_each_parcel_would_get
    value = settings(ELBOW, profile: 'haussmann', building: { 'lod' => 1 })
    result = plan(value)
    layout_parcels(value).each do |parcel|
      built = ParcelBuilding.call(value, parcel, registry: registry, intake: intake, materials: materials).value
      placed = result['parcels'].find { |p| p['id'] == parcel['id'] }
      assert_equal GeometryEngine.plan_digest(built.plan), GeometryEngine.plan_digest(result['definitions'][placed['definition_id']]), parcel['id']
    end
  end

  def test_face_counts_are_exact
    value = settings(ELBOW, profile: 'haussmann', building: { 'lod' => 1, 'mode' => 'structural' })
    result = plan(value)
    built = layout_parcels(value).map { |parcel| ParcelBuilding.call(value, parcel, registry: registry, intake: intake, materials: materials).value.plan }
    assert_equal built.sum { |p| p['metrics']['expanded_face_count'] }, result['metrics']['expanded_face_count']
    assert_equal result['definitions'].values.sum { |p| p['metrics']['unique_face_count'] }, result['metrics']['unique_face_count']
    assert_operator result['metrics']['unique_face_count'], :<, built.sum { |p| p['metrics']['unique_face_count'] }, 'le partage doit réellement économiser'
  end

  # --- Placement

  def test_matrices_place_each_parcel_on_its_ring
    value = settings(ELBOW)
    result = plan(value)
    layout_parcels(value).each do |parcel|
      m = result['parcels'].find { |p| p['id'] == parcel['id'] }['matrix']
      parcel['local_ring_m'].zip(parcel['ring_m']).each do |(x, y), expected|
        assert_in_delta expected[0], (m[0] * x) + (m[4] * y) + m[12], 5e-6, parcel['id']
        assert_in_delta expected[1], (m[1] * x) + (m[5] * y) + m[13], 5e-6, parcel['id']
      end
      assert_in_delta 1.0, (m[0] * m[5]) - (m[1] * m[4]), 1e-9, 'rotation directe'
    end
  end

  def test_no_negative_zero_in_matrices
    plan(settings(ELBOW))['parcels'].each do |parcel|
      assert(parcel['matrix'].none? { |c| c.zero? && 1.0 / c < 0 }, parcel['id'])
    end
  end

  # --- Reproductibilité

  def test_same_input_same_digest
    first = EnsembleEngine.digest(plan(settings(ELBOW)))
    assert_equal first, EnsembleEngine.digest(plan(settings(ELBOW)))
    assert_match(/\A[0-9a-f]{64}\z/, first)
  end

  def test_building_name_does_not_change_the_digest
    named = plan(settings(building: { 'name' => 'Rue A' }))
    other = plan(settings(building: { 'name' => 'Rue B' }))
    assert_equal EnsembleEngine.digest(named), EnsembleEngine.digest(other)
  end

  def test_geometry_changes_change_the_digest
    base = EnsembleEngine.digest(plan)
    refute_equal base, EnsembleEngine.digest(plan(settings(parcel: { 'depth_m' => 10 })))
    refute_equal base, EnsembleEngine.digest(plan(settings(building: { 'mode' => 'structural' })))
    refute_equal base, EnsembleEngine.digest(plan(settings([[0, 0], [60, 1]])))
  end

  def test_definition_ids_come_from_content
    plan(settings(ELBOW))['definitions'].each_key { |id| assert_match(%r{\Arow/[0-9a-f]{16}\z}, id) }
    assert_equal plan(settings(ELBOW))['definitions'].keys, plan(settings(ELBOW, seed: 2))['definitions'].keys, 'sans jitter, la seed ne change pas la géométrie'
    # La même parcelle dans un autre tracé garde sa définition.
    longer = plan(settings([[0, 0], [72, 0]]))
    assert_equal plan['definitions'].keys, longer['definitions'].keys
  end

  # D-01 : le jitter refuse presque toute graine, donc presque tout ensemble qui s'en sert.
  def test_jitter_refusal_is_located_on_a_parcel
    result = engine(settings(building: { 'facade' => { 'jitter_m' => 0.02 } }, seed: 7))
    refute result.ok?
    assert_equal '/parcels/left/0/0/facade/jitter_m', result.errors.first.path
  end

  # --- Budgets

  def test_expanded_budget_limit_and_first_excess
    total = plan['metrics']
    fits = { unique: total['unique_face_count'], expanded: total['expanded_face_count'] }
    assert engine(settings, limits: fits).ok?
    result = engine(settings, limits: fits.merge(expanded: total['expanded_face_count'] - 1))
    found = result.errors.first
    assert_equal 'E_STREET_BUDGET', found.code
    assert_equal 'ensemble_expanded_faces', found.params['reason']
    assert_equal total['expanded_face_count'] - 1, found.params['limit']
  end

  def test_unique_budget_limit_and_first_excess
    total = plan['metrics']
    fits = { unique: total['unique_face_count'], expanded: total['expanded_face_count'] }
    result = engine(settings, limits: fits.merge(unique: total['unique_face_count'] - 1))
    assert_equal 'ensemble_unique_faces', result.errors.first.params['reason']
    assert_equal '/parcel/target_width_m', result.errors.first.path
    assert_nil result.value
  end

  def test_default_limits_come_from_the_contract
    assert_equal 120_000, Limits::ENSEMBLE_MAX_UNIQUE_FACES
    assert_equal 600_000, Limits::ENSEMBLE_MAX_EXPANDED_FACES
  end

  # --- Refus

  def test_closed_trace_waits_for_a_form_of_access
    square = [[0, 0], [40, 0], [40, 40], [0, 40]]
    found = engine(settings(square, closed: true, profile: 'haussmann')).errors.first
    assert_equal 'E_STREET_ACCESS', found.code
    assert_equal '/building/profile', found.path
    assert_equal 'access_form_unavailable', found.params['reason']
  end

  def test_trace_refusals_pass_through
    assert_equal 'E_STREET_TRACE', engine(settings([[0, 0], [5, 0]])).errors.first.code
  end

  def test_one_refused_parcel_refuses_everything
    result = engine(settings(building: { 'roof' => { 'type' => 'hip' } }))
    refute result.ok?
    assert_nil result.value
    assert_equal 'E_STREET_ROOF', result.errors.first.code
  end

  def test_parcel_errors_are_located
    result = engine(settings(parcel: { 'bay_width_m' => 1.5 }, building: { 'facade' => { 'window_width_m' => 1.5 } }))
    refute result.ok?
    assert(result.errors.all? { |d| d.path.start_with?('/parcels/left/0/') }, result.errors.map(&:to_h).inspect)
  end

  # --- Avertissements et progression

  def test_warnings_are_repeated_per_parcel
    # Moins de trois niveaux : pas de balcon possible, avertissement sur chaque parcelle.
    result = engine(settings(profile: 'haussmann', building: { 'lod' => 1, 'levels' => { 'count' => 2 }, 'features' => { 'balcony' => true } }))
    assert result.ok?, result.errors.map(&:to_h).inspect
    paths = result.warnings.select { |d| d.code == 'W_DETAIL' }.map(&:path)
    assert_equal 5, paths.size
    assert_includes paths, '/parcels/left/0/3/features/balcony'
  end

  def test_progress_counts_every_parcel_in_order
    seen = []
    assert engine(settings) { |done, total| seen << [done, total] }.ok?
    assert_equal [[1, 5], [2, 5], [3, 5], [4, 5], [5, 5]], seen
  end

  # --- Validateur

  def test_validator_refuses_a_tampered_plan
    good = Canonical.deep_copy(plan)
    assert_empty EnsemblePlanValidator.call(good)

    bad = Canonical.deep_copy(good)
    bad['parcels'][0]['definition_id'] = 'row/absent'
    assert_includes EnsemblePlanValidator.call(bad).map { |d| d.params['reason'] }, 'missing_definition'

    bad = Canonical.deep_copy(good)
    bad['parcels'][0]['matrix'][0] = 2.0
    assert_includes EnsemblePlanValidator.call(bad).map { |d| d.params['reason'] }, 'non_rigid_matrix'

    bad = Canonical.deep_copy(good)
    bad['parcels'][1]['id'] = bad['parcels'][0]['id']
    assert_includes EnsemblePlanValidator.call(bad).map { |d| d.params['reason'] }, 'duplicate_parcel_id'

    bad = Canonical.deep_copy(good)
    bad['metrics']['expanded_face_count'] += 1
    assert_includes EnsemblePlanValidator.call(bad).map { |d| d.params['reason'] }, 'metric_mismatch'
  end

  def test_every_style_gives_a_valid_ensemble
    PROFILES.each do |profile|
      %w[shell structural].each do |mode|
        [0, 1].each do |lod|
          result = engine(settings(ELBOW, profile: profile, building: { 'mode' => mode, 'lod' => lod }))
          assert result.ok?, "#{profile} #{mode} LOD #{lod} : #{result.errors.map(&:to_h).inspect}"
        end
      end
    end
  end
end
