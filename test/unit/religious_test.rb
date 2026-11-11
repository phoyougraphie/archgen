# frozen_string_literal: true

require_relative '../test_helper'

# U102 : édifices religieux (AG-144, ADR-69) : clochers, abside, transept ; chapelle, églises romane et
# gothique, cathédrale construites seules, dans les deux modes et aux deux niveaux de détail.
class ReligiousTest < Minitest::Test
  include Archgen::Core

  STYLES = %w[chapelle eglise_romane eglise_gothique cathedrale].freeze

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def build(draft)
    config = ConfigResolver.resolve({ 'schema_version' => 1, 'lod' => 1 }.merge(draft), registry: registry, intake: TestData.intake)
    return config unless config.ok?

    GeometryEngine.generate(config.value, materials: TestData.materials)
  end

  def nodes(list, out = [])
    list.each do |n|
      out << n
      nodes(n['children'], out)
    end
    out
  end

  def node(plan, id)
    nodes(plan['nodes']).find { |n| n['id'] == id }
  end

  def test_each_style_builds_in_both_modes_and_lods
    STYLES.product(%w[shell structural], [0, 1]).each do |id, mode, lod|
      built = build('profile' => { 'id' => id }, 'mode' => mode, 'lod' => lod)
      assert built.ok?, "#{id} #{mode} #{lod} : #{built.errors.map(&:to_h).first(3).inspect}"
      assert_operator built.value['metrics']['expanded_face_count'], :<, Limits::MAX_EXPANDED_FACES
    end
  end

  def test_porch_tower_rises_above_the_nave_with_a_spire
    plan = build('profile' => { 'id' => 'eglise_gothique' }).value
    spire = node(plan, 'tower/0/spire')['primitive']['vertices']
    assert_operator spire.map(&:last).max, :>, plan['metrics']['wall_top_z_m'] + 10
    body = node(plan, 'tower/0/body')['primitive']['vertices']
    assert_operator body.map { |v| v[1] }.min, :<, 0, 'la tour avance devant la façade'
    refute_nil node(plan, 'tower/0/portal')
  end

  def test_cathedral_has_twin_towers_transept_and_apse
    plan = build('profile' => { 'id' => 'cathedrale' }).value
    refute_nil node(plan, 'tower/0/body')
    refute_nil node(plan, 'tower/1/body')
    assert_nil node(plan, 'tower/0/spire'), 'tours à terrasse'
    left = nodes(plan['nodes']).select { |n| n['id'].start_with?('transept/left/wall') }.flat_map { |n| n.dig('primitive', 'vertices') || [] }
    right = nodes(plan['nodes']).select { |n| n['id'].start_with?('transept/right/wall') }.flat_map { |n| n.dig('primitive', 'vertices') || [] }
    assert_in_delta(-11.0, left.map(&:first).min, 1e-6)
    assert_in_delta 33.0, right.map(&:first).max, 1e-6
    apse = node(plan, 'apse/body')['primitive']['vertices']
    # Cinq pans : le point le plus reculé est à r · sin 72°.
    assert_in_delta 58 + (8.8 * Math.sin(2 * Math::PI / 5)), apse.map { |v| v[1] }.max, 0.01
  end

  def test_no_window_hidden_behind_transept_or_apse
    plan = build('profile' => { 'id' => 'eglise_gothique' }).value
    main = plan['openings'].reject { |o| o['id'].start_with?('transept/') }
    assert_empty(main.select { |o| o['facade_id'] == 'rear' }, 'le chevet est sous l’abside')
    depth = 34.0
    aw = 14 * 0.7
    ya = (depth * 0.62) - (aw / 2)
    right = main.select { |o| o['facade_id'] == 'right' }
    assert(right.none? { |o| o['u_max_m'] > ya && o['u_min_m'] < ya + aw })
    assert_empty(plan['openings'].select { |o| o['id'].start_with?('transept/') && o['facade_id'] == 'rear' })
  end

  def test_refusals
    reasons = ->(r) { r.errors.map { |d| d.params['reason'] } }
    assert_includes reasons.call(build('profile' => { 'id' => 'eglise_gothique' }, 'footprint' => { 'depth_m' => 14 })), 'transept_no_room'
    assert_includes reasons.call(build('profile' => { 'id' => 'chapelle' }, 'facade' => { 'front_bays' => 3, 'entry_bay' => 1 })), 'bell_tower_over_opening'
    tree = { 'seed' => 1, 'trace' => { 'points_m' => [[0, 0], [80, 0]], 'closed' => false }, 'building' => { 'profile' => { 'id' => 'eglise_gothique' }, 'lod' => 1 } }
    row = EnsembleEngine.call(Archgen::Composition.ensemble_intake.settings(tree).value, registry: registry, intake: TestData.intake, materials: TestData.materials)
    assert_includes reasons.call(row), 'transept_in_row'
  end
end
