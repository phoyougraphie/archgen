# frozen_string_literal: true

require_relative '../test_helper'

# U98 : bâtiments isolés sur leur terrain (AG-136, ADR-64). Chaque bâtiment est un bâtiment seul
# posé dans sa parcelle, à l'écart des limites latérales et en retrait de la rue ; deux bâtiments
# voisins ne se touchent jamais ; un îlot n'a pas d'accès.
class DetachedTest < Minitest::Test
  include Archgen::Core

  DETACHED = { 'side_gap_m' => 3.0, 'front_setback_m' => 5.0, 'building_depth_m' => 10.0 }.freeze

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def run_street(points, profile, detached: DETACHED, closed: false, width: 16.0, depth: 25.0)
    tree = { 'seed' => 3, 'trace' => { 'points_m' => points, 'closed' => closed },
             'parcel' => { 'target_width_m' => width, 'depth_m' => depth, 'bay_width_m' => 3.0, 'detached' => detached },
             'building' => { 'profile' => { 'id' => profile }, 'lod' => 1 } }
    settings = Archgen::Composition.ensemble_intake.settings(tree)
    assert settings.ok?, settings.errors.map(&:to_h).inspect
    EnsembleEngine.call(settings.value, registry: registry, intake: TestData.intake, materials: TestData.materials)
  end

  # Coins au sol de chaque bâtiment posé, en repère de la rue.
  def boxes(plan)
    plan['parcels'].map do |parcel|
      m = parcel['matrix']
      metrics = plan['definitions'][parcel['definition_id']]['metrics']
      w = metrics['width_m']
      d = metrics['depth_m']
      [[0, 0], [w, 0], [w, d], [0, d]].map { |x, y| [m[0] * x + m[4] * y + m[12], m[1] * x + m[5] * y + m[13]] }
    end
  end

  def apart?(a, b)
    # Axe séparateur parmi les arêtes des deux rectangles.
    [a, b].any? do |poly|
      poly.each_index.any? do |i|
        p = poly[i]
        q = poly[(i + 1) % 4]
        n = [q[1] - p[1], p[0] - q[0]]
        pa = a.map { |v| v[0] * n[0] + v[1] * n[1] }
        pb = b.map { |v| v[0] * n[0] + v[1] * n[1] }
        pa.max < pb.min - 1e-6 || pb.max < pa.min - 1e-6
      end
    end
  end

  def test_houses_stand_apart_set_back_from_the_street
    result = run_street([[0, 0], [64, 0]], 'maison_moderne')
    assert result.ok?, result.errors.map(&:to_h).first(3).inspect
    plan = result.value
    shapes = boxes(plan)
    assert_equal 4, shapes.size
    shapes.each do |shape|
      assert_in_delta 5.0, shape.map(&:last).min, 1e-6
      assert_in_delta 10.0, shape.map(&:last).max - shape.map(&:last).min, 1e-6
      assert_in_delta 10.0, shape.map(&:first).max - shape.map(&:first).min, 1e-6
    end
    shapes.each_cons(2) { |a, b| assert apart?(a, b), 'deux maisons se touchent' }
    assert_equal 1, plan['metrics']['definition_count'], 'maisons identiques partagées'
  end

  def test_each_new_style_stands_alone_on_a_corner_and_in_a_block
    %w[maison_moderne baule_villa baule_front_de_mer].each do |id|
      [[[0, 0], [60, 0], [60, 50]], [[0, 0], [70, 0], [70, 70], [0, 70]]].each do |points|
        closed = points.size == 4
        result = run_street(points, id, closed: closed, width: id == 'baule_front_de_mer' ? 30.0 : 16.0,
                                        detached: id == 'baule_front_de_mer' ? DETACHED.merge('building_depth_m' => 14.0) : DETACHED)
        assert result.ok?, "#{id} #{points.size} : #{result.errors.map(&:to_h).first(3).inspect}"
        assert_empty result.value['accesses']
        boxes(result.value).combination(2).each { |a, b| assert apart?(a, b), "#{id} #{points.size} : deux bâtiments se touchent" }
      end
    end
  end

  def test_refusals
    narrow = run_street([[0, 0], [64, 0]], 'maison_moderne', detached: DETACHED.merge('side_gap_m' => 7.0))
    assert_includes narrow.errors.map { |d| d.params['reason'] }, 'detached_too_narrow'
    deep = run_street([[0, 0], [64, 0]], 'maison_moderne', detached: DETACHED.merge('building_depth_m' => 25.0))
    assert_includes deep.errors.map { |d| d.params['reason'] }, 'detached_too_deep'
  end
end
