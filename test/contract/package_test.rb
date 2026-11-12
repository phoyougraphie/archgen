# frozen_string_literal: true

require_relative '../test_helper'
require File.expand_path('../../scripts/package_rbz', __dir__)

# Contrôle Ruby du paquet. L'installation réelle relève de la recette hôte H01.
class PackageTest < Minitest::Test
  def central_names(zip)
    names = []
    offset = zip.index("PK\x01\x02".b)
    while offset && zip[offset, 4] == "PK\x01\x02".b
      name_size, extra, comment = zip[offset + 28, 6].unpack('vvv')
      names << zip[offset + 46, name_size]
      offset += 46 + name_size + extra + comment
    end
    names
  end

  def test_rbz_root_layout_excludes_tests_and_docs
    names = central_names(RbzPackager.build)
    assert_includes names, 'archgen.rb'
    assert_includes names, 'archgen/main.rb'
    assert(names.all? { |n| n == 'archgen.rb' || n.start_with?('archgen/') }, names.inspect)
  end

  def test_build_is_reproducible
    assert_equal RbzPackager.build, RbzPackager.build
  end

  def test_dialog_has_no_inline_script_or_remote_resource
    html = read_utf8('archgen', 'ui', 'panel.html')
    refute_match(%r{https?://}, html)
    refute_match(/<script(?![^>]*\bsrc=)/, html)
    assert_match(/Content-Security-Policy/, html)
  end

  def test_release_version_and_menu
    assert_match(/\A\d+\.\d+\.\d+(-dev)?\z/, Archgen::VERSION)
    # AG-145 : menu et barre d'outils partagent les commandes d'archgen/ui/commands.rb.
    assert_includes read_utf8('archgen', 'main.rb'), 'UI::Commands.install'
    commands = read_utf8('archgen', 'ui', 'commands.rb')
    ['Nouveau bâtiment', 'Tracer une rue', 'Tracer une voie', 'Tracer un réseau de voies', 'Modifier la sélection'].each { |label| assert_includes commands, "menu: '#{label}'" }
    assert_equal ['Le bâtiment sélectionné', 'L’ensemble sélectionné', 'La voie sélectionnée', 'Le réseau sélectionné', 'Afficher la barre d’outils ARCHGEN'],
                 commands.scan(/add_item\('([^']+)'\)/).flatten
    refute_includes central_names(RbzPackager.build).join(' '), 'diagnostic'
  end

  def test_release_is_documented
    assert_includes read_utf8('CHANGELOG.md'), "## #{Archgen::VERSION}"
    guide = read_utf8('docs', 'GUIDE.md')
    ['Windows', 'SketchUp 2026', 'Extensions', 'mètres'].each { |word| assert_includes guide, word }
  end

  def test_every_shipped_file_is_listed_and_no_host_probe_ships
    names = central_names(RbzPackager.build)
    assert_equal RbzPackager.entries, names
    assert(names.none? { |n| n.include?('test/') || n.end_with?('.py', '.md') }, names.inspect)
  end

  def test_core_manifest_never_touches_load_path
    Dir.glob(repo_path('archgen', '**', '*.rb')).each do |path|
      refute_match(/\$LOAD_PATH|\$:/, File.read(path, encoding: 'UTF-8'), path)
    end
  end
end
