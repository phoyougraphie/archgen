# frozen_string_literal: true

require_relative '../test_helper'

# U01 : validation des entrées et parité avec les schémas JSON.
class IntakeTest < Minitest::Test
  include Archgen::Core

  def intake
    TestData.intake
  end

  def neutral
    TestData.building('rect-neutre-shell')
  end

  def assert_rejected(result, code, path)
    refute result.ok?
    assert(result.errors.any? { |d| d.code == code && d.path == path },
           "attendu #{code} #{path}, reçu #{result.errors.map(&:to_h)}")
  end

  # --- Fixtures conformes

  def test_all_building_fixtures_are_valid_effective_configs
    %w[rect-neutre-shell rect-neutre-structural haussmann-12x9 toulousain brutalist].each do |name|
      assert intake.effective(TestData.read('examples', 'buildings', "#{name}.json")).ok?, name
    end
  end

  def test_creation_draft_is_a_valid_draft
    assert intake.draft(TestData.read('examples', 'creation-draft.json')).ok?
  end

  def test_minimal_draft_only_needs_version
    assert intake.draft('{"schema_version":1}').ok?
    assert_rejected intake.draft('{}'), 'E_SCHEMA', '/schema_version'
  end

  # --- Syntaxe et bornes

  def test_duplicate_key_rejected_with_path
    result = intake.draft('{"schema_version":1,"footprint":{"width_m":5,"width_m":6}}')
    assert_rejected result, 'E_SCHEMA', '/footprint/width_m'
    assert_equal 'duplicate_key', result.errors.first.params['reason']
  end

  def test_non_finite_numbers_rejected
    assert_rejected intake.draft('{"schema_version":1,"seed":1e999}'), 'E_SCHEMA', '/seed'
    refute intake.draft('{"schema_version":1,"seed":NaN}').ok?
    refute intake.draft('{"schema_version":1,"seed":Infinity}').ok?
    assert_rejected intake.draft({ 'schema_version' => 1, 'footprint' => { 'width_m' => Float::NAN } }), 'E_SCHEMA', '/footprint/width_m'
  end

  def test_invalid_utf8_rejected
    result = intake.draft("{\"schema_version\":1,\"name\":\"\xFF\"}")
    assert_equal 'invalid_utf8', result.errors.first.params['reason']
  end

  def test_size_and_depth_limits
    huge = %({"schema_version":1,"name":"#{'a' * (64 * 1024)}"})
    assert_equal 'too_large', intake.draft(huge).errors.first.params['reason']
    exactly = "#{'[' * 12}#{']' * 12}"
    assert StrictJson.parse(exactly).ok?
    assert_equal 'too_deep', StrictJson.parse("[#{exactly}]").errors.first.params['reason']
  end

  def test_malformed_json_is_a_diagnostic_never_an_exception
    ['', '{', '{"a"}', '{"a":1,}', '[1,]', '01', '1.', '"\\x"', '"\\ud800"', "\"\u0001\"", '{} x', 'tru'].each do |bad|
      result = StrictJson.parse(bad)
      refute result.ok?, bad.inspect
      assert_equal 'E_SCHEMA', result.errors.first.code
    end
  end

  def test_string_escapes_and_surrogates
    assert_equal "é😀\n", StrictJson.parse('"\\u00e9\\ud83d\\ude00\\n"').value
  end

  # --- Version

  def test_future_version_has_its_own_code
    assert_rejected intake.draft('{"schema_version":2}'), 'E_VERSION', '/schema_version'
    assert_rejected intake.effective(neutral.merge('schema_version' => 99)), 'E_VERSION', '/schema_version'
  end

  def test_string_version_is_a_type_error
    assert_rejected intake.draft('{"schema_version":"1"}'), 'E_SCHEMA', '/schema_version'
  end

  # --- Clés et types

  def test_unknown_key_rejected_with_path
    assert_rejected intake.draft('{"schema_version":1,"facade":{"bogus":1}}'), 'E_SCHEMA', '/facade/bogus'
    assert_rejected intake.effective(neutral.merge('uuid' => 'x')), 'E_SCHEMA', '/uuid'
  end

  def test_null_and_wrong_types_rejected
    assert_rejected intake.draft('{"schema_version":1,"name":null}'), 'E_SCHEMA', '/name'
    assert_rejected intake.draft('{"schema_version":1,"seed":"42"}'), 'E_SCHEMA', '/seed'
    assert_rejected intake.draft('{"schema_version":1,"footprint":{"width_m":"12"}}'), 'E_SCHEMA', '/footprint/width_m'
    assert_rejected intake.draft('{"schema_version":1,"features":{"cornice":1}}'), 'E_SCHEMA', '/features/cornice'
    assert_rejected intake.draft('{"schema_version":1,"seed":true}'), 'E_SCHEMA', '/seed'
  end

  def test_future_mode_rejected_explicitly
    assert_rejected intake.draft('{"schema_version":1,"mode":"interior"}'), 'E_SCHEMA', '/mode'
  end

  def test_multiline_name_pattern_cannot_bypass_anchors
    assert_rejected intake.draft(%({"schema_version":1,"materials":{"wall":"concrete\\nx"}})), 'E_SCHEMA', '/materials/wall'
    assert_rejected intake.draft(%({"schema_version":1,"profile":{"id":"a\\nb"}})), 'E_SCHEMA', '/profile/id'
  end

  # --- Normalisation

  def test_mathematical_integer_is_accepted_and_normalized
    value = intake.draft('{"schema_version":1.0,"seed":42.0,"lod":1.0,"levels":{"count":4.0},"footprint":{"width_m":12}}').value
    assert_kind_of Integer, value['schema_version']
    assert_kind_of Integer, value['seed']
    assert_kind_of Integer, value['lod']
    assert_kind_of Integer, value['levels']['count']
    assert_kind_of Float, value['footprint']['width_m']
    assert_rejected intake.draft('{"schema_version":1,"seed":1.5}'), 'E_SCHEMA', '/seed'
  end

  def test_required_fields_of_effective_config
    partial = neutral.reject { |k, _| k == 'roof' }
    assert_rejected intake.effective(partial), 'E_SCHEMA', '/roof'
    partial = neutral.merge('roof' => neutral['roof'].reject { |k, _| k == 'inset_m' })
    assert_rejected intake.effective(partial), 'E_SCHEMA', '/roof/inset_m'
  end

  # --- Parité : chaque borne déclarée dans le schéma est appliquée par le validateur

  def test_schema_parity_on_every_numeric_bound
    walk_bounds(TestData.schemas['config'], []) do |path, schema|
      pointer = "/#{path.join('/')}"
      { 'minimum' => -1, 'maximum' => 1 }.each do |bound, delta|
        next unless schema[bound]

        value = schema[bound] + delta
        input = set_path(TestData.building('rect-neutre-shell'), path, value)
        assert_rejected intake.effective(input), 'E_SCHEMA', pointer
        accepted = set_path(TestData.building('rect-neutre-shell'), path, schema[bound])
        assert intake.effective(accepted).ok?, "#{pointer}=#{schema[bound]}"
      end
    end
  end

  def test_unsupported_schema_keyword_is_refused_at_load
    assert_raises(ArgumentError) { SchemaValidator.new('properties' => { 'a' => { '$ref' => '#' } }) }
  end

  def test_shipped_schemas_use_only_supported_keywords
    TestData.schemas.each_value { |schema| SchemaValidator.new(schema) }
  end

  private

  def walk_bounds(schema, path, &block)
    block.call(path, schema) if schema['minimum'] || schema['maximum']
    schema.fetch('properties', {}).each { |key, child| walk_bounds(child, path + [key], &block) }
  end

  def set_path(hash, path, value)
    copy = JSON.parse(JSON.generate(hash))
    path[0..-2].reduce(copy) { |h, k| h[k] }[path.last] = value
    copy
  end
end
