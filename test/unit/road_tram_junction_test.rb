# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/road_net'
require File.expand_path('../../archgen/ui/messages', __dir__)

# U31 : tram au carrefour (docs/VOIRIE_CONTRACT.md, Carrefours ; AG-047). La voie à rails traverse
# le nœud tout droit ; ses rails passent au ras, sans interruption, à travers le cœur d'un carrefour
# simple ou à feux et à travers l'anneau et l'îlot central d'un giratoire. Toute autre disposition est
# refusée, et une voie ferrée sur ballast reste refusée jusqu'au passage à niveau (AG-050).
class RoadTramJunctionTest < Minitest::Test
  include Archgen::Core
  include RoadNet

  TOL = 1e-5
  BOX = [5, -45, 95, 45].freeze

  def tree(profile, other, type = nil, tee: false)
    roads = [road('a', [[0, 0], [100, 0]], profile), road('b', [[50, tee ? 0 : -50], [50, 50]], other)]
    return network(*roads) unless type

    id = plan(network(*roads))['junctions'].first['id']
    network(*roads, junctions: [{ 'id' => id, 'type' => type }])
  end

  def plan(tree)
    result = build(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def reasons(tree)
    build(tree).errors.map { |d| d.params['reason'] }.uniq
  end

  # Bandes de rail, par ligne de rail (y du milieu) : intervalles en x, fusionnés.
  def rail_runs(plan)
    s = surface(plan)
    faces = s['faces'].select { |f| f['material'] == 'road/rail_steel' }.map { |f| f['indices'].map { |i| s['vertices'][i] } }
    by_line = faces.group_by { |pts| (pts.map { |p| p[1] }.sum / pts.size).round(2) }
    by_line.transform_values do |list|
      spans = list.map { |pts| pts.map(&:first).minmax }.sort
      spans.each_with_object([]) do |(a, b), out|
        if out.any? && a <= out.last[1] + 1e-6
          out.last[1] = [out.last[1], b].max
        else
          out << [a, b]
        end
      end
    end
  end

  def test_rails_run_unbroken_across_every_kind_of_junction
    [nil, 'signals', 'roundabout'].each do |type|
      p = plan(tree('mixte', 'ville', type))
      runs = rail_runs(p)
      # Voie mixte : deux voies de tram, quatre rails, à 1,435 m d'écartement.
      assert_equal 4, runs.size, type.inspect
      runs.each_value { |spans| assert_equal [[0.0, 100.0]], spans.map { |a, b| [a.round(6), b.round(6)] }, type.inspect }
      gauges = runs.keys.sort.each_slice(2).map { |y0, y1| (y1 - y0).round(2) }
      assert_equal [1.44, 1.44], gauges
      rails = surface(p)['faces'].select { |f| f['material'] == 'road/rail_steel' }.flat_map { |f| f['indices'] }
      assert(rails.all? { |i| surface(p)['vertices'][i][2].abs < TOL }, 'au ras de la chaussée mixte')
    end
  end

  def test_sealed_with_the_tram_corridor
    {
      'mixte × rue' => [tree('mixte', 'ville'), 'mixte', 'ville', false],
      'mixte × rue, feux' => [tree('mixte', 'ville', 'signals'), 'mixte', 'ville', false],
      'plateforme × rue' => [tree('tram', 'ville'), 'tram', 'ville', false],
      'mixte T rue' => [tree('mixte', 'ville', tee: true), 'mixte', 'ville', true],
      'giratoire mixte × rue' => [tree('mixte', 'ville', 'roundabout'), 'mixte', 'ville', false],
      'giratoire plateforme T rue' => [tree('tram', 'ville', 'roundabout', tee: true), 'tram', 'ville', true]
    }.each do |label, (t, pa, pb, tee)|
      p = plan(t)
      strips = [strip([0, 0], [100, 0], pa), strip([50, tee ? 0 : -50], [50, 50], pb)]
      j = p['junctions'].first
      disc = j['type'] == 'roundabout' ? [j['point_m'], j['outer_radius_m']] : nil
      holes = coverage_defects(p, strips, BOX, step: 0.47, disc: disc)
      assert_empty holes, "#{label} #{holes.first(3)}"
      assert_equal [0, 0], edge_defects(p, strips), label
      assert_empty misfacing_walls(p, BOX), label
    end
  end

  def test_the_island_is_split_by_the_corridor
    p = plan(tree('mixte', 'ville', 'roundabout'))
    s = surface(p)
    island = s['faces'].select { |f| f['material'] == 'road/plant' }.flat_map { |f| f['indices'].map { |i| s['vertices'][i] } }
    # Couloir de la voie mixte : sa chaussée de ± 3,3 m ; rien de planté dedans.
    assert(island.all? { |v| v[1].abs >= 3.3 - TOL })
    assert(island.any? { |v| v[1] > 0 } && island.any? { |v| v[1].negative? })
    # Plateforme abaissée au cœur : le couloir est à 0, la plateforme garde 5 cm hors du carrefour.
    q = plan(tree('tram', 'ville'))
    core = surface(q)['faces'].select { |f| f['material'] == 'road/tram' }.flat_map { |f| f['indices'].map { |i| surface(q)['vertices'][i] } }
    assert(core.select { |v| (v[0] - 50).abs < 5 }.all? { |v| v[2].abs < TOL })
    assert(core.any? { |v| (v[2] - 0.05).abs < TOL })
  end

  def test_refusals
    assert_equal ['tram_not_through'], reasons(tree('ville', 'mixte', tee: true))
    assert_equal ['tram_not_through'], reasons(tree('mixte', 'mixte'))
    assert_equal ['rails_at_junction'], reasons(tree('fer', 'ville'))
    side = preset('tram').merge('bands' => [{ 'type' => 'sidewalk', 'width_m' => 3 }, { 'type' => 'tram', 'width_m' => 3.2 },
                                            { 'type' => 'lane', 'width_m' => 3.2 }, { 'type' => 'lane', 'width_m' => 3.2 },
                                            { 'type' => 'sidewalk', 'width_m' => 3 }])
    errors = build(tree(side, 'ville')).errors
    assert_equal [['tram_outside_carriageway', 'a']], errors.map { |d| [d.params['reason'], d.params['road']] }.uniq
    %w[tram_not_through tram_outside_carriageway rails_at_junction].each { |r| assert Archgen::UI::Messages::REASONS.key?(r), r }
  end
end
