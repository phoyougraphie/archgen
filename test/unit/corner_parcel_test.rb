# frozen_string_literal: true

require_relative '../test_helper'

# U18 : parcelle d'angle (docs/ENSEMBLE_CONTRACT.md, Bâtiment de rangée).
class CornerParcelTest < Minitest::Test
  include Archgen::Core

  Planar = Archgen::Geometry::Planar
  PROFILES = %w[haussmann toulousain brutalist].freeze
  ANGLES = [30, -30, 90, -90, 120, -120].freeze
  LENGTH = 40.0
  # Deux quantifications successives, dans chaque parcelle puis dans le passage au modèle.
  SHARED = 5e-6

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def intake
    @intake ||= Archgen::Composition.intake
  end

  def materials
    Archgen::Composition.materials.fetch('materials')
  end

  def elbow(angle)
    radians = angle * Math::PI / 180.0
    [[0, 0], [LENGTH, 0], [(LENGTH + (LENGTH * Math.cos(radians))).round(6), (LENGTH * Math.sin(radians)).round(6)]]
  end

  def settings(points, profile: 'haussmann', closed: false, building: {}, parcel: {})
    tree = { 'trace' => { 'points_m' => points, 'closed' => closed }, 'parcel' => parcel, 'building' => { 'profile' => { 'id' => profile } }.merge(building) }
    result = Archgen::Composition.ensemble_intake.settings(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def parcels_of(value)
    layout = Archgen::Geometry::ParcelLayout.call(value)
    assert layout.ok?, layout.errors.map(&:to_h).inspect
    layout.value['parcels']
  end

  def build(value, parcel)
    ParcelBuilding.call(value, parcel, registry: registry, intake: intake, materials: materials)
  end

  def plan_for(value, parcel)
    result = build(value, parcel)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value.plan
  end

  # Les deux parcelles qui se rejoignent au coude.
  def corner_pair(value)
    all = parcels_of(value)
    index = all.index { |p| p['delta_right_m'] != 0.0 }
    [all[index], all[index + 1]]
  end

  def to_model(parcel, point)
    x, y, z = point
    origin = parcel['origin_m']
    t = parcel['tangent']
    [origin[0] + (x * t[0]) - (y * t[1]), origin[1] + (x * t[1]) + (y * t[0]), z]
  end

  def node(plan, id)
    walk = lambda do |list|
      list.each do |item|
        return item if item['id'] == id

        found = walk.call(item['children'])
        return found if found
      end
      nil
    end
    walk.call(plan['nodes'])
  end

  def vertices(plan, id)
    node(plan, id)['primitive']['vertices']
  end

  def all_of_category(plan, category)
    walk = lambda { |list| list.flat_map { |item| (item['category'] == category ? [item] : []) + walk.call(item['children']) } }
    walk.call(plan['nodes'])
  end

  def roof_points(plan)
    all_of_category(plan, 'roof_face').flat_map { |n| n['primitive']['vertices'] } + all_of_category(plan, 'gable_end').flat_map { |n| n['primitive']['vertices'] }
  end

  def on_side?(footprint_x, point, depth, delta, side)
    expected = side == :left ? delta * point[1] / depth : footprint_x - (delta * point[1] / depth)
    (point[0] - expected).abs < SHARED
  end

  def face_normal(primitive, face)
    points = face['indices'].map { |i| primitive['vertices'][i] }
    points.each_with_index.reduce([0.0, 0.0, 0.0]) do |total, (p, i)|
      q = points[(i + 1) % points.size]
      [total[0] + ((p[1] - q[1]) * (p[2] + q[2])), total[1] + ((p[2] - q[2]) * (p[0] + q[0])), total[2] + ((p[0] - q[0]) * (p[1] + q[1]))]
    end
  end

  def assert_points_match(expected, actual, message)
    expected.each do |point|
      nearest = actual.map { |other| point.zip(other).map { |a, b| (a - b).abs }.max }.min
      assert_operator nearest, :<, SHARED, "#{message} : #{point.inspect}"
    end
  end

  # --- Forme

  def test_shell_walls_follow_the_trapezoid
    value = settings(elbow(90))
    first, = corner_pair(value)
    plan = plan_for(value, first)
    width = first['width_m']
    assert_equal 9.0, first['delta_right_m']
    right = vertices(plan, 'wall/right')
    assert_includes right, [width, 0.0, 0.0]
    assert_includes right, [width - 9.0, 9.0, 0.0]
    rear = vertices(plan, 'wall/rear')
    assert_includes rear, [width - 9.0, 9.0, 0.0]
    assert_includes rear, [0.0, 9.0, 0.0]
  end

  def test_shell_wall_normals_point_outward_on_every_angle
    ANGLES.each do |angle|
      value = settings(elbow(angle))
      corner_pair(value).each do |parcel|
        plan = plan_for(value, parcel)
        centre = [parcel['width_m'] / 2.0, parcel['depth_m'] / 2.0]
        all_of_category(plan, 'wall').each do |wall|
          primitive = wall['primitive']
          primitive['faces'].each do |face|
            normal = face_normal(primitive, face)
            point = primitive['vertices'][face['indices'].first]
            outward = (normal[0] * (point[0] - centre[0])) + (normal[1] * (point[1] - centre[1]))
            assert_operator outward, :>, 0.0, "angle #{angle}, #{wall['id']}"
            assert_in_delta 0.0, normal[2], 1e-6
          end
        end
      end
    end
  end

  def test_rear_keeps_its_own_bays
    value = settings(elbow(90))
    first, = corner_pair(value)
    built = build(value, first).value
    assert_equal 12.0, first['width_m']
    assert_equal 3.0, first['rear_m']
    assert_equal 4, built.config.dig('facade', 'front_bays')
    assert_equal 1, built.rear_bays
    rear = built.plan['openings'].select { |o| o['facade_id'] == 'rear' }
    assert_equal 5, rear.size, 'une par niveau'
    rear.each { |o| assert_operator o['u_max_m'], :<, 3.0 }
  end

  # --- Onglets entre voisines

  def test_neighbours_share_their_walls_on_the_mitre
    ANGLES.each do |angle|
      value = settings(elbow(angle))
      first, second = corner_pair(value)
      a = vertices(plan_for(value, first), 'wall/right').map { |p| to_model(first, p) }
      b = vertices(plan_for(value, second), 'wall/left').map { |p| to_model(second, p) }
      assert_points_match a, b, "angle #{angle}"
      assert_points_match b, a, "angle #{angle}"
    end
  end

  def test_neighbours_share_their_roof_on_the_mitre
    PROFILES.each do |profile|
      ANGLES.each do |angle|
        value = settings(elbow(angle), profile: profile)
        first, second = corner_pair(value)
        a = roof_points(plan_for(value, first)).select { |p| on_side?(first['width_m'], p, first['depth_m'], first['delta_right_m'], :right) }.map { |p| to_model(first, p) }
        b = roof_points(plan_for(value, second)).select { |p| on_side?(second['width_m'], p, second['depth_m'], second['delta_left_m'], :left) }.map { |p| to_model(second, p) }
        refute_empty a, "#{profile} #{angle}"
        assert_points_match a, b, "#{profile} #{angle}"
        assert_points_match b, a, "#{profile} #{angle}"
      end
    end
  end

  def test_roof_faces_point_up_and_gables_stay_vertical
    PROFILES.each do |profile|
      ANGLES.each do |angle|
        value = settings(elbow(angle), profile: profile)
        plan = plan_for(value, corner_pair(value).first)
        all_of_category(plan, 'roof_face').each do |leaf|
          leaf['primitive']['faces'].each { |face| assert_operator face_normal(leaf['primitive'], face)[2], :>, 0.0, "#{profile} #{angle}" }
        end
        all_of_category(plan, 'gable_end').each do |leaf|
          leaf['primitive']['faces'].each { |face| assert_in_delta 0.0, face_normal(leaf['primitive'], face)[2], 1e-5, "#{profile} #{angle}" }
        end
      end
    end
  end

  def test_gable_faces_outward_on_the_mitre
    value = settings(elbow(90), profile: 'toulousain')
    first, = corner_pair(value)
    plan = plan_for(value, first)
    leaf = node(plan, 'roof/gable/right/0')
    normal = face_normal(leaf['primitive'], leaf['primitive']['faces'].first)
    assert_operator normal[0], :>, 0.0
    assert_operator normal[1], :>, 0.0
    assert_in_delta normal[0], normal[1], 1e-6, 'à 90°, la bissectrice est à 45°'
  end

  # --- Structural

  def structural(angle, profile: 'haussmann')
    value = settings(elbow(angle), profile: profile, building: { 'mode' => 'structural' })
    [value, *corner_pair(value)]
  end

  def test_inner_joint_is_at_the_wall_thickness_from_both_walls
    ANGLES.each do |angle|
      value, first, = structural(angle)
      plan = plan_for(value, first)
      t = build(value, first).value.config.dig('structure', 'wall_m')
      a = [first['width_m'], 0.0]
      b = [first['width_m'] - first['delta_right_m'], first['depth_m']]
      front = vertices(plan, 'wall/front').select { |p| p[2].zero? && (p[1] - t).abs < SHARED }
      inner = front.max_by(&:first)
      assert_in_delta t, inner[1], SHARED, "angle #{angle}"
      assert_in_delta t, Planar.segment_point_distance(a, b.map(&:to_f), inner.first(2)), 2 * SHARED, "angle #{angle}"
    end
  end

  def test_joint_vertices_are_common_to_both_walls
    ANGLES.each do |angle|
      value, first, = structural(angle)
      plan = plan_for(value, first)
      front = vertices(plan, 'wall/front')
      right = vertices(plan, 'wall/right')
      common = right.select { |p| front.any? { |q| p.zip(q).map { |x, y| (x - y).abs }.max < SHARED } }
      assert_operator common.size, :>=, 4, "angle #{angle} : arête extérieure et arête intérieure, en bas et en haut"
    end
  end

  # Le mur avant reste du bon côté du plan d'onglet : pas de recouvrement de volume.
  def test_no_wall_crosses_the_mitre_plane
    ANGLES.each do |angle|
      value, first, = structural(angle)
      plan = plan_for(value, first)
      width = first['width_m']
      t = build(value, first).value.config.dig('structure', 'wall_m')
      corner = [width, 0.0]
      joint = vertices(plan, 'wall/front').select { |p| p[2].zero? && (p[1] - t).abs < SHARED }.max_by(&:first)
      direction = Planar.sub(joint.first(2), corner)
      vertices(plan, 'wall/front').each do |point|
        assert_operator Planar.cross(direction, Planar.sub(point.first(2), corner)), :>=, -SHARED, "angle #{angle}, mur avant : #{point.inspect}"
      end
      vertices(plan, 'wall/right').each do |point|
        assert_operator Planar.cross(direction, Planar.sub(point.first(2), corner)), :<=, SHARED, "angle #{angle}, mur droit : #{point.inspect}"
      end
    end
  end

  def test_slabs_are_inside_the_trapezoid
    value, first, = structural(90)
    plan = plan_for(value, first)
    t = build(value, first).value.config.dig('structure', 'wall_m')
    slabs = all_of_category(plan, 'slab')
    assert_equal 4, slabs.size
    slabs.each do |slab|
      corners = slab['primitive']['vertices'].map(&:first).zip(slab['primitive']['vertices'].map { |v| v[1] }).uniq
      assert_equal 4, corners.size
      corners.each do |point|
        distance = [point[1], first['depth_m'] - point[1], point[0], ((first['width_m'] - (9.0 * point[1] / 9.0)) - point[0]) / Math.sqrt(2.0)].min
        assert_operator distance, :>=, t - (2 * SHARED)
      end
    end
  end

  def test_every_solid_passes_the_validator
    PROFILES.each do |profile|
      ANGLES.each do |angle|
        [0, 1].each do |lod|
          value = settings(elbow(angle), profile: profile, building: { 'mode' => 'structural', 'lod' => lod })
          parcels_of(value).each do |parcel|
            result = build(value, parcel)
            assert result.ok?, "#{profile} #{angle} LOD #{lod} #{parcel['id']} : #{result.errors.map(&:to_h).inspect}"
          end
        end
      end
    end
  end

  # --- Détails

  def lod1(angle, features)
    settings(elbow(angle), building: { 'lod' => 1, 'features' => features })
  end

  def cornice_points(plan)
    all_of_category(plan, 'cornice').first['primitive']['vertices']
  end

  def test_cornice_meets_its_neighbour_on_a_salient_angle
    value = lod1(90, 'cornice' => true)
    first, second = corner_pair(value)
    a = cornice_points(plan_for(value, first))
    b = cornice_points(plan_for(value, second))
    assert_in_delta first['width_m'] + 0.15, a.map(&:first).max, 1e-6, 'prolongée jusqu’à l’onglet'
    assert_in_delta(-0.15, b.map(&:first).min, 1e-6)
    tip_a = a.select { |p| p[1] < -0.1 }.max_by(&:first)
    tip_b = b.select { |p| p[1] < -0.1 && p[0] < 0 }.min_by(&:first)
    assert_points_match [to_model(first, tip_a)], [to_model(second, tip_b)], 'pointe commune'
  end

  def test_cornice_stops_at_the_mitre_on_a_reentrant_angle
    value = lod1(-90, 'cornice' => true)
    first, = corner_pair(value)
    a = cornice_points(plan_for(value, first))
    assert_in_delta first['width_m'], a.map(&:first).max, 1e-6
    assert_in_delta first['width_m'] - 0.15, a.select { |p| p[1] < -0.1 }.map(&:first).max, 1e-6
  end

  def test_balcony_does_not_cross_the_mitre_on_a_reentrant_angle
    value = lod1(-90, 'balcony' => true)
    first, = corner_pair(value)
    plan = plan_for(value, first)
    balconies = all_of_category(plan, 'balcony')
    refute_empty balconies
    balconies.each do |balcony|
      far = balcony['primitive']['vertices'].select { |p| p[1] < -0.5 }.map(&:first).max
      assert_in_delta first['width_m'] - 0.9, far, 1e-6
    end
  end

  def test_balcony_keeps_its_margins_on_a_salient_angle
    value = lod1(90, 'balcony' => true)
    first, = corner_pair(value)
    margin = build(value, first).value.config.dig('facade', 'margin_m')
    all_of_category(plan_for(value, first), 'balcony').each do |balcony|
      assert_in_delta first['width_m'] - margin, balcony['primitive']['vertices'].map(&:first).max, 1e-6
    end
  end

  def test_balcony_without_room_is_omitted_with_a_warning
    # Deux onglets rentrants très ouverts : à 0,9 m devant la façade, il ne reste plus de largeur.
    footprint = Archgen::Geometry::FootprintSolver.trapezoid(width_m: 4.0, depth_m: 9.0, delta_left_m: -20.0, delta_right_m: -20.0)
    config = { 'facade' => { 'margin_m' => 0.6 }, 'lod' => 1, 'features' => { 'cornice' => false, 'balcony' => true, 'surrounds' => false }, 'materials' => { 'wall' => 'limestone', 'frames' => 'painted_wood' }, 'structure' => { 'wall_m' => 0.24 }, 'mode' => 'shell' }
    levels = [Archgen::Geometry::Level.new(index: 0, base_z_m: 0.0, top_z_m: 3.0, slab_bottom_z_m: nil), Archgen::Geometry::Level.new(index: 1, base_z_m: 3.0, top_z_m: 6.0, slab_bottom_z_m: 2.8), Archgen::Geometry::Level.new(index: 2, base_z_m: 6.0, top_z_m: 9.0, slab_bottom_z_m: 5.8)]
    result = Archgen::Geometry::DetailSolver.call(footprint: footprint, levels: levels, openings: [], config: config)
    assert result.ok?
    assert_empty result.value.nodes
    assert_equal 'balcony_no_room', result.warnings.first.params['reason']
  end

  # --- Refus

  # Virage de 120°, façade à 30° du mur latéral : le joint intérieur recule de 3,73 × 0,24 = 0,9 m.
  def test_bays_tighten_between_the_joints_of_a_closed_corner
    value = settings(elbow(120), building: { 'facade' => { 'margin_m' => 0.2, 'window_width_m' => 1.0 } }, parcel: { 'bay_width_m' => 2.0 })
    first, = corner_pair(value)
    plan = plan_for(value, first)
    last = plan['openings'].select { |o| o['facade_id'] == 'front' }.map { |o| o['u_max_m'] }.max
    joint = 0.24 * Math.tan(75.0 * Math::PI / 180.0)
    assert_in_delta 0.9, joint, 0.01
    assert_operator first['width_m'] - last, :>=, joint + 0.1
  end

  def test_a_straight_parcel_keeps_the_exact_grid
    value = settings([[0, 0], [24, 0]])
    plan = plan_for(value, parcels_of(value).first)
    first_window = plan['openings'].select { |o| o['facade_id'] == 'rear' && o['level_index'].zero? }.map { |o| o['u_min_m'] }.min
    assert_equal 1.35, first_window, 'M + P/2 − w/2 = 0,6 + 1,35 − 0,6'
  end

  def test_windows_that_no_longer_fit_are_refused
    value = settings(elbow(120), building: { 'facade' => { 'margin_m' => 0.2, 'window_width_m' => 1.95 } }, parcel: { 'bay_width_m' => 2.0 })
    first, = corner_pair(value)
    result = build(value, first)
    refute result.ok?
    assert_equal 'E_OPENING_CLEARANCE', result.errors.first.code
    assert result.errors.first.path.start_with?("/parcels/#{first['id']}/facade/"), result.errors.first.path
  end

  def test_wall_too_short_for_its_joints_is_refused
    footprint = Archgen::Geometry::FootprintSolver.trapezoid(width_m: 12.0, depth_m: 4.0, delta_left_m: 5.0, delta_right_m: 5.0)
    assert_empty Archgen::Geometry::FootprintSolver.inner_problems(footprint, 0.24)
    tight = Archgen::Geometry::FootprintSolver.trapezoid(width_m: 6.0, depth_m: 4.0, delta_left_m: 2.95, delta_right_m: 2.95)
    found = Archgen::Geometry::FootprintSolver.inner_problems(tight, 0.5).first
    assert_equal 'E_STREET_CORNER', found.code
    assert_equal 'wall_too_short', found.params['reason']
    assert_equal 'rear', found.params['id']
  end

  def test_roof_overhang_crossing_the_mitres_is_refused
    footprint = Archgen::Geometry::FootprintSolver.trapezoid(width_m: 22.0, depth_m: 9.0, delta_left_m: 10.0, delta_right_m: 10.0)
    roof = { 'type' => 'flat', 'overhang_m' => 2.0, 'pitch_deg' => 0.0, 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0 }
    result = Archgen::Geometry::RowRoofSolver.call(footprint, 10.0, roof, materials: { 'roof' => 'zinc', 'wall' => 'limestone' })
    refute result.ok?
    assert_equal 'roof_rear_too_short', result.errors.first.params['reason']
    assert_equal '/roof/overhang_m', result.errors.first.path
  end

  # --- Îlot de référence

  def test_reference_square_builds_in_every_style_mode_and_lod
    square = fixture_json('examples', 'ensembles', 'carre-40m.json')
    PROFILES.each do |profile|
      %w[shell structural].each do |mode|
        [0, 1].each do |lod|
          value = settings(square.dig('trace', 'points_m'), profile: profile, closed: true, building: { 'mode' => mode, 'lod' => lod })
          parcels_of(value).each do |parcel|
            result = build(value, parcel)
            assert result.ok?, "#{profile} #{mode} LOD #{lod} #{parcel['id']} : #{result.errors.map(&:to_h).inspect}"
          end
        end
      end
    end
  end

  def test_reentrant_contour_builds
    tree = fixture_json('examples', 'ensembles', 'contour-rentrant.json')
    value = settings(tree.dig('trace', 'points_m'), closed: true, parcel: tree['parcel'], building: { 'mode' => 'structural', 'lod' => 1 })
    parcels_of(value).each do |parcel|
      result = build(value, parcel)
      assert result.ok?, "#{parcel['id']} : #{result.errors.map(&:to_h).inspect}"
    end
  end

  def test_same_corner_same_plan
    value = settings(elbow(90))
    first, = corner_pair(value)
    assert_equal GeometryEngine.plan_digest(plan_for(value, first)), GeometryEngine.plan_digest(plan_for(value, first))
  end
end
