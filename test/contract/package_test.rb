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
    html = read_utf8('archgen', 'ui', 'diagnostic.html')
    refute_match(%r{https?://}, html)
    refute_match(/<script(?![^>]*\bsrc=)/, html)
    assert_match(/Content-Security-Policy/, html)
  end

  def test_core_manifest_never_touches_load_path
    Dir.glob(repo_path('archgen', '**', '*.rb')).each do |path|
      refute_match(/\$LOAD_PATH|\$:/, File.read(path, encoding: 'UTF-8'), path)
    end
  end
end
