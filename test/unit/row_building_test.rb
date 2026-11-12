# frozen_string_literal: true

require_relative '../test_helper'

# U17 : bâtiment de rangée rectangulaire (docs/ENSEMBLE_CONTRACT.md, Bâtiment de rangée).
class RowBuildingTest < Minitest::Test
  include Archgen::Core

  PROFILES = %w[haussmann toulousain brutalist].freeze
  STREET = [[0, 0], [60, 0]].freeze

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def intake
    @intake ||= Archgen::Composition.intake
  end

  def materials
    Archgen::Composition.materials.fetch('materials')
  end

  def settings(profile: 'haussmann', points: STREET, parcel: {}, building: {}, seed: 1)
    tree = { 'seed' => seed, 'trace' => { 'points_m' => points, 'closed' => false }, 'parcel' => parcel,
             'building' => { 'profile' => { 'id' => profile } }.merge(building) }
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

  def built(value = settings, parcel = parcels_of(value).first)
    result = build(value, parcel)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def roof_faces(plan, category = nil)
    roof = plan['nodes'].first['children'].find { |n| n['category'] == 'roof' }
    roof['children'].select { |n| category.nil? || n['category'] == category }.map do |leaf|
      primitive = leaf['primitive']
      primitive['faces'].first['indices'].map { |i| primitive['vertices'][i] }
    end
  end

  def newell(points)
    points.each_with_index.reduce([0.0, 0.0, 0.0]) do |total, (p, i)|
      q = points[(i + 1) % points.size]
      [total[0] + ((p[1] - q[1]) * (p[2] + q[2])), total[1] + ((p[2] - q[2]) * (p[0] + q[0])), total[2] + ((p[0] - q[0]) * (p[1] + q[1]))]
    end
  end

  def openings_on(plan, side)
    plan['openings'].select { |o| o['facade_id'] == side }
  end

  def slope(degrees)
    Math.tan(degrees * Math::PI / 180.0)
  end

  # --- Configuration et travées

  def test_bays_are_computed_from_the_parcel
    value = built
    assert_equal 12.0, value.config.dig('footprint', 'width_m')
    assert_equal 9.0, value.config.dig('footprint', 'depth_m')
    assert_equal 4, value.config.dig('facade', 'front_bays')
    assert_equal 0, value.config.dig('facade', 'side_bays')
    assert_equal 2, value.config.dig('facade', 'entry_bay')
    assert_equal 4, value.rear_bays
  end

  def test_bay_count_follows_the_bay_width_and_rounds_down
    value = settings(parcel: { 'bay_width_m' => 5 })
    assert_equal 2, built(value).config.dig('facade', 'front_bays')
    assert_equal 1, built(value).config.dig('facade', 'entry_bay')
    assert_equal 2, ParcelBuilding.bays(10.0, 5.0, 1)
    assert_equal 1, ParcelBuilding.bays(9.999, 5.0, 1)
  end

  def test_a_narrow_parcel_keeps_one_front_bay_and_no_rear_bay
    value = settings(points: [[0, 0], [6, 0]], parcel: { 'bay_width_m' => 7 })
    result = built(value)
    assert_equal 1, result.config.dig('facade', 'front_bays')
    assert_equal 0, result.rear_bays
    assert_empty openings_on(result.plan, 'rear')
    refute_empty openings_on(result.plan, 'front')
  end

  def test_side_walls_are_blind_and_emitted
    PROFILES.each do |profile|
      plan = built(settings(profile: profile)).plan
      assert_empty openings_on(plan, 'left'), profile
      assert_empty openings_on(plan, 'right'), profile
      walls = plan['nodes'].first['children'].find { |n| n['category'] == 'walls' }
      assert_includes walls['children'].map { |n| n['id'][/left|right/] }, 'left', profile
      assert_includes walls['children'].map { |n| n['id'][/left|right/] }, 'right', profile
    end
  end

  def test_door_is_on_the_street_side
    doors = built.plan['openings'].select { |o| o['kind'] == 'door' }
    assert_equal 1, doors.size
    assert_equal 'front', doors.first['facade_id']
  end

  def test_parcel_seed_is_stable_and_specific
    assert_equal ParcelBuilding.seed(1, 'left/0/0'), ParcelBuilding.seed(1, 'left/0/0')
    refute_equal ParcelBuilding.seed(1, 'left/0/0'), ParcelBuilding.seed(1, 'left/0/1')
    refute_equal ParcelBuilding.seed(1, 'left/0/0'), ParcelBuilding.seed(2, 'left/0/0')
    assert ParcelBuilding.seed(1, 'left/0/0').between?(0, 0xFFFF_FFFF)
    assert_equal ParcelBuilding.seed(1, 'left/0/0'), built.config.dig('seed')
  end

  def test_same_parcel_same_plan
    assert_equal GeometryEngine.plan_digest(built.plan), GeometryEngine.plan_digest(built.plan)
  end

  # --- Toits

  def test_no_roof_face_goes_past_the_side_walls
    PROFILES.each do |profile|
      value = built(settings(profile: profile))
      width = value.config.dig('footprint', 'width_m')
      xs = roof_faces(value.plan).flatten(1).map(&:first)
      assert_equal 0.0, xs.min, profile
      assert_equal width, xs.max, profile
    end
  end

  def test_overhang_stays_at_front_and_rear
    value = built(settings(profile: 'toulousain'))
    e = value.config.dig('roof', 'overhang_m')
    assert_operator e, :>, 0.0
    ys = roof_faces(value.plan, 'roof_face').flatten(1).map { |p| p[1] }
    assert_equal(-e, ys.min)
    assert_equal 9.0 + e, ys.max
  end

  def test_gable_section_is_exact
    value = built(settings(profile: 'toulousain'))
    roof = value.config.dig('roof')
    h = value.plan['metrics']['wall_top_z_m']
    r = slope(roof['pitch_deg'])
    assert_in_delta h + (r * 4.5), value.plan['metrics']['roof_top_z_m'], 1e-6
    assert_equal 2, roof_faces(value.plan, 'roof_face').size
    assert_equal 2, roof_faces(value.plan, 'gable_end').size
    ridge = roof_faces(value.plan, 'gable_end').first.max_by(&:last)
    assert_equal 4.5, ridge[1]
  end

  def test_mansard_has_no_side_pans
    value = built(settings(profile: 'haussmann'))
    roof = value.config.dig('roof')
    h = value.plan['metrics']['wall_top_z_m']
    pans = roof_faces(value.plan, 'roof_face')
    assert_equal 4, pans.size, 'bas et haut, en façade et à l’arrière'
    pans.each { |pan| assert_equal 4, pan.size }
    ring = h + (slope(roof['lower_pitch_deg']) * roof['inset_m'])
    top = ring + (slope(roof['pitch_deg']) * (4.5 - roof['inset_m']))
    assert_in_delta top, value.plan['metrics']['roof_top_z_m'], 1e-6
    assert_equal 4, roof_faces(value.plan, 'gable_end').size, 'deux pignons en deux morceaux'
  end

  def test_flat_roof_is_one_face
    value = built(settings(profile: 'brutalist'))
    assert_equal 1, roof_faces(value.plan, 'roof_face').size
    assert_empty roof_faces(value.plan, 'gable_end')
  end

  def test_roof_normals_point_up_and_gables_outward
    PROFILES.each do |profile|
      plan = built(settings(profile: profile)).plan
      roof_faces(plan, 'roof_face').each { |face| assert_operator newell(face)[2], :>, 0.0, profile }
      roof_faces(plan, 'gable_end').each do |face|
        x = face.first[0]
        normal = newell(face)
        x.zero? ? assert_operator(normal[0], :<, 0.0, profile) : assert_operator(normal[0], :>, 0.0, profile)
      end
    end
  end

  def test_neighbours_share_their_roof_line
    PROFILES.each do |profile|
      value = settings(profile: profile, points: [[0, 0], [29, 0]], parcel: { 'target_width_m' => 14.5 })
      first, second = parcels_of(value)
      a = built(value, first)
      b = built(value, second)
      right = roof_faces(a.plan).flatten(1).select { |p| p[0] == first['width_m'] }.map { |p| p[1, 2] }.uniq.sort
      left = roof_faces(b.plan).flatten(1).select { |p| p[0].zero? }.map { |p| p[1, 2] }.uniq.sort
      assert_equal right, left, profile
    end
  end

  def test_plan_is_valid_in_every_mode_and_lod
    PROFILES.each do |profile|
      %w[shell structural].each do |mode|
        [0, 1].each do |lod|
          value = settings(profile: profile, building: { 'mode' => mode, 'lod' => lod })
          parcels_of(value).each do |parcel|
            result = build(value, parcel)
            assert result.ok?, "#{profile} #{mode} LOD #{lod} : #{result.errors.map(&:to_h).inspect}"
            assert_empty PlanValidator.call(result.value.plan, materials: materials)
          end
        end
      end
    end
  end

  def test_mansard_details_stay_within_the_parcel
    plan = built(settings(profile: 'haussmann', building: { 'lod' => 1, 'features' => { 'cornice' => true } })).plan
    details = plan['nodes'].first['children'].find { |n| n['category'] == 'details' }
    cornice = details['children'].find { |n| n['category'] == 'cornice' }
    xs = cornice['primitive']['vertices'].map(&:first)
    assert_equal 0.0, xs.min
    assert_equal 12.0, xs.max
  end

  # --- Refus

  def test_hip_roof_is_refused_without_substitution
    value = settings(building: { 'roof' => { 'type' => 'hip' } })
    result = build(value, parcels_of(value).first)
    refute result.ok?
    found = result.errors.first
    assert_equal 'E_STREET_ROOF', found.code
    assert_equal '/building/roof/type', found.path
    assert_equal 'hip_in_row', found.params['reason']
  end

  def test_profile_is_required
    tree = { 'trace' => { 'points_m' => STREET, 'closed' => false } }
    value = Archgen::Composition.ensemble_intake.settings(tree).value
    result = build(value, parcels_of(value).first)
    assert_equal 'E_PROFILE_UNAVAILABLE', result.errors.first.code
    assert_equal '/parcels/left/0/0/profile', result.errors.first.path
  end

  def test_engine_refusals_are_located_on_the_parcel
    value = settings(points: [[0, 0], [6, 0]], building: { 'facade' => { 'margin_m' => 3 } })
    result = build(value, parcels_of(value).first)
    refute result.ok?
    assert(result.errors.all? { |d| d.path.start_with?('/parcels/left/0/0/') }, result.errors.map(&:to_h).inspect)
  end

  # --- Un bâtiment seul ne change pas

  def test_lone_building_keeps_its_own_roof
    config = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'toulousain' }, 'footprint' => { 'width_m' => 12.0, 'depth_m' => 9.0 } }, registry: registry, intake: intake).value
    lone = GeometryEngine.generate(config).value
    row = GeometryEngine.generate(config, row: { rear_bays: config.dig('facade', 'front_bays') }).value
    xs = roof_faces(lone).flatten(1).map(&:first)
    assert_operator xs.min, :<, 0.0, 'un bâtiment seul garde son débord latéral'
    refute_equal GeometryEngine.plan_digest(lone), GeometryEngine.plan_digest(row)
    assert_equal lone['openings'], row['openings'], 'mêmes baies si les travées arrière sont les mêmes'
  end

  # Les parcelles voisines peuvent avoir des largeurs différentes : la section ne dépend pas de W.
  def test_roof_line_does_not_depend_on_the_width
    PROFILES.each do |profile|
      narrow = built(settings(profile: profile, points: [[0, 0], [10, 0]], parcel: { 'target_width_m' => 10 }))
      wide = built(settings(profile: profile, points: [[0, 0], [16, 0]], parcel: { 'target_width_m' => 16 }))
      line = ->(plan) { roof_faces(plan).flatten(1).map { |p| p[1, 2] }.uniq.sort }
      assert_equal line.call(narrow.plan), line.call(wide.plan), profile
    end
  end
end
