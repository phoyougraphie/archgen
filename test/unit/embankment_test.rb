# frozen_string_literal: true

require_relative '../test_helper'

# U15 : talus (docs/TERRAIN_CONTRACT.md). Les mesures passent par Geo, indépendant du noyau.
class EmbankmentTest < Minitest::Test
  include Archgen::Core
  SitePlanner = Archgen::Geometry::SitePlanner

  WIDTH = 12.0
  DEPTH = 9.0
  SUITE_SEED = 20_261_106
  OUTWARD = { 'front' => [0, -1], 'right' => [1, 0], 'rear' => [0, 1], 'left' => [-1, 0] }.freeze

  def intake
    @intake ||= Archgen::Composition.site_intake
  end

  def catalogue
    @catalogue ||= Archgen::Composition.site_materials
  end

  def tree_for(settings)
    axes = SurveyGrid.plan(width_m: WIDTH, depth_m: DEPTH, settings: settings).value
    { 'schema_version' => 1, 'xs_m' => axes['xs_m'], 'ys_m' => axes['ys_m'],
      'z_m' => axes['ys_m'].map { |y| axes['xs_m'].map { |x| yield(x, y) } } }
  end

  def plan_site(draft = {}, name: 'rect-neutre-shell', facade: nil, &ground)
    settings = intake.settings({ 'earthwork' => 'embankment' }.merge(draft)).value
    base = TestData.intake.effective(TestData.building(name)).value
    base = Merge.leaves(base, 'facade' => facade) if facade
    config = BuildingConfig.new(base)
    plan = GeometryEngine.generate(config, materials: TestData.materials).value
    grid = intake.grid(tree_for(settings, &ground), width_m: WIDTH, depth_m: DEPTH, settings: settings).value
    assise = SiteAssise.call(grid, settings, width_m: WIDTH, depth_m: DEPTH)
    return assise unless assise.ok?

    SitePlanner.call(plan: plan, config: config.to_h, grid: grid, settings: settings, assise: assise.value, materials: catalogue)
  end

  def site(draft = {}, **options, &ground)
    result = plan_site(draft, **options, &ground)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def leaf(plan, facade)
    Geo.find_node(plan['nodes'], "site/embankment/#{facade}")
  end

  def triangles(plan, facade)
    primitive = leaf(plan, facade)['primitive']
    primitive['faces'].map { |face| Geo.polygon(primitive, face) }
  end

  def all_triangles(plan)
    %w[front right rear left].flat_map { |facade| leaf(plan, facade) ? triangles(plan, facade) : [] }
  end

  # Terrain plat à 100 m, plateforme relevée d'un mètre : remblai uniforme de 1 m.
  def raised(draft = {})
    site({ 'platform' => { 'offset_m' => 1 } }.merge(draft)) { 100.0 }
  end

  def assert_refused(result, code, path, reason = nil)
    refute result.ok?, 'attendu un refus'
    found = result.errors.find { |d| d.code == code && d.path == path }
    assert found, result.errors.map(&:to_h).inspect
    assert_equal reason, found.params['reason'] if reason
    found
  end

  # --- Catalogue

  def test_earth_is_in_a_separate_catalogue
    assert_equal 'Terre', catalogue.dig('earth', 'label')
    assert_match(/\A#\h{6}\z/, catalogue.dig('earth', 'srgb'))
    refute Archgen::Composition.materials.fetch('materials').key?('earth'), 'le catalogue du bâtiment ne change pas'
    assert_equal 1, Archgen::Composition.materials.fetch('schema_version')
    assert catalogue.key?('concrete')
  end

  def test_all_embankment_faces_are_earth
    materials = %w[front right rear left].flat_map { |facade| leaf(raised, facade)['primitive']['faces'].map { |f| f['material'] } }
    assert_equal ['earth'], materials.uniq
  end

  # --- Forme exacte

  def test_slope_is_exact_on_flat_ground
    straight_front(raised).each do |polygon|
      normal = Geo.unit_normal(polygon)
      assert_in_delta 1.0 / 1.5, -normal[1] / normal[2], 1e-3, 'une pente de 1 pour 1,5 vers l’avant'
    end
  end

  # Les bandes droites de la façade avant, sans l'éventail de son angle.
  def straight_front(plan)
    triangles(plan, 'front').select { |polygon| polygon.all? { |p| p[0].between?(0.0, WIDTH) } }
  end

  def test_toe_lies_below_the_terrain_by_the_contract_margin
    plan = raised
    tips = all_triangles(plan).flatten(1).select { |p| p[2].negative? }
    assert(tips.all? { |p| (p[2] + 1.05).abs < 1e-4 }, tips.map { |p| p[2] }.uniq.first(5).inspect)
    assert_in_delta 1.575, plan['metrics']['embankment_reach_m'], 1e-4
  end

  def test_steeper_ratio_gives_a_shorter_reach
    assert_in_delta 1.05, raised('embankment_ratio' => 1)['metrics']['embankment_reach_m'], 1e-4
    assert_in_delta 3.15, raised('embankment_ratio' => 3)['metrics']['embankment_reach_m'], 1e-4
  end

  def test_area_of_the_front_face_matches_its_slope
    expected = WIDTH * Math.hypot(1.575, 1.05)
    assert_in_delta expected, straight_front(raised).sum { |polygon| Geo.area(polygon) }, 1e-3
  end

  def test_faces_look_up_and_outward
    plan = raised
    %w[front right rear left].each do |facade|
      triangles(plan, facade).each do |polygon|
        normal = Geo.unit_normal(polygon)
        assert_operator normal[2], :>, 0.0, facade
        center = polygon.transpose.map { |values| values.sum / 3.0 }
        out = [center[0] - (WIDTH / 2.0), center[1] - (DEPTH / 2.0)]
        assert_operator (normal[0] * out[0]) + (normal[1] * out[1]), :>, 0.0, facade
      end
    end
  end

  def test_the_talus_starts_on_the_wall_foot_at_platform_height
    origins = all_triangles(raised).flatten(1).select { |p| p[2].zero? }
    refute_empty origins
    origins.each do |p|
      on_edge = [p[0], p[1]].then { |x, y| [0.0, WIDTH].include?(x) || [0.0, DEPTH].include?(y) }
      inside = p[0].between?(0.0, WIDTH) && p[1].between?(0.0, DEPTH)
      assert(on_edge && inside, p.inspect)
    end
  end

  def test_no_plinth_with_an_embankment
    assert_nil Geo.find_node(raised['nodes'], 'site/plinth')
    refute_nil Geo.find_node(raised['nodes'], 'site/platform')
    refute_nil Geo.find_node(raised['nodes'], 'site/embankment')
  end

  # --- Angles

  def test_corner_has_a_fan_of_three_rays
    plan = raised
    corner = [WIDTH, 0.0, 0.0]
    fan = triangles(plan, 'front').select { |polygon| polygon.include?(corner) && polygon.count { |p| p[2].zero? } == 1 }
    assert_equal 4, fan.size, 'quatre triangles entre la normale avant et la normale droite'
    tips = fan.flatten(1).reject { |p| p == corner }.uniq
    angles = tips.map { |p| Math.atan2(p[1], p[0] - WIDTH) }.sort
    expected = [-90.0, -67.5, -45.0, -22.5, 0.0].map { |deg| deg * Math::PI / 180.0 }
    angles.zip(expected).each { |actual, want| assert_in_delta want, actual, 1e-3 }
  end

  def test_corner_rays_keep_the_same_reach_on_flat_ground
    corner = [WIDTH, 0.0, 0.0]
    tips = triangles(raised, 'front').select { |polygon| polygon.include?(corner) }.flatten(1).reject { |p| p == corner || p[2].zero? }.uniq
    tips.each { |p| assert_in_delta 1.575, Math.hypot(p[0] - WIDTH, p[1]), 1e-4 }
  end

  def test_fan_triangles_do_not_overlap_in_plan
    plan = raised
    sign = all_triangles(plan).map do |polygon|
      a, b, c = polygon
      ((b[0] - a[0]) * (c[1] - a[1])) - ((b[1] - a[1]) * (c[0] - a[0]))
    end
    assert(sign.all?(&:positive?), 'tous les triangles tournent dans le même sens vus de dessus')
  end

  # --- Terrain réel

  def test_slope_meets_rising_ground_sooner
    plan = site { |x, _y| 100.0 + (0.08 * x) }
    left = triangles(plan, 'left').flatten(1).map { |p| p[0] }.min
    # Plateforme à 100,96 ; à gauche le terrain est à 100 et continue de descendre.
    assert_operator left, :<, -1.0
    right_reach = leaf(plan, 'right') ? triangles(plan, 'right').flatten(1).map { |p| p[0] }.max : WIDTH
    assert_operator right_reach - WIDTH, :<, -left, 'le côté amont s’arrête bien plus tôt'
  end

  def test_tip_is_below_the_ground_it_reached
    settings = intake.settings('earthwork' => 'embankment').value
    tree = tree_for(settings) { |x, y| 100.0 + (0.05 * x) + (0.03 * y) }
    grid = intake.grid(tree, width_m: WIDTH, depth_m: DEPTH, settings: settings).value
    plan = site { |x, y| 100.0 + (0.05 * x) + (0.03 * y) }
    platform = plan['metrics']['platform_z_m']
    all_triangles(plan).flatten(1).select { |p| p[2].negative? }.each do |p|
      terrain = grid.altitude_at(p[0], p[1]) - platform
      # 0,05 m sous le pied le long de la pente : la pointe suit le talus, pas le terrain.
      assert_in_delta terrain - 0.05, p[2], 0.01, p.inspect
      assert_operator p[2], :<, terrain, p.inspect
    end
  end

  def test_no_face_where_the_ground_is_above_the_platform
    plan = site({ 'platform' => { 'policy' => 'mean' } }) { |x, _y| 100.0 + (0.08 * x) }
    xs = all_triangles(plan).flatten(1).select { |p| p[1].zero? && p[2].zero? }.map { |p| p[0] }
    assert_operator xs.max, :<, WIDTH, 'pas de talus au pied du mur amont'
  end

  def test_door_rules_still_apply
    result = plan_site({ 'platform' => { 'offset_m' => -0.5 } }, facade: { 'entry_bay' => 3 }) { |x, _y| 100.0 + (0.08 * x) }
    assert_refused result, 'E_SITE_DOOR_BURIED', '/site/platform'
    warned = plan_site { |x, _y| 100.0 + (0.08 * x) }
    assert(warned.warnings.any? { |d| d.code == 'W_SITE_DOOR_GAP' })
  end

  # --- Refus

  def test_ground_falling_faster_than_the_slope_is_refused_by_facade
    # Plateforme au niveau du terrain : rayon sans longueur, donc aucun pied à chercher.
    assert plan_site({ 'embankment_ratio' => 3 }) { |_x, y| y.negative? ? 100.0 + (y * 2.0) : 100.0 }.ok?
    falling = plan_site({ 'embankment_ratio' => 3, 'platform' => { 'offset_m' => 0.5 } }) { |_x, y| y.negative? ? 100.0 + (y * 2.0) : 100.0 }
    assert_refused falling, 'E_SITE_TOE', '/site/embankment_ratio', 'toe_not_found'
    # La façade avant, et la gauche dont l'éventail d'angle regarde aussi vers l'avant.
    assert_equal %w[front left], falling.errors.select { |d| d.code == 'E_SITE_TOE' }.map { |d| d.params['id'] }
  end

  def test_hole_met_by_a_ray_is_refused_and_located
    hole = plan_site({ 'platform' => { 'offset_m' => 1 } }) { |x, y| y.negative? && y > -3.0 && x.between?(3.0, 5.0) ? nil : 100.0 }
    found = assert_refused hole, 'E_SITE_SURVEY', '/site/survey', 'missing_points'
    assert_operator found.params['count'], :>, 0
    refute_empty found.params['points']
  end

  def test_hole_beyond_the_toe_does_not_matter
    plan = site({ 'platform' => { 'offset_m' => 1 } }) { |_x, y| y < -8.0 ? nil : 100.0 }
    assert_in_delta 1.575, plan['metrics']['embankment_reach_m'], 1e-4
  end

  # --- Plan et budget

  def test_plan_validates_with_the_full_catalogue
    assert_empty SitePlanValidator.call(raised, materials: catalogue)
  end

  def test_unknown_material_is_caught_with_the_building_catalogue_only
    reasons = SitePlanValidator.call(raised, materials: TestData.materials).map { |d| d.params['reason'] }
    assert_includes reasons, 'unknown_material'
  end

  def test_face_count_is_declared
    plan = raised
    counted = 0
    Geo.walk(plan['nodes']) { |n| counted += n['primitive']['faces'].size if n['primitive'] }
    assert_equal counted, plan['metrics']['site_face_count']
  end

  def test_plinth_plan_reports_no_reach
    settings = intake.settings({}).value
    base = BuildingConfig.new(TestData.intake.effective(TestData.building('rect-neutre-shell')).value)
    plan = GeometryEngine.generate(base, materials: TestData.materials).value
    grid = intake.grid(fixture_json('examples', 'terrain', 'pente-8pct-12x9.json'), width_m: WIDTH, depth_m: DEPTH, settings: settings).value
    assise = SiteAssise.call(grid, settings, width_m: WIDTH, depth_m: DEPTH).value
    assert_equal 0.0, SitePlanner.call(plan: plan, config: base.to_h, grid: grid, settings: settings, assise: assise).value['metrics']['embankment_reach_m']
  end

  def test_same_input_same_digest
    assert_equal SitePlanner.digest(raised), SitePlanner.digest(raised)
    refute_equal SitePlanner.digest(raised), SitePlanner.digest(raised('embankment_ratio' => 2))
  end

  # --- 100 terrains pseudo-aléatoires bornés

  def random_ground(rng)
    tilt_x = rng.rand(-0.2..0.2)
    tilt_y = rng.rand(-0.2..0.2)
    bumps = Array.new(3) { [rng.rand(0.1..0.8), rng.rand(0.1..0.8), rng.rand(0.0..6.28), rng.rand(0.0..0.7)] }
    lambda do |x, y|
      100.0 + (tilt_x * x) + (tilt_y * y) + bumps.sum { |fx, fy, phase, amp| amp * Math.sin((fx * x) + (fy * y) + phase) }
    end
  end

  def test_one_hundred_pseudo_random_terrains
    rng = Random.new(SUITE_SEED)
    known = %w[E_SITE_DOOR_BURIED E_SITE_TOE E_SITE_RELIEF E_SITE_BUDGET]
    outcomes = Hash.new(0)
    100.times do |i|
      ground = random_ground(rng)
      draft = { 'embankment_ratio' => rng.rand(1.0..3.0).round(3),
                'platform' => { 'policy' => %w[high mean].sample(random: rng), 'offset_m' => rng.rand(-1.0..1.0).round(3) } }
      context = "suite=#{SUITE_SEED} tirage=#{i} #{draft}"
      result = plan_site(draft, &ground)
      unless result.ok?
        result.errors.each { |d| assert_includes known, d.code, context }
        outcomes[:refused] += 1
        next
      end
      outcomes[:ok] += 1
      plan = result.value
      assert_empty SitePlanValidator.call(plan, materials: catalogue), context
      assert_equal SitePlanner.digest(plan), SitePlanner.digest(plan_site(draft, &ground).value), context
      all_triangles(plan).each { |polygon| assert_operator Geo.unit_normal(polygon)[2], :>, 0.0, context }
    end
    assert_operator outcomes[:ok], :>=, 40, "trop peu de plans valides : #{outcomes} (suite=#{SUITE_SEED})"
  end
end
