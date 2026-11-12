# frozen_string_literal: true

require_relative '../test_helper'

# U65 : stores bannes et pergolas (docs/VILLE_MIXTE_CONTRACT.md, AG-098).
class ShopFrontTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def base
    TestData.intake.effective(TestData.building('rect-neutre-shell')).value
  end

  # Fixture neutre en commerce : rez-de-chaussée de 4,0 m, porte en travée 1.
  def building(front, extra = {})
    blocks = { 'lod' => 1, 'ground_floor' => 'shop', 'shop' => { 'height_m' => 4.0 }, 'features' => { 'shop_front' => front } }
    blocks['materials'] = { 'awning' => 'canvas_green' } if front == 'awning'
    BuildingConfig.new(Merge.leaves(base, Merge.leaves(blocks, extra)))
  end

  def plan(cfg)
    r = GeometryEngine.generate(cfg, materials: TestData.materials)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def parts(built)
    built['nodes'].first['children'].find { |n| n['id'] == 'details' }['children'].select { |n| n['category'] == 'shop_front' }
  end

  def box(node)
    node['primitive']['vertices'].transpose.map(&:minmax)
  end

  def test_awning_over_each_shopfront_only
    built = plan(building('awning'))
    shopfronts = built['openings'].select { |o| o['kind'] == 'shopfront' }
    awnings = parts(built).select { |n| n['id'].start_with?('shop_front/awning/') }
    assert_equal shopfronts.size, awnings.size, 'pas de store devant la porte'
    (x0, x1), (y0, y1), (z0, z1) = box(awnings.first)
    assert_in_delta shopfronts.first['u_max_m'] - shopfronts.first['u_min_m'], x1 - x0, 1e-6
    assert_in_delta(-1.5, y0, 1e-6)
    assert_in_delta 0.0, y1, 1e-6
    assert_in_delta 3.5, z1, 1e-6, 'sous le bandeau'
    assert_operator z0, :<, 3.0
    assert_equal ['canvas_green'], parts(built).flat_map { |n| n['primitive']['faces'].map { |f| f['material'] } }.uniq
  end

  def test_pergola_stops_at_the_entrance
    built = plan(building('pergola'))
    door = built['openings'].find { |o| o['kind'] == 'door' }
    list = parts(built)
    refute_empty list.select { |n| n['id'].include?('/post/') }
    list.each do |n|
      (x0, x1), = box(n)
      refute(x0 < door['u_max_m'] + 0.3 - 1e-6 && x1 > door['u_min_m'] - 0.3 + 1e-6, "#{n['id']} devant la porte")
    end
    assert_in_delta(-2.4, list.map { |n| box(n)[1][0] }.min, 1e-6)
  end

  def test_resolution_and_refusals
    cfg = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'toulousain' }, 'ground_floor' => 'shop', 'features' => { 'shop_front' => 'awning' } },
                                 registry: registry, intake: TestData.intake).value.to_h
    assert_equal 'canvas_red', cfg['materials']['awning']
    none = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'toulousain' }, 'features' => { 'shop_front' => 'none' } },
                                  registry: registry, intake: TestData.intake).value.to_h
    refute none['features'].key?('shop_front')
    reasons = ConstraintValidator.call(Merge.leaves(base, 'features' => { 'shop_front' => 'pergola' })).map { |d| d.params['reason'] }
    assert_includes reasons, 'shop_front_without_shop'
  end
end
