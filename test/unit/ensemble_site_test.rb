# frozen_string_literal: true

require_relative '../test_helper'

# U22 : l'étagement d'un ensemble, noyau pur. La preuve native est H18.
class EnsembleSiteTest < Minitest::Test
  include Archgen::Core

  STREET = {
    'trace' => { 'points_m' => [[0, 0], [48, 0]], 'closed' => false },
    'building' => { 'profile' => { 'id' => 'brutalist' } }
  }.freeze
  ELBOW = {
    'trace' => { 'points_m' => [[0, 0], [48, 0], [48, 48]], 'closed' => false },
    'building' => { 'profile' => { 'id' => 'brutalist' } }
  }.freeze
  SQUARE_PORCH = {
    'trace' => { 'points_m' => [[0, 0], [40, 0], [40, 40], [0, 40]], 'closed' => true },
    'building' => { 'profile' => { 'id' => 'haussmann' } }
  }.freeze

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def intake
    Archgen::Composition.intake
  end

  def site_intake
    Archgen::Composition.site_intake
  end

  def catalog
    Archgen::Composition.site_materials
  end

  def settings_for(tree)
    result = Archgen::Composition.ensemble_intake.settings(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def site(tree = {})
    result = site_intake.settings(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def world(matrix, x, y)
    [(matrix[0] * x) + (matrix[4] * y) + matrix[12], (matrix[1] * x) + (matrix[5] * y) + matrix[13]]
  end

  # Grilles relevées sur une fonction du repère de la racine ; le bloc peut renvoyer nil.
  def grids_for(requests, &altitude)
    requests.to_h do |request|
      axes = request['axes']
      rows = axes['ys_m'].map { |y| axes['xs_m'].map { |x| altitude.call(*world(request['matrix'], x, y)) } }
      tree = { 'schema_version' => 1, 'xs_m' => axes['xs_m'], 'ys_m' => axes['ys_m'], 'z_m' => rows }
      grid = site_intake.parcel_grid(tree, axes)
      assert grid.ok?, grid.errors.map(&:to_h).inspect
      [request['id'], grid.value]
    end
  end

  def run_site(tree, site_tree = {}, root_z: 100.0, &altitude)
    settings = settings_for(tree)
    plan = EnsembleEngine.call(settings, registry: registry, intake: intake, materials: Archgen::Composition.materials.fetch('materials'))
    assert plan.ok?, plan.errors.map(&:to_h).inspect
    layout = EnsembleEngine.layout_for(settings, registry: registry).value
    chosen = site(site_tree)
    requests = EnsembleSite.requests(plan.value, layout, chosen)
    assert requests.ok?, requests.errors.map(&:to_h).inspect
    EnsembleSite.call(settings: settings, site: chosen, plan: plan.value, layout: layout, grids: grids_for(requests.value, &altitude),
                      root_z_m: root_z, registry: registry, intake: intake, materials: catalog)
  end

  def slope(gradient = 0.05)
    ->(x, _y) { 100.0 + (gradient * x) }
  end

  def ok_site(*args, **options, &block)
    result = run_site(*args, **options, &block)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result
  end

  # --- Un rectangle donne l'assise d'un bâtiment seul.

  def test_a_rectangle_gives_the_same_assise_as_a_single_building
    [{}, { 'platform' => { 'policy' => 'mean', 'offset_m' => 0.3 } }, { 'survey' => { 'step_m' => 1.5 } }].each do |tree|
      chosen = site(tree)
      axes = SurveyGrid.plan(width_m: 12.0, depth_m: 9.0, settings: chosen).value
      rows = axes['ys_m'].map { |y| axes['xs_m'].map { |x| Quant.q(50.0 + (0.07 * x) + (0.02 * y) + (0.3 * Math.sin(x * y))) } }
      grid = SurveyGrid.new('schema_version' => 1, 'xs_m' => axes['xs_m'], 'ys_m' => axes['ys_m'], 'z_m' => rows)
      ring = [[0.0, 0.0], [12.0, 0.0], [12.0, 9.0], [0.0, 9.0]]
      assert_equal SiteAssise.call(grid, chosen, width_m: 12.0, depth_m: 9.0).value, SiteAssise.for_ring(grid, chosen, ring: ring).value
    end
  end

  def test_box_axes_of_a_rectangle_are_the_axes_of_a_single_building
    chosen = site
    assert_equal SurveyGrid.plan(width_m: 12.0, depth_m: 9.0, settings: chosen).value,
                 SurveyGrid.plan_box(x_min_m: 0.0, x_max_m: 12.0, depth_m: 9.0, settings: chosen).value
  end

  # --- Étagement.

  def test_parcels_step_along_a_slope
    result = ok_site(STREET, root_z: 100.0, &slope)
    parcels = result.value['parcels']
    assert_equal 4, parcels.size
    levels = parcels.map { |p| p['level_m'] }
    assert_equal levels.sort, levels
    assert_operator levels.uniq.size, :>, 1
    parcels.each_with_index do |parcel, index|
      assert_in_delta 100.0 + (0.05 * 12.0 * (index + 1)), parcel['platform_z_m'], 1e-6
      assert_in_delta parcel['platform_z_m'] - 100.0, parcel['level_m'], 1e-6
    end
    assert_in_delta 0.6, result.value['metrics']['max_step_m'], 1e-6
  end

  def test_level_follows_the_root_altitude
    high = ok_site(STREET, root_z: 90.0, &slope).value
    low = ok_site(STREET, root_z: 100.0, &slope).value
    assert_equal high['metrics'], low['metrics']
    high['parcels'].zip(low['parcels']).each { |a, b| assert_in_delta a['level_m'] - 10.0, b['level_m'], 1e-6 }
  end

  def test_the_site_plan_is_deterministic
    a = ok_site(ELBOW, &slope)
    b = ok_site(ELBOW, &slope)
    assert_equal EnsembleSite.digest(a.value), EnsembleSite.digest(b.value)
  end

  def test_flat_ground_shares_and_has_no_step
    result = ok_site(STREET) { 100.0 }
    assert_equal 1, result.value['metrics']['site_definition_count']
    assert_equal 0.0, result.value['metrics']['max_step_m']
    assert_equal 0.0, result.value['metrics']['fill_max_m']
  end

  def test_a_regular_slope_shares_the_assises_of_identical_parcels
    result = ok_site(STREET) { |x, _y| 100.0 + (0.5 * x) }
    metrics = result.value['metrics']
    assert_operator metrics['site_definition_count'], :<, metrics['parcel_count']
    assert_operator metrics['unique_site_face_count'], :<, metrics['expanded_site_face_count']
  end

  def test_the_higher_parcel_closes_the_step_with_its_plinth
    result = ok_site(STREET, &slope)
    second = result.value['parcels'][1]
    nodes = result.value['definitions'].fetch(second['site_definition_id'])['nodes']
    groups = nodes.first['children']
    plinth = groups.find { |n| n['id'] == 'site/plinth' }
    assert plinth
    left = plinth['children'].find { |n| n['id'] == 'site/plinth/left' }
    assert left, plinth['children'].map { |n| n['id'] }.inspect
    lowest = left['primitive']['vertices'].map { |v| v[2] }.min
    assert_in_delta(-(0.6 + 0.05), lowest, 1e-3)
  end

  # --- Le trapèze.

  def test_a_corner_parcel_counts_the_terrain_at_its_acute_corner_only_inside
    settings = settings_for(ELBOW)
    layout = EnsembleEngine.layout_for(settings, registry: registry).value
    corner = layout['parcels'].find { |p| p['delta_right_m'].positive? }
    # Boîte du trapèze : un point hors du trapèze ne doit pas relever sa plateforme.
    assert_operator corner['delta_right_m'], :>, 0.0
    chosen = site
    axes = EnsembleSite.axes_for(corner, chosen).value
    high_x = axes['xs_m'].last
    high_y = axes['ys_m'].last
    rows = axes['ys_m'].map { |y| axes['xs_m'].map { |x| x == high_x && y == high_y ? 150.0 : 100.0 } }
    grid = SurveyGrid.new('schema_version' => 1, 'xs_m' => axes['xs_m'], 'ys_m' => axes['ys_m'], 'z_m' => rows)
    ring = Archgen::Geometry::FootprintSolver.trapezoid(width_m: corner['width_m'], depth_m: corner['depth_m'], delta_left_m: corner['delta_left_m'], delta_right_m: corner['delta_right_m']).ring
    result = SiteAssise.for_ring(grid, chosen, ring: ring)
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_operator result.value['platform_z_m'], :<, 150.0
    assert_equal 0.0, result.value['cut_max_m']
    assert_equal 0.0, result.value['cut_volume_m3'], 'pas de déblai annoncé pour un angle hors de la parcelle'
  end

  def test_a_hole_outside_the_cells_of_the_trapezoid_is_not_refused_but_one_inside_is
    chosen = site('survey' => { 'step_m' => 1.0 })
    ring = Archgen::Geometry::FootprintSolver.trapezoid(width_m: 12.0, depth_m: 9.0, delta_left_m: 0.0, delta_right_m: 9.0).ring
    axes = SurveyGrid.plan_box(x_min_m: 0.0, x_max_m: 12.0, depth_m: 9.0, settings: chosen).value
    holed = lambda do |hx, hy|
      rows = axes['ys_m'].map { |y| axes['xs_m'].map { |x| x == hx && y == hy ? nil : 100.0 } }
      SurveyGrid.new('schema_version' => 1, 'xs_m' => axes['xs_m'], 'ys_m' => axes['ys_m'], 'z_m' => rows)
    end
    assert SiteAssise.for_ring(holed.call(12.0, 9.0), chosen, ring: ring).ok?
    refused = SiteAssise.for_ring(holed.call(1.0, 1.0), chosen, ring: ring)
    refute refused.ok?
    assert_equal 'E_SITE_SURVEY', refused.errors.first.code
  end

  def test_a_reentrant_corner_surveys_below_zero
    tree = { 'trace' => { 'points_m' => [[0, 0], [48, 0], [48, -48]], 'closed' => false }, 'building' => { 'profile' => { 'id' => 'brutalist' } } }
    settings = settings_for(tree)
    layout = EnsembleEngine.layout_for(settings, registry: registry).value
    reentrant = layout['parcels'].find { |p| p['delta_left_m'].negative? || p['delta_right_m'].negative? }
    assert reentrant
    axes = EnsembleSite.axes_for(reentrant, site).value
    span = axes['xs_m'].last - axes['xs_m'].first
    assert_operator span, :>, reentrant['width_m']
    assert ok_site(tree, &slope)
  end

  def test_corner_plans_pass_the_validator_with_their_slanted_plinths
    result = ok_site(ELBOW) { |x, y| 100.0 + (0.08 * x) + (0.03 * y) + (0.2 * Math.sin(x / 7.0)) }
    assert_operator result.value['metrics']['expanded_site_face_count'], :>, 0
  end

  # --- Refus et avertissements, localisés sur la parcelle.

  # --- U73 : talus en rangée droite et soutènement mitoyen (docs/TEINTES_ABORDS_CONTRACT.md, AG-109).

  def test_embankment_is_refused_at_a_bend
    settings = settings_for(ELBOW)
    plan = EnsembleEngine.call(settings, registry: registry, intake: intake).value
    layout = EnsembleEngine.layout_for(settings, registry: registry).value
    refused = EnsembleSite.requests(plan, layout, site('earthwork' => 'embankment'))
    refute refused.ok?
    assert_equal 'E_STREET_SITE', refused.errors.first.code
    assert_equal '/site/earthwork', refused.errors.first.path
    assert_equal 'embankment_bend', refused.errors.first.params['reason']
  end

  def site_nodes(result, parcel)
    result.value['definitions'].fetch(parcel['site_definition_id'])['nodes'].first['children']
  end

  def test_a_straight_row_gets_front_and_rear_embankments_and_retaining_walls
    result = ok_site(STREET, { 'earthwork' => 'embankment' }) { |x, y| 100.0 + (0.08 * x) + (0.05 * y) }
    parcels = result.value['parcels']
    assert_operator parcels.size, :>, 2
    levels = parcels.map { |p| p['platform_z_m'] }
    assert_operator levels.uniq.size, :>, 1, 'plateformes étagées'
    parcels.each_with_index do |parcel, i|
      ids = site_nodes(result, parcel).map { |n| n['id'] }
      assert_includes ids, 'site/embankment'
      assert_includes ids, 'site/plinth', 'côté mitoyen en soubassement'
      walls = site_nodes(result, parcel).find { |n| n['id'] == 'site/retaining' }
      if i < parcels.size - 1 && (levels[i + 1] - levels[i]).abs > 0.01
        refute_nil walls, "soutènement à droite de #{parcel['id']}"
        walls['children'].each do |wall|
          xs = wall['primitive']['vertices'].map { |v| v[0].round(6) }.uniq
          assert_equal 1, xs.size, 'dans le plan de la limite mitoyenne'
          assert(wall['primitive']['faces'].all? { |f| f['material'] == 'concrete' })
        end
      end
      embankment = site_nodes(result, parcel).find { |n| n['id'] == 'site/embankment' }['children'].map { |n| n['id'] }
      assert_includes embankment, 'site/embankment/front'
      assert_equal i.zero?, embankment.include?('site/embankment/left')
      assert_equal i == parcels.size - 1, embankment.include?('site/embankment/right')
    end
  end

  def test_the_survey_budget_is_checked_before_any_ray
    tree = { 'trace' => { 'points_m' => [[0, 0], [1200, 0]], 'closed' => false }, 'building' => { 'profile' => { 'id' => 'brutalist' } } }
    settings = settings_for(tree)
    plan = EnsembleEngine.call(settings, registry: registry, intake: intake, limits: { unique: 10**9, expanded: 10**9 }).value
    layout = EnsembleEngine.layout_for(settings, registry: registry).value
    refused = EnsembleSite.requests(plan, layout, site('survey' => { 'step_m' => 0.5 }))
    refute refused.ok?
    assert_equal 'E_SITE_BUDGET', refused.errors.first.code
    assert_equal 'survey_points', refused.errors.first.params['reason']
  end

  def test_relief_is_refused_on_the_parcel
    refused = run_site(STREET) { |x, _y| x > 24.0 ? 100.0 + (x - 24.0) : 100.0 }
    refute refused.ok?
    found = refused.errors.find { |d| d.code == 'E_SITE_RELIEF' }
    assert found, refused.errors.map(&:to_h).inspect
    assert_match %r{\A/parcels/[^/]+/\d+/\d+/site/platform\z}, found.path
  end

  def test_a_hole_is_refused_on_the_parcel_without_interpolating
    refused = run_site(STREET) { |x, _y| x > 30.0 && x < 34.0 ? nil : 100.0 }
    refute refused.ok?
    found = refused.errors.find { |d| d.code == 'E_SITE_SURVEY' }
    assert found
    assert_match %r{\A/parcels/}, found.path
  end

  def test_mean_policy_can_bury_a_door_on_the_parcel
    refused = run_site(STREET, { 'platform' => { 'policy' => 'mean', 'offset_m' => -2.0 } }) { 100.0 }
    refute refused.ok?
    found = refused.errors.find { |d| d.code == 'E_SITE_DOOR_BURIED' }
    assert found, refused.errors.map(&:to_h).inspect
    assert_match %r{\A/parcels/}, found.path
  end

  def test_door_gap_warns_on_each_parcel
    result = ok_site(STREET, { 'entrance' => 'none' }) { |_x, y| 100.0 + (0.1 * y) }
    warnings = result.diagnostics.select { |d| d.code == 'W_SITE_DOOR_GAP' }
    assert_equal 4, warnings.size
    stepped = ok_site(STREET) { |_x, y| 100.0 + (0.1 * y) } # AG-105 : perron par défaut, seuils résolus
    assert_empty(stepped.diagnostics.select { |d| d.code == 'W_SITE_DOOR_GAP' })
    assert(warnings.all? { |d| d.path.start_with?('/parcels/') })
  end

  # --- Porche.

  def test_a_porch_passage_buried_at_its_rear_is_refused
    refused = run_site(SQUARE_PORCH, { 'platform' => { 'policy' => 'mean', 'offset_m' => -1.5 } }) { 100.0 }
    refute refused.ok?
    found = refused.errors.find { |d| d.params['reason'] == 'passage_buried' }
    assert found, refused.errors.map(&:to_h).inspect
    assert_equal 'E_SITE_DOOR_BURIED', found.code
  end

  def test_a_porch_gap_warns
    result = ok_site(SQUARE_PORCH) { |x, y| 100.0 + (0.1 * x) + (0.1 * y) }
    assert(result.diagnostics.any? { |d| d.params['reason'] == 'passage_gap' }, result.diagnostics.map(&:to_h).inspect)
  end

  def test_structural_porch_floor_reaches_both_ends_of_the_passage
    tree = SQUARE_PORCH.merge('building' => { 'profile' => { 'id' => 'haussmann' }, 'mode' => 'structural' })
    shell = ok_site(SQUARE_PORCH) { 100.0 }
    structural = ok_site(tree) { 100.0 }
    count = ->(result) { result.value['definitions'].values.map { |d| d['nodes'].first['children'].find { |n| n['id'] == 'site/platform' }['primitive']['faces'].size } }
    assert_equal [1], count.call(shell).uniq
    assert_includes count.call(structural), 3
    assert_includes count.call(structural), 1
  end

  # --- Plafonds.

  def test_total_faces_are_checked_against_the_ensemble_limits
    settings = settings_for(STREET)
    plan = EnsembleEngine.call(settings, registry: registry, intake: intake, materials: Archgen::Composition.materials.fetch('materials')).value
    layout = EnsembleEngine.layout_for(settings, registry: registry).value
    chosen = site
    grids = grids_for(EnsembleSite.requests(plan, layout, chosen).value, &slope)
    refused = EnsembleSite.call(settings: settings, site: chosen, plan: plan, layout: layout, grids: grids, root_z_m: 100.0, registry: registry, intake: intake, materials: catalog,
                                limits: { unique: plan['metrics']['unique_face_count'], expanded: 10**9 })
    refute refused.ok?
    assert_equal 'E_SITE_BUDGET', refused.errors.first.code
  end

  def test_max_step_closes_a_closed_contour
    result = ok_site(SQUARE_PORCH) { |x, _y| 100.0 + (0.05 * x) }
    assert_operator result.value['metrics']['max_step_m'], :>, 0.0
    assert_equal result.value['parcels'].size, result.value['metrics']['parcel_count']
  end
end
