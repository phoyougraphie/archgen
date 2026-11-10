# frozen_string_literal: true

require_relative '../test_helper'

# U82 — Mobilier urbain : catalogue et formes (docs/MOBILIER_CONTRACT.md §1, AG-120).
class RoadFurnitureTest < Minitest::Test
  include Archgen::Core
  Shapes = Archgen::Geometry::RoadItemShapes
  P = Archgen::Geometry::RoadItems::PREFIX

  def intake
    @intake ||= Archgen::Composition.road_intake
  end

  def profile(items, band: 'sidewalk')
    { 'bands' => [{ 'type' => band, 'width_m' => 3.0, 'items' => items }, { 'type' => 'lane', 'width_m' => 3.5 }] }
  end

  def settings(items, band: 'sidewalk')
    intake.settings({ 'trace' => { 'points_m' => [[0, 0], [100, 0]], 'radii_m' => [] }, 'profile' => profile(items, band: band) })
  end

  def plan(items)
    s = settings(items)
    assert s.ok?, s.errors.map(&:to_h).inspect
    result = RoadEngine.call(s.value, bands: Archgen::Composition.road_bands, items: Archgen::Composition.road_items)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def instances(built, kind)
    built['nodes'][0]['children'].flat_map { |g| g['children'] }.select { |n| n.dig('primitive', 'type') == 'instance' && n['id'].start_with?("#{kind}/") }
  end

  # Chaque arête parcourue une fois dans chaque sens, volume positif.
  def assert_closed(primitive, label)
    edges = Hash.new(0)
    primitive['faces'].each do |f|
      f['indices'].each_with_index { |a, i| edges[[a, f['indices'][(i + 1) % f['indices'].size]]] += 1 }
    end
    edges.each { |(a, b), n| assert_equal n, edges[[b, a]], "#{label} : arête #{a}-#{b} non fermée" }
    assert Shapes.normal_out?(primitive), "#{label} : normales vers l'intérieur"
  end

  def solids(kind, variant, height, count: nil)
    Shapes.definition(kind, variant, height, count: count).map { |n| n['primitive'] }
  end

  def extent(parts, axis)
    parts.flat_map { |p| p['vertices'].map { |v| v[axis] } }.minmax
  end

  def test_every_shape_is_closed_and_stands_from_the_ground_to_its_height
    cases = [['bench', 'bench', 0.85], ['bin', 'bin', 0.9], ['bike_rack', 'hoop', 0.75], ['bus_stop', 'shelter', 2.5]] +
            Archgen::Geometry::RoadFurnitureShapes::SIGNS.keys.map { |v| ['sign', v, 2.3] }
    cases.each do |kind, variant, h|
      parts = solids(kind, variant, h, count: 3)
      parts.each_with_index { |p, i| assert_closed(p, "#{kind}/#{variant}/#{i}") }
      low, high = extent(parts, 2)
      assert_in_delta 0.0, low, 1e-9, kind
      assert_in_delta(kind == 'bus_stop' ? 2.6 : h, high, 1e-9, "#{kind}/#{variant}")
    end
  end

  def test_bike_rack_hoops_follow_the_count_and_the_pitch
    assert_equal 3, solids('bike_rack', 'hoop', 0.75, count: 1).size
    nine = solids('bike_rack', 'hoop', 0.75, count: 3)
    assert_equal 9, nine.size
    assert_equal [-0.825, 0.825], extent(nine, 0).map { |x| x.round(6) }
  end

  def test_shelter_opens_toward_the_carriageway_and_uses_glass
    parts = solids('bus_stop', 'shelter', 2.5)
    glass = parts.select { |p| p['faces'].first['material'] == 'road/item/glass' }
    assert_equal 3, glass.size
    back = glass.min_by { |p| extent([p], 1)[1] }
    assert_operator extent([back], 1)[1], :<, -0.6, 'fond du côté opposé à la chaussée'
    glass.each { |p| assert_operator extent([p], 1)[1], :<=, 0.3 + 1e-9, 'rien de vitré côté chaussée' }
  end

  def test_sign_plate_faces_the_arrivals_and_uses_its_colours
    stop = solids('sign', 'stop', 2.3)
    plates = stop.drop(1)
    plates.each { |p| assert_operator extent([p], 0)[1], :<=, 0.0, 'plaque devant le mât, côté −X' }
    assert_equal %w[road/item/white road/item/red], plates.map { |p| p['faces'].first['material'] }
    assert_in_delta 2.3 - 0.7, extent(plates, 2)[0], 0.02, 'plaque de 0,7 m sous le haut'
    assert_equal 4, solids('sign', 'prohibition', 2.3).size, 'barre blanche du sens interdit'
  end

  def test_road_places_shared_definitions_with_count
    built = plan([{ 'kind' => 'bench' }, { 'kind' => 'bike_rack', 'count' => 4 }, { 'kind' => 'bin', 'spacing_m' => 25 }])
    benches = instances(built, 'bench')
    assert_equal 5, benches.size, '100 m au pas de 20 m'
    assert_equal ["#{P}bench/bench/850"], benches.map { |n| n['primitive']['definition_id'] }.uniq
    assert_equal ["#{P}bike_rack/hoop/750/4"], instances(built, 'bike_rack').map { |n| n['primitive']['definition_id'] }.uniq
    assert_equal 4, instances(built, 'bin').size
    assert built['definitions'].key?("#{P}bike_rack/hoop/750/4")
  end

  def test_refusals
    reasons = ->(items, band: 'sidewalk') { settings(items, band: band).errors.map { |e| e.params['reason'] } }
    too_many = settings([{ 'kind' => 'bike_rack', 'count' => 11 }]).errors
    assert(too_many.any? { |e| e.path.end_with?('/count') }, 'onze arceaux refusés')
    assert_includes reasons.call([{ 'kind' => 'bench', 'count' => 2 }]), 'count_unavailable'
    assert_includes reasons.call([{ 'kind' => 'bench' }], band: 'cycle'), 'item_band_mismatch'
    assert_includes reasons.call([{ 'kind' => 'bench', 'spacing_m' => 2 }]), 'spacing_range'
  end

  def test_new_materials_are_in_the_road_catalogue
    catalogue = Archgen::Composition.road_materials.fetch('materials')
    %w[blue glass yellow].each { |part| assert catalogue.key?("road/item/#{part}"), part }
    assert_equal 0.35, catalogue['road/item/glass']['alpha']
  end
end
