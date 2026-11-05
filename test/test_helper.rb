# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require File.expand_path('../archgen/loader', __dir__)

Archgen::Loader.load_core
require_relative 'support/data'

module TestSupport
  REPO = File.expand_path('..', __dir__)

  def repo_path(*parts)
    File.join(REPO, *parts)
  end

  def read_utf8(*parts)
    File.read(repo_path(*parts), mode: 'rb', encoding: 'UTF-8')
  end

  def fixture_json(*parts)
    JSON.parse(read_utf8(*parts))
  end
end

Minitest::Test.include(TestSupport)
