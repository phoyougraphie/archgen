# frozen_string_literal: true

require_relative '../test_helper'

# U13 : réglages d'assise, grille de relevé, plateforme et relief (docs/TERRAIN_CONTRACT.md).
class SiteTest < Minitest::Test
  include Archgen::Core

  WIDTH = 12.0
  DEPTH = 9.0
  BUDGET_ROWS = 60
  BUDGET_COLUMNS = 50

  def intake
    @intake ||= Archgen::Composition.site_intake
  end

  def settings(draft = {})
    result = intake.settings(draft)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def fixture(name)
    fixture_json('examples', 'terrain', "#{name}.json")
  end

  def grid(tree = fixture('pente-8pct-12x9'), config = settings, width: WIDTH, depth: DEPTH)
    result = intake.grid(tree, width_m: width, depth_m: depth, settings: config)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def assise(name = 'pente-8pct-12x9', draft = {})
    config = settings(draft)
    SiteAssise.call(grid(fixture(name), config), config, width_m: WIDTH, depth_m: DEPTH)
  end

  def built_grid(width: WIDTH, depth: DEPTH, config: settings)
    axes = SurveyGrid.plan(width_m: width, depth_m: depth, settings: config).value
    z = axes['ys_m'].map { |y| axes['xs_m'].map { |x| yield(x, y) } }
    { 'schema_version' => 1, 'xs_m' => axes['xs_m'], 'ys_m' => axes['ys_m'], 'z_m' => z }
  end

  def assert_refused(result, code, path, reason = nil)
    refute result.ok?, 'attendu un refus'
    assert_nil result.value
    found = result.errors.find { |d| d.path == path && d.code == code }
    assert found, result.errors.map(&:to_h).inspect
    assert_equal reason, found.params['reason'] if reason
  end

  # --- Réglages

  def test_defaults_are_those_of_the_contract
    config = settings
    assert_equal 1, config['site_version']
    assert_equal({ 'policy' => 'high', 'offset_m' => 0.0 }, config['platform'])
    assert_equal 'plinth', config['earthwork']
    assert_in_delta 1.5, config['embankment_ratio']
    assert_equal 'concrete', config['plinth_material']
    assert_in_delta 2.0, config.dig('survey', 'step_m')
    assert_predicate config, :frozen?
  end

  def test_partial_input_keeps_the_other_defaults
    config = settings('platform' => { 'offset_m' => 1 })
    assert_equal 'high', config.dig('platform', 'policy')
    assert_in_delta 1.0, config.dig('platform', 'offset_m')
    assert_instance_of Float, config.dig('platform', 'offset_m')
  end

  def test_hostile_settings_are_refused_with_their_path
    {
      { 'evil' => 1 } => '/site/evil',
      { 'platform' => { 'evil' => 1 } } => '/site/platform/evil',
      { 'platform' => { 'policy' => 'low' } } => '/site/platform/policy',
      { 'platform' => { 'offset_m' => 2.001 } } => '/site/platform/offset_m',
      { 'platform' => { 'offset_m' => -2.001 } } => '/site/platform/offset_m',
      { 'earthwork' => 'cut' } => '/site/earthwork',
      { 'embankment_ratio' => 0 } => '/site/embankment_ratio',
      { 'embankment_ratio' => 3.001 } => '/site/embankment_ratio',
      { 'plinth_material' => 'http://evil/x.png' } => '/site/plinth_material',
      { 'plinth_material' => 'unobtainium' } => '/site/plinth_material',
      { 'survey' => { 'step_m' => 0.499 } } => '/site/survey/step_m',
      { 'survey' => { 'step_m' => 5.001 } } => '/site/survey/step_m',
      { 'survey' => { 'step_m' => '2' } } => '/site/survey/step_m'
    }.each { |draft, path| assert_refused intake.settings(draft), 'E_SCHEMA', path }
  end

  def test_exact_bounds_are_accepted
    [{ 'platform' => { 'offset_m' => 2 } }, { 'platform' => { 'offset_m' => -2 } }, { 'embankment_ratio' => 1 }, { 'embankment_ratio' => 3 },
     { 'survey' => { 'step_m' => 0.5 } }, { 'survey' => { 'step_m' => 5 } }].each { |draft| assert intake.settings(draft).ok?, draft.inspect }
  end

  def test_json_text_is_bounded_and_strict
    assert_refused intake.settings('{"earthwork":"plinth","earthwork":"embankment"}'), 'E_SCHEMA', '/site/earthwork', 'duplicate_key'
    assert_refused intake.settings('pas du json'), 'E_SCHEMA', '/site', 'invalid_json'
    assert_refused intake.settings(%({"plinth_material":"#{'x' * 70_000}"})), 'E_SCHEMA', '/site', 'too_large'
    assert_refused intake.settings('[]'), 'E_SCHEMA', '/site', 'type'
  end

  def test_future_version_has_its_own_code
    assert_refused intake.settings('site_version' => 2), 'E_VERSION', '/site/site_version', 'unsupported'
    assert_refused intake.stored_settings(settings.merge('site_version' => 2)), 'E_VERSION', '/site/site_version'
  end

  def test_stored_settings_get_no_default
    complete = settings('earthwork' => 'embankment')
    assert_equal complete, intake.stored_settings(Canonical.dump(complete)).value
    assert_refused intake.stored_settings(complete.reject { |k, _| k == 'embankment_ratio' }), 'E_SCHEMA', '/site/embankment_ratio', 'required'
    partial = complete.merge('platform' => { 'policy' => 'high' })
    assert_refused intake.stored_settings(partial), 'E_SCHEMA', '/site/platform/offset_m', 'required'
  end

  # --- Axes

  def test_axes_always_reach_both_ends_without_a_sliver
    axes = SurveyGrid.plan(width_m: 12.001, depth_m: 9.0, settings: settings).value
    assert_equal 0.0, axes['xs_m'].first
    assert_equal 12.001, axes['xs_m'].last
    assert_equal 8, axes['xs_m'].size, 'sept intervalles égaux plutôt qu’un intervalle de 1 mm au bout'
    assert_equal [0.0, 1.8, 3.6, 5.4, 7.2, 9.0], axes['ys_m']
    gaps = axes['xs_m'].each_cons(2).map { |a, b| b - a }
    assert_in_delta gaps.min, gaps.max, 1e-5
    assert_operator gaps.max, :<=, 2.0
  end

  def test_short_side_keeps_both_ends
    axes = SurveyGrid.plan(width_m: 1.0, depth_m: 1.0, settings: settings).value
    assert_equal [0.0, 1.0], axes['xs_m']
  end

  def test_margin_covers_the_highest_fill_the_settings_allow
    config = settings('earthwork' => 'embankment', 'embankment_ratio' => 2, 'platform' => { 'offset_m' => -1 })
    assert_in_delta 16.0, SurveyGrid.margin_m(config)
    axes = SurveyGrid.plan(width_m: WIDTH, depth_m: DEPTH, settings: config).value
    assert_operator axes['xs_m'].first, :<=, -16.0
    assert_operator axes['xs_m'].last, :>=, WIDTH + 16.0
    assert_includes axes['xs_m'], 0.0
    assert_includes axes['xs_m'], WIDTH
  end

  def test_plinth_needs_no_margin
    assert_equal 0.0, SurveyGrid.margin_m(settings)
  end

  def test_point_budget_exact_limit_and_first_overflow
    config = settings('survey' => { 'step_m' => 1 })
    exact = SurveyGrid.plan(width_m: (BUDGET_COLUMNS - 1).to_f, depth_m: (BUDGET_ROWS - 1).to_f, settings: config)
    assert exact.ok?
    assert_equal Limits::SITE_MAX_SURVEY_POINTS, exact.value['xs_m'].size * exact.value['ys_m'].size
    over = SurveyGrid.plan(width_m: BUDGET_COLUMNS.to_f, depth_m: (BUDGET_ROWS - 1).to_f, settings: config)
    assert_refused over, 'E_SITE_BUDGET', '/site/survey/step_m', 'survey_points'
    assert_equal SurveyGrid::HINT, over.errors.first.params['hint']
    assert_equal 3060, over.errors.first.params['value']
  end

  # --- Grille

  def test_fixtures_are_read_and_quantized
    read = grid
    assert_equal 7, read.xs.size
    assert_equal 6, read.ys.size
    assert_in_delta 100.96, read.z(6, 0)
    assert_predicate read.to_h, :frozen?
  end

  def test_grid_is_quantized_to_the_micrometre
    tree = built_grid { 100.1234567 }
    assert_equal 100.123457, grid(tree).z(0, 0)
  end

  def test_same_grid_same_digest_and_other_grid_other_digest
    assert_equal grid.digest, grid.digest
    refute_equal grid.digest, grid(fixture('creux-12x9')).digest
  end

  def test_hostile_grids_are_refused
    good = fixture('pente-8pct-12x9')
    {
      good.merge('evil' => 1) => '/site/survey/evil',
      good.reject { |k, _| k == 'z_m' } => '/site/survey/z_m',
      good.merge('schema_version' => 2) => '/site/survey/schema_version',
      good.merge('xs_m' => good['xs_m'].map(&:to_s)) => '/site/survey/xs_m/0',
      good.merge('z_m' => 'beaucoup') => '/site/survey/z_m',
      good.merge('z_m' => good['z_m'].map { |row| row.map { 'haut' } }) => '/site/survey/z_m/0/0',
      good.merge('z_m' => good['z_m'].map { |row| row.map { Float::NAN } }) => '/site/survey/z_m/0/0'
    }.each { |tree, path| assert_refused intake.grid(tree, width_m: WIDTH, depth_m: DEPTH, settings: settings), 'E_SCHEMA', path }
  end

  def test_grid_with_other_axes_is_refused
    good = fixture('pente-8pct-12x9')
    {
      'non croissante' => good.merge('xs_m' => good['xs_m'].reverse),
      'angle absent' => good.merge('xs_m' => good['xs_m'][0..-2] + [11.0]),
      'autre pas' => good.merge('ys_m' => [0.0, 3.0, 4.0, 5.0, 6.0, 9.0])
    }.each do |label, tree|
      result = intake.grid(tree, width_m: WIDTH, depth_m: DEPTH, settings: settings)
      assert_refused result, 'E_SCHEMA', '/site/survey', 'grid_axes'
      assert result.errors.one?, label
    end
    assert_refused intake.grid(good, width_m: 14.0, depth_m: DEPTH, settings: settings), 'E_SCHEMA', '/site/survey', 'grid_axes'
  end

  def test_grid_of_the_wrong_shape_is_refused
    good = fixture('pente-8pct-12x9')
    short_row = good['z_m'].dup
    short_row[2] = short_row[2][0..-2]
    [good.merge('z_m' => good['z_m'][0..-2]), good.merge('z_m' => short_row)].each do |tree|
      assert_refused intake.grid(tree, width_m: WIDTH, depth_m: DEPTH, settings: settings), 'E_SCHEMA', '/site/survey', 'grid_shape'
    end
  end

  def test_budget_is_checked_before_reading_the_grid
    config = settings('survey' => { 'step_m' => 0.5 })
    assert_refused intake.grid(fixture('pente-8pct-12x9'), width_m: 60.0, depth_m: 60.0, settings: config), 'E_SITE_BUDGET', '/site/survey/step_m'
  end

  # --- Interpolation

  def test_altitude_at_nodes_and_between
    read = grid
    assert_in_delta 100.32, read.altitude_at(4.0, 3.6)
    assert_in_delta 100.4, read.altitude_at(5.0, 4.0)
    assert_in_delta 100.96, read.altitude_at(WIDTH, DEPTH)
    assert_in_delta 100.0, read.altitude_at(0.0, 0.0)
  end

  def test_bilinear_between_four_different_corners
    tree = built_grid(width: 2.0, depth: 2.0) { |x, y| 10.0 + x + (2 * y) + (x * y) }
    assert_in_delta 10.0 + 1 + 2 + 1, grid(tree, width: 2.0, depth: 2.0).altitude_at(1.0, 1.0)
  end

  def test_altitude_is_nil_outside_or_next_to_a_hole
    read = grid(fixture('trou-12x9'))
    assert_nil read.altitude_at(-0.5, 1.0)
    assert_nil read.altitude_at(12.5, 1.0)
    assert_nil read.altitude_at(1.0, 9.5)
    assert_nil read.altitude_at(3.0, 3.0), 'cellule touchant le trou'
    assert_nil read.altitude_at(5.0, 4.0), 'cellule touchant le trou'
    assert_in_delta 100.08, read.altitude_at(1.0, 1.0)
  end

  # --- Assise

  def test_high_policy_on_the_eight_percent_slope
    value = assise.value
    assert_in_delta 100.96, value['platform_z_m']
    assert_in_delta 100.0, value['terrain_min_z_m']
    assert_in_delta 100.96, value['terrain_max_z_m']
    assert_in_delta 0.96, value['relief_m']
    assert_equal 0.0, value['cut_max_m']
    assert_in_delta 0.96, value['fill_max_m']
    assert_equal 0.0, value['cut_volume_m3']
    assert_in_delta 51.84, value['fill_volume_m3']
    assert_predicate value, :frozen?
  end

  def test_mean_policy_on_the_eight_percent_slope
    value = assise('pente-8pct-12x9', 'platform' => { 'policy' => 'mean' }).value
    assert_in_delta 100.48, value['platform_z_m']
    assert_in_delta 0.48, value['cut_max_m']
    assert_in_delta 0.48, value['fill_max_m']
    assert_in_delta 12.96, value['cut_volume_m3']
    assert_in_delta 12.96, value['fill_volume_m3']
  end

  def test_offset_is_added_to_the_reference
    up = assise('pente-8pct-12x9', 'platform' => { 'offset_m' => 0.5 }).value
    assert_in_delta 101.46, up['platform_z_m']
    assert_in_delta 1.46, up['fill_max_m']
    down = assise('pente-8pct-12x9', 'platform' => { 'offset_m' => -0.5 }).value
    assert_in_delta 100.46, down['platform_z_m']
    assert_in_delta 0.5, down['cut_max_m']
  end

  def test_uneven_hollow_uses_every_point_under_the_footprint
    value = assise('creux-12x9').value
    assert_in_delta 102.8125, value['platform_z_m']
    assert_in_delta 100.0405, value['terrain_min_z_m']
    assert_in_delta 2.772, value['relief_m']
  end

  def test_flat_ground_needs_no_earthwork
    config = settings
    value = SiteAssise.call(grid(built_grid { 42.0 }, config), config, width_m: WIDTH, depth_m: DEPTH).value
    assert_equal [42.0, 0.0, 0.0, 0.0, 0.0], value.values_at('platform_z_m', 'cut_max_m', 'fill_max_m', 'cut_volume_m3', 'fill_volume_m3')
  end

  def test_points_outside_the_footprint_do_not_count
    config = settings('earthwork' => 'embankment')
    # Fort relief et trou hors emprise : seule la zone du talus les verra (AG-023).
    tree = built_grid(config: config) { |x, y| x.between?(0.0, WIDTH) && y.between?(0.0, DEPTH) ? 50.0 : (x < -5 ? nil : 90.0) }
    result = SiteAssise.call(grid(tree, config), config, width_m: WIDTH, depth_m: DEPTH)
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal 50.0, result.value['platform_z_m']
    assert_equal 0.0, result.value['relief_m']
  end

  def test_hole_under_the_footprint_is_refused_and_located
    result = assise('trou-12x9')
    assert_refused result, 'E_SITE_SURVEY', '/site/survey', 'missing_points'
    assert_equal 1, result.errors.first.params['count']
    assert_equal [[4.0, 3.6]], result.errors.first.params['points']
  end

  def test_missing_points_are_listed_within_a_bound
    config = settings
    result = SiteAssise.call(grid(built_grid { nil }, config), config, width_m: WIDTH, depth_m: DEPTH)
    assert_equal 42, result.errors.first.params['count']
    assert_equal SiteAssise::MAX_LISTED_POINTS, result.errors.first.params['points'].size
  end

  def test_relief_exact_limit_and_first_overflow
    config = settings
    exact = built_grid { |x, _y| 100.0 + (6.0 * x / WIDTH) }
    assert_in_delta 6.0, SiteAssise.call(grid(exact, config), config, width_m: WIDTH, depth_m: DEPTH).value['relief_m']
    over = built_grid { |x, _y| 100.0 + (6.001 * x / WIDTH) }
    result = SiteAssise.call(grid(over, config), config, width_m: WIDTH, depth_m: DEPTH)
    assert_refused result, 'E_SITE_RELIEF', '/site/platform', 'relief_exceeded'
    assert_in_delta 6.001, result.errors.first.params['value']
    assert_equal Limits::SITE_RELIEF_MAX_M, result.errors.first.params['limit']
  end

  def test_same_input_gives_the_same_result
    assert_equal Canonical.digest(assise.value), Canonical.digest(assise.value)
  end

  def test_negative_altitudes_are_ordinary
    config = settings
    value = SiteAssise.call(grid(built_grid { |x, _y| -5.0 + x }, config), config, width_m: WIDTH, depth_m: DEPTH)
    assert_refused value, 'E_SITE_RELIEF', '/site/platform'
    flat = SiteAssise.call(grid(built_grid { -5.0 }, config), config, width_m: WIDTH, depth_m: DEPTH).value
    assert_equal(-5.0, flat['platform_z_m'])
  end

  # --- Le format du bâtiment ne bouge pas

  def test_building_plans_are_untouched
    expected = fixture_json('test', 'fixtures', 'plan_digests.json')
    refute_empty expected
    expected.each do |name, digest|
      config = BuildingConfig.new(TestData.intake.effective(TestData.building(name)).value)
      plan = GeometryEngine.generate(config, materials: TestData.materials).value
      assert_equal digest, GeometryEngine.plan_digest(plan), name
    end
  end
end
