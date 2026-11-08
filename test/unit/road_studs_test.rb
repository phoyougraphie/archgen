# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/road_net'
require File.expand_path('../../archgen/ui/messages', __dir__)

# U41 : « clous » (D-10, ADR-42). C : plot de chaussée, élément d'une bande roulante posé sur sa limite
# gauche ; B : clous de passage piéton, en option d'un carrefour à feux.
class RoadStudsTest < Minitest::Test
  include Archgen::Core
  include RoadNet

  C = Archgen::Composition

  def band(type, width, items = [])
    { 'type' => type, 'width_m' => width, 'items' => items }
  end

  def stud(variant = 'plain', **extra)
    { 'kind' => 'road_stud', 'variant' => variant }.merge(extra.transform_keys(&:to_s))
  end

  # Bande dérasée de 0,5 m, deux voies de 3,5 m, bande dérasée : plots sur les limites à 0,5, 4 et 7,5 m.
  def profile
    { 'road_profile_version' => 1, 'bands' => [band('edge', 0.5), band('lane', 3.5, [stud]), band('lane', 3.5, [stud('reflective')]), band('edge', 0.5, [stud])] }
  end

  def section(tree = profile)
    r = C.road_profile_intake.profile(tree)
    assert r.ok?, r.errors.map(&:to_h).inspect
    Archgen::Geometry::RoadSection.call(r.value, bands: C.road_bands, items: C.road_items)
  end

  def test_road_studs_mark_the_left_line_of_their_band
    items = section['items']
    assert_equal [0.5, 4.0, 7.5], items.map { |i| i['x_m'] }
    assert_equal [0.0], items.map { |i| i['z_m'] }.uniq
    assert_equal [12.0, 0.02], items.first.values_at('spacing_m', 'height_m')
  end

  def test_road_studs_are_laid_along_the_road
    tree = { 'trace' => { 'points_m' => [[0, 0], [100, 0]], 'radii_m' => [] }, 'profile' => profile }
    s = C.road_intake.settings(tree).value
    p = RoadEngine.call(s, bands: C.road_bands, items: C.road_items).value
    studs = p['nodes'][0]['children'].find { |n| n['id'] == 'road/furniture' }['children']
    assert_equal 3 * 8, studs.size # 6 m, puis tous les 12 m jusqu'à 90 m
    assert_equal %w[road1/road_stud/plain/20 road1/road_stud/reflective/20], p['definitions'].keys.grep(/stud/).sort
    reflective = p['definitions']['road1/road_stud/reflective/20'].first['primitive']['faces'].map { |f| f['material'] }.uniq
    assert_equal ['road/item/reflector'], reflective
    assert_empty RoadPlanValidator.call(p)
  end

  def test_road_studs_only_on_rolling_bands_and_in_range
    bad = C.road_profile_intake.profile('road_profile_version' => 1, 'bands' => [band('sidewalk', 2, [stud])])
    assert_equal 'item_band_mismatch', bad.errors.first.params['reason']
    high = C.road_profile_intake.profile('road_profile_version' => 1, 'bands' => [band('lane', 3.5, [stud('plain', height_m: 0.051)])])
    assert_equal 'height_range', high.errors.first.params['reason']
  end

  def signals(**opts)
    network(road('a', [[0, 0], [100, 0]]), road('b', [[50, -60], [50, 60]]),
            junctions: [{ 'id' => 'a@50.0+b@60.0', 'type' => 'signals' }.merge(opts.transform_keys(&:to_s))])
  end

  def studs_of(plan)
    out = []
    walk = lambda do |n|
      out << n if n['id'].start_with?('crossing_stud/')
      n['children'].each(&walk)
    end
    plan['nodes'].each(&walk)
    out
  end

  # Rue de ville : deux voies de 3 m par branche (stationnement exclu) ; 6 clous par voie (0,25 m du bord,
  # tous les 0,5 m jusqu'à 0,25 m de l'autre bord), deux rangées par passage, quatre passages : 96 clous.
  def test_crossing_studs_on_request_at_signals
    plain = build(signals).value
    with = build(signals(crossing_studs: true))
    assert with.ok?, with.errors.map(&:to_h).inspect
    p = with.value
    assert_empty studs_of(plain)
    studs = studs_of(p)
    assert_equal 96, studs.size
    assert_equal [0.0], studs.map { |n| n['primitive']['matrix'][14] }.uniq
    assert p['definitions'].key?('road1/crossing_stud/metal/20')
    j = p['junctions'].first
    reach = j['reach_m'].max
    studs.each do |n|
      x, y = n['primitive']['matrix'].values_at(12, 13)
      d = Math.hypot(x - 50, y)
      assert_operator d, :<=, reach + 1e-6
    end
    assert_empty RoadPlanValidator.call(p)
  end

  def test_crossing_studs_need_a_signals_junction
    r = build(network(road('a', [[0, 0], [100, 0]]), road('b', [[50, -60], [50, 60]]),
                      junctions: [{ 'id' => 'a@50.0+b@60.0', 'type' => 'simple', 'crossing_studs' => true }]))
    assert_equal 'crossing_studs_unavailable', r.errors.first.params['reason']
    assert_match(/carrefour à feux/, Archgen::UI::Messages.text(r.errors.first))
  end

  def test_a_signals_network_without_the_option_keeps_its_settings
    s = C.road_network_intake.settings(signals(crossing_studs: false)).value
    refute s['junctions'].first.key?('crossing_studs')
  end
end
