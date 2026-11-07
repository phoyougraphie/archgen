# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/road_net'
require File.expand_path('../../archgen/ui/messages', __dir__)

# U29 : giratoire (docs/VOIRIE_CONTRACT.md, Carrefours ; AG-045). Géométrie à la main sur une rue de
# ville (chaussée de ± 4 m, trottoirs de 2,5 m) : anneau de 15 m, îlot central de 8 m, entrées
# arrondies de 6 m, îlot séparateur de 2 × 8 m ; limites et premier dépassement ; étanchéité.
class RoadRoundaboutTest < Minitest::Test
  include Archgen::Core
  include RoadNet

  TOL = 1e-5
  BOX = [5, -45, 95, 45].freeze
  X = [RoadNet.road('a', [[0, 0], [100, 0]]), RoadNet.road('b', [[50, -50], [50, 50]])].freeze

  def roundabout(roads, **rest)
    id = plan(network(*roads))['junctions'].first['id']
    network(*roads, junctions: [{ 'id' => id, 'type' => 'roundabout' }.merge(rest.transform_keys(&:to_s))])
  end

  def plan(tree)
    result = build(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def faces(plan, material)
    s = surface(plan)
    s['faces'].select { |f| f['material'] == material }.map { |f| f['indices'].map { |i| s['vertices'][i] } }
  end

  def dist(p, c = [50, 0])
    Math.hypot(p[0] - c[0], p[1] - c[1])
  end

  def assert_sealed(plan, roads, label, walk: nil)
    strips = roads.map { |r| strip(r['road']['trace']['points_m'].first, r['road']['trace']['points_m'].last, r['road']['profile']) }
    j = plan['junctions'].first
    holes = coverage_defects(plan, strips, BOX, step: 0.47, disc: [j['point_m'], j['outer_radius_m']])
    assert_empty holes, "#{label} : trous ou recouvrements #{holes.first(4)}"
    if walk
      spill = coverage_defects(plan, strips, BOX, step: 0.47, disc: [j['point_m'], j['outer_radius_m'] + walk], spill: true)
      assert_empty spill, "#{label} : faces hors du giratoire #{spill.first(4)}"
    end
    assert_equal [0, 0], edge_defects(plan, strips), label
    assert_empty misfacing_walls(plan, BOX), label
  end

  def test_the_ring_island_and_entries_by_hand
    p = plan(roundabout(X))
    j = p['junctions'].first
    assert_equal ['roundabout', 15.0, 7.0, 6.0], j.values_at('type', 'outer_radius_m', 'ring_width_m', 'corner_radius_m')
    # Îlot central : disque de 8 m à 0,14 m, planté.
    island = faces(p, 'road/plant').flatten(1).uniq
    assert(island.all? { |v| (dist(v) - 8).abs < TOL && (v[2] - 0.14).abs < TOL })
    # Îlot séparateur de la branche est : base de 2 m à 16 m du centre (anneau + 1 m), pointe à 24 m.
    splitter = faces(p, 'road/median').flatten(1).uniq.select { |v| v[0] > 55 }
    assert_equal [[66.0, -1.0], [66.0, 0.0], [66.0, 1.0], [74.0, 0.0]], splitter.map { |v| v[0, 2].map { |c| c.round(6) } }.sort
    # Coupe : bout de l'îlot + 1 m, 25 m sur chaque branche.
    assert_equal [25.0] * 4, j['cuts_m']
    # Bordure de l'anneau : arc de 15 m ; arrondi d'entrée tangent au bord de chaussée (y = 4) en
    # x = 50 + √(21² − 10²) et à l'anneau sur la droite du centre de l'arrondi.
    tangent = 50 + Math.sqrt((21**2) - (10**2))
    curb = faces(p, 'road/curb').flatten(1).uniq
    assert(curb.any? { |v| (v[0] - tangent).abs < TOL && (v[1] - 4).abs < TOL }, 'tangente sur le bord de chaussée')
    on_ring = [50 + ((tangent - 50) * 15 / 21), 10.0 * 15 / 21]
    assert(curb.any? { |v| (v[0] - on_ring[0]).abs < TOL && (v[1] - on_ring[1]).abs < TOL }, 'tangente sur l’anneau')
    # Entre deux entrées (de 28,4° à 61,6° dans chaque quart), la bordure est l'anneau lui-même.
    ring = faces(p, 'road/lane').flatten(1).uniq.select do |v|
      deg = (Math.atan2(v[1], v[0] - 50) * 180 / Math::PI) % 90
      dist(v) > 14 && dist(v) < 16 && deg > 35 && deg < 55
    end
    refute_empty ring
    assert(ring.all? { |v| (dist(v) - 15).abs < TOL })
  end

  def test_sealed_and_nothing_spills
    {
      'rue X' => [X, {}, 2.5],
      'rue T' => [[road('a', [[0, 0], [100, 0]]), road('b', [[50, 0], [50, 50]])], {}, 2.5],
      'rue Y à 120°' => [[road('a', [[0, 0], [50, 0]]), road('b', [[50, 0], [25, 43.3]]), road('c', [[50, 0], [25, -43.3]])], {}, 2.5],
      'rue, anneau minimal' => [X, { outer_radius_m: 13, ring_width_m: 6 }, 2.5],
      'nationale X' => [[road('a', [[0, 0], [100, 0]], 'nationale'), road('b', [[50, -50], [50, 50]], 'nationale')], {}, nil],
      'boulevard X' => [[road('a', [[0, 0], [100, 0]], 'boulevard'), road('b', [[50, -50], [50, 50]], 'boulevard')], { outer_radius_m: 25 }, nil],
      'campagne X à 79°' => [[road('a', [[0, 0], [100, 0]], 'campagne'), road('b', [[50, -50], [30, 50]], 'campagne')], {}, nil],
      'rue × campagne' => [[road('a', [[0, 0], [100, 0]]), road('b', [[50, -50], [50, 50]], 'campagne')], {}, nil]
    }.each do |label, (roads, opts, walk)|
      assert_sealed(plan(roundabout(roads, **opts)), roads, label, walk: walk)
    end
  end

  def test_narrow_roads_get_no_splitter_island
    roads = [road('a', [[0, 0], [100, 0]], 'campagne'), road('b', [[50, -50], [50, 50]], 'campagne')]
    p = plan(roundabout(roads))
    assert_empty faces(p, 'road/median')
    refute_empty faces(p, 'road/plant')
  end

  def test_limits_and_first_overrun
    assert plan(roundabout(X, outer_radius_m: 13, ring_width_m: 6))
    long = [road('a', [[0, 0], [400, 0]]), road('b', [[200, -200], [200, 200]])]
    assert plan(roundabout(long, outer_radius_m: 60, ring_width_m: 12))
    [{ outer_radius_m: 12.99 }, { outer_radius_m: 60.01 }, { ring_width_m: 5.99 }, { ring_width_m: 12.01 }].each do |opts|
      errors = build(roundabout(X, **opts)).errors
      assert_equal ['E_SCHEMA'], errors.map(&:code).uniq, opts.inspect
    end
  end

  def test_refusals
    paths = [road('a', [[0, 0], [100, 0]]), road('b', [[50, 0], [50, 50]], 'pieton')]
    assert_equal ['roundabout_without_carriageway'], build(roundabout(paths)).errors.map { |d| d.params['reason'] }.uniq
    # Six voies de 4,5 m : 13,5 m de demi-chaussée pour un anneau de 13 m.
    wide = preset('nationale').merge('bands' => Array.new(6) { { 'type' => 'lane', 'width_m' => 4.5 } } +
                                                 [{ 'type' => 'verge', 'width_m' => 1 }])
    wide['bands'].unshift({ 'type' => 'verge', 'width_m' => 1 })
    errors = build(roundabout([road('a', [[0, 0], [100, 0]], wide), road('b', [[50, -50], [50, 50]])], outer_radius_m: 13)).errors
    assert_includes errors.map { |d| d.params['reason'] }, 'ring_too_small'
    assert_equal 'a', errors.find { |d| d.params['reason'] == 'ring_too_small' }.params['road']
    # Deux branches à 53° : les arrondis d'entrée se chevauchent.
    close = [road('a', [[0, 0], [100, 0]], 'nationale'), road('b', [[50, 0], [20, 40]], 'nationale')]
    assert_equal ['roundabout_arms_too_close'], build(roundabout(close)).errors.map { |d| d.params['reason'] }.uniq
    %w[roundabout_without_carriageway ring_too_small roundabout_arms_too_close].each { |r| assert Archgen::UI::Messages::REASONS.key?(r), r }
  end

  def test_items_stay_out_and_the_plan_is_stable
    p = plan(roundabout(X))
    reach = p['junctions'].first['reach_m'].max
    inside = []
    walk = lambda do |node|
      if node['primitive'] && node['primitive']['type'] == 'instance'
        x, y = node['primitive']['matrix'].values_at(12, 13)
        inside << [x, y] if Math.hypot(x - 50, y) < reach - 1
      end
      node['children'].each(&walk)
    end
    p['nodes'].each(&walk)
    assert_empty inside
    assert_equal RoadEngine.digest(p), RoadEngine.digest(plan(roundabout(X)))
  end
end
