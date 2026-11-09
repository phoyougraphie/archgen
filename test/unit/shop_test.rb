# frozen_string_literal: true

require_relative '../test_helper'

# U45 : rez-de-chaussée commerçant (docs/DETAILS_CONTRACT.md, AG-065, ADR-45).
class ShopTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def resolve(draft)
    ConfigResolver.resolve({ 'schema_version' => 1 }.merge(draft), registry: registry, intake: TestData.intake)
  end

  def config(draft)
    r = resolve(draft)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def generate(cfg)
    GeometryEngine.generate(cfg, materials: TestData.materials)
  end

  def plan(cfg)
    r = generate(cfg)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def base
    TestData.intake.effective(TestData.building('rect-neutre-shell')).value
  end

  # Fixture neutre : 12 m, quatre travées de 2,7 m, entrée en travée 1.
  def shop(blocks = {})
    BuildingConfig.new(Merge.leaves(base, { 'lod' => 1, 'ground_floor' => 'shop', 'shop' => { 'height_m' => 4.0 } }.merge(blocks)))
  end

  def front_ground(built)
    built['openings'].select { |o| o['facade_id'] == 'front' && o['level_index'].zero? }
  end

  def reasons(result)
    result.errors.map { |d| [d.path, d.params['reason']] }
  end

  def box(node)
    node['primitive']['vertices'].transpose.map(&:minmax)
  end

  # --- Format

  def test_dwelling_is_not_written_and_shop_takes_its_style_height
    plain = config('profile' => { 'id' => 'toulousain' }, 'ground_floor' => 'dwelling').to_h
    refute plain.key?('ground_floor')
    refute plain.key?('shop')
    refute config('profile' => { 'id' => 'haussmann' }).to_h.key?('shop'), 'la hauteur du style ne s’écrit pas sans commerce'
    assert_equal({ 'height_m' => 4.0 }, config('profile' => { 'id' => 'toulousain' }, 'ground_floor' => 'shop').to_h['shop'])
    assert_equal({ 'height_m' => 4.5 }, config('profile' => { 'id' => 'haussmann' }, 'ground_floor' => 'shop').to_h['shop'])
    given = config('profile' => { 'id' => 'haussmann' }, 'ground_floor' => 'shop', 'shop' => { 'height_m' => 5.2 }).to_h
    assert_equal 5.2, given['shop']['height_m']
  end

  def test_heights_per_level_take_precedence_and_a_shop_height_with_them_is_refused
    heights = { 'count' => 3, 'heights_m' => [4.2, 3.0, 3.0] }
    cfg = config('profile' => { 'id' => 'toulousain' }, 'ground_floor' => 'shop', 'levels' => heights).to_h
    refute cfg.key?('shop')
    assert_equal 'shop', cfg['ground_floor']
    both = resolve('profile' => { 'id' => 'toulousain' }, 'ground_floor' => 'shop', 'levels' => heights, 'shop' => { 'height_m' => 4.0 })
    assert_includes reasons(both), ['/shop/height_m', 'shop_with_heights']
    low = resolve('profile' => { 'id' => 'toulousain' }, 'ground_floor' => 'shop', 'levels' => heights.merge('heights_m' => [3.0, 3.0, 3.0]))
    assert_includes reasons(low), ['/levels/heights_m/0', 'shop_ground_too_low']
  end

  def test_inconsistent_stored_configs_are_refused
    {
      'shop_without_ground_floor' => Merge.leaves(base, 'shop' => { 'height_m' => 4.0 }),
      'shop_height_required' => Merge.leaves(base, 'ground_floor' => 'shop')
    }.each do |reason, data|
      assert_includes ConstraintValidator.call(data).map { |d| d.params['reason'] }, reason
    end
    refute TestData.intake.effective(Merge.leaves(base, 'ground_floor' => 'dwelling')).ok?, 'un logement ne s’enregistre pas'
  end

  def test_style_change_keeps_the_shop
    stored = config('profile' => { 'id' => 'toulousain' }, 'ground_floor' => 'shop')
    edited = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'haussmann', 'revision' => 2 } },
                                    registry: registry, intake: TestData.intake, base: stored)
    assert edited.ok?, edited.errors.map(&:to_h).inspect
    assert_equal ['shop', 4.5], [edited.value.to_h['ground_floor'], edited.value.to_h.dig('shop', 'height_m')]
  end

  # --- Géométrie

  def test_ground_floor_takes_the_shop_height_and_upper_levels_keep_theirs
    built = plan(shop)
    assert_in_delta 4.0 + (3 * 3.2), built['metrics']['wall_top_z_m'], 1e-6
    first = built['openings'].find { |o| o['facade_id'] == 'front' && o['level_index'] == 1 }
    assert_in_delta 4.0 + 0.85, first['z_min_m'], 1e-6
  end

  def test_shopfronts_follow_the_bays_between_piers_and_the_entry_keeps_its_door
    ground = front_ground(plan(shop('facade' => { 'jitter_m' => 0.1 })))
    assert_equal %w[shopfront door shopfront shopfront], ground.map { |o| o['kind'] }
    pitch = (12.0 - (2 * 0.6)) / 4
    ground.select { |o| o['kind'] == 'shopfront' }.each do |o|
      centre = 0.6 + ((o['bay_index'] + 0.5) * pitch)
      assert_in_delta pitch - 0.6, o['u_max_m'] - o['u_min_m'], 1e-6
      assert_in_delta centre, (o['u_min_m'] + o['u_max_m']) / 2, 1e-6, 'pas de variation sur une vitrine'
      assert_in_delta 0.15, o['z_min_m'], 1e-6
      assert_in_delta 4.0 - 0.6, o['z_max_m'], 1e-6
    end
    assert_equal 1, ground.find { |o| o['kind'] == 'door' }['bay_index']
  end

  def test_a_bay_too_narrow_for_a_shopfront_is_refused_not_shrunk
    r = generate(shop('facade' => { 'front_bays' => 7, 'window_width_m' => 0.6, 'door_width_m' => 0.8 }))
    refute r.ok?
    assert_includes reasons(r), ['/facade/front_bays', 'shopfront_too_narrow']
  end

  def test_fascia_runs_margin_to_margin_under_the_first_floor
    built = plan(shop)
    fascia = built['nodes'].first['children'].find { |n| n['id'] == 'details' }['children'].find { |n| n['id'] == 'fascia' }
    (x0, x1), (y0, y1), (z0, z1) = box(fascia)
    assert_equal [0.6, 11.4], [x0, x1].map { |v| v.round(6) }
    assert_equal [-0.1, 0.0], [y0, y1].map { |v| v.round(6) }
    assert_equal [3.5, 3.9], [z0, z1].map { |v| v.round(6) }
    assert_equal ['painted_wood'], fascia['primitive']['faces'].map { |f| f['material'] }.uniq
    refute(plan(shop('lod' => 0))['nodes'].first['children'].any? { |n| n['id'] == 'details' })
  end

  def test_fascia_in_front_of_the_entry_door_is_refused
    r = generate(shop('shop' => { 'height_m' => 3.2 }, 'facade' => { 'door_height_m' => 2.8 }))
    assert_includes reasons(r), ['/shop/height_m', 'fascia_over_entrance']
  end

  def test_glazed_shopfront_has_a_fixed_pane_and_a_door_beside_the_entrance
    built = plan(shop('features' => { 'glazing' => true }, 'materials' => { 'glass' => 'glass' }))
    ids = built['definitions'].keys.grep(%r{^frame/shopfront/})
    assert_equal 2, ids.size, 'vitrine de gauche et vitrines de droite'
    left = built['definitions'].fetch(ids.find { |id| id.end_with?('/door-right') })
    right = built['definitions'].fetch(ids.find { |id| id.end_with?('/door-left') })
    width = 2.1
    door = box(left.find { |n| n['id'] == 'pane/door' })
    assert_in_delta width - 0.04 - 0.90, door[0][0], 1e-6, 'porte au bord droit, côté entrée'
    assert_in_delta 0.04, box(right.find { |n| n['id'] == 'pane/door' })[0][0], 1e-6
    assert_equal %w[bar/left bar/right bar/top bar/bottom bar/mullion pane/door pane], left.map { |n| n['id'] }
    plain = plan(shop)
    assert_equal ['frame/shopfront/2100000x3250000/painted_wood'], plain['definitions'].keys.grep(%r{^frame/shopfront/})
  end

  def test_first_balcony_rises_with_the_taller_ground_floor
    built = plan(shop('features' => { 'balcony' => true }, 'levels' => { 'count' => 4 }))
    balcony = built['nodes'].first['children'].find { |n| n['id'] == 'details' }['children'].find { |n| n['id'] == 'balcony/2' }
    assert_in_delta 4.0 + 3.2, box(balcony)[2][1], 1e-6
  end

  def test_three_published_styles_take_a_shop_in_both_modes
    %w[haussmann toulousain brutalist].product(%w[shell structural]).each do |id, mode|
      built = plan(config('profile' => { 'id' => id }, 'mode' => mode, 'lod' => 1, 'ground_floor' => 'shop'))
      assert(built['openings'].any? { |o| o['kind'] == 'shopfront' }, "#{id} #{mode}")
      assert_operator built['metrics']['expanded_face_count'], :<, Limits::MAX_EXPANDED_FACES
    end
  end

  # --- Rue

  def street(profile, points, closed)
    tree = { 'seed' => 1, 'trace' => { 'points_m' => points, 'closed' => closed },
             'building' => { 'profile' => { 'id' => profile }, 'lod' => 1, 'ground_floor' => 'shop' } }
    settings = Archgen::Composition.ensemble_intake.settings(tree).value
    r = EnsembleEngine.call(settings, registry: registry, intake: TestData.intake, materials: TestData.materials)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def test_a_whole_street_turns_shop
    plans = street('haussmann', [[0, 0], [48, 0]], false)['definitions'].values
    refute_empty plans
    plans.each do |built|
      kinds = front_ground(built).map { |o| o['kind'] }
      assert_equal 1, kinds.count('door')
      assert_equal kinds.size - 1, kinds.count('shopfront')
    end
  end

  def test_shopfronts_stop_short_of_a_porch
    porch_plans = street('toulousain', [[0, 0], [40, 0], [40, 40], [0, 40]], true)['definitions'].values
                  .select { |built| built['openings'].any? { |o| o['kind'] == 'porch' } }
    refute_empty porch_plans
    porch_plans.each do |built|
      ground = front_ground(built)
      passage = ground.find { |o| o['kind'] == 'porch' }
      ground.select { |o| o['kind'] == 'shopfront' }.each do |o|
        gap = [passage['u_min_m'] - o['u_max_m'], o['u_min_m'] - passage['u_max_m']].max
        assert_operator gap, :>=, Quant::CLEARANCE_M - 1e-6
        assert_operator o['u_max_m'] - o['u_min_m'], :>=, Archgen::Geometry::OpeningSolver::SHOPFRONT_MIN_WIDTH_M - 1e-6
      end
      assert(ground.any? { |o| o['kind'] == 'shopfront' && (passage['u_min_m'] - o['u_max_m']).round(6) == Quant::CLEARANCE_M.round(6) },
             'une vitrine arrêtée au ras du dégagement')
    end
  end
end
