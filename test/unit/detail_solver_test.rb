# frozen_string_literal: true

require_relative '../test_helper'

# U11 : détails LOD 1, profils actifs, baies ouvertes, silhouette stable.
class DetailSolverTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def resolve(draft)
    ConfigResolver.resolve({ 'schema_version' => 1 }.merge(draft), registry: registry, intake: TestData.intake)
  end

  def neutral(**blocks)
    base = TestData.intake.effective(TestData.building('rect-neutre-shell')).value
    BuildingConfig.new(Merge.leaves(base, { 'lod' => 1 }.merge(blocks.transform_keys(&:to_s))))
  end

  def generate(config)
    GeometryEngine.generate(config, materials: TestData.materials)
  end

  def plan(config)
    result = generate(config)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def details(built, category)
    Geo.find_nodes(built['nodes'], category)
  end

  def bounds(primitive)
    primitive['vertices'].transpose.map(&:minmax)
  end

  def assert_bounds(primitive, x, y, z)
    [x, y, z].zip(bounds(primitive)) do |want, got|
      assert_in_delta want[0], got[0], 1e-6
      assert_in_delta want[1], got[1], 1e-6
    end
  end

  # Boîte d'une barre de cadre, en repère monde, après sa matrice.
  def world_vertices(built, node)
    matrix = node['primitive']['matrix']
    built['definitions'][node['primitive']['definition_id']].flat_map do |bar|
      bar['primitive']['vertices'].map do |x, y, z|
        (0..2).map { |i| (matrix[i] * x) + (matrix[4 + i] * y) + (matrix[8 + i] * z) + matrix[12 + i] }
      end
    end
  end

  # --- Cadres

  def test_one_frame_per_opening_without_changing_the_opening
    built = plan(neutral)
    frames = details(built, 'frame')
    assert_equal 32, frames.size
    assert_equal plan(neutral(lod: 0))['openings'], built['openings']
  end

  def test_two_shared_definitions_for_the_neutral_fixture
    built = plan(neutral)
    assert_equal 2, built['metrics']['detail_definition_count']
    assert_equal 2, built['definitions'].size
  end

  def test_window_has_four_bars_door_has_no_threshold_bar
    built = plan(neutral)
    window = built['definitions'].find { |id, _| id.include?('window') }.last
    door = built['definitions'].find { |id, _| id.include?('door') }.last
    assert_equal %w[bar/left bar/right bar/top bar/bottom], window.map { |n| n['id'] }
    assert_equal %w[bar/left bar/right bar/top], door.map { |n| n['id'] }
  end

  def test_bars_have_the_contract_section_and_positions
    built = plan(neutral)
    window = built['definitions'].find { |id, _| id.include?('window') }.last.to_h { |n| [n['id'], n['primitive']] }
    assert_bounds window['bar/left'], [0, 0.04], [0, 0.04], [0, 1.8]
    assert_bounds window['bar/right'], [1.16, 1.2], [0, 0.04], [0, 1.8]
    assert_bounds window['bar/top'], [0.04, 1.16], [0, 0.04], [1.76, 1.8]
    assert_bounds window['bar/bottom'], [0.04, 1.16], [0, 0.04], [0, 0.04]
  end

  def test_face_counts_expand_through_instances
    built = plan(neutral)
    # 31 fenêtres × 24 faces + 1 porte × 18 faces, en plus des 218 du plan.
    assert_equal 218 + 24 + 18, built['metrics']['unique_face_count']
    assert_equal 218 + (31 * 24) + 18, built['metrics']['expanded_face_count']
  end

  def test_shell_frame_starts_at_wall_plane
    built = plan(neutral)
    node = details(built, 'frame').find { |n| n['id'] == 'frame/front/1/0' }
    world = world_vertices(built, node).transpose.map(&:minmax)
    assert_in_delta 1.35, world[0][0], 1e-6
    assert_in_delta 2.55, world[0][1], 1e-6
    assert_in_delta 0.0, world[1][0], 1e-6
    assert_in_delta 0.04, world[1][1], 1e-6
    assert_in_delta 4.05, world[2][0], 1e-6
    assert_in_delta 5.85, world[2][1], 1e-6
  end

  def test_structural_frame_is_recessed_by_contract_formula
    built = plan(neutral(mode: 'structural'))
    node = details(built, 'frame').find { |n| n['id'] == 'frame/front/1/0' }
    world = world_vertices(built, node).transpose.map(&:minmax)
    assert_in_delta 0.16, world[1][0], 1e-6, 'min(0,16 ; 0,24−0,04)'
    assert_in_delta 0.20, world[1][1], 1e-6
    thin = plan(neutral(mode: 'structural', structure: { 'wall_m' => 0.12 }))
    node = details(thin, 'frame').find { |n| n['id'] == 'frame/front/1/0' }
    assert_in_delta 0.08, world_vertices(thin, node).transpose[1].min, 1e-6
  end

  def test_frames_on_each_side_stay_on_their_facade
    built = plan(neutral(facade: { 'side_bays' => 1 }))
    { 'rear' => [8.96, 9.0], 'front' => [0.0, 0.04] }.each do |side, (low, high)|
      node = details(built, 'frame').find { |n| n['id'] == "frame/#{side}/0/0" }
      ys = world_vertices(built, node).map { |v| v[1] }.minmax
      assert_in_delta low, ys[0], 1e-6, side
      assert_in_delta high, ys[1], 1e-6, side
    end
    right = details(built, 'frame').find { |n| n['id'] == 'frame/right/0/0' }
    xs = world_vertices(built, right).map { |v| v[0] }.minmax
    assert_in_delta 11.96, xs[0], 1e-6
    assert_in_delta 12.0, xs[1], 1e-6
    left = details(built, 'frame').find { |n| n['id'] == 'frame/left/0/0' }
    xs = world_vertices(built, left).map { |v| v[0] }.minmax
    assert_in_delta 0.0, xs[0], 1e-6
    assert_in_delta 0.04, xs[1], 1e-6
  end

  def test_opening_center_stays_clear_of_every_frame_bar
    built = plan(neutral(mode: 'structural'))
    built['openings'].each do |o|
      u = (o['u_min_m'] + o['u_max_m']) / 2.0
      z = (o['z_min_m'] + o['z_max_m']) / 2.0
      node = details(built, 'frame').find { |n| n['id'] == o['id'].sub('opening/', 'frame/') }
      matrix = node['primitive']['matrix']
      built['definitions'][node['primitive']['definition_id']].each do |bar|
        lx, _, lz = bar['primitive']['vertices'].transpose.map(&:minmax)
        origin_u = o['u_min_m']
        origin_z = o['z_min_m']
        refute((u - origin_u).between?(*lx) && (z - origin_z).between?(*lz), "#{o['id']} #{bar['id']} #{matrix.first}")
      end
    end
  end

  # --- Corniche

  def test_cornice_box
    built = plan(neutral(features: { 'cornice' => true }))
    node = details(built, 'cornice').first
    assert_equal 'lime_plaster', node['primitive']['faces'].first['material']
    assert_bounds node['primitive'], [0, 12], [-0.15, 0], [12.72, 12.8]
  end

  def test_cornice_too_close_to_window_head_refused
    result = generate(neutral(features: { 'cornice' => true }, levels: { 'count' => 1 }, facade: { 'entry_bay' => 0, 'window_height_m' => 2.2 }))
    assert_equal ['E_OPENING_CLEARANCE', '/features/cornice'], [result.errors.first.code, result.errors.first.path]
    assert_equal 'cornice_head_margin', result.errors.first.params['reason']
  end

  def test_cornice_coplanar_with_flat_overhang_refused
    result = generate(neutral(features: { 'cornice' => true }, roof: { 'overhang_m' => 0.3 }))
    assert_equal ['E_ROOF_GEOMETRY', '/features/cornice'], [result.errors.first.code, result.errors.first.path]
  end

  def test_cornice_accepted_on_mansard_reference
    roof = { 'type' => 'mansard', 'overhang_m' => 0.15, 'pitch_deg' => 25.0, 'lower_pitch_deg' => 65.0, 'inset_m' => 0.9 }
    assert generate(neutral(features: { 'cornice' => true }, roof: roof)).ok?
  end

  # --- Balcon

  def test_balcony_at_level_two_only_for_five_levels
    built = plan(neutral(features: { 'balcony' => true }, levels: { 'count' => 5 }))
    nodes = details(built, 'balcony')
    assert_equal %w[balcony/2], nodes.map { |n| n['id'] }
    assert_bounds nodes.first['primitive'], [0.6, 11.4], [-0.9, 0], [6.28, 6.4]
  end

  def test_balconies_at_levels_two_and_five_for_six_levels
    built = plan(neutral(features: { 'balcony' => true }, levels: { 'count' => 6 }))
    assert_equal %w[balcony/2 balcony/5], details(built, 'balcony').map { |n| n['id'] }
  end

  def test_no_balcony_level_gives_a_warning_and_no_geometry
    result = generate(neutral(features: { 'balcony' => true }, levels: { 'count' => 2 }))
    assert result.ok?
    assert_equal ['W_DETAIL'], result.warnings.map(&:code)
    assert_equal '/features/balcony', result.warnings.first.path
    assert_empty details(result.value, 'balcony')
  end

  # Les dégagements de baie rendent ce cas inatteignable depuis une configuration
  # (dalle + 0,10 m ≥ 0,20 m > 0,12 m) : la garde se teste directement sur le solveur.
  def test_balcony_in_front_of_window_refused
    data = neutral(features: { 'balcony' => true }).to_h
    footprint = Archgen::Geometry::FootprintSolver.call(width_m: 12.0, depth_m: 9.0)
    levels = Archgen::Geometry::FloorPlanner.call(data['levels'], slab_m: 0.2)
    opening = Archgen::Geometry::Opening.new(id: 'opening/front/1/0', facade_id: 'front', level_index: 1, bay_index: 0, kind: 'window',
                                             u_min_m: 1.35, u_max_m: 2.55, z_min_m: 4.05, z_max_m: 6.3)
    result = Archgen::Geometry::DetailSolver.call(footprint: footprint, levels: levels, openings: [opening], config: data)
    assert_equal ['E_OPENING_CLEARANCE', '/features/balcony'], [result.errors.first.code, result.errors.first.path]
  end

  def test_balcony_keeps_clear_of_windows_at_the_tightest_configuration
    assert generate(neutral(features: { 'balcony' => true, 'surrounds' => true }, structure: { 'slab_m' => 0.1 }, facade: { 'window_height_m' => 2.15 })).ok?
  end

  # --- Encadrements

  def test_surrounds_only_on_windows_of_every_pierced_facade
    built = plan(neutral(features: { 'surrounds' => true }))
    ids = details(built, 'surround').map { |n| n['id'] }
    assert_equal 31 * 3, ids.size
    assert_empty(ids.grep(%r{front/0/1/}), 'pas d’encadrement sur la porte')
    assert(ids.any? { |id| id.start_with?('surround/rear/') })
  end

  def test_surround_bars_positions
    built = plan(neutral(features: { 'surrounds' => true }))
    bars = details(built, 'surround').select { |n| n['id'].start_with?('surround/front/1/0/') }.to_h { |n| [n['id'].split('/').last, n['primitive']] }
    assert_bounds bars['left'], [1.31, 1.35], [-0.03, 0], [4.05, 5.85]
    assert_bounds bars['right'], [2.55, 2.59], [-0.03, 0], [4.05, 5.85]
    assert_bounds bars['top'], [1.31, 2.59], [-0.03, 0], [5.85, 5.89]
  end

  def test_rear_surrounds_project_outward
    built = plan(neutral(features: { 'surrounds' => true }))
    bar = details(built, 'surround').find { |n| n['id'] == 'surround/rear/1/0/top' }
    ys = bar['primitive']['vertices'].map { |v| v[1] }.minmax
    assert_in_delta 9.0, ys[0], 1e-6
    assert_in_delta 9.03, ys[1], 1e-6
  end

  def test_every_detail_solid_is_positive_and_valid
    built = plan(neutral(features: { 'surrounds' => true, 'cornice' => true, 'balcony' => true }, mode: 'structural'))
    %w[surround cornice balcony].each do |category|
      details(built, category).each { |n| assert_operator Geo.signed_volume(n['primitive']), :>, 0.0, n['id'] }
    end
    assert_empty PlanValidator.call(built, materials: TestData.materials)
  end

  # --- LOD et silhouette

  def all_features
    { 'surrounds' => true, 'cornice' => true, 'balcony' => true }
  end

  def test_lod_zero_emits_no_detail_but_keeps_settings
    built = plan(neutral(lod: 0, features: all_features))
    %w[frame surround cornice balcony details].each { |c| assert_empty details(built, c), c }
    assert_equal({}, built['definitions'])
    assert_equal true, neutral(lod: 0, features: all_features).to_h['features']['cornice']
  end

  def test_lod_one_keeps_base_volume_openings_and_roof
    roof = { 'type' => 'gable', 'pitch_deg' => 30.0, 'overhang_m' => 0.3 }
    low = plan(neutral(lod: 0, features: all_features, roof: roof))
    high = plan(neutral(lod: 1, features: all_features, roof: roof))
    assert_equal low['openings'], high['openings']
    assert_equal Geo.find_node(low['nodes'], 'walls'), Geo.find_node(high['nodes'], 'walls')
    assert_equal Geo.find_node(low['nodes'], 'roof'), Geo.find_node(high['nodes'], 'roof')
    %w[width_m depth_m wall_top_z_m roof_top_z_m opening_count wall_cell_count].each { |k| assert_equal low['metrics'][k], high['metrics'][k], k }
    assert_equal PlanProjection.call(low), PlanProjection.call(high)
  end

  def test_lod_zero_digests_did_not_change
    golden = fixture_json('test', 'fixtures', 'plan_digests.json')
    assert_equal golden['rect-neutre-shell'], GeometryEngine.plan_digest(plan(neutral(lod: 0)))
  end

  def test_plan_is_deterministic_and_serializable_at_lod_one
    a = plan(neutral(features: all_features))
    b = plan(neutral(features: all_features))
    assert_equal GeometryEngine.serialize(a), GeometryEngine.serialize(b)
    assert_equal GeometryEngine.serialize(a), Canonical.dump(JSON.parse(GeometryEngine.serialize(a)))
  end

  def test_budget_counts_frames_at_exact_opening_limit
    built = plan(neutral(mode: 'structural', footprint: { 'width_m' => 60.0, 'depth_m' => 60.0 }, levels: { 'count' => 15, 'height_m' => 4.0 },
                         facade: { 'front_bays' => 12, 'side_bays' => 12 }))
    assert_equal 720, details(built, 'frame').size
    assert_equal 2, built['metrics']['detail_definition_count']
  end

  # --- Profils publiés : défauts, fixtures, règles, signatures

  PROFILES = %w[haussmann toulousain brutalist].freeze

  def test_real_composition_publishes_the_three_profiles
    # Les styles régionaux (AG-075 et suivants) s'ajoutent ; les trois premiers restent publiés.
    assert_empty PROFILES - registry.active_profiles.map(&:id)
  end

  def test_every_profile_generates_in_both_modes_at_both_lods
    PROFILES.product(%w[shell structural], [0, 1]).each do |id, mode, lod|
      resolved = resolve('profile' => { 'id' => id }, 'mode' => mode, 'lod' => lod)
      assert resolved.ok?, "#{id}: #{resolved.errors.map(&:to_h)}"
      assert_empty resolved.warnings, "#{id} : les défauts doivent respecter ses propres règles"
      built = generate(resolved.value)
      assert built.ok?, "#{id} #{mode} #{lod}: #{built.errors.map(&:to_h)}"
      assert_empty built.warnings, id
    end
  end

  def test_acceptance_fixtures_generate_at_their_lod
    { 'haussmann-12x9' => %w[cornice balcony], 'toulousain' => %w[surround], 'brutalist' => [] }.each do |name, categories|
      config = ConfigResolver.load_effective(TestData.read('examples', 'buildings', "#{name}.json"), registry: registry, intake: TestData.intake)
      assert config.ok?, name
      built = plan(config.value)
      assert_equal config.value.to_h['lod'], 1, name
      refute_empty details(built, 'frame'), name
      categories.each { |c| refute_empty details(built, c), "#{name} #{c}" }
    end
  end

  def signature(id, mode = 'shell', revision: nil)
    config = resolve('profile' => { 'id' => id, 'revision' => revision }.compact, 'mode' => mode, 'lod' => 1).value
    [config.to_h, plan(config)]
  end

  def test_haussmann_signature
    data, built = signature('haussmann')
    assert_equal %w[limestone zinc], [data['materials']['wall'], data['materials']['roof']]
    assert_equal 'mansard', data['roof']['type']
    refute_empty details(built, 'cornice')
    assert_equal %w[balcony/2], details(built, 'balcony').map { |n| n['id'] }, 'pas de balcon 5 à cinq niveaux'
    assert_empty details(built, 'surround')
  end

  def test_toulousain_signature
    data, built = signature('toulousain')
    assert_equal %w[brick_foraine terracotta_canal], [data['materials']['wall'], data['materials']['roof']]
    assert_equal 'gable', data['roof']['type']
    refute_empty details(built, 'surround')
    assert_empty details(built, 'cornice') + details(built, 'balcony')
    hip = resolve('profile' => { 'id' => 'toulousain' }, 'lod' => 1, 'roof' => { 'type' => 'hip' })
    assert hip.ok?, 'variante croupe testable'
    assert_empty hip.warnings
    assert generate(hip.value).ok?
  end

  def test_brutalist_signature_recesses_frames_in_structural
    data, built = signature('brutalist', 'structural')
    assert_equal %w[concrete concrete dark_metal], data['materials'].values_at('wall', 'roof', 'frames')
    assert_equal 'flat', data['roof']['type']
    node = details(built, 'frame').find { |n| n['id'] == 'frame/front/1/0' }
    assert_in_delta 0.16, world_vertices(built, node).map { |v| v[1] }.min, 1e-6
    _, shell = signature('brutalist', 'shell')
    assert_equal shell['openings'], built['openings'], 'mêmes baies qu’en Shell'
  end

  def test_signatures_are_distinct
    plans = PROFILES.map { |id| GeometryEngine.plan_digest(signature(id).last) }
    assert_equal 3, plans.uniq.size
  end

  def test_fidelity_rules_on_each_profile
    # haussmann : quatre niveaux ; toulousain : six ; brutaliste : toit en pente.
    cases = {
      'haussmann' => { 'levels' => { 'count' => 4 } },
      'toulousain' => { 'levels' => { 'count' => 2, 'height_m' => 3.1 }, 'facade' => { 'window_height_m' => 1.0 } },
      'brutalist' => { 'roof' => { 'type' => 'gable' } }
    }
    cases.each do |id, change|
      base = { 'profile' => { 'id' => id } }.merge(change)
      assert_equal 'E_HISTORICAL', resolve(base.merge('fidelity' => 'strict')).errors.first.code, id
      plausible = resolve(base.merge('fidelity' => 'plausible'))
      assert plausible.ok?, id
      assert_includes plausible.warnings.map(&:code), 'W_HISTORICAL', id
      assert_empty resolve(base.merge('fidelity' => 'creative')).diagnostics, id
    end
  end

  def test_adverse_values_are_refused_for_each_profile
    PROFILES.each do |id|
      result = resolve('profile' => { 'id' => id }, 'facade' => { 'window_width_m' => 8.0 }, 'fidelity' => 'creative')
      built = result.ok? ? generate(result.value) : result
      refute built.ok?, id
      assert_equal 'E_OPENING_CLEARANCE', built.errors.first.code, id
    end
  end

  def test_profile_plans_stay_inside_budgets
    PROFILES.each do |id|
      metrics = signature(id, 'structural').last['metrics']
      assert_operator metrics['expanded_face_count'], :<, Limits::MAX_EXPANDED_FACES, id
      assert_operator metrics['detail_definition_count'], :<, Limits::MAX_DETAIL_DEFINITIONS, id
    end
  end

  def test_canonical_profile_plans_are_stable
    golden = fixture_json('test', 'fixtures', 'profile_plan_digests.json')
    PROFILES.product(%w[shell structural]).each do |id, mode|
      assert_equal golden["#{id}-#{mode}"], GeometryEngine.plan_digest(signature(id, mode, revision: 1).last), "#{id} #{mode}"
    end
  end
end
