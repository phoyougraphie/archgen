# frozen_string_literal: true

require_relative '../test_helper'

# U58-U61 : volumes modernes (docs/VOLUMES_MODERNES_CONTRACT.md, AG-090 à AG-093, ADR-48).
class ModernTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def base
    TestData.intake.effective(TestData.building('rect-neutre-shell')).value
  end

  # Fixture neutre : 12 × 9 m, quatre niveaux de 3,2 m, dalle 0,20 m, quatre travées, marges 0,60 m.
  def building(blocks = {})
    BuildingConfig.new(Merge.leaves(base, Merge.leaves({ 'lod' => 1 }, blocks)))
  end

  def generate(cfg)
    GeometryEngine.generate(cfg, materials: TestData.materials)
  end

  def plan(cfg)
    r = generate(cfg)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def details(built, category)
    node = built['nodes'].first['children'].find { |n| n['id'] == 'details' }
    node ? node['children'].select { |n| n['category'] == category } : []
  end

  def box(node)
    node['primitive']['vertices'].transpose.map(&:minmax)
  end

  # --- U58 bandeaux et murs-rideaux

  def test_bays_is_not_written
    cfg = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'brutalist' }, 'facade' => { 'ribbon' => 'bays' } },
                                 registry: registry, intake: TestData.intake)
    refute cfg.value.to_h['facade'].key?('ribbon')
  end

  def test_band_gives_one_opening_per_upper_level_margin_to_margin
    built = plan(building('facade' => { 'ribbon' => 'band' }))
    front = built['openings'].select { |o| o['facade_id'] == 'front' }
    ribbons = front.select { |o| o['kind'] == 'ribbon' }
    assert_equal [1, 2, 3], ribbons.map { |o| o['level_index'] }
    ribbons.each do |o|
      assert_equal [0.6, 11.4], [o['u_min_m'], o['u_max_m']]
      assert_in_delta 0.85, o['z_min_m'] - (3.2 * o['level_index']), 1e-6
      assert_in_delta 1.80, o['z_max_m'] - o['z_min_m'], 1e-6
    end
    assert_equal 4, front.count { |o| o['level_index'].zero? }, 'le rez-de-chaussée garde ses baies'
    assert(built['openings'].any? { |o| o['facade_id'] == 'rear' && o['kind'] == 'ribbon' })
  end

  def test_curtain_runs_floor_to_ceiling_with_mullions_and_panes
    built = plan(building('facade' => { 'ribbon' => 'curtain' }, 'features' => { 'glazing' => true }, 'materials' => { 'glass' => 'glass' }))
    o = built['openings'].find { |x| x['id'] == 'opening/front/1/ribbon' }
    assert_in_delta 3.2 + 0.15, o['z_min_m'], 1e-6
    assert_in_delta 6.4 - 0.2 - 0.15, o['z_max_m'], 1e-6
    id, nodes = built['definitions'].find { |k, _| k.start_with?('frame/ribbon/') }
    assert_match %r{/modules/}, id
    mullions = nodes.count { |n| n['id'].start_with?('bar/mullion/') }
    panes = nodes.count { |n| n['id'].start_with?('pane/') }
    assert_equal mullions + 1, panes
    assert_operator panes, :>=, 10, '10,72 m de jour en modules de 0,80 m au moins'
  end

  # --- U59 pilotis

  def walls(built)
    built['nodes'].first['children'].find { |n| n['id'] == 'walls' }['children']
  end

  def test_pilotis_open_the_ground_floor_on_posts
    built = plan(building('features' => { 'pilotis' => true }))
    assert(built['openings'].none? { |o| o['level_index'].zero? }, 'ni porte ni baie au rez-de-chaussée')
    front = walls(built).find { |n| n['id'] == 'wall/front' }['primitive']
    assert(front['vertices'].all? { |v| v[2] >= 3.2 - 1e-6 }, 'pas de mur sous le premier plancher')
    posts = walls(built).select { |n| n['id'].start_with?('wall/piloti/') }
    assert_equal 5 * 2, posts.size, 'deux angles et trois limites de travée, avant et arrière'
    posts.each { |n| assert_equal [0.0, 3.2], box(n)[2] }
    assert(walls(built).any? { |n| n['id'] == 'wall/soffit' })
    refute(walls(plan(building('mode' => 'structural', 'features' => { 'pilotis' => true }))).any? { |n| n['id'] == 'wall/soffit' })
  end

  def test_pilotis_refusals
    reasons = ->(data) { ConstraintValidator.call(data).map { |d| d.params['reason'] } }
    assert_includes reasons.call(Merge.leaves(base, 'features' => { 'pilotis' => true }, 'levels' => { 'count' => 1 })), 'pilotis_levels'
    assert_includes reasons.call(Merge.leaves(base, 'features' => { 'pilotis' => true }, 'ground_floor' => 'shop', 'shop' => { 'height_m' => 4.0 })), 'pilotis_with_shop'
    tree = { 'trace' => { 'points_m' => [[0, 0], [30, 0]], 'closed' => false }, 'building' => { 'profile' => { 'id' => 'brutalist' }, 'features' => { 'pilotis' => true } } }
    r = EnsembleEngine.call(Archgen::Composition.ensemble_intake.settings(tree).value, registry: registry, intake: TestData.intake, materials: TestData.materials)
    assert r.ok?, r.errors.map(&:to_h).inspect
    assert(r.warnings.any? { |d| d.params['reason'] == 'pilotis_in_row' }, 'omis et dit en rangée')
  end

  # --- U60 sheds

  SAW = { 'type' => 'sawtooth', 'overhang_m' => 0.0, 'pitch_deg' => 30.0, 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0 }.freeze

  def test_sawtooth_teeth_with_rear_facing_lights
    built = plan(building('roof' => SAW, 'features' => { 'glazing' => true }, 'materials' => { 'glass' => 'glass' }))
    roof = built['nodes'].first['children'].find { |n| n['id'] == 'roof' }['children']
    teeth = roof.select { |n| n['id'].start_with?('roof/tooth/') }
    assert_equal 2, teeth.size, '9 m de profondeur en dents de 4 m'
    lights = roof.select { |n| n['id'].start_with?('roof/light/') }
    assert_equal ['glass'], lights.flat_map { |n| n['primitive']['faces'].map { |f| f['material'] } }.uniq
    assert_in_delta 12.8 + (Math.tan(30 * Math::PI / 180) * 4.5), built['metrics']['roof_top_z_m'], 1e-6
  end

  def test_sawtooth_in_a_street_with_a_corner_and_overhang_refused
    tree = { 'seed' => 1, 'trace' => { 'points_m' => [[0, 0], [40, 0], [40, 30]], 'closed' => false },
             'building' => { 'profile' => { 'id' => 'brutalist' }, 'roof' => { 'type' => 'sawtooth' } } }
    r = EnsembleEngine.call(Archgen::Composition.ensemble_intake.settings(tree).value, registry: registry, intake: TestData.intake, materials: TestData.materials)
    assert r.ok?, r.errors.map(&:to_h).inspect
    stored = Merge.leaves(base, 'roof' => SAW.merge('overhang_m' => 0.4))
    refute_empty ConstraintValidator.call(stored).select { |d| d.path == '/roof/overhang_m' }
  end

  # --- U61 trame et brise-soleil

  def test_structural_grid_bands_and_posts_skip_openings
    built = plan(building('features' => { 'structural_grid' => true }))
    parts = details(built, 'structure')
    bands = parts.select { |n| n['id'].start_with?('structure/front/band/') }
    assert_equal 4, bands.size, 'trois planchers et le haut'
    built['openings'].select { |o| o['facade_id'] == 'front' }.each do |o|
      parts.select { |n| n['id'].start_with?('structure/front/post/') }.each do |n|
        (x0, x1), _, (z0, z1) = box(n)
        refute(x0 < o['u_max_m'] - 1e-6 && x1 > o['u_min_m'] + 1e-6 && z0 < o['z_max_m'] - 1e-6 && z1 > o['z_min_m'] + 1e-6, n['id'])
      end
    end
    reasons = ConstraintValidator.call(Merge.leaves(base, 'features' => { 'structural_grid' => true, 'shutters' => true }, 'materials' => { 'shutters' => 'painted_wood' }))
                                 .map { |d| d.params['reason'] }
    assert_includes reasons, 'structural_grid_with_shutters'
  end

  def test_sun_shades_above_windows_and_ribbons
    built = plan(building('features' => { 'sun_shades' => true }, 'facade' => { 'ribbon' => 'band' }))
    shades = details(built, 'sun_shade')
    assert_equal 3 + 3, shades.size, 'trois fenêtres au rez-de-chaussée, trois bandeaux'
    shades.each { |n| assert_equal [-0.6, 0.0], box(n)[1].map { |v| v.round(6) } }
  end
end
