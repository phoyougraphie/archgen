# frozen_string_literal: true

require_relative '../test_helper'

# U44 : menuiseries et vitrage (docs/DETAILS_CONTRACT.md, AG-064, ADR-45).
class GlazingTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def resolve(draft)
    ConfigResolver.resolve({ 'schema_version' => 1 }.merge(draft), registry: registry, intake: TestData.intake)
  end

  def config(draft)
    r = resolve(draft)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def plan(cfg)
    r = GeometryEngine.generate(cfg, materials: TestData.materials)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def neutral(blocks = {})
    base = TestData.intake.effective(TestData.building('rect-neutre-shell')).value
    BuildingConfig.new(Merge.leaves(base, { 'lod' => 1 }.merge(blocks)))
  end

  def glazed(blocks = {})
    neutral(Merge.leaves({ 'features' => { 'glazing' => true }, 'materials' => { 'glass' => 'glass' } }, blocks))
  end

  def parts(built, kind)
    built['definitions'].select { |id, _| id.start_with?("frame/#{kind}/") }
  end

  def box(node)
    node['primitive']['vertices'].transpose.map(&:minmax)
  end

  def materials(node)
    node['primitive']['faces'].map { |f| f['material'] }.uniq
  end

  # --- Format

  def test_new_revision_glazes_and_old_revision_stays_as_it_was
    now = config('profile' => { 'id' => 'haussmann' }).to_h
    assert_equal [2, true, 'glass'], [now['profile']['revision'], now['features']['glazing'], now['materials']['glass']]
    before = config('profile' => { 'id' => 'haussmann', 'revision' => 1 }).to_h
    refute before['features'].key?('glazing')
    refute before['materials'].key?('glass')
  end

  def test_unticked_glazing_is_not_written_and_ticked_takes_the_catalogue_glass
    off = config('profile' => { 'id' => 'haussmann' }, 'features' => { 'glazing' => false }).to_h
    refute off['features'].key?('glazing')
    refute off['materials'].key?('glass')
    on = config('profile' => { 'id' => 'haussmann', 'revision' => 1 }, 'features' => { 'glazing' => true }).to_h
    assert_equal 'glass', on['materials']['glass']
  end

  def test_inconsistent_stored_configs_are_refused
    base = TestData.intake.effective(TestData.building('rect-neutre-shell')).value
    {
      'glass_without_glazing' => Merge.leaves(base, 'materials' => { 'glass' => 'glass' }),
      'glass_required' => Merge.leaves(base, 'features' => { 'glazing' => true }),
      'glazing_false_written' => Merge.leaves(base, 'features' => { 'glazing' => false })
    }.each do |reason, data|
      found = ConstraintValidator.call(data, materials: TestData.materials).map { |d| d.params['reason'] }
      assert_includes found, reason
    end
    unknown = Merge.leaves(base, 'features' => { 'glazing' => true }, 'materials' => { 'glass' => 'crystal' })
    assert_includes ConstraintValidator.call(unknown, materials: TestData.materials).map { |d| d.params['reason'] }, 'unknown_material'
  end

  # --- Géométrie

  def test_window_pane_fills_the_frame_light_within_its_depth
    built = plan(glazed)
    windows = parts(built, 'window')
    refute_empty windows
    windows.each do |id, nodes|
      assert id.end_with?('/glazed/glass'), id
      pane = nodes.find { |n| n['id'] == 'pane' }
      width, height = id.split('/')[2].split('x').map { |v| v.to_f / Quant::SCALE }
      (x0, x1), (y0, y1), (z0, z1) = box(pane)
      assert_in_delta 0.04, x0, 1e-6
      assert_in_delta width - 0.04, x1, 1e-6
      assert_in_delta 0.04, z0, 1e-6
      assert_in_delta height - 0.04, z1, 1e-6
      assert_operator y0, :>, 0.0
      assert_operator y1, :<, 0.04
      assert_equal ['glass'], materials(pane)
      assert_equal 5, nodes.size, 'quatre barres et une vitre'
    end
  end

  def test_door_gets_a_solid_leaf_and_a_tall_door_a_glazed_transom
    built = plan(glazed)
    doors = parts(built, 'door')
    assert_equal 1, doors.size
    _, nodes = doors.first
    leaf = nodes.find { |n| n['id'] == 'leaf' }
    assert_equal ['painted_wood'], materials(leaf)
    (_, _), (y0, y1), (z0, _) = box(leaf)
    assert_in_delta 0.0, z0, 1e-6
    assert(y0.positive? && y1 < 0.04)

    tall = plan(glazed('facade' => { 'door_height_m' => 2.8 }))
    _, nodes = parts(tall, 'door').first
    assert_equal %w[bar/left bar/right bar/top leaf bar/transom pane], nodes.map { |n| n['id'] }
    assert_in_delta 2.20, box(nodes.find { |n| n['id'] == 'leaf' })[2][1], 1e-6
    assert_in_delta 2.24, box(nodes.find { |n| n['id'] == 'pane' })[2][0], 1e-6
  end

  def test_no_joinery_at_lod_zero_nor_without_the_option
    assert_empty plan(glazed('lod' => 0))['definitions']
    plain = plan(neutral)
    refute(plain['definitions'].keys.any? { |id| id.include?('/glazed/') })
    refute(plain['definitions'].values.flatten.any? { |n| %w[pane leaf].include?(n['id']) })
  end

  def test_plan_is_valid_and_counts_the_new_faces
    plain = plan(neutral)
    glass = plan(glazed)
    added = glass['metrics']['unique_face_count'] - plain['metrics']['unique_face_count']
    windows = parts(glass, 'window').size
    assert_equal (windows * 6) + 6, added, 'une vitre par définition de fenêtre, un vantail par porte'
  end

  def test_three_published_styles_glaze_in_both_modes_within_budget
    %w[haussmann toulousain brutalist].product(%w[shell structural]).each do |id, mode|
      built = plan(config('profile' => { 'id' => id }, 'mode' => mode, 'lod' => 1))
      assert(built['definitions'].keys.any? { |k| k.end_with?('/glazed/glass') }, "#{id} #{mode}")
      assert_operator built['metrics']['expanded_face_count'], :<, Limits::MAX_EXPANDED_FACES
    end
  end

  # --- Rue

  def test_a_street_of_the_new_revision_is_glazed_and_an_old_one_is_not
    run = lambda do |profile|
      tree = { 'trace' => { 'points_m' => [[0, 0], [36, 0]], 'closed' => false }, 'building' => { 'profile' => profile, 'lod' => 1 } }
      settings = Archgen::Composition.ensemble_intake.settings(tree).value
      r = EnsembleEngine.call(settings, registry: registry, intake: TestData.intake, materials: TestData.materials)
      assert r.ok?, r.errors.map(&:to_h).inspect
      r.value['definitions'].values.flat_map { |d| d['definitions'].keys }
    end
    assert(run.call('id' => 'haussmann').any? { |k| k.include?('/glazed/') })
    refute(run.call('id' => 'haussmann', 'revision' => 1).any? { |k| k.include?('/glazed/') })
  end
end
