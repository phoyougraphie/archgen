# frozen_string_literal: true

require_relative '../test_helper'

# U37 : canal à écluses sur un terrain (docs/EAU_CONTRACT.md, AG-054). Canal à chemin de halage
# (eau de 14 m, revanche 0,8 m, profondeur 2,5 m, quais), terrain z = 20 − 0,05 s sans pente en travers.
# Points de pente tous les 20 m ; chute 3 m, chambre 40 m, approches 10 m.
class RoadCanalTest < Minitest::Test
  include Archgen::Core

  C = Archgen::Composition
  G = Archgen::Geometry::RoadGround

  def preset(id)
    C.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def tree(points: [[0, 0], [300, 0]], radii: [], profile: 'canal', water: {})
    { 'trace' => { 'points_m' => points, 'radii_m' => radii }, 'profile' => preset(profile), 'ground' => {},
      'water' => { 'mode' => 'canal' }.merge(water) }
  end

  def settings(input)
    s = C.road_intake.settings(input)
    assert s.ok?, s.errors.map(&:to_h).inspect
    s.value
  end

  def survey(input, &terrain)
    s = settings(input)
    width = Archgen::Geometry::RoadSection.call(s['profile'], bands: C.road_bands, items: C.road_items)['width_m']
    t = s['trace']
    stations = Archgen::Geometry::RoadAxis.call(t['points_m'], t['radii_m'], left_m: width / 2, right_m: width / 2).value
    length = stations.each_cons(2).sum { |a, b| Math.hypot(b.point[0] - a.point[0], b.point[1] - a.point[1]) }
    axes = G.axes(length, width / 2, width / 2, G.settings(s['ground'])).value
    axes.merge('z_m' => axes['s_m'].map { |x| axes['u_m'].map { |u| terrain.call(x, u) } })
  end

  SLOPE = ->(s, _u) { 20 - (0.05 * s) }

  def build(input, terrain = SLOPE)
    RoadEngine.call(settings(input), bands: C.road_bands, items: C.road_items, survey: survey(input, &terrain))
  end

  def plan(input, terrain = SLOPE)
    r = build(input, terrain)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def refusal(input, terrain)
    r = build(input, terrain)
    refute r.ok?
    r.errors.first
  end

  def node(plan, id)
    plan['nodes'][0]['children'].find { |n| n['id'] == id }
  end

  # À 80 m le terrain est 4 m sous le premier bief (20 m) : écluse dont la chambre finit au point
  # précédent, 60 m. Puis 140 m → chambre 80–120 ; 200 m → 140–180 ; 260 m → 200–240. Biefs à 20, 17, 14, 11, 8.
  def test_locks_placed_by_the_rule_by_hand
    p = plan(tree)
    locks = p['water']['locks']
    assert_equal [20.0, 80.0, 140.0, 200.0], locks.map { |l| l['s_m'] }
    assert(locks.all? { |l| l['length_m'] == 40.0 && l['drop_m'] == -3.0 })
    assert_equal [4, 12.0], p['metrics'].values_at('lock_count', 'water_drop_m')
    assert_empty RoadPlanValidator.call(p)
  end

  def test_water_is_flat_in_each_reach_and_low_in_each_chamber
    p = plan(tree)
    vs = node(p, 'road/water')['primitive']['vertices']
    level = ->(x) { vs.select { |v| (v[0] - x).abs < 1e-6 }.map { |v| v[2] }.uniq }
    assert_equal [-0.8], level.call(0.0)
    assert_equal [-0.8, -3.8], level.call(20.0).sort.reverse # bief haut jusqu'à la porte amont, chambre au niveau bas
    assert_equal [-3.8], level.call(60.0) # porte aval : chambre et bief suivant au même niveau
    assert_equal [-3.8, -6.8], level.call(80.0).sort.reverse # porte amont de la deuxième écluse
    assert_equal [-12.8], level.call(300.0)
    by_x = vs.group_by { |v| v[0].round(6) }.sort.map { |_, list| list.map { |v| v[2] }.min }
    assert_equal by_x, by_x.sort.reverse, 'eau jamais remontante'
  end

  def test_banks_ramp_along_the_chamber_and_a_chute_wall_closes_the_bed
    p = plan(tree)
    surface = node(p, 'road/surface')['primitive']
    v = surface['vertices']
    # Bord du chemin de halage (5 m du bord gauche, axe au milieu de 26,5 m : y = 8,25) : le chemin passe
    # de 0,02 m à la porte amont (20 m) à −2,98 m à la porte aval (60 m), en rampe droite le long de la chambre.
    towpath = ->(x) { v.select { |p3| (p3[0] - x).abs < 1e-6 && (p3[1] - 8.25).abs < 1e-6 }.map { |p3| p3[2] }.max }
    assert_equal 0.02, towpath.call(20.0)
    assert_equal(-2.98, towpath.call(60.0))
    ramp = surface['faces'].count do |f|
      pts = f['indices'].map { |i| v[i] }
      f['material'] == 'road/track' && pts.map { |p3| p3[0] }.minmax == [20.0, 60.0]
    end
    assert_operator ramp, :>=, 1
    walls = surface['faces'].select do |f|
      pts = f['indices'].map { |i| v[i] }
      f['material'] == 'road/quay' && pts.all? { |p3| (p3[0] - 20).abs < 1e-6 } && pts.map { |p3| p3[2] }.minmax == [-6.3, -3.3]
    end
    assert_equal 1, walls.size
  end

  def test_two_gates_per_lock_closed_solids
    p = plan(tree)
    gates = node(p, 'road/locks')['children']
    assert_equal 8, gates.size
    first = gates.first['primitive']['vertices']
    assert_equal [-6.3, 0.2], first.map { |x| x[2] }.minmax.map { |z| z.round(6) }
    assert_equal [19.8, 20.2], first.map { |x| x[0] }.minmax.map { |x| x.round(6) }
    assert_empty RoadPlanValidator.call(p)
  end

  def test_lock_on_a_curve_is_refused
    curved = tree(points: [[0, 0], [100, 0], [100, 200]], radii: [30])
    found = refusal(curved, SLOPE)
    assert_equal ['E_ROAD_WATER', '/trace', 'lock_on_curve', 80.0], [found.code, found.path, found.params['reason'], found.params['s_m']]
  end

  def test_locks_too_close_or_outside_the_trace
    cliff = ->(s, _u) { 20 - (0.35 * [0.0, s - 80].max) }
    found = refusal(tree, cliff)
    assert_equal ['locks_too_close', 40.0], found.params.values_at('reason', 's_m')
    found = refusal(tree, ->(s, _u) { 20 - (0.08 * s) })
    assert_equal ['lock_outside_trace', -20.0, 10.0], found.params.values_at('reason', 's_m', 'limit')
  end

  def test_a_gentle_terrain_needs_no_lock
    p = plan(tree, ->(s, _u) { 20 - (0.005 * s) })
    assert_equal 0, p['metrics']['lock_count']
    assert_equal [], p['water']['locks']
    refute node(p, 'road/locks')
  end

  def test_canal_on_ground_needs_quays_and_flat_still_waits
    r = C.road_intake.settings(tree(profile: 'riviere'))
    assert_equal ['/profile/bands/2', 'canal_needs_quays'], [r.errors.first.path, r.errors.first.params['reason']]
    wide = tree
    wide['profile'] = Marshal.load(Marshal.dump(wide['profile']))
    wide['profile']['bands'][3]['width_m'] = 40.001
    r = C.road_intake.settings(wide)
    assert_equal ['/profile/bands/3/width_m', 'lock_too_wide', 40.0], [r.errors.first.path, r.errors.first.params['reason'], r.errors.first.params['limit']]
    r = C.road_intake.settings(tree.merge('water' => { 'mode' => 'flat' }))
    assert_equal 'water_ground_unavailable', r.errors.first.params['reason']
  end

  def test_lock_drop_and_chamber_length_follow_the_settings
    p = plan(tree(water: { 'lock_drop_m' => 5, 'lock_length_m' => 30 }))
    locks = p['water']['locks']
    assert(locks.all? { |l| l['length_m'] == 30.0 && l['drop_m'] == -5.0 })
    assert_equal 2, locks.size
  end
end
