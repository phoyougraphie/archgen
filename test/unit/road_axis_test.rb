# frozen_string_literal: true

require_relative '../test_helper'

# U24 : axe à rayons et rubans d'une voie (docs/VOIRIE_CONTRACT.md, Tronçon).
class RoadAxisTest < Minitest::Test
  include Archgen::Core

  SUITE_SEED = 20_261_107
  RANDOM_CASES = 100
  TOL = 1e-5

  def intake
    @intake ||= Archgen::Composition.road_intake
  end

  def preset(id)
    Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def tree(points, radii, profile = preset('ville'), **rest)
    { 'trace' => { 'points_m' => points, 'radii_m' => radii }, 'profile' => profile }.merge(wet(profile)).merge(rest.transform_keys(&:to_s))
  end

  # Une coupe à eau exige son régime (EAU_CONTRACT) ; les tests de voirie la posent à un seul niveau.
  def wet(profile)
    profile.is_a?(Hash) && profile['bands'].is_a?(Array) && profile['bands'].any? { |b| b.is_a?(Hash) && %w[water sea].include?(b['type']) } ? { 'water' => { 'mode' => 'flat' } } : {}
  end

  def build(input, **opts)
    settings = intake.settings(input)
    return settings unless settings.ok?

    RoadEngine.call(settings.value, bands: Archgen::Composition.road_bands, items: Archgen::Composition.road_items, **opts)
  end

  def plan(input)
    result = build(input)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def surface(plan)
    plan['nodes'][0]['children'][0]['primitive']
  end

  def assert_refused(result, code, path, reason)
    refute result.ok?, 'attendu un refus'
    found = result.errors.find { |d| d.code == code && d.path == path && d.params['reason'] == reason }
    assert found, result.errors.map(&:to_h).inspect
    found
  end

  # --- Droite : valeurs à la main

  def test_straight_city_street_by_hand
    p = plan(tree([[0, 0], [100, 0]], []))
    m = p['metrics']
    # Trottoir coupé par sa bordure (2), contremarche, stationnement, deux voies, contremarche, trottoir (2).
    assert_equal [9, 20, 2, 13.0, 100.0], m.values_at('surface_face_count', 'vertex_count', 'station_count', 'width_m', 'length_m')
    ys = surface(p)['vertices'].map { |v| v[1] }.uniq.sort
    # Axe au milieu : bord gauche à y = 6,5, bord droit à −6,5 ; bordures de 0,16 m.
    assert_equal [-6.5, -4.16, -4.0, -1.0, 2.0, 4.0, 4.16, 6.5], ys
  end

  def test_axis_on_an_edge
    left = surface(plan(tree([[0, 0], [50, 0]], [], axis: 'left')))['vertices'].map { |v| v[1] }
    right = surface(plan(tree([[0, 0], [50, 0]], [], axis: 'right')))['vertices'].map { |v| v[1] }
    assert_equal [-13.0, 0.0], left.minmax
    assert_equal [0.0, 13.0], right.minmax
  end

  def test_every_horizontal_face_looks_up_and_risers_face_the_low_side
    s = surface(plan(tree([[0, 0], [100, 0]], [])))
    s['faces'].each do |f|
      pts = f['indices'].map { |i| s['vertices'][i] }
      n = normal(pts)
      if pts.map { |q| q[2] }.uniq.size == 1
        assert_operator n[2], :>, 0.99
      else
        # Contremarche à gauche du trottoir droit : la face regarde vers le stationnement, à gauche (+y).
        assert_in_delta 1.0, n.map(&:abs).max, 1e-9
      end
    end
  end

  def test_neighbour_ribbons_share_their_vertices
    p = plan(tree([[0, 0], [100, 0], [100, 80]], [40], preset('boulevard')))
    distinct = Archgen::Geometry::RoadRibbons.cross_line(section(preset('boulevard'))).flat_map { |a, b, _| [a, b] }.uniq.size
    assert_equal p['metrics']['station_count'] * distinct, p['metrics']['vertex_count']
  end

  # --- Courbe : largeurs exactes, corde

  def test_widths_are_exact_along_an_arc
    radius = 40.0
    p = plan(tree([[0, 0], [100, 0], [100, 100]], [radius], preset('boulevard')))
    center = [100 - radius, radius]
    w = p['metrics']['width_m']
    expected = Archgen::Geometry::RoadRibbons.cross_line(section(preset('boulevard'))).flat_map { |a, b, _| [a[0], b[0]] }.uniq.map { |x| radius - ((w / 2) - x) }
    on_arc = surface(p)['vertices'].select { |v| v[0] > 60 + 1e-6 && v[1] < 100 - 1e-6 && v[0] < 140 && v[1] > -40 && v[1] > 1e-6 && v[0] < 100 + 30 }
    refute_empty on_arc
    on_arc.each do |v|
      r = Math.hypot(v[0] - center[0], v[1] - center[1])
      assert(expected.any? { |e| (e - r).abs < TOL }, "rayon #{r} hors des bords attendus")
    end
  end

  def test_chord_error_stays_within_tolerance_at_the_outer_edge
    radius = 30.0
    p = plan(tree([[0, 0], [100, 0], [100, 100]], [radius], preset('autoroute')))
    outer = radius + (p['metrics']['width_m'] / 2)
    center = [100 - radius, radius]
    ring = surface(p)['vertices'].select { |v| (Math.hypot(v[0] - center[0], v[1] - center[1]) - outer).abs < TOL && v[2].abs > 1.0 }
    ring = ring.sort_by { |v| Math.atan2(v[1] - center[1], v[0] - center[0]) }
    assert_operator ring.size, :>, 4
    ring.each_cons(2) do |a, b|
      mid = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2]
      assert_operator outer - Math.hypot(mid[0] - center[0], mid[1] - center[1]), :<=, Limits::ROAD_CHORD_TOLERANCE_M + 1e-9
    end
  end

  def test_sharp_corner_keeps_each_width_perpendicular_to_both_segments
    p = plan(tree([[0, 0], [100, 0], [100, 100]], [0]))
    corner = surface(p)["vertices"].map { |v| [v[0], v[1]] }.uniq
    # À l'onglet d'un angle droit, le bord gauche passe par (100 − 6,5, 6,5) et le droit par (106,5, −6,5).
    assert_includes corner, [93.5, 6.5]
    assert_includes corner, [106.5, -6.5]
  end

  # --- Refus et limites

  def test_inner_radius_limit_and_first_step_beyond
    profile = preset('boulevard')
    min = (35.2 / 2) + 1.0
    plan(tree([[0, 0], [100, 0], [100, 100]], [min], profile))
    found = assert_refused(build(tree([[0, 0], [100, 0], [100, 100]], [min - 0.001], profile)), 'E_ROAD_TRACE', '/trace/radii_m/0', 'radius_too_small')
    assert_in_delta min, found.params['min'], 1e-9
    # Virage à droite : c'est le bord droit qui compte, axe à gauche donc 35,2 m à droite.
    plan(tree([[0, 0], [100, 0], [100, -100]], [36.2], profile, axis: 'left'))
    assert_refused(build(tree([[0, 0], [100, 0], [100, -100]], [36.199], profile, axis: 'left')), 'E_ROAD_TRACE', '/trace/radii_m/0', 'radius_too_small')
  end

  def test_arcs_longer_than_their_segment_are_refused
    # Angle droit, R = 60 : tangente de 60 m de chaque côté ; deux arcs sur 100 m n'y tiennent pas.
    assert_refused(build(tree([[0, 0], [100, 0], [100, 100], [0, 100]], [60, 60])), 'E_ROAD_TRACE', '/trace/segments/1', 'arcs_too_long')
    plan(tree([[0, 0], [100, 0], [100, 100], [0, 100]], [50, 50]))
  end

  def test_trace_refusals
    assert_refused(build(tree([[0, 0]], [])), 'E_ROAD_TRACE', '/trace/points_m', 'too_few_points')
    assert_refused(build(tree([[1, 0], [50, 0]], [])), 'E_ROAD_TRACE', '/trace/points_m/0', 'first_point_not_road_origin')
    assert_refused(build(tree([[0, 0], [2001, 0]], [])), 'E_ROAD_TRACE', '/trace/points_m/1', 'coordinate_range')
    assert_refused(build(tree([[0, 0], [50, 0], [50, 50]], [])), 'E_ROAD_TRACE', '/trace/radii_m', 'radii_count')
    assert_refused(build(tree([[0, 0], [0.4, 0]], [])), 'E_ROAD_TRACE', '/trace/segments/0', 'segment_too_short')
    assert_refused(build(tree([[0, 0], [50, 0], [0, 0.001]], [0])), 'E_ROAD_TRACE', '/trace/points_m/1', 'reversal')
  end

  def test_a_sharp_hairpin_folds_its_inner_edge
    # 150° à onglet sur des segments de 10 m : le bord intérieur recule de 6,5 × tan 75° ≈ 24 m.
    found = assert_refused(build(tree([[0, 0], [10, 0], [10 - (10 * Math.cos(Math::PI / 6)), 10 * Math.sin(Math::PI / 6)]], [0])),
                           'E_ROAD_TRACE', '/trace/points_m/2', 'inner_edge_folds')
    assert found
  end

  def test_a_road_crossing_itself_is_refused_before_junctions_exist
    assert_refused(build(tree([[0, 0], [100, 0], [100, 100], [50, 100], [50, -50]], [0, 0, 0])), 'E_ROAD_TRACE', '/trace/points_m/4', 'self_overlap')
  end

  def test_face_budget
    found = assert_refused(build(tree([[0, 0], [100, 0], [100, 100]], [40], preset('boulevard')), limits: { unique: 100 }), 'E_ROAD_BUDGET', '/trace', 'road_faces')
    assert_equal 100, found.params['limit']
  end

  def test_profile_problems_are_reported_under_the_profile
    bad = preset('ville').merge('bands' => [{ 'type' => 'lane', 'width_m' => 9 }])
    assert_refused(build(tree([[0, 0], [50, 0]], [], bad)), 'E_ROAD_BAND', '/profile/bands/0/width_m', 'width_range')
    warned = intake.settings(tree([[0, 0], [50, 0]], [], { 'bands' => [{ 'type' => 'rail', 'width_m' => 4.5 }, { 'type' => 'lane', 'width_m' => 3.5 }] }))
    assert warned.ok?
    assert_equal ['/profile/bands/0'], warned.warnings.map(&:path)
  end

  def test_settings_refusals
    assert_refused(intake.settings(tree([[0, 0], [50, 0]], []).merge('road_version' => 2)), 'E_VERSION', '/road_version', 'unsupported_road')
    assert_refused(intake.settings(tree([[0, 0], [50, 0]], []).merge('colour' => 1)), 'E_SCHEMA', '/colour', 'unknown_key')
    assert_refused(intake.settings(tree([[0, 0], [50, 0], [50, 50]], [-1])), 'E_SCHEMA', '/trace/radii_m/0', 'minimum')
    value = intake.settings(tree([[0, 0], [50, 0]], [])).value
    assert_equal [1, 'center'], value.values_at('seed', 'axis')
    assert value.frozen?
  end

  def test_every_preset_follows_a_curve_and_a_sharp_corner
    Archgen::Composition.road_presets.fetch('presets').each do |p|
      width = section(p['profile'])['width_m']
      plan(tree([[0, 0], [200, 0], [200, 200]], [(width / 2) + 5], p['profile']))
      plan(tree([[0, 0], [200, 0], [200, 200]], [0], p['profile']))
    end
  end

  # Ces raisons passent par une méthode error : le relevé des messages du panneau ne les voit pas.
  def test_every_road_reason_has_a_message
    Archgen::Loader.load_internal('ui/messages')
    sources = %w[core/road_intake.rb geometry/road_axis.rb core/road_engine.rb].map { |f| read_utf8('archgen', *f.split('/')) }.join
    reasons = sources.scan(/(?:error|budget)\([^)]*?'([a-z_]+)'/).flatten + sources.scan(/reason: '([a-z_]+)'/).flatten
    missing = reasons.uniq - Archgen::UI::Messages::REASONS.keys - %w[E_ROAD_TRACE]
    assert_empty missing
    assert_operator reasons.uniq.size, :>=, 12
  end

  # --- Reproductibilité

  def test_one_hundred_pseudo_random_traces_are_reproducible
    presets = Archgen::Composition.road_presets.fetch('presets')
    accepted = 0
    RANDOM_CASES.times do |k|
      input = random_tree(k, presets)
      first = build(input)
      second = build(JSON.parse(JSON.generate(input)))
      assert_equal first.ok?, second.ok?, "cas #{k}"
      if first.ok?
        accepted += 1
        assert_equal RoadEngine.digest(first.value), RoadEngine.digest(second.value), "cas #{k}"
        assert_empty RoadPlanValidator.call(first.value), "cas #{k}"
      else
        assert_equal first.errors.map(&:to_h), second.errors.map(&:to_h), "cas #{k}"
        assert((first.errors.map(&:code) - %w[E_ROAD_TRACE E_ROAD_BUDGET]).empty?, "cas #{k} : #{first.errors.map(&:to_h)}")
      end
    end
    assert_operator accepted, :>=, 50, 'la plupart des tracés tirés doivent passer'
  end

  private

  def section(profile)
    effective = Archgen::Composition.road_profile_intake.profile(profile).value
    Archgen::Geometry::RoadSection.call(effective, bands: Archgen::Composition.road_bands, items: Archgen::Composition.road_items)
  end

  def unit(k, key)
    DeterministicRandom.unit(SUITE_SEED, "road/#{k}/#{key}")
  end

  def random_tree(k, presets)
    count = 2 + (unit(k, 'count') * 5).floor
    heading = 0.0
    points = [[0.0, 0.0]]
    (count - 1).times do |i|
      heading += (unit(k, "turn/#{i}") - 0.5) * Math::PI * 1.2 if i.positive?
      length = 30 + (unit(k, "length/#{i}") * 270)
      last = points.last
      points << [(last[0] + (length * Math.cos(heading))).round(3), (last[1] + (length * Math.sin(heading))).round(3)]
    end
    radii = (count - 2).times.map { |i| unit(k, "sharp/#{i}") < 0.2 ? 0 : (10 + (unit(k, "radius/#{i}") * 120)).round(2) }
    profile = presets[(unit(k, 'preset') * presets.size).floor]['profile']
    tree(points, radii, profile, axis: %w[center left right][(unit(k, 'axis') * 3).floor])
  end

  def normal(points)
    n = [0.0, 0.0, 0.0]
    points.each_with_index do |p, i|
      q = points[(i + 1) % points.size]
      n[0] += (p[1] - q[1]) * (p[2] + q[2])
      n[1] += (p[2] - q[2]) * (p[0] + q[0])
      n[2] += (p[0] - q[0]) * (p[1] + q[1])
    end
    size = Math.sqrt(n.sum { |c| c * c })
    n.map { |c| c / size }
  end
end
