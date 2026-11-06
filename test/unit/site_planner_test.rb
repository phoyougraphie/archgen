# frozen_string_literal: true

require_relative '../test_helper'

# U14 : plan d'assise, soubassement et plancher (docs/TERRAIN_CONTRACT.md). Les mesures passent
# par Geo, indépendant du noyau.
class SitePlannerTest < Minitest::Test
  include Archgen::Core
  SitePlanner = Archgen::Geometry::SitePlanner

  WIDTH = 12.0
  DEPTH = 9.0
  NORMALS = { 'front' => [0, -1, 0], 'right' => [1, 0, 0], 'rear' => [0, 1, 0], 'left' => [-1, 0, 0] }.freeze

  def intake
    @intake ||= Archgen::Composition.site_intake
  end

  def building(name = 'rect-neutre-shell', **blocks)
    base = TestData.intake.effective(TestData.building(name)).value
    config = BuildingConfig.new(Merge.leaves(base, blocks.transform_keys(&:to_s)))
    plan = GeometryEngine.generate(config, materials: TestData.materials)
    assert plan.ok?, plan.errors.map(&:to_h).inspect
    [config.to_h, plan.value]
  end

  def slope(gradient = 0.08)
    settings = intake.settings({}).value
    axes = SurveyGrid.plan(width_m: WIDTH, depth_m: DEPTH, settings: settings).value
    { 'schema_version' => 1, 'xs_m' => axes['xs_m'], 'ys_m' => axes['ys_m'],
      'z_m' => axes['ys_m'].map { |y| axes['xs_m'].map { |x| block_given? ? yield(x, y) : 100.0 + (gradient * x) } } }
  end

  # Ruby range `'platform' => x` parmi les mots-clés : les clés chaînes sont les réglages d'assise.
  def plan_site(tree = fixture_json('examples', 'terrain', 'pente-8pct-12x9.json'), draft = {}, name: 'rect-neutre-shell', **options)
    settings = intake.settings(draft.merge(options.select { |key, _| key.is_a?(String) })).value
    config, plan = building(name, **options.select { |key, _| key.is_a?(Symbol) })
    grid = intake.grid(tree, width_m: WIDTH, depth_m: DEPTH, settings: settings).value
    assise = SiteAssise.call(grid, settings, width_m: WIDTH, depth_m: DEPTH).value
    SitePlanner.call(plan: plan, config: config, grid: grid, settings: settings, assise: assise)
  end

  def site(*args, **options)
    result = plan_site(*args, **options)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result
  end

  def strip(result, facade)
    Geo.find_node(result.value['nodes'], "site/plinth/#{facade}")
  end

  def points(result, facade)
    primitive = strip(result, facade)['primitive']
    primitive['faces'].map { |face| Geo.polygon(primitive, face) }
  end

  def assert_refused(result, code, path, reason = nil)
    refute result.ok?, 'attendu un refus'
    found = result.errors.find { |d| d.code == code && d.path == path }
    assert found, result.errors.map(&:to_h).inspect
    assert_equal reason, found.params['reason'] if reason
    found
  end

  # --- Structure

  def test_plan_structure_and_categories
    plan = site.value
    assert_equal [1, 'm'], plan.values_at('schema_version', 'units')
    assert_equal ['site'], plan['nodes'].map { |n| n['id'] }
    assert_empty SitePlanValidator.call(plan, materials: TestData.materials)
    categories = []
    Geo.walk(plan['nodes']) { |n| categories << n['category'] }
    assert_equal %w[platform plinth site], categories.uniq.sort
    assert_predicate plan, :frozen?
  end

  def test_all_faces_use_the_plinth_material
    plan = site(fixture_json('examples', 'terrain', 'pente-8pct-12x9.json'), 'plinth_material' => 'limestone').value
    materials = []
    Geo.walk(plan['nodes']) { |n| n['primitive'] && n['primitive']['faces'].each { |f| materials << f['material'] } }
    assert_equal ['limestone'], materials.uniq
  end

  def test_metrics_repeat_the_assise_and_count_faces
    metrics = site.value['metrics']
    assert_in_delta 100.96, metrics['platform_z_m']
    assert_in_delta 0.96, metrics['fill_max_m']
    counted = 0
    Geo.walk(site.value['nodes']) { |n| counted += n['primitive']['faces'].size if n['primitive'] }
    assert_equal counted, metrics['site_face_count']
  end

  # --- Soubassement

  def test_strips_stand_in_the_plane_of_each_wall_and_face_outward
    result = site
    %w[front right rear left].each do |facade|
      points(result, facade).each do |polygon|
        normal = Geo.unit_normal(polygon)
        NORMALS[facade].each_with_index { |value, i| assert_in_delta value, normal[i], 1e-6, facade }
      end
    end
    assert(points(result, 'front').flatten(1).all? { |p| p[1].zero? })
    assert(points(result, 'right').flatten(1).all? { |p| p[0] == WIDTH })
    assert(points(result, 'rear').flatten(1).all? { |p| p[1] == DEPTH })
    assert(points(result, 'left').flatten(1).all? { |p| p[0].zero? })
  end

  def test_strip_bottom_is_terrain_minus_the_toe
    points(site, 'front').flatten(1).select { |p| p[2].negative? }.each do |p|
      assert_in_delta(-0.96 + (0.08 * p[0]) - SitePlanner::TOE_M, p[2], 1e-6)
    end
  end

  def test_front_strip_area_matches_the_slope
    assert_in_delta 6.36, points(site, 'front').sum { |polygon| Geo.area(polygon) }, 1e-5
  end

  def test_uphill_strip_reduces_to_the_toe_and_downhill_to_the_full_height
    assert_in_delta 9 * 0.05, points(site, 'right').sum { |polygon| Geo.area(polygon) }, 1e-5
    assert_in_delta 9 * 1.01, points(site, 'left').sum { |polygon| Geo.area(polygon) }, 1e-5
  end

  def test_neighbouring_strips_share_their_corner
    result = site
    corner = [WIDTH, 0.0]
    front = points(result, 'front').flatten(1).select { |p| p[0, 2] == corner }.map { |p| p[2] }
    right = points(result, 'right').flatten(1).select { |p| p[0, 2] == corner }.map { |p| p[2] }
    assert_equal front.uniq.sort, right.uniq.sort
    refute_empty front
  end

  def test_no_strip_where_terrain_is_above_the_platform
    result = site(fixture_json('examples', 'terrain', 'pente-8pct-12x9.json'), 'platform' => { 'policy' => 'mean' })
    assert_nil strip(result, 'right'), 'le terrain passe partout au-dessus du bas du mur'
    refute_nil strip(result, 'left')
    xs = points(result, 'front').flatten(1).map { |p| p[0] }
    assert_in_delta 6.625, xs.max, 1e-5, 'point de passage à terrain − 0,05 m = 0'
    assert(points(result, 'front').flatten(1).all? { |p| p[2] <= 0.0 })
  end

  def test_buried_strip_ends_with_a_triangle
    result = site(fixture_json('examples', 'terrain', 'pente-8pct-12x9.json'), 'platform' => { 'policy' => 'mean' })
    assert_equal 3, points(result, 'front').last.size
    assert_equal 3, points(result, 'front').map(&:size).min
    assert_equal 4, points(result, 'front').first.size
  end

  def test_ground_above_the_whole_perimeter_is_refused_by_the_door
    # Sans bande sur aucune façade, le seuil est forcément sous le terrain.
    assert_refused plan_site(slope { 100.0 }, 'platform' => { 'offset_m' => -1 }), 'E_SITE_DOOR_BURIED', '/site/platform'
  end

  def test_flat_ground_gets_a_hidden_toe_only
    result = site(slope { 100.0 })
    assert_in_delta 2 * (WIDTH + DEPTH) * 0.05, %w[front right rear left].sum { |f| points(result, f).sum { |polygon| Geo.area(polygon) } }, 1e-5
  end

  # --- Cas limites des arêtes courtes

  def test_strip_cell_keeps_every_edge_at_least_two_millimetres
    limit = Quant::MIN_EDGE_M - Quant::EPSILON
    samples = [-3.0, -0.2, -0.003, -0.002, -0.0019, 0.0, 0.0019, 0.002, 0.003, 0.2, 3.0]
    samples.product(samples).each do |b0, b1|
      cell = SitePlanner.strip_cell(1.0, b0, 3.0, b1)
      next unless cell

      cell.each_with_index do |(u, z), i|
        nu, nz = cell[(i + 1) % cell.size]
        assert_operator Math.hypot(nu - u, nz - z), :>=, limit, "#{b0} #{b1} #{cell.inspect}"
      end
      assert_operator cell.size, :>=, 3
    end
  end

  def test_strip_cell_cases
    assert_nil SitePlanner.strip_cell(0.0, 0.5, 2.0, 0.5)
    assert_nil SitePlanner.strip_cell(0.0, 0.0, 2.0, 0.0)
    assert_equal [[0.0, -1.0], [2.0, -1.0], [2.0, 0.0], [0.0, 0.0]], SitePlanner.strip_cell(0.0, -1.0, 2.0, -1.0)
    assert_equal [[0.0, -1.0], [1.0, 0.0], [0.0, 0.0]], SitePlanner.strip_cell(0.0, -1.0, 2.0, 1.0)
    assert_equal [[1.0, 0.0], [2.0, -1.0], [2.0, 0.0]], SitePlanner.strip_cell(0.0, 1.0, 2.0, -1.0)
    assert_equal [[0.0, -1.0], [2.0, 0.0], [0.0, 0.0]], SitePlanner.strip_cell(0.0, -1.0, 2.0, 0.001)
  end

  def test_sliver_triangles_are_omitted
    assert_nil SitePlanner.strip_cell(0.0, -0.003, 2.0, 6.0), 'triangle de moins de 2 mm'
    assert_nil SitePlanner.strip_cell(0.0, 6.0, 2.0, -0.003)
  end

  def test_steep_noisy_ground_always_validates
    tree = slope { |x, y| 100.0 + (2.9 * Math.sin((x * 1.7) + (y * 2.3))) }
    [{}, { 'platform' => { 'policy' => 'mean' } }, { 'platform' => { 'policy' => 'high', 'offset_m' => -1.5 } }].each do |draft|
      result = plan_site(tree, draft, name: 'rect-neutre-structural', facade: { 'entry_bay' => 0 })
      next if result.errors.any? { |d| d.code == 'E_SITE_DOOR_BURIED' }

      assert result.ok?, result.errors.map(&:to_h).inspect
    end
  end

  # --- Plancher

  def test_platform_covers_the_footprint_in_shell
    polygon = Geo.polygon(Geo.find_node(site.value['nodes'], 'site/platform')['primitive'], Geo.find_node(site.value['nodes'], 'site/platform')['primitive']['faces'].first)
    assert_equal [[0.0, 0.0, 0.0], [12.0, 0.0, 0.0], [12.0, 9.0, 0.0], [0.0, 9.0, 0.0]], polygon
    assert_in_delta 1.0, Geo.unit_normal(polygon)[2]
  end

  def test_platform_is_inset_by_the_wall_in_structural
    node = Geo.find_node(site(name: 'rect-neutre-structural').value['nodes'], 'site/platform')
    polygon = Geo.polygon(node['primitive'], node['primitive']['faces'].first)
    assert_equal [[0.24, 0.24, 0.0], [11.76, 0.24, 0.0], [11.76, 8.76, 0.0], [0.24, 8.76, 0.0]], polygon
  end

  def test_structural_keeps_the_same_strips
    shell = site
    structural = site(name: 'rect-neutre-structural')
    %w[front right rear left].each { |facade| assert_equal strip(shell, facade), strip(structural, facade) }
  end

  # --- Porte et baies

  def test_door_far_above_the_ground_warns_with_its_height
    result = site
    warning = result.warnings.find { |d| d.code == 'W_SITE_DOOR_GAP' }
    refute_nil warning
    assert_in_delta 0.588, warning.params['value'], 1e-5
    assert_in_delta 0.588, result.value['metrics']['door_gap_m'], 1e-5
    assert_equal 'door_gap', warning.params['reason']
  end

  def test_gap_exactly_at_the_limit_stays_silent
    door_center = 4.65
    tree = slope { |x, _y| 100.0 + (0.08 * x) }
    high = 100.96
    offset = (100.0 + (0.08 * door_center) + 0.20) - high
    result = site(tree, 'platform' => { 'offset_m' => offset })
    assert_in_delta 0.20, result.value['metrics']['door_gap_m'], 1e-5
    assert_empty result.warnings.select { |d| d.code == 'W_SITE_DOOR_GAP' }
  end

  def test_door_below_the_ground_is_refused_and_located
    result = plan_site(fixture_json('examples', 'terrain', 'pente-8pct-12x9.json'), { 'platform' => { 'offset_m' => -0.5 } }, facade: { 'entry_bay' => 3 })
    found = assert_refused result, 'E_SITE_DOOR_BURIED', '/site/platform', 'door_buried'
    assert_equal 'opening/front/0/3', found.params['id']
    assert_operator found.params['value'], :>, 0.3
    assert_nil result.value
  end

  def test_door_within_the_tolerance_is_accepted
    door_edge = 5.15
    offset = (100.0 + (0.08 * door_edge) - 0.02) - 100.96
    assert plan_site(slope, 'platform' => { 'offset_m' => offset }).ok?
    assert_refused plan_site(slope, 'platform' => { 'offset_m' => offset - 0.001 }), 'E_SITE_DOOR_BURIED', '/site/platform'
  end

  def test_only_the_high_edge_of_the_door_is_buried
    door_edge = 5.15
    offset = (100.0 + (0.08 * door_edge) - 0.03) - 100.96
    found = assert_refused plan_site(slope, 'platform' => { 'offset_m' => offset }), 'E_SITE_DOOR_BURIED', '/site/platform'
    assert_in_delta 0.03, found.params['value'], 1e-5, 'mesuré au bord haut, le milieu reste sous le seuil'
  end

  def test_terrain_above_platform_warns_with_height_and_touched_openings
    result = site(slope(0.2), 'platform' => { 'policy' => 'mean' })
    warning = result.warnings.find { |d| d.code == 'W_SITE_BURIED' }
    refute_nil warning
    assert_in_delta 1.2, warning.params['value'], 1e-5
    assert_equal 2, warning.params['count'], 'dernière fenêtre du RDC, en façade avant et arrière'
    assert_equal 2, result.value['metrics']['buried_opening_count']
  end

  def test_high_policy_buries_nothing
    result = site
    assert_empty result.warnings.select { |d| d.code == 'W_SITE_BURIED' }
    assert_equal 0, result.value['metrics']['buried_opening_count']
  end

  # --- Refus et budgets

  def test_budget_exact_limits_and_first_overflow
    small = { 'expanded_face_count' => 100, 'unique_face_count' => 100 }
    assert_empty SitePlanner.budget_problems({ 'site_face_count' => Limits::SITE_MAX_FACES }, small)
    over = SitePlanner.budget_problems({ 'site_face_count' => Limits::SITE_MAX_FACES + 1 }, small)
    assert_equal ['site_faces'], over.map { |d| d.params['reason'] }
    assert_equal ['/site/survey/step_m'], over.map(&:path)
  end

  def test_total_with_the_building_is_bounded
    fits = { 'expanded_face_count' => Limits::MAX_EXPANDED_FACES - 10, 'unique_face_count' => 100 }
    assert_empty SitePlanner.budget_problems({ 'site_face_count' => 10 }, fits)
    assert_equal ['total_faces'], SitePlanner.budget_problems({ 'site_face_count' => 11 }, fits).map { |d| d.params['reason'] }
    unique = { 'expanded_face_count' => 100, 'unique_face_count' => Limits::MAX_UNIQUE_FACES - 10 }
    assert_equal ['total_faces'], SitePlanner.budget_problems({ 'site_face_count' => 11 }, unique).map { |d| d.params['reason'] }
  end

  # --- Déterminisme et bâtiment intact

  def test_same_input_same_digest
    assert_equal SitePlanner.digest(site.value), SitePlanner.digest(site.value)
  end

  def test_order_of_openings_does_not_change_the_plan
    settings = intake.settings({}).value
    config, plan = building
    grid = intake.grid(slope, width_m: WIDTH, depth_m: DEPTH, settings: settings).value
    assise = SiteAssise.call(grid, settings, width_m: WIDTH, depth_m: DEPTH).value
    direct = SitePlanner.call(plan: plan, config: config, grid: grid, settings: settings, assise: assise)
    shuffled = plan.merge('openings' => plan['openings'].reverse)
    reversed = SitePlanner.call(plan: shuffled, config: config, grid: grid, settings: settings, assise: assise)
    assert_equal SitePlanner.digest(direct.value), SitePlanner.digest(reversed.value)
  end

  def test_other_terrain_or_setting_changes_the_digest
    base = SitePlanner.digest(site.value)
    refute_equal base, SitePlanner.digest(site(slope(0.05)).value)
    refute_equal base, SitePlanner.digest(site(fixture_json('examples', 'terrain', 'pente-8pct-12x9.json'), 'plinth_material' => 'limestone').value)
  end

  def test_building_plan_is_not_touched
    settings = intake.settings({}).value
    config, plan = building
    before = GeometryEngine.plan_digest(plan)
    grid = intake.grid(slope, width_m: WIDTH, depth_m: DEPTH, settings: settings).value
    assise = SiteAssise.call(grid, settings, width_m: WIDTH, depth_m: DEPTH).value
    SitePlanner.call(plan: plan, config: config, grid: grid, settings: settings, assise: assise)
    assert_equal before, GeometryEngine.plan_digest(plan)
    assert_equal fixture_json('test', 'fixtures', 'plan_digests.json').fetch('rect-neutre-shell'), before
  end

  def test_building_validator_still_refuses_site_categories
    config, plan = building
    assert config
    node = Marshal.load(Marshal.dump(plan))
    node['nodes'].first['children'] << { 'id' => 'x', 'category' => 'plinth', 'children' => [] }
    reasons = PlanValidator.call(node, materials: TestData.materials).map { |d| d.params['reason'] }
    assert_includes reasons, 'unknown_category'
  end

  # --- Validateur

  def valid_copy
    Marshal.load(Marshal.dump(site.value))
  end

  def reasons(plan)
    SitePlanValidator.call(plan, materials: TestData.materials).map { |d| d.params['reason'] }
  end

  def test_validator_refuses_a_bad_header
    assert_includes reasons(valid_copy.merge('units' => 'in')), 'bad_header'
    assert_includes reasons(valid_copy.reject { |k, _| k == 'metrics' }), 'missing_metrics'
  end

  def test_validator_refuses_a_second_root_or_a_building_category
    plan = valid_copy
    plan['nodes'] << plan['nodes'].first
    assert_includes reasons(plan), 'single_site_root'
    plan = valid_copy
    plan['nodes'].first['children'] << { 'id' => 'x', 'category' => 'wall', 'children' => [] }
    assert_includes reasons(plan), 'unknown_category'
  end

  def test_validator_refuses_wrong_counts_and_materials
    plan = valid_copy
    plan['metrics']['site_face_count'] += 1
    assert_includes reasons(plan), 'metric_mismatch'
    plan = valid_copy
    Geo.find_node(plan['nodes'], 'site/platform')['primitive']['faces'].first['material'] = 'unobtainium'
    assert_includes reasons(plan), 'unknown_material'
  end

  def test_validator_refuses_bad_geometry
    plan = valid_copy
    Geo.find_node(plan['nodes'], 'site/platform')['primitive']['vertices'][0] = [0.1234567, 0.0, 0.0]
    assert_includes reasons(plan), 'unquantized_vertex'
    plan = valid_copy
    Geo.find_node(plan['nodes'], 'site/platform')['primitive']['faces'].first['indices'] = [0, 1, 2, 9]
    assert_includes reasons(plan), 'invalid_indices'
  end
end
