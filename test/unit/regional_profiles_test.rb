# frozen_string_literal: true

require_relative '../test_helper'

# U52 : profils régionaux de J13 (docs/STYLES_REGIONAUX_CONTRACT.md, AG-075 à AG-077, ADR-48).
# Chaque profil publié se crée par défaut en bâtiment seul, en rue droite, en rue à angle et en îlot.
class RegionalProfilesTest < Minitest::Test
  include Archgen::Core

  REGIONAL = %w[provencal_mas provencal_village breton_longere breton_bourg lyonnais bordelais_echoppe parisien_faubourien].freeze
  STREET = [[0, 0], [48, 0]].freeze
  CORNER = [[0, 0], [40, 0], [40, 30]].freeze
  BLOCK = [[0, 0], [40, 0], [40, 40], [0, 40]].freeze

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def resolve(draft)
    ConfigResolver.resolve({ 'schema_version' => 1 }.merge(draft), registry: registry, intake: TestData.intake)
  end

  def test_each_profile_is_active_in_its_family_with_local_materials
    REGIONAL.each do |id|
      profile = registry.fetch(id)
      assert profile.ok?, "#{id} : #{profile.errors.map(&:to_h).inspect}"
      assert_equal 'masonry_vernacular', profile.value.family_id
      materials = profile.value.defaults['materials'].values
      assert((materials - TestData.materials.keys).empty?, "#{id} : #{materials - TestData.materials.keys}")
      assert_includes registry.active_profiles.map(&:id), id
    end
  end

  def test_each_profile_builds_alone_in_both_modes_and_lods
    REGIONAL.product(%w[shell structural], [0, 1]).each do |id, mode, lod|
      config = resolve('profile' => { 'id' => id }, 'mode' => mode, 'lod' => lod)
      assert config.ok?, "#{id} #{mode} #{lod} : #{config.errors.map(&:to_h).inspect}"
      built = GeometryEngine.generate(config.value, materials: TestData.materials)
      assert built.ok?, "#{id} #{mode} #{lod} : #{built.errors.map(&:to_h).inspect}"
      assert_empty built.warnings.select(&:error?)
      assert_operator built.value['metrics']['expanded_face_count'], :<, Limits::MAX_EXPANDED_FACES
    end
  end

  def test_each_profile_builds_a_street_a_corner_and_a_block
    REGIONAL.product([STREET, CORNER, BLOCK]).each do |id, points|
      tree = { 'seed' => 1, 'trace' => { 'points_m' => points, 'closed' => points == BLOCK }, 'building' => { 'profile' => { 'id' => id }, 'lod' => 1 } }
      settings = Archgen::Composition.ensemble_intake.settings(tree)
      assert settings.ok?, settings.errors.map(&:to_h).inspect
      result = EnsembleEngine.call(settings.value, registry: registry, intake: TestData.intake, materials: TestData.materials)
      assert result.ok?, "#{id} #{points.size} : #{result.errors.map(&:to_h).first(3).inspect}"
    end
  end

  def test_rules_warn_out_of_range_and_refuse_in_strict_fidelity
    REGIONAL.each do |id|
      high = resolve('profile' => { 'id' => id }, 'levels' => { 'count' => 9 })
      assert high.ok?
      assert(high.diagnostics.any? { |d| d.path.start_with?('/levels') }, id)
      strict = resolve('profile' => { 'id' => id }, 'levels' => { 'count' => 9 }, 'fidelity' => 'strict')
      refute strict.ok?, id
    end
  end
end
