# frozen_string_literal: true

require_relative '../test_helper'

# Le RBZ embarque une copie des données ; elle doit rester identique aux références.
class EmbeddedDataTest < Minitest::Test
  def test_schemas_match_reference
    Dir.glob(repo_path('schemas', '*.json')).each do |path|
      copy = repo_path('archgen', 'schemas', File.basename(path))
      assert File.exist?(copy), "copie absente : #{copy}"
      assert_equal File.binread(path), File.binread(copy), File.basename(path)
    end
  end

  def test_profiles_match_reference
    Dir.glob(repo_path('examples', 'profiles', '*.json')).each do |path|
      copy = repo_path('archgen', 'styles', 'profiles', File.basename(path))
      assert File.exist?(copy), "copie absente : #{copy}"
      assert_equal File.binread(path), File.binread(copy), File.basename(path)
    end
  end

  def test_materials_match_reference
    assert_equal File.binread(repo_path('examples', 'materials.v1.json')),
                 File.binread(repo_path('archgen', 'styles', 'materials', 'materials.v1.json'))
    assert_equal File.binread(repo_path('examples', 'site_materials.v1.json')),
                 File.binread(repo_path('archgen', 'styles', 'materials', 'site_materials.v1.json'))
  end

  def test_ensemble_rules_match_reference
    assert_equal File.binread(repo_path('examples', 'ensemble_rules.v1.json')), File.binread(repo_path('archgen', 'styles', 'ensemble_rules.v1.json'))
  end

  def test_road_catalogues_match_reference
    %w[road_bands.v1.json road_items.v1.json road_presets.v1.json road_materials.v1.json].each do |name|
      assert_equal File.binread(repo_path('examples', name)), File.binread(repo_path('archgen', 'styles', 'road', name)), name
    end
  end

  def test_core_never_reads_files_outside_the_composition_point
    Dir.glob(repo_path('archgen', '{core,geometry}', '**', '*.rb')).each do |path|
      source = File.read(path, encoding: 'UTF-8')
      refute_match(/\b(File|Dir|IO)\.(read|open|glob|binread)/, source, path)
      refute_match(/\brand\b|\bRandom\.|SecureRandom|Net::|Sketchup|Geom::/, source.gsub(/#.*$/, ''), path)
    end
  end
end
