# frozen_string_literal: true

require_relative '../test_helper'

# U56, U57 : arcs et ornements classiques (docs/ARCS_ORNEMENTS_CONTRACT.md, AG-086, AG-087, ADR-48).
class OrnamentsTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def base
    TestData.intake.effective(TestData.building('rect-neutre-shell')).value
  end

  # Fixture neutre : 12 × 9 m, quatre travées, fenêtres de 1,20 × 1,80 m, porte de 1,00 × 2,20 m.
  def building(blocks = {})
    BuildingConfig.new(Merge.leaves(base, Merge.leaves({ 'lod' => 1 }, blocks)))
  end

  def generate(cfg)
    GeometryEngine.generate(cfg, materials: TestData.materials)
  end

  def plan(cfg)
    r = generate(cfg)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def pieces(built, category)
    node = built['nodes'].first['children'].find { |n| n['id'] == 'details' }
    node ? node['children'].select { |n| n['category'] == category } : []
  end

  def box(node)
    node['primitive']['vertices'].transpose.map(&:minmax)
  end

  # --- Arcs

  def test_flat_is_not_written
    cfg = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'toulousain' }, 'facade' => { 'arch' => 'flat' } },
                                 registry: registry, intake: TestData.intake)
    refute cfg.value.to_h['facade'].key?('arch')
  end

  def test_round_arch_fills_the_corners_above_the_springing
    built = plan(building('facade' => { 'arch' => 'round' }))
    window = built['openings'].find { |o| o['id'] == 'opening/front/1/0' }
    strips = pieces(built, 'arch').select { |n| n['id'].start_with?('arch/front/1/0/') }
    assert_equal 16, strips.size, 'huit bandes de chaque côté'
    spring = window['z_max_m'] - 0.6
    strips.each do |node|
      (x0, x1), (y0, y1), (z0, z1) = box(node)
      assert_operator x0, :>=, window['u_min_m'] - 1e-6
      assert_operator x1, :<=, window['u_max_m'] + 1e-6
      assert_operator z0, :>=, spring - 1e-6
      assert_in_delta window['z_max_m'], z1, 1e-6
      assert_equal [-0.02, 0.0], [y0, y1].map { |v| v.round(6) }
    end
    assert_equal ['lime_plaster'], strips.flat_map { |n| n['primitive']['faces'].map { |f| f['material'] } }.uniq
    assert(pieces(built, 'arch').any? { |n| n['id'].start_with?('arch/front/0/1/') }, 'la porte aussi')
  end

  def test_pointed_arch_springs_lower
    built = plan(building('facade' => { 'arch' => 'pointed' }))
    window = built['openings'].find { |o| o['id'] == 'opening/front/1/0' }
    low = pieces(built, 'arch').select { |n| n['id'].start_with?('arch/front/1/0/') }.map { |n| box(n)[2][0] }.min
    assert_in_delta window['z_max_m'] - (1.2 * Math.sqrt(3) / 2), low, 1e-3
  end

  def test_too_low_for_its_arch_is_refused_and_modes
    r = generate(building('facade' => { 'arch' => 'pointed', 'window_height_m' => 1.2 }))
    assert_equal [['/facade/window_height_m', 'arch_too_low']], r.errors.map { |d| [d.path, d.params['reason']] }.uniq
    %w[shell structural].each { |mode| refute_empty pieces(plan(building('mode' => mode, 'facade' => { 'arch' => 'round' })), 'arch') }
    assert_empty plan(building('lod' => 0, 'facade' => { 'arch' => 'round' }))['definitions']
  end

  # --- Ornements classiques

  def test_pilasters_plinth_and_pediment
    built = plan(building('features' => { 'classical' => true }))
    list = pieces(built, 'classical')
    pilasters = list.select { |n| n['id'].start_with?('classical/pilaster/') }
    assert_equal 2 + 3, pilasters.size, 'deux bouts et trois limites de travées'
    pilasters.each do |n|
      (x0, x1), (y0, _), (z0, z1) = box(n)
      assert_in_delta 0.30, x1 - x0, 1e-6
      assert_in_delta(-0.06, y0, 1e-6)
      assert_in_delta 0.80, z0, 1e-6
      assert_in_delta 12.8, z1, 1e-6
    end
    door = built['openings'].find { |o| o['kind'] == 'door' }
    plinth = list.select { |n| n['id'].start_with?('classical/plinth/') }
    assert_equal 2, plinth.size, 'coupé par la porte'
    plinth.each { |n| refute(box(n)[0][0] < door['u_max_m'] - 1e-6 && box(n)[0][1] > door['u_min_m'] + 1e-6) }
    pediment = box(list.find { |n| n['id'] == 'classical/pediment' })
    assert_in_delta door['z_max_m'] + 0.15, pediment[2][0], 1e-6
    assert_in_delta door['z_max_m'] + 0.65, pediment[2][1], 1e-6
  end

  def test_classical_refusals
    narrow = generate(building('features' => { 'classical' => true }, 'facade' => { 'window_width_m' => 2.5 }))
    assert_includes narrow.errors.map { |d| d.params['reason'] }, 'pilaster_no_room'
    reasons = ConstraintValidator.call(Merge.leaves(base, 'features' => { 'classical' => true, 'timber_frame' => true }, 'materials' => { 'timber' => 'dark_wood' }))
                                 .map { |d| d.params['reason'] }
    assert_includes reasons, 'classical_with_timber'
  end
end
