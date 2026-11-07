# frozen_string_literal: true

require_relative '../test_helper'

# U25 : arbres, lampadaires, potelets, poteaux, haies, barrières et glissières le long de la voie
# (docs/VOIRIE_CONTRACT.md, Éléments ; ADR-35).
class RoadItemsTest < Minitest::Test
  include Archgen::Core

  TOL = 1e-5

  def intake
    @intake ||= Archgen::Composition.road_intake
  end

  def preset(id)
    Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def tree(points, radii, profile, **rest)
    { 'trace' => { 'points_m' => points, 'radii_m' => radii }, 'profile' => profile }.merge(rest.transform_keys(&:to_s))
  end

  def build(input, **opts)
    settings = intake.settings(input)
    assert settings.ok?, settings.errors.map(&:to_h).inspect
    RoadEngine.call(settings.value, bands: Archgen::Composition.road_bands, items: Archgen::Composition.road_items, **opts)
  end

  def plan(input)
    result = build(input)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def instances(plan, prefix = '')
    group = plan['nodes'][0]['children'].find { |c| c['id'] == 'road/items' }
    (group ? group['children'] : []).select { |n| n['id'].start_with?(prefix) }
  end

  def origin(node)
    node['primitive']['matrix'].values_at(12, 13, 14)
  end

  def axis_x(node)
    node['primitive']['matrix'].values_at(0, 1)
  end

  # Un seul élément sur une bande : il est au milieu de la bande.
  def single(kind, variant: nil, height: nil, spacing: nil, band: 'sidewalk', width: 3, extra: {})
    item = { 'kind' => kind }
    item['variant'] = variant if variant
    item['height_m'] = height if height
    item['spacing_m'] = spacing if spacing
    { 'bands' => [{ 'type' => band, 'width_m' => width, 'items' => [item.merge(extra)] }, { 'type' => 'lane', 'width_m' => 3.5 }] }
  end

  # --- Droite : positions à la main

  def test_city_street_lamps_and_bollards_by_hand
    p = plan(tree([[0, 0], [100, 0]], [], preset('ville')))
    lamps = instances(p, 'item/0/')
    bollards = instances(p, 'item/4/')
    # Lampadaire au milieu du trottoir gauche (x = 1,25 dans la coupe, axe à 6,5) : y = 5,25, z = 0,14.
    assert_equal [[11.0, 5.25, 0.14], [33.0, 5.25, 0.14], [55.0, 5.25, 0.14], [77.0, 5.25, 0.14], [99.0, 5.25, 0.14]], lamps.map { |n| origin(n) }
    assert_equal 40, bollards.size
    assert_equal [1.25, -5.25, 0.14], origin(bollards.first)
    assert_equal [98.75, -5.25, 0.14], origin(bollards.last)
    assert_equal 45, p['metrics']['item_count']
  end

  def test_a_crosier_turns_toward_the_nearest_carriageway
    p = plan(tree([[0, 0], [100, 0]], [], preset('ville')))
    # Trottoir gauche : chaussée à droite, donc X local = −T et la crosse (+Y local) vise −y, la chaussée.
    assert_equal [-1.0, 0.0], axis_x(instances(p, 'item/0/').first)
    assert_equal [1.0, 0.0], axis_x(instances(p, 'item/4/').first)
  end

  def test_first_at_half_spacing_and_none_beyond_the_end
    p = plan(tree([[0, 0], [30, 0]], [], single('tree', spacing: 9)))
    xs = instances(p).map { |n| origin(n)[0] }
    assert_equal [4.5, 13.5, 22.5], xs
    assert_equal [], instances(plan(tree([[0, 0], [10, 0]], [], single('tree', spacing: 21))))
  end

  # --- Courbe : la pose suit la ligne de l'élément

  def test_spacing_is_measured_along_the_item_line_on_a_curve
    radius = 40.0
    p = plan(tree([[0, 0], [100, 0], [100, 100]], [radius], single('lamp', spacing: 7)))
    center = [100 - radius, radius]
    offset = (6.5 / 2) - 1.5 # milieu du trottoir, axe au milieu de 6,5 m : 1,75 m à gauche
    on_arc = instances(p).map { |n| origin(n) }.select { |x, y, _| x > center[0] + 1e-6 && y < center[1] - 1e-6 }
    refute_empty on_arc
    on_arc.each do |x, y, _|
      r = Math.hypot(x - center[0], y - center[1])
      assert_operator r, :<=, radius - offset + TOL
      assert_operator r, :>=, radius - offset - Limits::ROAD_CHORD_TOLERANCE_M
    end
    # Ligne intérieure : plus courte que l'axe de (π/2) × 1,75 m sur le quart de cercle.
    stations = Archgen::Geometry::RoadAxis.call([[0.0, 0.0], [100.0, 0.0], [100.0, 100.0]], [radius], left_m: 3.25, right_m: 3.25).value
    items = Archgen::Geometry::RoadItems
    length = items.polyline_length(items.offset_line(stations, offset))
    assert_in_delta p['metrics']['length_m'] - (Math::PI / 2 * offset), length, 0.01
    assert_equal items.spaced_positions(length, 7).size, instances(p).size
  end

  def test_items_follow_a_sharp_corner_and_stay_valid
    p = plan(tree([[0, 0], [60, 0], [60, 60]], [0], preset('boulevard')))
    assert_empty RoadPlanValidator.call(p)
    assert(instances(p).all? { |n| n['primitive']['matrix'].values_at(0, 1).map(&:abs).max <= 1.0 + 1e-12 })
  end

  # --- Définitions partagées et variation

  def test_one_definition_per_variant_and_height
    p = plan(tree([[0, 0], [300, 0]], [], preset('boulevard')))
    assert_equal %w[lamp/double/10000 tree/columnar/14000 tree/round/12000], p['definitions'].keys
    assert_equal p['metrics']['item_count'], instances(p).size
  end

  def test_height_variation_gives_three_heights_drawn_by_key
    profile = single('tree', height: 10, spacing: 5, band: 'plant', width: 3, extra: { 'height_variation' => 0.2 })
    a = plan(tree([[0, 0], [200, 0]], [], profile, seed: 7))
    b = plan(tree([[0, 0], [200, 0]], [], profile, seed: 7))
    c = plan(tree([[0, 0], [200, 0]], [], profile, seed: 8))
    assert_equal %w[tree/round/10000 tree/round/12000 tree/round/8000], a['definitions'].keys
    assert_equal RoadEngine.digest(a), RoadEngine.digest(b)
    refute_equal RoadEngine.digest(a), RoadEngine.digest(c)
    plain = plan(tree([[0, 0], [200, 0]], [], single('tree', height: 10, spacing: 5, band: 'plant', width: 3), seed: 7))
    assert_equal %w[tree/round/10000], plain['definitions'].keys
  end

  def test_each_definition_has_the_height_it_names
    p = plan(tree([[0, 0], [200, 0]], [], catalogue_profile))
    p['definitions'].each do |id, nodes|
      next if id.start_with?('post/')

      top = nodes.flat_map { |n| n['primitive']['vertices'] }.map { |v| v[2] }.max
      assert_in_delta id.split('/').last.to_i / 1000.0, top, 1e-6, id
    end
  end

  # --- Éléments continus

  def test_hedge_is_a_closed_solid_following_the_curve
    p = plan(tree([[0, 0], [100, 0], [100, 100]], [30], single('hedge', band: 'plant', width: 2)))
    linear = p['nodes'][0]['children'].find { |c| c['id'] == 'road/linear' }['children']
    assert_equal 1, linear.size
    assert_equal 'solid', linear[0]['primitive']['type']
    assert_empty RoadPlanValidator.call(p)
    zs = linear[0]['primitive']['vertices'].map { |v| v[2] }.uniq.sort
    assert_equal [0.05, 1.25], zs
  end

  def test_fences_and_guard_rails_have_posts_at_each_end_and_every_pitch
    fence = plan(tree([[0, 0], [21, 0]], [], single('fence', variant: 'fence', band: 'verge', width: 1)))
    assert_equal [0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 21.0], instances(fence).map { |n| origin(n)[0] }
    assert_equal 2, fence['nodes'][0]['children'].find { |c| c['id'] == 'road/linear' }['children'].size
    concrete = plan(tree([[0, 0], [21, 0]], [], single('guard', variant: 'concrete', band: 'median', width: 2)))
    assert_empty instances(concrete)
  end

  def test_every_catalogue_variant_on_a_curve_and_a_sharp_corner
    [[[0, 0], [150, 0], [150, 150]], [[0, 0], [150, 0], [150, 150]]].zip([[60], [0]]).each do |points, radii|
      p = plan(tree(points, radii, catalogue_profile))
      assert_empty RoadPlanValidator.call(p)
      kinds = p['definitions'].keys.map { |k| k.split('/')[0, 2].join('/') }.uniq
      %w[lamp/single lamp/double lamp/ped lamp/heritage lamp/high tree/round tree/columnar tree/wide tree/conifer bollard/bollard pole/pole].each do |k|
        assert_includes kinds, k
      end
    end
  end

  # --- Plafonds

  def test_item_limit_and_first_step_beyond
    input = tree([[0, 0], [100, 0]], [], preset('ville'))
    plan = build(input, limits: { items: 45 })
    assert plan.ok?
    refused = build(input, limits: { items: 44 })
    found = refused.errors.find { |d| d.params['reason'] == 'road_items' }
    assert found
    assert_equal 45, found.params['value']
  end

  def test_expanded_face_limit
    input = tree([[0, 0], [100, 0]], [], preset('ville'))
    total = plan(input)['metrics']['expanded_face_count']
    assert build(input, limits: { expanded: total }).ok?
    refute build(input, limits: { expanded: total - 1 }).ok?
  end

  def test_metrics_add_up
    p = plan(tree([[0, 0], [100, 0], [100, 100]], [40], catalogue_profile))
    m = p['metrics']
    definition_faces = p['definitions'].transform_values { |nodes| nodes.sum { |n| n['primitive']['faces'].size } }
    assert_equal m['surface_face_count'] + m['linear_face_count'] + definition_faces.values.sum, m['unique_face_count']
    assert_equal m['surface_face_count'] + m['linear_face_count'] + instances(p).sum { |n| definition_faces[n['primitive']['definition_id']] }, m['expanded_face_count']
  end

  private

  # Chaque variante de chaque élément, comme la scène « catalogue complet » de H19.
  def catalogue_profile
    lamps = %w[single double ped heritage high].zip([8, 10, 4, 5, 20]).map { |v, h| { 'kind' => 'lamp', 'variant' => v, 'height_m' => h } }
    trees = %w[round columnar wide conifer].zip([12, 14, 16, 11]).map { |v, h| { 'kind' => 'tree', 'variant' => v, 'height_m' => h, 'spacing_m' => 12 } }
    { 'bands' => [
      { 'type' => 'sidewalk', 'width_m' => 12, 'items' => lamps },
      { 'type' => 'parking', 'width_m' => 5.5, 'items' => [
        { 'kind' => 'hedge' }, { 'kind' => 'fence', 'variant' => 'fence' }, { 'kind' => 'fence', 'variant' => 'mesh' },
        { 'kind' => 'guard', 'variant' => 'guard' }, { 'kind' => 'guard', 'variant' => 'concrete' }
      ] },
      { 'type' => 'lane', 'width_m' => 3.5 }, { 'type' => 'lane', 'width_m' => 3.5 },
      { 'type' => 'sidewalk', 'width_m' => 12, 'items' => trees + [{ 'kind' => 'bollard' }, { 'kind' => 'pole' }] }
    ] }
  end
end
