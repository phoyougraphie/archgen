# frozen_string_literal: true

require_relative '../test_helper'

# U55 : pan de bois apparent (docs/PAN_DE_BOIS_CONTRACT.md, AG-083, ADR-48).
class TimberFrameTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def base
    TestData.intake.effective(TestData.building('rect-neutre-shell')).value
  end

  # Fixture neutre : 12 × 9 m, quatre niveaux de 3,2 m, quatre travées, fenêtres de 1,20 × 1,80 m.
  def building(blocks = {})
    BuildingConfig.new(Merge.leaves(base, Merge.leaves({ 'lod' => 1, 'features' => { 'timber_frame' => true }, 'materials' => { 'timber' => 'dark_wood' } }, blocks)))
  end

  def plan(cfg)
    r = GeometryEngine.generate(cfg, materials: TestData.materials)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def pieces(built)
    node = built['nodes'].first['children'].find { |n| n['id'] == 'details' }
    node ? node['children'].select { |n| n['category'] == 'timber' } : []
  end

  def box(node)
    node['primitive']['vertices'].transpose.map(&:minmax)
  end

  def test_resolution_and_refusals
    on = ConfigResolver.resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'brutalist' }, 'features' => { 'timber_frame' => true } },
                                registry: registry, intake: TestData.intake).value.to_h
    assert_equal 'dark_wood', on['materials']['timber']
    reasons = ->(data) { ConstraintValidator.call(data).map { |d| d.params['reason'] } }
    assert_includes reasons.call(Merge.leaves(base, 'features' => { 'timber_frame' => false })), 'timber_false_written'
    assert_includes reasons.call(Merge.leaves(base, 'features' => { 'timber_frame' => true })), 'timber_material_required'
    assert_includes reasons.call(Merge.leaves(base, 'materials' => { 'timber' => 'dark_wood' })), 'timber_material_without_timber'
    %w[surrounds shutters cornice cladding].each do |rival|
      data = Merge.leaves(base, 'features' => { 'timber_frame' => true, rival => true }, 'materials' => { 'timber' => 'dark_wood' })
      assert_includes reasons.call(data), "timber_with_#{rival}"
    end
  end

  def test_rails_posts_jambs_and_braces_on_the_upper_floors_only
    list = pieces(plan(building))
    refute_empty list
    list.each { |n| assert_operator box(n)[2][0], :>=, 3.2 - 1e-6, "#{n['id']} au-dessus du rez-de-chaussée" }
    front = list.select { |n| n['id'].start_with?('timber/front/') }
    rails = front.select { |n| n['id'].end_with?('/rail') }
    assert_equal 4, rails.size, 'trois pieds d’étage et le haut des murs'
    rails.each { |n| assert_equal [0.0, 12.0], box(n)[0].map { |v| v.round(6) } }
    jambs = front.select { |n| n['id'].include?('/jamb/') }
    assert_equal 3 * 4 * 2, jambs.size, 'deux huisseries par fenêtre'
    braces = front.select { |n| n['id'].include?('/brace/') }
    refute_empty braces
    assert_equal ['dark_wood'], list.flat_map { |n| n['primitive']['faces'].map { |f| f['material'] } }.uniq
    (_, _), (y0, y1), = box(rails.first)
    assert_equal [-0.04, 0.0], [y0, y1].map { |v| v.round(6) }
  end

  def test_no_piece_crosses_a_window
    built = plan(building)
    windows = built['openings'].select { |o| o['kind'] == 'window' && o['facade_id'] == 'front' }
    pieces(built).select { |n| n['id'].start_with?('timber/front/') }.each do |node|
      (x0, x1), _, (z0, z1) = box(node)
      windows.each do |w|
        inside = x0 < w['u_max_m'] - 1e-6 && x1 > w['u_min_m'] + 1e-6 && z0 < w['z_max_m'] - 1e-6 && z1 > w['z_min_m'] + 1e-6
        refute inside, "#{node['id']} devant #{w['id']}"
      end
    end
  end

  def test_sides_only_on_a_lone_building_and_both_modes
    assert(pieces(plan(building)).any? { |n| n['id'].start_with?('timber/left/') })
    %w[shell structural].each { |mode| refute_empty pieces(plan(building('mode' => mode))) }
    assert_empty pieces(plan(building('levels' => { 'count' => 1 })))
    tree = { 'seed' => 1, 'trace' => { 'points_m' => [[0, 0], [40, 0], [40, 30]], 'closed' => false },
             'building' => { 'profile' => { 'id' => 'brutalist' }, 'lod' => 1, 'features' => { 'timber_frame' => true } } }
    r = EnsembleEngine.call(Archgen::Composition.ensemble_intake.settings(tree).value, registry: registry, intake: TestData.intake, materials: TestData.materials)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value['definitions'].each_value do |built|
      ids = pieces(built).map { |n| n['id'] }
      refute(ids.any? { |i| i.start_with?('timber/left/', 'timber/right/') }, 'côtés mitoyens nus en rangée')
    end
  end
end
