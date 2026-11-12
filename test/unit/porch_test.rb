# frozen_string_literal: true

require_relative '../test_helper'

# U21 : accès à la cour par porche (docs/ENSEMBLE_CONTRACT.md, Accès à la cour).
class PorchTest < Minitest::Test
  include Archgen::Core

  SQUARE = [[0, 0], [40, 0], [40, 40], [0, 40]].freeze
  PROFILES = %w[haussmann toulousain].freeze

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def intake
    @intake ||= Archgen::Composition.intake
  end

  def materials
    Archgen::Composition.materials.fetch('materials')
  end

  def settings(points = SQUARE, profile: 'haussmann', access: {}, parcel: {}, building: {})
    tree = { 'trace' => { 'points_m' => points, 'closed' => true }, 'access' => access, 'parcel' => parcel,
             'building' => { 'profile' => { 'id' => profile } }.merge(building) }
    result = Archgen::Composition.ensemble_intake.settings(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def engine(value = settings)
    EnsembleEngine.call(value, registry: registry, intake: intake, materials: materials)
  end

  def plan(value = settings)
    result = engine(value)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def layout(value = settings)
    EnsembleEngine.layout_for(value, registry: registry).value
  end

  # Le plan du bâtiment qui porte le premier accès.
  def porch_plan(value = settings)
    built = plan(value)
    access = built['accesses'].first
    placed = built['parcels'].find { |p| p['id'] == access['id'] }
    built['definitions'].fetch(placed['definition_id'])
  end

  def openings(row, side, level = nil)
    row['openings'].select { |o| o['facade_id'] == side && (level.nil? || o['level_index'] == level) }
  end

  def node(row, id)
    walk = lambda do |list|
      list.each do |item|
        return item if item['id'] == id

        found = walk.call(item['children'])
        return found if found
      end
      nil
    end
    walk.call(row['nodes'])
  end

  def faces_of(primitive)
    primitive['faces'].map { |face| face['indices'].map { |i| primitive['vertices'][i] } }
  end

  def normal(points)
    points.each_with_index.reduce([0.0, 0.0, 0.0]) do |total, (p, i)|
      q = points[(i + 1) % points.size]
      [total[0] + ((p[1] - q[1]) * (p[2] + q[2])), total[1] + ((p[2] - q[2]) * (p[0] + q[0])), total[2] + ((p[0] - q[0]) * (p[1] + q[1]))]
    end
  end

  # --- Le catalogue

  def test_both_styles_can_now_close
    PROFILES.each do |profile|
      value = plan(settings(profile: profile))
      assert_equal 3, value['metrics']['access_count'], profile
      assert_equal 12, value['metrics']['parcel_count'], 'un porche garde sa parcelle'
      value['accesses'].each { |access| assert_equal 'porch', access['form'] }
    end
  end

  def test_brutalist_keeps_its_gap
    value = plan(settings(profile: 'brutalist'))
    assert_equal 9, value['metrics']['parcel_count']
    value['accesses'].each { |access| assert_equal 'gap', access['form'] }
  end

  def test_default_height_fits_every_style_with_a_porch
    assert_equal 2.7, settings.dig('access', 'height_m')
    PROFILES.each { |profile| assert engine(settings(profile: profile)).ok?, profile }
  end

  # --- Le passage

  def test_passage_runs_through_at_the_same_place
    row = porch_plan
    front = openings(row, 'front', 0).find { |o| o['kind'] == 'porch' }
    rear = openings(row, 'rear', 0).find { |o| o['kind'] == 'porch' }
    # Parcelle de 16 m, passage de 3,5 m centré.
    assert_equal 6.25, front['u_min_m']
    assert_equal 9.75, front['u_max_m']
    assert_equal 0.0, front['z_min_m']
    assert_equal 2.7, front['z_max_m']
    assert_equal [6.25, 9.75, 0.0, 2.7], [rear['u_min_m'], rear['u_max_m'], rear['z_min_m'], rear['z_max_m']]
  end

  def test_no_wall_cell_stays_in_the_passage
    row = porch_plan
    %w[wall/front wall/rear].each do |id|
      primitive = node(row, id)['primitive']
      faces_of(primitive).each do |points|
        centre = points.transpose.map { |values| values.sum / values.size }
        inside = centre[0] > 6.25 && centre[0] < 9.75 && centre[2] < 2.7
        refute inside, "#{id} : #{points.inspect}"
      end
    end
  end

  def test_floors_above_are_untouched
    row = porch_plan
    upper = openings(row, 'front', 1)
    assert_equal 5, upper.size, 'parcelle de 16 m au pas de 3 m'
    assert(upper.all? { |o| o['kind'] == 'window' })
    assert_equal row['openings'].count { |o| o['facade_id'] == 'front' && o['level_index'] == 2 }, upper.size
  end

  def test_covered_ground_floor_openings_are_gone
    row = porch_plan
    ground = openings(row, 'front', 0)
    ground.reject { |o| o['kind'] == 'porch' }.each do |o|
      assert_operator [6.25 - o['u_max_m'], o['u_min_m'] - 9.75].max, :>=, 0.10 - 1e-6, o.inspect
    end
    assert_operator ground.size, :<, openings(row, 'front', 1).size + 1
  end

  def test_the_passage_replaces_the_door
    row = porch_plan
    assert_empty(row['openings'].select { |o| o['kind'] == 'door' })
    other = plan['definitions'].values.find { |d| d['openings'].none? { |o| o['kind'] == 'porch' } && d['metrics']['width_m'] == 16.0 }
    assert_equal 1, other['openings'].count { |o| o['kind'] == 'door' } unless other.nil?
  end

  def test_walls_and_ceiling_close_the_passage_in_shell
    primitive = node(porch_plan, 'wall/passage')['primitive']
    faces = faces_of(primitive)
    assert_equal 3, faces.size
    left, right, ceiling = faces
    assert_operator normal(left)[0], :>, 0.0, 'la paroi regarde le passage'
    assert_operator normal(right)[0], :<, 0.0
    assert_operator normal(ceiling)[2], :<, 0.0, 'le plafond regarde vers le bas'
    assert_equal [0.0, 9.0], primitive['vertices'].map { |v| v[1] }.uniq.sort
    assert_equal [6.25, 9.75], primitive['vertices'].map(&:first).uniq.sort
  end

  def test_passage_stops_at_the_inner_faces_in_structural
    row = porch_plan(settings(building: { 'mode' => 'structural' }))
    wall = row['nodes'].first['children'].find { |n| n['category'] == 'walls' }
    assert_includes wall['children'].map { |n| n['id'] }, 'wall/passage'
    ys = node(row, 'wall/passage')['primitive']['vertices'].map { |v| v[1] }.uniq.sort
    assert_equal [0.24, 8.76], ys
  end

  def test_structural_jambs_close_the_wall_thickness
    row = porch_plan(settings(building: { 'mode' => 'structural' }))
    faces = faces_of(node(row, 'wall/front')['primitive'])
    jambs = faces.select { |points| points.map(&:first).uniq == [6.25] }
    refute_empty jambs, 'jambage dans l’épaisseur du mur'
    assert(jambs.all? { |points| points.map(&:last).max <= 2.7 })
    lintel = faces.select { |points| points.map(&:last).uniq == [2.7] && points.map(&:first).min >= 6.25 && points.map(&:first).max <= 9.75 }
    refute_empty lintel, 'linteau dans l’épaisseur du mur'
  end

  def test_no_threshold_in_the_passage
    row = porch_plan(settings(building: { 'mode' => 'structural' }))
    faces = faces_of(node(row, 'wall/front')['primitive'])
    assert(faces.none? { |points| points.map(&:last).uniq == [0.0] && points.map(&:first).min >= 6.25 - 1e-6 && points.map(&:first).max <= 9.75 + 1e-6 })
  end

  def test_slab_stays_above_the_ceiling
    row = porch_plan(settings(building: { 'mode' => 'structural' }))
    slab = node(row, 'slab/1')['primitive']['vertices'].map(&:last).min
    assert_operator slab, :>=, 2.7 + 0.10 - 1e-6
  end

  def test_no_frame_in_the_passage
    row = porch_plan(settings(building: { 'lod' => 1, 'features' => { 'surrounds' => true } }))
    details = row['nodes'].first['children'].find { |n| n['category'] == 'details' }
    ids = details['children'].map { |n| n['id'] }
    refute(ids.any? { |id| id.include?('/-1') || id.include?('porch') }, ids.inspect)
  end

  def test_passage_counts_in_the_faces
    with = porch_plan
    assert_equal 2, with['openings'].count { |o| o['kind'] == 'porch' }
    assert_empty PlanValidator.call(with, materials: materials)
  end

  # --- Limites

  def test_height_limit_and_first_excess
    # Haussmann : RDC de 3,2 m, dalle de 0,2 m, soit 2,9 m au plus.
    assert engine(settings(access: { 'height_m' => 2.9 })).ok?
    result = engine(settings(access: { 'height_m' => 2.901 }))
    refute result.ok?
    found = result.errors.first
    assert_equal 'E_STREET_ACCESS', found.code
    assert_equal 'porch_too_high', found.params['reason']
    assert_equal 2.9, found.params['limit']
    assert_match(%r{\A/parcels/ring/\d/1/access/height_m\z}, found.path)
  end

  def test_taller_ground_floor_allows_a_taller_passage
    assert engine(settings(access: { 'height_m' => 3.5 }, building: { 'levels' => { 'count' => 3, 'heights_m' => [4.0, 3.2, 3.2] } })).ok?
  end

  def test_single_level_building_has_no_slab_above
    result = engine(settings(access: { 'height_m' => 3.1 }, building: { 'levels' => { 'count' => 1, 'heights_m' => [] } }))
    assert result.ok?, result.errors.map(&:to_h).inspect
  end

  def test_width_limit
    # Mur de 0,24 m + 0,10 m de chaque côté : 16 − 2 × 0,34 = 15,32 m au plus, plafonné à 6 m par le réglage.
    narrow = settings(parcel: { 'target_width_m' => 6.0 }, access: { 'width_m' => 6.0 })
    result = EnsembleEngine.layout_for(narrow, registry: registry)
    refute result.ok?, 'une parcelle de 6 m ne peut pas céder 6 m'
    assert_equal 'access_no_room', result.errors.first.params['reason']
  end

  def test_room_problem_when_the_walls_would_not_fit
    row = { 'width_m' => 6.5, 'height_m' => 2.7 }
    footprint = Archgen::Geometry::FootprintSolver.call(width_m: 6.6, depth_m: 9.0)
    level = Archgen::Geometry::Level.new(index: 0, base_z_m: 0.0, top_z_m: 3.2, slab_bottom_z_m: nil)
    config = { 'structure' => { 'wall_m' => 0.24, 'slab_m' => 0.2 } }
    found = Archgen::Geometry::PorchSolver.call([], footprint: footprint, levels: [level], config: config, porch: row).errors.first
    assert_equal 'porch_no_room', found.params['reason']
    assert_equal '/access/width_m', found.path
  end

  # --- Reproductibilité et partage

  def test_same_input_same_digest
    assert_equal EnsembleEngine.digest(plan), EnsembleEngine.digest(plan)
  end

  def test_a_porch_never_shares_a_definition_with_a_plain_parcel
    value = plan
    porch_ids = value['accesses'].map { |a| a['id'] }
    porch_definitions = value['parcels'].select { |p| porch_ids.include?(p['id']) }.map { |p| p['definition_id'] }.uniq
    plain_definitions = value['parcels'].reject { |p| porch_ids.include?(p['id']) }.map { |p| p['definition_id'] }.uniq
    assert_equal 1, porch_definitions.size, 'les trois porches sont identiques'
    assert_empty porch_definitions & plain_definitions
  end

  def test_lone_buildings_and_streets_have_no_porch
    tree = { 'trace' => { 'points_m' => [[0, 0], [60, 0]], 'closed' => false }, 'building' => { 'profile' => { 'id' => 'haussmann' } } }
    street = plan(Archgen::Composition.ensemble_intake.settings(tree).value)
    assert_empty street['accesses']
    street['definitions'].each_value { |row| assert_nil node(row, 'wall/passage') }
  end

  def test_every_mode_and_lod_validates
    PROFILES.each do |profile|
      %w[shell structural].each do |mode|
        [0, 1].each do |lod|
          result = engine(settings(profile: profile, building: { 'mode' => mode, 'lod' => lod }))
          assert result.ok?, "#{profile} #{mode} LOD #{lod} : #{result.errors.map(&:to_h).inspect}"
        end
      end
    end
  end

  def test_layout_marks_the_porch_parcel
    value = layout
    access = value['accesses'].first
    parcel = value['parcels'].find { |p| p['id'] == access['id'] }
    assert_equal({ 'width_m' => 3.5, 'height_m' => 2.7 }, parcel['porch'])
    assert_nil(value['parcels'].find { |p| p['id'] != access['id'] && !value['accesses'].map { |a| a['id'] }.include?(p['id']) }['porch'])
  end
end
