# frozen_string_literal: true

require_relative '../test_helper'

# U16 : réglages d'ensemble, tracé et parcelles (docs/ENSEMBLE_CONTRACT.md).
class ParcelLayoutTest < Minitest::Test
  include Archgen::Core

  Layout = Archgen::Geometry::ParcelLayout
  Planar = Archgen::Geometry::Planar
  SUITE_SEED = 20_261_106
  RANDOM_CASES = 100
  TOLERANCE = 2e-6

  def intake
    @intake ||= Archgen::Composition.ensemble_intake
  end

  def settings(tree)
    result = intake.settings(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def fixture(name)
    fixture_json('examples', 'ensembles', "#{name}.json")
  end

  def trace(points, closed: false, **rest)
    { 'trace' => { 'points_m' => points, 'closed' => closed } }.merge(rest.transform_keys(&:to_s))
  end

  def layout(tree)
    Layout.call(settings(tree))
  end

  def parcels(tree)
    result = layout(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value['parcels']
  end

  def assert_refused(result, code, path, reason = nil)
    refute result.ok?, 'attendu un refus'
    assert_nil result.value
    found = result.errors.find { |d| d.code == code && d.path == path && (reason.nil? || d.params['reason'] == reason) }
    assert found, result.errors.map(&:to_h).inspect
    found
  end

  # --- Réglages

  def test_defaults_of_an_open_street
    value = settings(trace([[0, 0], [30, 0]]))
    assert_equal({ 'side' => 'left' }, value['layout'])
    assert_equal 12.0, value.dig('parcel', 'target_width_m')
    assert_equal 9.0, value.dig('parcel', 'depth_m')
    refute value.key?('access')
    assert value.frozen?
  end

  def test_defaults_of_a_closed_trace
    value = settings(fixture('carre-40m'))
    assert_equal({ 'count' => 'auto', 'width_m' => 3.5, 'height_m' => 2.7 }, value['access'])
    refute value.key?('layout')
  end

  def test_street_width_default_applies_only_on_both_sides
    assert_equal 12.0, settings(trace([[0, 0], [30, 0]], layout: { 'side' => 'both' })).dig('layout', 'street_width_m')
    assert_refused intake.settings(trace([[0, 0], [30, 0]], layout: { 'street_width_m' => 10 })), 'E_SCHEMA', '/layout/street_width_m', 'street_width_without_both'
  end

  def test_settings_that_do_not_apply_are_refused
    assert_refused intake.settings(trace([[0, 0], [30, 0]], access: { 'count' => 1 })), 'E_SCHEMA', '/access', 'access_on_open_trace'
    square = [[0, 0], [40, 0], [40, 40], [0, 40]]
    assert_refused intake.settings(trace(square, closed: true, layout: { 'side' => 'left' })), 'E_SCHEMA', '/layout', 'layout_on_closed_trace'
  end

  def test_unknown_keys_and_bad_values_are_refused
    assert_refused intake.settings(trace([[0, 0], [30, 0]], admin: true)), 'E_SCHEMA', '/admin', 'unknown_key'
    assert_refused intake.settings(trace([[0, 0], [30, 0]], parcel: { 'depth_m' => 3.9 })), 'E_SCHEMA', '/parcel/depth_m', 'minimum'
    assert_refused intake.settings(trace([[0, 0], [30, 0, 1]])), 'E_SCHEMA', '/trace/points_m/1', 'max_items'
    assert_refused intake.settings('trace' => { 'closed' => false }), 'E_SCHEMA', '/trace/points_m', 'required'
    assert_refused intake.settings({}), 'E_SCHEMA', '/trace', 'required'
  end

  def test_access_count_accepts_auto_and_one_to_three
    square = [[0, 0], [40, 0], [40, 40], [0, 40]]
    ['auto', 1, 2, 3].each { |count| assert_equal count, settings(trace(square, closed: true, access: { 'count' => count })).dig('access', 'count') }
    assert_refused intake.settings(trace(square, closed: true, access: { 'count' => 4 })), 'E_SCHEMA', '/access/count', 'enum'
  end

  def test_future_version_is_refused
    assert_refused intake.settings(trace([[0, 0], [30, 0]], ensemble_version: 2)), 'E_VERSION', '/ensemble_version', 'unsupported'
  end

  def test_settings_read_from_json_text
    assert intake.settings(JSON.generate(trace([[0, 0], [30, 0]]))).ok?
    refute intake.settings('{"trace":{"points_m":[],"closed":false},"trace":{}}').ok?
  end

  def test_building_fields_computed_by_parcel_are_refused
    {
      'footprint' => { 'width_m' => 10 }, 'seed' => 3, 'facade' => { 'front_bays' => 2 }
    }.each do |key, value|
      path = key == 'facade' ? '/building/facade/front_bays' : "/building/#{key}"
      assert_refused intake.settings(trace([[0, 0], [30, 0]], building: { key => value })), 'E_SCHEMA', path, 'computed_by_parcel'
    end
    assert_refused intake.settings(trace([[0, 0], [30, 0]], building: { 'facade' => { 'side_bays' => 1 } })), 'E_SCHEMA', '/building/facade/side_bays', 'computed_by_parcel'
    assert_refused intake.settings(trace([[0, 0], [30, 0]], building: { 'facade' => { 'entry_bay' => 0 } })), 'E_SCHEMA', '/building/facade/entry_bay', 'computed_by_parcel'
  end

  def test_building_draft_is_validated
    assert_refused intake.settings(trace([[0, 0], [30, 0]], building: { 'mode' => 'interior' })), 'E_SCHEMA', '/building/mode', 'enum'
    assert_equal 'haussmann', settings(trace([[0, 0], [30, 0]], building: { 'profile' => { 'id' => 'haussmann' } })).dig('building', 'profile', 'id')
  end

  # --- Tracé

  def test_too_few_points
    assert_refused layout(trace([[0, 0]])), 'E_STREET_TRACE', '/trace/points_m', 'too_few_points'
    assert_refused layout(trace([[0, 0], [30, 0]], closed: true)), 'E_STREET_TRACE', '/trace/points_m', 'too_few_points'
  end

  def test_first_point_must_be_the_origin
    assert_refused layout(trace([[1, 0], [30, 0]])), 'E_STREET_TRACE', '/trace/points_m/0', 'first_point_not_origin'
  end

  def test_point_range_limit_and_first_excess
    assert layout(trace([[0, 0], [2000, 0]], parcel: { 'target_width_m' => 60 })).ok?
    assert_refused layout(trace([[0, 0], [2000.001, 0]])), 'E_STREET_TRACE', '/trace/points_m/1', 'point_out_of_range'
  end

  def test_segment_length_limit_and_first_excess
    assert layout(trace([[0, 0], [6, 0]])).ok?
    assert_refused layout(trace([[0, 0], [5.999, 0]])), 'E_STREET_TRACE', '/trace/segments/0', 'segment_short'
  end

  def test_repeated_closing_point_is_a_short_segment
    assert_refused layout(trace([[0, 0], [40, 0], [40, 40], [0, 40], [0, 0]], closed: true)), 'E_STREET_TRACE', '/trace/segments/4', 'segment_short'
  end

  def test_self_intersection_names_both_segments
    found = assert_refused layout(trace([[0, 0], [40, 0], [40, 40], [20, 40], [20, -10]])), 'E_STREET_TRACE', '/trace/segments/0', 'self_intersection'
    assert_equal 3, found.params['other']
  end

  def test_touching_itself_is_refused
    assert_refused layout(trace([[0, 0], [40, 0], [40, 40], [0, 0]])), 'E_STREET_TRACE', '/trace/segments/0', 'self_intersection'
  end

  def test_folding_back_is_refused
    assert_refused layout(trace([[0, 0], [40, 0], [10, 0]])), 'E_STREET_TRACE', '/trace/segments/0', 'self_intersection'
  end

  # --- Carré de référence, calculé à la main : δ = 9, c = 12, R = 16, m = 1

  def test_reference_square
    result = layout(fixture('carre-40m'))
    assert result.ok?
    all = result.value['parcels']
    assert_equal 12, all.size
    assert_equal({ 'parcel_count' => 12, 'row_count' => 1, 'facade_length_m' => 160.0 }, result.value['metrics'])
    all.each_slice(3) do |side|
      assert_equal [12.0, 16.0, 12.0], side.map { |p| p['width_m'] }
      assert_equal [3.0, 16.0, 3.0], side.map { |p| p['rear_m'] }
      assert_equal [true, false, true], side.map { |p| p['corner'] }
    end
  end

  def test_reference_square_first_side_coordinates
    first, middle, last = parcels(fixture('carre-40m')).first(3)
    assert_equal 'ring/0/0', first['id']
    assert_equal [[0.0, 0.0], [12.0, 0.0], [12.0, 9.0], [9.0, 9.0]], first['ring_m']
    assert_equal [[12.0, 0.0], [28.0, 0.0], [28.0, 9.0], [12.0, 9.0]], middle['ring_m']
    assert_equal [[28.0, 0.0], [40.0, 0.0], [31.0, 9.0], [28.0, 9.0]], last['ring_m']
    assert_equal [[0.0, 0.0], [12.0, 0.0], [3.0, 9.0], [0.0, 9.0]], last['local_ring_m']
    assert_equal 9.0, last['delta_right_m']
    assert_equal 0.0, last['delta_left_m']
  end

  def test_reference_square_rear_edges_form_the_courtyard
    rear = parcels(fixture('carre-40m')).first(3).sum { |p| p['rear_m'] }
    assert_equal 22.0, rear
  end

  def test_clockwise_contour_gives_the_same_shape_with_input_segments
    clockwise = parcels(trace([[0, 0], [0, 40], [40, 40], [40, 0]], closed: true))
    assert_equal 12, clockwise.size
    assert_equal [12.0, 16.0, 12.0], clockwise.first(3).map { |p| p['width_m'] }
    assert_equal [2, 1, 0, 3], clockwise.map { |p| p['segment'] }.uniq
    clockwise.each { |p| assert_operator Planar.signed_area(p['ring_m']), :>, 0.0 }
  end

  def test_corner_parcels_widen_when_the_mitre_requires_it
    # Carré de 40 m, D = 12 : δ = 12, c = max(12, 14) = 14, R = 12, m = 1.
    all = parcels(trace([[0, 0], [40, 0], [40, 40], [0, 40]], closed: true, parcel: { 'depth_m' => 12 }))
    assert_equal [14.0, 12.0, 14.0], all.first(3).map { |p| p['width_m'] }
    assert_equal [2.0, 12.0, 2.0], all.first(3).map { |p| p['rear_m'] }
  end

  def test_remainder_too_short_goes_to_the_corner_parcels
    # Carré de 40 m, D = 18 : δ = 18, c = 20, R = 0.
    assert_equal [20.0, 20.0], parcels(trace([[0, 0], [40, 0], [40, 40], [0, 40]], closed: true, parcel: { 'depth_m' => 18 })).first(2).map { |p| p['width_m'] }
    # Carré de 45 m, D = 18, cible 12 : R = 5, round(5/12) = 0, soit 2,5 de plus par angle.
    assert_equal [22.5, 22.5], parcels(trace([[0, 0], [45, 0], [45, 45], [0, 45]], closed: true, parcel: { 'depth_m' => 18 })).first(2).map { |p| p['width_m'] }
  end

  def test_segment_too_short_for_two_corners_is_one_parcel
    # D = 9 : δ = 9, c = 12 > 11,5, donc une seule parcelle, d'arrière 2,5.
    first = parcels(trace([[0, 0], [11.5, 0], [11.5, 40]])).first
    assert_equal 11.5, first['width_m']
    assert_equal 2.5, first['rear_m']
    assert_equal 9.0, first['delta_right_m']
  end

  def test_angle_too_closed_for_the_depth
    # Carré de 40 m, D = 20 : arrière nul. Il manque 2 m.
    found = assert_refused layout(trace([[0, 0], [40, 0], [40, 40], [0, 40]], closed: true, parcel: { 'depth_m' => 20 })), 'E_STREET_CORNER', '/trace/segments/0', 'rear_too_short'
    assert_equal 2.0, found.params['missing_m']
  end

  def test_rear_limit_and_first_excess
    # Segment de 21 m, angle droit : D = 19 laisse exactement 2 m à l'arrière, D = 19,001 non.
    assert_equal 2.0, parcels(trace([[0, 0], [21, 0], [21, 21]], parcel: { 'depth_m' => 19 })).first['rear_m']
    assert_refused layout(trace([[0, 0], [21, 0], [21, 21]], parcel: { 'depth_m' => 19.001 })), 'E_STREET_CORNER', '/trace/segments/0', 'rear_too_short'
  end

  def test_acute_angle_is_judged_on_geometry
    assert layout(trace([[0, 0], [60, 0], [60 + (60 * Math.cos(2.0)), 60 * Math.sin(2.0)]], parcel: { 'depth_m' => 6 })).ok?
    sharp = trace([[0, 0], [20, 0], [20 + (20 * Math.cos(3.0)), 20 * Math.sin(3.0)]], parcel: { 'depth_m' => 9 })
    assert_refused layout(sharp), 'E_STREET_CORNER', '/trace/segments/0', 'rear_too_short'
  end

  # --- Rangées

  def test_left_and_right_sides_are_mirrors
    left = parcels(trace([[0, 0], [24, 0]], layout: { 'side' => 'left' }))
    right = parcels(trace([[0, 0], [24, 0]], layout: { 'side' => 'right' }))
    assert_equal [[0.0, 0.0], [12.0, 0.0], [12.0, 9.0], [0.0, 9.0]], left.first['ring_m']
    assert_equal [[24.0, 0.0], [12.0, 0.0], [12.0, -9.0], [24.0, -9.0]], right.first['ring_m']
    assert_equal 'right/0/0', right.first['id']
  end

  def test_elbow_street_on_both_sides
    # Coude à 90° vers la gauche, rue de 12 m, D = 9, façades à ±6 de l'axe.
    # Rangée gauche : 54 m puis 42 m, angle saillant, δ = 9. Rangée droite : 66 m puis 54 m, angle rentrant, δ = −9.
    all = parcels(fixture('rue-coudee-deux-cotes'))
    left = all.select { |p| p['row'] == 'left' }
    right = all.select { |p| p['row'] == 'right' }
    assert_in_delta 54.0, left.select { |p| p['segment'].zero? }.sum { |p| p['width_m'] }, TOLERANCE
    assert_in_delta 42.0, left.select { |p| p['segment'] == 1 }.sum { |p| p['width_m'] }, TOLERANCE
    assert_in_delta 66.0, right.select { |p| p['segment'].zero? }.sum { |p| p['width_m'] }, TOLERANCE
    assert_in_delta 54.0, right.select { |p| p['segment'] == 1 }.sum { |p| p['width_m'] }, TOLERANCE
    assert_equal [6.0], left.select { |p| p['segment'].zero? }.flat_map { |p| p['ring_m'].first(2).map(&:last) }.uniq
    assert_equal [-6.0], right.select { |p| p['segment'].zero? }.flat_map { |p| p['ring_m'].first(2).map(&:last) }.uniq
    assert_equal(-9.0, right.find { |p| p['segment'] == 1 && p['corner'] }['delta_right_m'])
    assert_equal(-9.0, right.find { |p| p['segment'].zero? && p['corner'] }['delta_left_m'])
  end

  def test_offset_row_can_vanish_in_a_tight_elbow
    tight = trace([[0, 0], [8, 0], [8, 8]], layout: { 'side' => 'both', 'street_width_m' => 12 })
    assert_refused layout(tight), 'E_STREET_TRACE', '/trace/segments/0', 'segment_short'
  end

  def test_reentrant_contour_lengthens_the_rear
    # Angle rentrant en (30, 30), D = 6 : l'arrière s'allonge de 6 de chaque côté du sommet.
    all = parcels(fixture('contour-rentrant'))
    reentrant = all.select { |p| p['delta_right_m'].negative? || p['delta_left_m'].negative? }
    assert_equal 2, reentrant.size
    assert_equal [12.0, 12.0], reentrant.map { |p| p['width_m'] }
    assert_equal [18.0, 18.0], reentrant.map { |p| p['rear_m'] }
  end

  # --- Contrôles d'ensemble

  def test_facing_parcels_limit_and_first_excess
    # Rue repliée en U : deux tronçons à 21 m l'un de l'autre, D = 9, soit 3 m entre arrières.
    at_limit = trace([[0, 0], [60, 0], [60, 21], [0, 21]], parcel: { 'depth_m' => 9 })
    assert layout(at_limit).ok?
    under = trace([[0, 0], [60, 0], [60, 20.999], [0, 20.999]], parcel: { 'depth_m' => 9 })
    assert_refused layout(under), 'E_STREET_OVERLAP', '/parcels/left/0/1', 'parcels_too_close'
  end

  def test_overlapping_parcels_are_refused
    # Le dernier segment redescend sur la bande du premier, entre x = 30 et x = 39.
    fold = trace([[0, 0], [60, 0], [60, 20], [30, 20], [30, 5]], parcel: { 'depth_m' => 9 })
    found = assert_refused layout(fold), 'E_STREET_OVERLAP', '/parcels/left/0/2', 'parcels_overlap'
    assert found.params['other'].start_with?('left/3/')
  end

  def test_courtyard_too_narrow_is_refused
    assert_refused layout(trace([[0, 0], [40, 0], [40, 40], [0, 40]], closed: true, parcel: { 'depth_m' => 19 })), 'E_STREET_OVERLAP', '/parcels/ring/0/0', 'parcels_too_close'
  end

  def test_both_sides_street_width_is_the_gap
    assert layout(trace([[0, 0], [60, 0]], layout: { 'side' => 'both', 'street_width_m' => 3 })).ok?
    all = parcels(trace([[0, 0], [60, 0]], layout: { 'side' => 'both', 'street_width_m' => 3 }))
    assert_equal 10, all.size
  end

  def test_parcel_budget_limit_and_first_excess
    # Deux segments de 1 200 m : 100 + 100 parcelles. À 1 206 m, le premier passe à 101.
    assert_equal 200, layout(trace([[0, 0], [1200, 0], [1200, 1200]], parcel: { 'target_width_m' => 12, 'depth_m' => 4 })).value['metrics']['parcel_count']
    over = layout(trace([[0, 0], [1206, 0], [1206, 1200]], parcel: { 'target_width_m' => 12, 'depth_m' => 4 }))
    found = assert_refused over, 'E_STREET_BUDGET', '/parcel/target_width_m', 'parcel_count'
    assert_equal 201, found.params['value']
  end

  # --- Invariants

  def test_same_input_same_layout
    first = layout(fixture('carre-40m')).value
    second = layout(fixture('carre-40m')).value
    assert_equal Canonical.digest(first), Canonical.digest(second)
    assert first.frozen?
  end

  def test_random_traces_stay_coherent
    random = Random.new(SUITE_SEED)
    accepted = 0
    RANDOM_CASES.times do |index|
      tree = random_tree(random)
      result = layout(tree)
      message = "suite #{SUITE_SEED}, cas #{index} : #{JSON.generate(tree)}"
      unless result.ok?
        assert((result.errors.map(&:code) - %w[E_STREET_TRACE E_STREET_CORNER E_STREET_OVERLAP E_STREET_BUDGET]).empty?, message)
        next
      end
      accepted += 1
      assert_coherent(result.value['parcels'], message)
    end
    assert_operator accepted, :>=, RANDOM_CASES / 3, 'la suite doit couvrir de vrais tracés'
  end

  def test_random_traces_cover_their_length
    random = Random.new(SUITE_SEED + 1)
    checked = 0
    RANDOM_CASES.times do
      tree = random_contour(random)
      result = layout(tree)
      next unless result.ok?

      points = tree.dig('trace', 'points_m')
      expected = points.each_index.sum { |i| Planar.length(Planar.sub(points[(i + 1) % points.size], points[i])) }
      assert_in_delta expected, result.value['parcels'].sum { |p| p['width_m'] }, 1e-3, JSON.generate(tree)
      checked += 1
    end
    assert_operator checked, :>=, RANDOM_CASES / 3
  end

  private

  def random_tree(random)
    return random_contour(random) if random.rand < 0.5

    points = [[0.0, 0.0]]
    heading = random.rand * Math::PI * 2
    (2 + random.rand(4)).times do
      length = 15.0 + (random.rand * 60.0)
      points << [(points.last[0] + (length * Math.cos(heading))).round(3), (points.last[1] + (length * Math.sin(heading))).round(3)]
      heading += (random.rand - 0.5) * 2.4
    end
    side = %w[left right both][random.rand(3)]
    trace(points, layout: { 'side' => side }, parcel: { 'depth_m' => 5.0 + (random.rand * 8.0), 'target_width_m' => 8.0 + (random.rand * 10.0) })
  end

  # Contour étoilé autour d'un centre : simple par construction, convexe ou non.
  def random_contour(random)
    count = 3 + random.rand(5)
    angles = (0...count).map { |i| (i + (random.rand * 0.6)) * 2 * Math::PI / count }
    raw = angles.map do |angle|
      radius = 30.0 + (random.rand * 40.0)
      [radius * Math.cos(angle), radius * Math.sin(angle)]
    end
    points = raw.map { |x, y| [(x - raw[0][0]).round(3), (y - raw[0][1]).round(3)] }
    trace(points, closed: true, parcel: { 'depth_m' => 4.0 + (random.rand * 6.0), 'target_width_m' => 8.0 + (random.rand * 10.0) })
  end

  def assert_coherent(all, message)
    all.each do |parcel|
      assert_operator Planar.signed_area(parcel['ring_m']), :>, 0.0, message
      assert_operator parcel['rear_m'], :>=, Limits::ENSEMBLE_REAR_MIN_M - TOLERANCE, message
      front = Planar.sub(parcel['ring_m'][1], parcel['ring_m'][0])
      rear = Planar.sub(parcel['ring_m'][2], parcel['ring_m'][3])
      assert_in_delta parcel['width_m'], Planar.length(front), 2 * TOLERANCE, message
      assert_in_delta parcel['rear_m'], Planar.length(rear), 4 * TOLERANCE, message
      assert_operator Planar.dot(front, rear), :>, 0.0, message
      assert_in_delta 0.0, Planar.cross(Planar.unit(front), Planar.unit(rear)), 1e-5, message
    end
    all.group_by { |p| p['row'] }.each_value { |row| assert_row_continuous(row, message) }
    all.permutation(2).each { |first, second| refute inside_by_ray?(second['ring_m'], centre(first['ring_m'])), "#{first['id']} dans #{second['id']}, #{message}" }
  end

  def centre(ring)
    [ring.sum(&:first) / ring.size, ring.sum(&:last) / ring.size]
  end

  # Contrôle indépendant du code testé : tir de rayon, sans hypothèse de convexité.
  def inside_by_ray?(ring, point)
    crossings = ring.each_index.count do |i|
      a = ring[i]
      b = ring[(i + 1) % ring.size]
      (a[1] > point[1]) != (b[1] > point[1]) && point[0] < a[0] + ((point[1] - a[1]) * (b[0] - a[0]) / (b[1] - a[1]))
    end
    crossings.odd?
  end

  # La façade d'une parcelle reprend là où la précédente s'arrête : le tracé est couvert sans trou.
  def assert_row_continuous(row, message)
    row.each_cons(2) do |first, second|
      assert_in_delta first['ring_m'][1][0], second['ring_m'][0][0], 2 * TOLERANCE, message
      assert_in_delta first['ring_m'][1][1], second['ring_m'][0][1], 2 * TOLERANCE, message
      next unless first['segment'] != second['segment']

      # Sur l'onglet, les deux parcelles partagent aussi le sommet arrière.
      assert_in_delta first['ring_m'][2][0], second['ring_m'][3][0], 4 * TOLERANCE, message
      assert_in_delta first['ring_m'][2][1], second['ring_m'][3][1], 4 * TOLERANCE, message
    end
  end
end
