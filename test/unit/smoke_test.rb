# frozen_string_literal: true

require_relative '../test_helper'

class SmokeTest < Minitest::Test
  def test_core_loads_without_sketchup
    refute defined?(::Sketchup), 'le noyau doit se charger sans SketchUp'
    assert_match(/\A\d+\.\d+\.\d+/, Archgen::VERSION)
    assert_equal '1', Archgen::ENGINE_VERSION
  end

  def test_ruby_baseline
    assert_operator Gem::Version.new(RUBY_VERSION), :>=, Gem::Version.new('3.2.0')
  end
end
