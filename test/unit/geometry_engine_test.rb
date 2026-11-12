# frozen_string_literal: true

require_relative '../test_helper'

# U09 et U10 : moteur, déterminisme, budgets et configurations pseudo-aléatoires.
class GeometryEngineTest < Minitest::Test
  include Archgen::Core

  # Graine de la suite, reproduite dans les messages d'erreur.
  SUITE_SEED = 20_261_105

  def config(name, **blocks)
    base = TestData.intake.effective(TestData.building(name)).value
    BuildingConfig.new(Merge.leaves(base, blocks.transform_keys(&:to_s)))
  end

  def generate(name, **blocks)
    GeometryEngine.generate(config(name, **blocks), materials: TestData.materials)
  end

  def plan(name, **blocks)
    result = generate(name, **blocks)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def shell
    @shell ||= plan('rect-neutre-shell')
  end

  def structural
    @structural ||= plan('rect-neutre-structural')
  end

  # --- Comptes de référence

  def test_reference_counts
    assert_equal 259, shell['metrics']['wall_cell_count']
    assert_equal 218, shell['metrics']['unique_face_count']
    assert_equal 259, structural['metrics']['wall_cell_count']
    assert_equal 709, structural['metrics']['unique_face_count']
  end

  def test_metrics_of_neutral_fixture
    assert_equal({ 'width_m' => 12.0, 'depth_m' => 9.0, 'wall_top_z_m' => 12.8, 'roof_top_z_m' => 12.8,
                   'opening_count' => 32, 'unique_face_count' => 218, 'expanded_face_count' => 218,
                   'wall_cell_count' => 259, 'detail_definition_count' => 0 }, shell['metrics'])
  end

  # --- Contrat du plan

  def test_plan_shape
    assert_equal 1, shell['schema_version']
    assert_equal Archgen::ENGINE_VERSION, shell['engine_version']
    assert_equal 'm', shell['units']
    assert_equal({}, shell['definitions'])
    assert_equal ['building'], shell['nodes'].map { |n| n['category'] }
    assert_equal %w[walls roof], shell['nodes'].first['children'].map { |n| n['id'] }
    assert_equal %w[walls slabs roof], structural['nodes'].first['children'].map { |n| n['id'] }
  end

  def test_plan_is_frozen
    assert shell.frozen?
    assert shell['nodes'].first['children'].first.frozen?
  end

  def test_material_assignment_by_role
    data = plan('rect-neutre-shell', roof: { 'type' => 'gable', 'pitch_deg' => 25.0 }, materials: { 'roof' => 'zinc' })
    assert_equal ['lime_plaster'], Geo.find_nodes(data['nodes'], 'wall').flat_map { |n| n['primitive']['faces'].map { |f| f['material'] } }.uniq
    assert_equal ['zinc'], Geo.find_nodes(data['nodes'], 'roof_face').flat_map { |n| n['primitive']['faces'].map { |f| f['material'] } }.uniq
    assert_equal ['lime_plaster'], Geo.find_nodes(data['nodes'], 'gable_end').flat_map { |n| n['primitive']['faces'].map { |f| f['material'] } }.uniq
  end

  # --- Déterminisme

  def test_same_input_same_serialization
    assert_equal GeometryEngine.serialize(shell), GeometryEngine.serialize(plan('rect-neutre-shell'))
  end

  def test_plan_independent_of_name
    assert_equal GeometryEngine.plan_digest(plan('rect-neutre-shell')),
                 GeometryEngine.plan_digest(GeometryEngine.generate(BuildingConfig.new(config('rect-neutre-shell').to_h.merge('name' => 'Autre'))).value)
  end

  def test_seed_changes_plan_only_through_jitter
    assert_equal GeometryEngine.plan_digest(plan('rect-neutre-shell', seed: 1)), GeometryEngine.plan_digest(plan('rect-neutre-shell', seed: 2))
    # Un seul niveau : aucune coupe de colonne ne peut tomber à moins de 2 mm d'une autre.
    single = { levels: { 'count' => 1 }, facade: { 'jitter_m' => 0.02, 'entry_bay' => 0 } }
    a = plan('rect-neutre-shell', seed: 1, **single)
    b = plan('rect-neutre-shell', seed: 2, **single)
    refute_equal GeometryEngine.plan_digest(a), GeometryEngine.plan_digest(b)
  end

  def test_neutral_digests_are_stable
    golden = fixture_json('test', 'fixtures', 'plan_digests.json')
    assert_equal golden['rect-neutre-shell'], GeometryEngine.plan_digest(shell)
    assert_equal golden['rect-neutre-structural'], GeometryEngine.plan_digest(structural)
  end

  def test_serialization_round_trips_as_json
    parsed = JSON.parse(GeometryEngine.serialize(structural))
    assert_equal 709, parsed['metrics']['unique_face_count']
    assert_equal GeometryEngine.serialize(structural), Canonical.dump(parsed)
  end

  # --- Modes partagés

  def test_modes_share_openings_and_silhouette
    assert_equal shell['openings'], structural['openings']
    assert_equal Geo.find_node(shell['nodes'], 'roof'), Geo.find_node(structural['nodes'], 'roof')
    %w[width_m depth_m wall_top_z_m roof_top_z_m opening_count wall_cell_count].each do |key|
      assert_equal shell['metrics'][key], structural['metrics'][key], key
    end
  end

  def test_active_profile_fixtures_at_lod_zero
    %w[toulousain brutalist].each do |name|
      data = TestData.building(name)
      forced = data.merge('lod' => 0)
      built = GeometryEngine.generate(BuildingConfig.new(TestData.intake.effective(forced).value), materials: TestData.materials)
      assert built.ok?, "#{name}: #{built.errors.map(&:to_h)}"
    end
    haussmann = TestData.building('haussmann-12x9').merge('lod' => 0)
    built = GeometryEngine.generate(BuildingConfig.new(TestData.intake.effective(haussmann).value), materials: TestData.materials)
    assert built.ok?, built.errors.map(&:to_h).inspect
    expected = 12.8 + (Math.tan(65 * Math::PI / 180) * 0.9) + (Math.tan(25 * Math::PI / 180) * 3.6)
    assert_in_delta expected, built.value['metrics']['roof_top_z_m'], 1e-5
  end

  def test_opening_problem_stops_before_plan
    result = generate('rect-neutre-shell', facade: { 'window_width_m' => 3.0 })
    refute result.ok?
    assert_nil result.value
    assert_equal 'E_OPENING_CLEARANCE', result.errors.first.code
  end

  # --- U10 budgets : limite exacte et premier dépassement

  def test_budget_exact_limits_pass_and_first_overflow_fails
    limits = {
      'width_m' => Limits::MAX_FOOTPRINT_M, 'depth_m' => Limits::MAX_FOOTPRINT_M,
      'wall_top_z_m' => Limits::MAX_WALL_TOP_M, 'roof_top_z_m' => Limits::MAX_ROOF_TOP_M,
      'opening_count' => Limits::MAX_OPENINGS, 'unique_face_count' => Limits::MAX_UNIQUE_FACES,
      'expanded_face_count' => Limits::MAX_EXPANDED_FACES, 'wall_cell_count' => Limits::MAX_WALL_CELLS,
      'detail_definition_count' => Limits::MAX_DETAIL_DEFINITIONS
    }
    limits.each do |key, limit|
      assert_empty Budget.check(key => limit), key
      over = limit.is_a?(Float) ? limit + 0.001 : limit + 1
      problems = Budget.check(key => over)
      assert_equal ['E_BUDGET'], problems.map(&:code), key
      assert_equal key, problems.first.params['reason']
      assert_equal Budget::HINT, problems.first.params['hint']
    end
  end

  def max_openings_config
    { footprint: { 'width_m' => 60.0, 'depth_m' => 60.0 }, levels: { 'count' => 15, 'height_m' => 4.0 },
      facade: { 'front_bays' => 12, 'side_bays' => 12, 'margin_m' => 0.6, 'window_width_m' => 1.2, 'window_height_m' => 1.8, 'door_width_m' => 1.0 } }
  end

  def test_exact_opening_limit_generates
    data = plan('rect-neutre-structural', **max_openings_config)
    assert_equal 720, data['metrics']['opening_count']
    assert_equal 60.0, data['metrics']['wall_top_z_m']
  end

  # D-01 tranchée (ADR-43) : avant, 1 % des graines passaient à 2 cm ; sur la grille de 5 mm, toutes passent
  # (500 graines mesurées de 1 à 30 cm, sur les deux fixtures neutres).
  def test_jittered_openings_are_accepted_for_every_seed
    (1..40).each do |seed|
      result = generate('rect-neutre-shell', seed: seed, facade: { 'jitter_m' => 0.02 })
      assert result.ok?, "graine #{seed} : #{result.errors.map(&:to_h)}"
    end
  end

  def test_face_estimate_stops_generation_before_meshing
    grids = [Struct.new(:cell_count, :rows, :columns) { def solid?(_c, _r) = true }.new(40_000, 200, 200)]
    footprint = Struct.new(:width_m, :depth_m).new(12.0, 9.0)
    levels = [Struct.new(:top_z_m).new(3.0)]
    problems = GeometryEngine.send(:estimate_budget, { 'mode' => 'shell' }, footprint, levels, [], grids)
    assert_equal ['unique_face_count'], problems.map { |d| d.params['reason'] }
  end

  # --- U10 configurations pseudo-aléatoires bornées

  def random_blocks(rng)
    type = %w[flat gable hip mansard].sample(random: rng)
    roof = { 'type' => type, 'overhang_m' => rng.rand(0..4) * 0.1, 'pitch_deg' => 0.0, 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0 }
    roof['pitch_deg'] = rng.rand(5..45).to_f unless type == 'flat'
    roof.merge!('lower_pitch_deg' => rng.rand(46..80).to_f, 'inset_m' => rng.rand(2..12) * 0.1) if type == 'mansard'
    count = rng.rand(1..8)
    {
      seed: rng.rand(0..0xFFFF_FFFF),
      footprint: { 'width_m' => rng.rand(6..30).to_f, 'depth_m' => rng.rand(6..30).to_f },
      levels: { 'count' => count, 'height_m' => rng.rand(26..45) * 0.1 },
      facade: { 'front_bays' => rng.rand(1..6), 'side_bays' => rng.rand(0..4), 'entry_bay' => 0, 'margin_m' => rng.rand(4..10) * 0.1,
                'window_width_m' => rng.rand(5..14) * 0.1, 'window_height_m' => rng.rand(8..16) * 0.1, 'sill_m' => rng.rand(4..9) * 0.1,
                'jitter_m' => count == 1 ? rng.rand(0..3) * 0.01 : 0.0 },
      structure: { 'wall_m' => rng.rand(10..35) * 0.01, 'slab_m' => rng.rand(10..30) * 0.01 },
      roof: roof
    }
  end

  def test_one_hundred_pseudo_random_configs
    rng = Random.new(SUITE_SEED)
    known = %w[E_OPENING_CLEARANCE E_ROOF_GEOMETRY E_BUDGET]
    outcomes = Hash.new(0)
    100.times do |i|
      blocks = random_blocks(rng)
      context = "suite=#{SUITE_SEED} tirage=#{i} config=#{blocks.inspect}"
      modes = %w[shell structural].map do |mode|
        data = config('rect-neutre-shell', mode: mode, **blocks)
        hard = ConstraintValidator.call(data)
        next [:rejected, hard] unless hard.empty?

        result = GeometryEngine.generate(data, materials: TestData.materials)
        next [:rejected, result.errors] unless result.ok?

        assert_empty PlanValidator.call(result.value, materials: TestData.materials), context
        assert_equal GeometryEngine.plan_digest(result.value), GeometryEngine.plan_digest(GeometryEngine.generate(data, materials: TestData.materials).value), context
        [:ok, result.value]
      end
      assert_equal modes[0][0], modes[1][0], "les deux modes doivent décider pareil : #{context}"
      outcomes[modes[0][0]] += 1
      if modes[0][0] == :ok
        assert_equal modes[0][1]['openings'], modes[1][1]['openings'], context
        assert_equal Geo.find_node(modes[0][1]['nodes'], 'roof'), Geo.find_node(modes[1][1]['nodes'], 'roof'), context
        structural_walls_closed(modes[1][1], context)
      else
        modes[0][1].each { |d| assert_includes known + ['E_SCHEMA'], d.code, context }
      end
    end
    assert_operator outcomes[:ok], :>=, 40, "trop peu de plans valides : #{outcomes} (suite=#{SUITE_SEED})"
  end

  # --- U10 : jusqu'aux bornes du schéma, LOD 1 et profils actifs

  def wide_blocks(rng)
    count = rng.rand(1..15)
    width = rng.rand(6..60).to_f
    front = rng.rand(1..[12, (width / 2).floor].min)
    {
      seed: rng.rand(0..0xFFFF_FFFF), mode: %w[shell structural].sample(random: rng), lod: 1,
      footprint: { 'width_m' => width, 'depth_m' => rng.rand(6..60).to_f },
      levels: { 'count' => count, 'height_m' => rng.rand(26..40) * 0.1 },
      facade: { 'front_bays' => front, 'side_bays' => rng.rand(0..12), 'entry_bay' => 0 }
    }
  end

  def test_pseudo_random_configs_up_to_the_schema_bounds
    rng = Random.new(SUITE_SEED + 1)
    known = %w[E_OPENING_CLEARANCE E_ROOF_GEOMETRY E_BUDGET E_SCHEMA]
    accepted = 0
    %w[haussmann-12x9 toulousain brutalist].cycle.first(24).each_with_index do |fixture, i|
      blocks = wide_blocks(rng)
      context = "suite=#{SUITE_SEED + 1} tirage=#{i} #{fixture} config=#{blocks.inspect}"
      data = config(fixture, **blocks)
      hard = ConstraintValidator.call(data)
      result = hard.empty? ? GeometryEngine.generate(data, materials: TestData.materials) : Result.fail(hard)
      unless result.ok?
        result.errors.each { |d| assert_includes known, d.code, context }
        next
      end

      accepted += 1
      assert_empty Budget.check(result.value['metrics']), context
      assert_equal GeometryEngine.plan_digest(result.value), GeometryEngine.plan_digest(GeometryEngine.generate(data, materials: TestData.materials).value), context
    end
    assert_operator accepted, :>=, 8, "trop peu de plans valides (suite=#{SUITE_SEED + 1})"
  end

  # Le schéma borne le pire cas loin des plafonds : aucun détail caché ne s'en approche.
  def test_largest_accepted_plan_stays_under_every_budget
    data = plan('toulousain', mode: 'structural', lod: 1, **max_openings_config)
    metrics = data['metrics']
    assert_equal 720, metrics['opening_count']
    assert_operator metrics['unique_face_count'], :<, Limits::MAX_UNIQUE_FACES
    assert_operator metrics['expanded_face_count'], :<, Limits::MAX_EXPANDED_FACES
    assert_operator metrics['wall_cell_count'], :<, Limits::MAX_WALL_CELLS
    assert_operator metrics['detail_definition_count'], :<, Limits::MAX_DETAIL_DEFINITIONS
  end

  def test_first_overflow_in_a_real_config_is_refused
    tall = config('rect-neutre-structural', levels: { 'count' => 15, 'height_m' => 4.01 })
    problems = ConstraintValidator.call(tall)
    problems = GeometryEngine.generate(tall, materials: TestData.materials).errors if problems.empty?
    assert_equal ['E_BUDGET'], problems.map(&:code).uniq
    assert_equal '/levels', problems.first.path
  end

  def structural_walls_closed(data, context)
    Geo.find_nodes(data['nodes'], 'wall').each do |node|
      assert_operator Geo.signed_volume(node['primitive']), :>, 0.0, context
    end
  end

  # --- Projection 2D

  def test_projection_is_numeric_only
    view = PlanProjection.call(shell)
    assert_equal [[0.0, 0.0], [12.0, 0.0], [12.0, 9.0], [0.0, 9.0]], view['plan_view']['footprint']
    assert_equal 16, view['front_elevation']['openings'].size
    assert_equal({ 'window_count' => 31, 'door_count' => 1, 'roof_top_z_m' => 12.8 }, view['summary'])
    flat = Canonical.dump(view)
    refute_match(/[<>]/, flat)
  end

  def test_projection_of_gable_silhouette
    data = plan('rect-neutre-shell', roof: { 'type' => 'gable', 'pitch_deg' => 30.0, 'overhang_m' => 0.3 })
    silhouette = PlanProjection.call(data)['front_elevation']['roof_silhouette']
    assert_equal [-0.3, 12.3], silhouette.map(&:first).minmax
    assert_in_delta data['metrics']['roof_top_z_m'], silhouette.map(&:last).max, 1e-9
  end

  def test_projection_is_identical_across_modes
    assert_equal PlanProjection.call(shell), PlanProjection.call(structural).merge('summary' => PlanProjection.call(shell)['summary'])
  end

  def test_core_runs_faster_than_preview_target
    times = Array.new(23) do
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      plan('haussmann-12x9', lod: 0, mode: 'structural')
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    end.drop(3).sort
    assert_operator times[18], :<, 1.0, 'garde-fou large ; la cible 150 ms se mesure en AG-018'
  end
end
