# frozen_string_literal: true

require_relative '../test_helper'

# U02 suite : résolution, fidélité et transition de style.
class ConfigResolverTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= StyleRegistry.load(
      TestData.profiles, schema: TestData.schemas['profile'],
      config_validator: SchemaValidator.new(TestData.schemas['config']),
      capabilities: StyleRegistry::KNOWN_CAPABILITIES, materials: TestData.materials
    ).value
  end

  def resolve(request, **kwargs)
    ConfigResolver.resolve(request, registry: registry, intake: TestData.intake, **kwargs)
  end

  def draft(**fields)
    { 'schema_version' => 1, 'profile' => { 'id' => 'haussmann' } }.merge(fields.transform_keys(&:to_s))
  end

  def normalized(name)
    TestData.intake.effective(TestData.building(name)).value
  end

  def without_name(hash)
    hash.reject { |k, _| k == 'name' }
  end

  # --- Création

  def test_creation_draft_resolves_to_documented_fixture
    result = resolve(TestData.read('examples', 'creation-draft.json'))
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal without_name(normalized('haussmann-12x9')), without_name(result.value.to_h)
    assert_equal 'Mon immeuble', result.value.to_h['name']
  end

  def test_four_levels_trigger_expected_historical_warning
    result = resolve(TestData.read('examples', 'creation-draft.json'))
    assert_equal ['W_HISTORICAL'], result.diagnostics.map(&:code)
    assert_equal '/levels/count', result.warnings.first.path
  end

  def test_default_name_and_trim
    assert_equal 'Bâtiment ARCHGEN', resolve(draft).value.to_h['name']
    assert_equal 'Tour', resolve(draft(name: '  Tour  ')).value.to_h['name']
  end

  def test_profile_required_at_creation
    result = resolve('{"schema_version":1}')
    assert_equal 'E_PROFILE_UNAVAILABLE', result.errors.first.code
  end

  def test_current_revision_is_recorded
    assert_equal({ 'id' => 'haussmann', 'revision' => 1 }, resolve(draft).value.to_h['profile'])
  end

  def test_internal_profile_only_on_test_bench
    neutral = { 'schema_version' => 1, 'profile' => { 'id' => 'generic' } }
    refute resolve(neutral).ok?
    assert resolve(neutral, allow_internal: true).ok?
  end

  def test_neutral_fixtures_resolve_from_generic
    %w[rect-neutre-shell rect-neutre-structural].each do |name|
      expected = normalized(name)
      result = resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'generic' }, 'name' => expected['name'], 'mode' => expected['mode'] }, allow_internal: true)
      assert_equal expected, result.value.to_h, name
    end
  end

  def test_active_fixtures_load_as_effective
    %w[haussmann-12x9 toulousain brutalist].each do |name|
      result = ConfigResolver.load_effective(TestData.read('examples', 'buildings', "#{name}.json"), registry: registry, intake: TestData.intake)
      assert result.ok?, "#{name}: #{result.errors.map(&:to_h)}"
    end
  end

  # --- Effectif : aucun défaut réappliqué

  def test_load_effective_requires_complete_data
    incomplete = normalized('toulousain').reject { |k, _| k == 'features' }
    result = ConfigResolver.load_effective(incomplete, registry: registry, intake: TestData.intake)
    assert_equal '/features', result.errors.first.path
  end

  def test_load_effective_refuses_missing_revision
    stored = normalized('toulousain').merge('profile' => { 'id' => 'toulousain', 'revision' => 9 })
    result = ConfigResolver.load_effective(stored, registry: registry, intake: TestData.intake)
    assert_equal 'missing_revision', result.errors.first.params['reason']
  end

  # --- Toit

  def test_roof_type_change_rebuilds_block_with_presets
    roof = resolve(draft(roof: { 'type' => 'hip' })).value.to_h['roof']
    assert_equal({ 'type' => 'hip', 'overhang_m' => 0.0, 'pitch_deg' => 25.0, 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0 }, roof)
    flat = resolve(draft(roof: { 'type' => 'flat' })).value.to_h['roof']
    assert_equal 0.0, flat['pitch_deg']
    assert_equal 0.0, flat['overhang_m']
  end

  def test_explicit_roof_fields_apply_after_presets
    roof = resolve(draft(roof: { 'type' => 'gable', 'pitch_deg' => 40, 'overhang_m' => 0.3 })).value.to_h['roof']
    assert_equal 40.0, roof['pitch_deg']
    assert_equal 0.3, roof['overhang_m']
    assert_equal 0.0, roof['inset_m']
  end

  def test_mansard_presets_from_another_type
    toulouse = { 'schema_version' => 1, 'profile' => { 'id' => 'toulousain' }, 'roof' => { 'type' => 'mansard' } }
    roof = resolve(toulouse.merge('fidelity' => 'creative')).value.to_h['roof']
    assert_equal [25.0, 65.0, 0.9, 0.0], roof.values_at('pitch_deg', 'lower_pitch_deg', 'inset_m', 'overhang_m')
  end

  def test_explicit_non_zero_inactive_roof_field_refused
    result = resolve(draft(roof: { 'type' => 'flat', 'pitch_deg' => 10 }))
    assert_equal ['E_ROOF_GEOMETRY', '/roof/pitch_deg'], [result.errors.first.code, result.errors.first.path]
    assert resolve(draft(roof: { 'type' => 'flat', 'pitch_deg' => 0 })).ok?
  end

  # --- Fidélité : les modes changent la sévérité, jamais une contrainte hard

  def test_historical_severity_by_fidelity
    wide = { 'levels' => { 'count' => 4 } }
    assert_equal 'E_HISTORICAL', resolve(draft(fidelity: 'strict', **wide.transform_keys(&:to_sym))).errors.first.code
    assert_equal ['W_HISTORICAL'], resolve(draft(fidelity: 'plausible', **wide.transform_keys(&:to_sym))).diagnostics.map(&:code)
    assert_empty resolve(draft(fidelity: 'creative', **wide.transform_keys(&:to_sym))).diagnostics
  end

  def test_hard_constraint_refused_in_all_fidelities
    %w[strict plausible creative].each do |fidelity|
      result = resolve(draft(fidelity: fidelity, facade: { 'entry_bay' => 9 }))
      assert_equal '/facade/entry_bay', result.errors.first.path, fidelity
    end
  end

  def test_severity_table_matches_contract
    expected = { 'hard' => %i[error error error], 'historical' => %i[error warning ignore], 'soft' => %i[warning warning ignore] }
    expected.each do |kind, levels|
      assert_equal levels, %w[strict plausible creative].map { |f| FidelityRules.severity(kind, f) }, kind
    end
  end

  def test_each_rule_kind_reports_a_localized_path
    rules = {
      'window_ratio' => { 'facade' => { 'window_height_m' => 1.0, 'window_width_m' => 1.2 } },
      'roof_type' => { 'roof' => { 'type' => 'flat' } }
    }
    paths = { 'window_ratio' => '/facade/window_height_m', 'roof_type' => '/roof/type' }
    rules.each do |rule, fields|
      result = resolve(draft(**fields.transform_keys(&:to_sym)))
      assert(result.warnings.any? { |d| d.path == paths[rule] && d.params['rule'] == rule }, rule)
    end
  end

  def test_material_allowed_rule
    profile = StyleProfile.new(rules: [{ 'id' => 'm', 'kind' => 'soft', 'rule' => 'material_allowed', 'params' => { 'role' => 'wall', 'values' => ['concrete'] } }])
    data = { 'fidelity' => 'plausible', 'materials' => { 'wall' => 'limestone' } }
    assert_equal '/materials/wall', FidelityRules.call(data, profile).first.path
  end

  def test_feature_chance_uses_seed_and_is_overridable
    chance = ->(p) { { 'id' => 'c', 'kind' => 'decorative', 'rule' => 'feature_chance', 'params' => { 'feature' => 'surrounds', 'probability' => p } } }
    profile = StyleProfile.new(rules: [chance.call(1.0)], defaults: {})
    values = { 'seed' => 42, 'features' => { 'surrounds' => false } }
    on = ConfigResolver.send(:with_chances, values, profile, 42)
    assert_equal true, on['features']['surrounds']
    off = ConfigResolver.send(:with_chances, values, StyleProfile.new(rules: [chance.call(0.0)]), 42)
    assert_equal false, off['features']['surrounds']
    draw = DeterministicRandom.unit(42, 'feature/surrounds')
    near = ConfigResolver.send(:with_chances, values, StyleProfile.new(rules: [chance.call(draw)]), 42)
    assert_equal false, near['features']['surrounds'], 'comparaison stricte : unit < probabilité'
  end

  # --- Édition

  def base
    @base ||= resolve(draft(name: 'A', footprint: { 'width_m' => 14 }, levels: { 'count' => 5 }, seed: 9)).value
  end

  def test_edit_same_profile_applies_only_sent_fields
    result = resolve({ 'schema_version' => 1, 'footprint' => { 'depth_m' => 11 } }, base: base)
    data = result.value.to_h
    assert_equal 14.0, data['footprint']['width_m']
    assert_equal 11.0, data['footprint']['depth_m']
    assert_equal 'A', data['name']
    assert_equal 9, data['seed']
  end

  def test_edit_profile_change_requires_exact_revision
    result = resolve({ 'schema_version' => 1, 'profile' => { 'id' => 'toulousain' } }, base: base)
    assert_equal '/profile/revision', result.errors.first.path
  end

  def test_style_change_keeps_dimensions_and_replaces_style_blocks
    change = { 'schema_version' => 1, 'profile' => { 'id' => 'toulousain', 'revision' => 1 } }
    data = resolve(change, base: base).value.to_h
    assert_equal({ 'id' => 'toulousain', 'revision' => 1 }, data['profile'])
    assert_equal 14.0, data['footprint']['width_m']
    assert_equal 5, data['levels']['count']
    assert_equal 9, data['seed']
    assert_equal 'A', data['name']
    assert_equal 'gable', data['roof']['type']
    assert_equal 'brick_foraine', data['materials']['wall']
    assert_equal true, data['features']['surrounds']
    assert_equal false, data['features']['balcony']
  end

  def test_style_change_applies_explicit_overrides_last
    change = { 'schema_version' => 1, 'profile' => { 'id' => 'brutalist', 'revision' => 1 }, 'materials' => { 'frames' => 'painted_wood' } }
    data = resolve(change, base: base).value.to_h
    assert_equal 'concrete', data['materials']['wall']
    assert_equal 'painted_wood', data['materials']['frames']
  end

  def test_count_change_with_explicit_heights_requires_adjustment
    edited = resolve({ 'schema_version' => 1, 'levels' => { 'heights_m' => [4, 3, 3, 3, 3] } }, base: base).value
    refused = resolve({ 'schema_version' => 1, 'levels' => { 'count' => 6 } }, base: edited)
    assert_equal '/levels/heights_m', refused.errors.first.path
    cleared = resolve({ 'schema_version' => 1, 'levels' => { 'count' => 6, 'heights_m' => [] } }, base: edited)
    assert cleared.ok?
  end

  def test_rejected_edit_leaves_base_untouched
    before = base.to_h
    resolve({ 'schema_version' => 1, 'facade' => { 'entry_bay' => 11 } }, base: base)
    assert_equal before, base.to_h
  end
end
