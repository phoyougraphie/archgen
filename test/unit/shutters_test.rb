# frozen_string_literal: true

require_relative '../test_helper'

# U49 : volets (docs/VOLETS_LUCARNES_CONTRACT.md, AG-071, ADR-47).
class ShuttersTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def base
    TestData.intake.effective(TestData.building('rect-neutre-shell')).value
  end

  # Fixture neutre : 12 m, quatre travées de 2,7 m, fenêtres de 1,20 m, porte en travée 1.
  def building(blocks = {})
    BuildingConfig.new(Merge.leaves(base, Merge.leaves({ 'lod' => 1, 'features' => { 'shutters' => true }, 'materials' => { 'shutters' => 'painted_wood_blue' } }, blocks)))
  end

  def generate(cfg)
    GeometryEngine.generate(cfg, materials: TestData.materials)
  end

  def plan(cfg)
    r = generate(cfg)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def leaves(built)
    built['nodes'].first['children'].find { |n| n['id'] == 'details' }['children'].select { |n| n['category'] == 'shutter' }
  end

  def test_resolution_and_refusals
    on = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'toulousain' }, 'features' => { 'shutters' => true } },
                                registry: registry, intake: TestData.intake).value.to_h
    assert_equal 'painted_wood', on['materials']['shutters']
    off = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'toulousain' }, 'features' => { 'shutters' => false }, 'materials' => { 'shutters' => 'painted_wood_green' } },
                                 registry: registry, intake: TestData.intake).value.to_h
    refute off['features'].key?('shutters')
    refute off['materials'].key?('shutters')
    reasons = lambda { |data| ConstraintValidator.call(data, materials: TestData.materials).map { |d| d.params['reason'] } }
    assert_includes reasons.call(Merge.leaves(base, 'features' => { 'shutters' => true })), 'shutters_material_required'
    assert_includes reasons.call(Merge.leaves(base, 'materials' => { 'shutters' => 'painted_wood' })), 'shutters_material_without_shutters'
    assert_includes reasons.call(Merge.leaves(base, 'features' => { 'shutters' => false })), 'shutters_false_written'
  end

  def test_two_leaves_beside_each_window_against_the_wall
    built = plan(building)
    windows = built['openings'].select { |o| o['kind'] == 'window' }
    assert_equal windows.size * 2, leaves(built).size
    id, nodes = built['definitions'].find { |k, _| k.start_with?('shutter/') }
    assert_equal 'shutter/600000x1800000/painted_wood_blue', id
    assert_equal ['painted_wood_blue'], nodes.first['primitive']['faces'].map { |f| f['material'] }.uniq
    left = leaves(built).find { |n| n['id'] == 'shutter/front/1/0/0' }['primitive']['matrix']
    window = windows.find { |o| o['id'] == 'opening/front/1/0' }
    assert_in_delta window['u_min_m'] - 0.6, left[12], 1e-6, 'battant gauche collé au tableau'
    assert_in_delta(-0.04, left[13], 1e-6, 'à 1 cm devant le mur')
  end

  def test_nothing_on_doors_shopfronts_nor_at_lod_zero
    built = plan(building('ground_floor' => 'shop', 'shop' => { 'height_m' => 4.0 }))
    ids = leaves(built).map { |n| n['id'] }
    refute(ids.any? { |i| i.start_with?('shutter/front/0/') }, 'pas de volet au rez-de-chaussée commerçant')
    refute(plan(building('lod' => 0))['nodes'].first['children'].any? { |n| n['id'] == 'details' })
  end

  def test_surrounds_push_the_leaves_outward
    plain = leaves(plan(building)).find { |n| n['id'] == 'shutter/front/1/0/0' }['primitive']['matrix'][12]
    framed = leaves(plan(building('features' => { 'surrounds' => true }))).find { |n| n['id'] == 'shutter/front/1/0/0' }['primitive']['matrix'][12]
    assert_in_delta plain - 0.04, framed, 1e-6
  end

  def test_no_room_is_refused_with_the_window_id
    r = generate(building('facade' => { 'window_width_m' => 2.0 }))
    refute r.ok?
    found = r.errors.map { |d| [d.path, d.params['reason']] }.uniq
    assert_equal [['/features/shutters', 'shutters_no_room']], found
    assert(r.errors.all? { |d| d.params['id'].start_with?('opening/') })
  end

  def test_a_toulousain_street_takes_shutters
    tree = { 'trace' => { 'points_m' => [[0, 0], [40, 0]], 'closed' => false },
             'building' => { 'profile' => { 'id' => 'toulousain' }, 'lod' => 1, 'features' => { 'shutters' => true }, 'materials' => { 'shutters' => 'painted_wood_green' } } }
    settings = Archgen::Composition.ensemble_intake.settings(tree).value
    r = EnsembleEngine.call(settings, registry: registry, intake: TestData.intake, materials: TestData.materials)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value['definitions'].each_value { |built| refute_empty leaves(built) }
  end
end
