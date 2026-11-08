# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/road_net'
require File.expand_path('../../archgen/ui/messages', __dir__)

# U28 : carrefour à feux (docs/VOIRIE_CONTRACT.md, Carrefours ; AG-044). Circulation à droite.
# Au-delà de la coupe du carrefour simple : passage piéton sur chaque branche à trottoir, ligne
# d'arrêt sur les voies qui entrent, un feu par branche à chaussée, à droite de ceux qui arrivent.
class RoadSignalsTest < Minitest::Test
  include Archgen::Core
  include RoadNet

  TOL = 1e-6
  BOX = [10, -45, 90, 45].freeze
  X = [RoadNet.road('a', [[0, 0], [100, 0]]), RoadNet.road('b', [[50, -50], [50, 50]])].freeze

  def signals(roads, id, **rest)
    network(*roads, junctions: [{ 'id' => id, 'type' => 'signals' }.merge(rest.transform_keys(&:to_s))])
  end

  def plan(tree)
    result = build(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def lights(plan)
    out = []
    walk = lambda do |node|
      out << node if node['id'].start_with?('signal/')
      node['children'].each(&walk)
    end
    plan['nodes'].each(&walk)
    out
  end

  def markings(plan)
    s = surface(plan)
    s['faces'].select { |f| f['material'] == 'road/marking' }.map { |f| f['indices'].map { |i| s['vertices'][i] } }
  end

  # Marquage de la branche est (x > 50) d'une rue droite : [x mini, x maxi, y mini, y maxi] par face.
  def east(plan)
    markings(plan).select { |pts| pts.all? { |p| p[0] > 55 } }.map do |pts|
      [pts.map(&:first).minmax, pts.map { |p| p[1] }.minmax].flatten
    end
  end

  def test_a_signals_crossing_has_one_light_per_arm_at_the_stop_line
    p = plan(signals(X, 'a@50.0+b@50.0'))
    assert_equal 'signals', p['junctions'].first['type']
    assert_equal 4, p['metrics']['signal_count']
    assert_equal 4, lights(p).size
    # Rue de 13 m : coupe à 10 m, passage de 4 m, garde de 1 m, ligne d'arrêt de 0,5 m.
    assert_equal [15.5] * 4, p['junctions'].first['reach_m']
    light = lights(p).find { |n| n['primitive']['matrix'][12] > 55 }
    m = light['primitive']['matrix']
    # Branche est : on y arrive vers l'ouest, sur la moitié nord ; le feu est sur le trottoir nord,
    # 0,5 m derrière la bordure, au droit de la ligne d'arrêt, optiques vers l'est.
    assert_in_delta 65.25, m[12], TOL
    assert_in_delta 4.5, m[13], TOL
    assert_in_delta 0.14, m[14], TOL
    assert_equal [-1.0, 0.0], m[0, 2]
    assert_equal 'road_furniture', Archgen::Geometry::RoadItems.family(light)
    assert p['definitions'].key?('road1/signal/tricolor/3000')
  end

  def test_stripes_and_stop_line_on_the_east_arm
    p = plan(signals(X, 'a@50.0+b@50.0'))
    faces = east(p)
    crossing = faces.select { |x0, x1, _, _| x0 >= 60 - TOL && x1 <= 64 + TOL }
    stop = faces.select { |x0, x1, _, _| x0 >= 65 - TOL && x1 <= 65.5 + TOL }
    assert_equal faces.size, crossing.size + stop.size, 'aucun marquage hors du passage et de la ligne'
    # Bandes de 0,5 m dans le sens de la voie, à l'intérieur de la chaussée (± 4 m).
    widths = crossing.map { |_, _, y0, y1| (y1 - y0).round(6) }.uniq
    assert_equal [0.5], widths
    assert(crossing.all? { |_, _, y0, y1| y0 >= -4 + 0.25 - TOL && y1 <= 4 - 0.25 + TOL })
    # Ligne d'arrêt : la seule voie qui entre. Rue de ville : stationnement au nord (2 à 4 m), deux
    # voies de 3 m de -4 à 2 m ; on arrive par la voie nord, de -1 à 2 m.
    assert_equal [[-1.0, 2.0]], stop.map { |_, _, y0, y1| [y0.round(6), y1.round(6)] }.uniq.minmax.uniq
    assert(markings(p).flatten(1).all? { |pt| pt[2].abs < TOL }, 'marquage au ras de la chaussée')
  end

  def test_a_road_without_walkway_gets_a_stop_line_but_no_crossing
    roads = [road('a', [[0, 0], [100, 0]], 'nationale'), road('b', [[50, 0], [50, 50]], 'nationale')]
    p = plan(signals(roads, 'a@50.0+b@0.0'))
    j = p['junctions'].first
    assert_equal j['cuts_m'].map { |c| (c + 1.5).round(6) }, j['reach_m']
    assert_equal 3, p['metrics']['signal_count']
    # Une face de ligne d'arrêt par voie qui entre : une voie par branche.
    assert_equal 3, markings(p).size
  end

  def test_a_path_arm_gets_neither_light_nor_marking
    roads = [road('a', [[0, 0], [100, 0]]), road('b', [[50, 0], [50, 50]], 'pieton')]
    p = plan(signals(roads, 'a@50.0+b@0.0'))
    assert_equal 2, p['metrics']['signal_count']
    assert(markings(p).flatten(1).none? { |pt| pt[1] > 7 }, 'rien sur le chemin')
  end

  def test_signals_seal_like_a_simple_junction
    {
      'rue X' => [X, 'a@50.0+b@50.0'],
      'rue T' => [[road('a', [[0, 0], [100, 0]]), road('b', [[50, 0], [50, 50]])], 'a@50.0+b@0.0'],
      'boulevard X' => [[road('a', [[0, 0], [100, 0]], 'boulevard'), road('b', [[50, -50], [50, 50]], 'boulevard')], 'a@50.0+b@50.0'],
      'nationale T 53' => [[road('a', [[0, 0], [100, 0]], 'nationale'), road('b', [[50, 0], [80, 40]], 'nationale')], 'a@50.0+b@0.0'],
      'rural X 79' => [[road('a', [[0, 0], [100, 0]], 'rural'), road('b', [[50, -50], [30, 50]], 'rural')], nil],
      'rue T chemin' => [[road('a', [[0, 0], [100, 0]]), road('b', [[50, 0], [50, 50]], 'pieton')], 'a@50.0+b@0.0']
    }.each do |label, (roads, id)|
      id ||= plan(network(*roads))['junctions'].first['id']
      p = plan(signals(roads, id))
      strips = roads.map { |r| strip(r['road']['trace']['points_m'].first, r['road']['trace']['points_m'].last, r['road']['profile']) }
      assert_empty coverage_defects(p, strips, BOX, step: 0.41), label
      assert_equal [0, 0], edge_defects(p, strips), label
      assert_empty misfacing_walls(p, BOX), label
    end
  end

  def test_items_stay_out_of_the_marked_zone
    p = plan(signals(X, 'a@50.0+b@50.0'))
    reach = p['junctions'].first['reach_m'].max
    items = []
    walk = lambda do |node|
      items << node if node['primitive'] && node['primitive']['type'] == 'instance' && !node['id'].start_with?('signal/')
      node['children'].each(&walk)
    end
    p['nodes'].each(&walk)
    inside = items.map { |n| n['primitive']['matrix'].values_at(12, 13) }.select { |x, y| (x - 50).abs < reach - TOL && y.abs < reach - TOL }
    assert_empty inside
  end

  def test_type_changes_the_plan_and_stays_deterministic
    simple = plan(network(*X))
    a = plan(signals(X, 'a@50.0+b@50.0'))
    b = plan(signals(X, 'a@50.0+b@50.0'))
    assert_equal RoadEngine.digest(a), RoadEngine.digest(b)
    refute_equal RoadEngine.digest(simple), RoadEngine.digest(a)
    assert_equal 0, simple['metrics']['signal_count']
    assert_equal 'simple', simple['junctions'].first['type']
  end

  def test_refusals
    paths = [road('a', [[0, 0], [100, 0]], 'pieton'), road('b', [[50, -50], [50, 50]], 'pieton')]
    errors = build(signals(paths, 'a@50.0+b@50.0')).errors
    assert_equal [['signals_without_carriageway', '/junctions/a@50.0+b@50.0']], errors.map { |d| [d.params['reason'], d.path] }
    bare = preset('nationale').merge('bands' => preset('nationale')['bands'].select { |b| %w[edge lane].include?(b['type']) })
    errors = build(signals([road('a', [[0, 0], [100, 0]], bare), road('b', [[50, -50], [50, 50]], bare)], 'a@50.0+b@50.0')).errors
    assert_equal ['no_room_for_signal'], errors.map { |d| d.params['reason'] }.uniq
    assert_equal %w[a b], errors.map { |d| d.params['road'] }.uniq.sort
    errors = build(signals(X, 'a@50.0+b@50.0').tap { |t| t['junctions'][0]['type'] = 'interchange' }).errors
    assert_equal ['E_SCHEMA'], errors.map(&:code).uniq
    %w[signals_without_carriageway no_room_for_signal].each { |r| assert Archgen::UI::Messages::REASONS.key?(r), r }
  end
end
