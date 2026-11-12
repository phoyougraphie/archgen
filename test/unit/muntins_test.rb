# frozen_string_literal: true

require_relative '../test_helper'

# U48 : petits bois (docs/VOLETS_LUCARNES_CONTRACT.md, AG-070, ADR-47).
class MuntinsTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def base
    TestData.intake.effective(TestData.building('rect-neutre-shell')).value
  end

  # Fixture neutre : fenêtres de 1,20 × 1,80 m.
  def building(blocks = {})
    glazed = { 'lod' => 1, 'features' => { 'glazing' => true, 'muntins' => true }, 'materials' => { 'glass' => 'glass' }, 'facade' => { 'muntin_rows' => 3 } }
    BuildingConfig.new(Merge.leaves(base, Merge.leaves(glazed, blocks)))
  end

  def plan(cfg)
    r = GeometryEngine.generate(cfg, materials: TestData.materials)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def window_parts(built)
    built['definitions'].select { |id, _| id.start_with?('frame/window/') }
  end

  def box(node)
    node['primitive']['vertices'].transpose.map(&:minmax)
  end

  def reasons(data)
    ConstraintValidator.call(data).map { |d| d.params['reason'] }
  end

  def test_resolution_writes_rows_only_with_the_option
    on = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'haussmann' }, 'features' => { 'muntins' => true } },
                                registry: registry, intake: TestData.intake).value.to_h
    assert_equal [true, 3], [on['features']['muntins'], on['facade']['muntin_rows']]
    off = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'haussmann' }, 'features' => { 'muntins' => false }, 'facade' => { 'muntin_rows' => 4 } },
                                 registry: registry, intake: TestData.intake).value.to_h
    refute off['features'].key?('muntins')
    refute off['facade'].key?('muntin_rows')
  end

  def test_inconsistent_configs_are_refused
    assert_includes reasons(Merge.leaves(base, 'features' => { 'muntins' => true }, 'facade' => { 'muntin_rows' => 3 })), 'muntins_without_glazing'
    assert_includes reasons(Merge.leaves(base, 'features' => { 'muntins' => false })), 'muntins_false_written'
    assert_includes reasons(Merge.leaves(base, 'facade' => { 'muntin_rows' => 3 })), 'muntin_rows_without_muntins'
    glazed = Merge.leaves(base, 'features' => { 'glazing' => true, 'muntins' => true }, 'materials' => { 'glass' => 'glass' })
    assert_includes reasons(glazed), 'muntin_rows_required'
  end

  def test_a_window_gets_a_mullion_and_rows_minus_one_bars_per_leaf
    windows = window_parts(plan(building))
    refute_empty windows
    windows.each do |id, nodes|
      assert id.end_with?('/glazed/glass/muntins/3'), id
      bars = nodes.select { |n| n['id'].start_with?('muntin/') }
      assert_equal 1 + (2 * 2), bars.size, 'un montant, deux traverses par vantail'
      mullion = box(nodes.find { |n| n['id'] == 'muntin/mullion' })
      assert_in_delta 0.6, (mullion[0][0] + mullion[0][1]) / 2, 1e-6
      pane = box(nodes.find { |n| n['id'] == 'pane' })
      assert_operator mullion[1][1], :<, pane[1][0], 'devant la vitre, sans la toucher'
      bar = box(nodes.find { |n| n['id'] == 'muntin/0/1' })
      assert_in_delta 0.04 + ((1.8 - 0.08) / 3), (bar[2][0] + bar[2][1]) / 2, 1e-6
      assert_equal ['painted_wood'], bars.flat_map { |n| n['primitive']['faces'].map { |f| f['material'] } }.uniq
    end
  end

  def test_narrow_window_has_one_leaf_and_doors_have_none
    built = plan(building('facade' => { 'window_width_m' => 0.7, 'muntin_rows' => 2 }))
    _, nodes = window_parts(built).first
    bars = nodes.select { |n| n['id'].start_with?('muntin/') }.map { |n| n['id'] }
    assert_equal ['muntin/0/1'], bars
    built['definitions'].each do |id, list|
      next if id.start_with?('frame/window/')

      refute(list.any? { |n| n['id'].start_with?('muntin/') }, id)
    end
  end

  def test_one_row_means_a_mullion_only_and_lod_zero_nothing
    _, nodes = window_parts(plan(building('facade' => { 'muntin_rows' => 1 }))).first
    assert_equal ['muntin/mullion'], nodes.map { |n| n['id'] }.grep(/^muntin/)
    assert_empty plan(building('lod' => 0))['definitions']
  end

  def test_three_styles_take_muntins_in_both_modes
    %w[haussmann toulousain brutalist].product(%w[shell structural]).each do |id, mode|
      cfg = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => id }, 'mode' => mode, 'lod' => 1, 'features' => { 'muntins' => true } },
                                   registry: registry, intake: TestData.intake)
      assert cfg.ok?, cfg.errors.map(&:to_h).inspect
      assert(plan(cfg.value)['definitions'].keys.any? { |k| k.include?('/muntins/') }, "#{id} #{mode}")
    end
  end
end
