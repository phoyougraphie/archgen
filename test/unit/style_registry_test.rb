# frozen_string_literal: true

require_relative '../test_helper'

# U02 : hiérarchie, révisions, capacités, fusion et règles.
class StyleRegistryTest < Minitest::Test
  include Archgen::Core

  ALL_CAPS = StyleRegistry::KNOWN_CAPABILITIES

  def load(profiles = TestData.profiles, capabilities: ALL_CAPS)
    StyleRegistry.load(
      profiles,
      schema: TestData.schemas['profile'],
      config_validator: SchemaValidator.new(TestData.schemas['config']),
      capabilities: capabilities,
      materials: TestData.materials
    )
  end

  def registry(**kwargs)
    result = load(**kwargs)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def family(id: 'fam', revision: 1, parent: { 'id' => 'generic', 'revision' => 1 }, **extra)
    { 'schema_version' => 1, 'id' => id, 'revision' => revision, 'kind' => 'family', 'status' => 'internal',
      'parent' => parent, 'family_id' => id, 'label' => id, 'context' => { 'period' => '', 'regions' => [], 'typologies' => [] },
      'requires' => [], 'defaults' => {}, 'rules' => [] }.merge(extra.transform_keys(&:to_s))
  end

  def leaf(id: 'leaf', revision: 1, status: 'active', parent: { 'id' => 'fam', 'revision' => 1 }, family_id: 'fam', **extra)
    family(id: id, revision: revision, parent: parent).merge(
      'kind' => 'profile', 'status' => status, 'family_id' => family_id
    ).merge(extra.transform_keys(&:to_s))
  end

  def generic
    TestData.profiles.find { |p| p['id'] == 'generic' }
  end

  def assert_load_error(reason, profiles, **kwargs)
    result = load(profiles, **kwargs)
    refute result.ok?, 'chargement inattendu'
    assert(result.errors.any? { |d| d.params['reason'] == reason }, "attendu #{reason}, reçu #{result.errors.map(&:to_h)}")
  end

  # --- Chargement des fixtures

  def test_repository_profiles_load
    assert_equal %w[brutalist haussmann toulousain], registry.active_profiles.map(&:id)
  end

  def test_only_available_capabilities_are_published
    limited = registry(capabilities: %w[rectangle rect_opening flat])
    assert_equal %w[brutalist], limited.active_profiles.map(&:id)
    refused = limited.fetch('haussmann')
    refute refused.ok?
    assert_equal 'E_PROFILE_UNAVAILABLE', refused.errors.first.code
    assert_equal 'missing_capability', refused.errors.first.params['reason']
    assert_includes refused.errors.first.params['missing'], 'mansard'
  end

  # --- Héritage et fusion

  def test_requires_is_ordered_union_parent_then_child
    assert_equal %w[rectangle rect_opening flat mansard cornice balcony], registry.fetch('haussmann').value.requires
  end

  def test_defaults_merge_leaf_by_leaf_and_arrays_replace
    defaults = registry.fetch('toulousain').value.defaults
    assert_equal 3.1, defaults['levels']['height_m']
    assert_equal 3, defaults['levels']['count']
    assert_equal 0.6, defaults['facade']['margin_m'], 'hérité de generic'
    assert_equal 'brick_foraine', defaults['materials']['wall']
    assert_equal true, defaults['features']['surrounds']
    assert_equal false, defaults['features']['cornice'], 'hérité de generic'
  end

  def test_resolved_profile_is_frozen
    profile = registry.fetch('haussmann').value
    assert profile.frozen?
    assert profile.defaults['roof'].frozen?
    assert profile.rules.first.frozen?
  end

  def test_child_rule_replaces_inherited_by_id
    parent_rule = { 'id' => 'levels', 'kind' => 'soft', 'rule' => 'level_count', 'params' => { 'min' => 1, 'max' => 5 } }
    child_rule = parent_rule.merge('params' => { 'min' => 2, 'max' => 3 })
    set = [generic, family(rules: [parent_rule]), leaf(rules: [child_rule])]
    assert_equal [child_rule], registry_for(set).fetch('leaf').value.rules
  end

  def registry_for(set)
    result = load(set)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def test_hard_rule_cannot_be_weakened
    hard = { 'id' => 'levels', 'kind' => 'hard', 'rule' => 'level_count', 'params' => { 'min' => 1, 'max' => 5 } }
    weak = hard.merge('kind' => 'soft')
    assert_load_error 'hard_rule_changed', [generic, family(rules: [hard]), leaf(rules: [weak])]
  end

  # --- Hiérarchie invalide

  def test_cycle_refused
    a = family(id: 'a', parent: { 'id' => 'b', 'revision' => 1 })
    b = family(id: 'b', parent: { 'id' => 'a', 'revision' => 1 })
    assert_load_error 'cycle', [generic, a, b]
  end

  def test_missing_parent_revision_refused
    assert_load_error 'missing_parent', [generic, family(parent: { 'id' => 'generic', 'revision' => 9 })]
  end

  def test_duplicate_revision_refused
    assert_load_error 'duplicate_revision', [generic, family, family]
  end

  def test_incoherent_family_refused
    assert_load_error 'family_id_mismatch', [generic, family, leaf(family_id: 'autre')]
  end

  def test_profile_must_descend_from_family
    assert_load_error 'profile_parent_not_family', [generic, leaf(parent: { 'id' => 'generic', 'revision' => 1 }, family_id: 'generic')]
  end

  def test_illegal_status_refused
    assert_load_error 'illegal_status', [generic, family(status: 'active')]
  end

  def test_schema_violation_refused
    assert_load_error 'unknown_key', [generic.merge('bogus' => 1)]
  end

  # --- Règles

  def test_rule_params_must_be_exact
    bad = { 'id' => 'r', 'kind' => 'soft', 'rule' => 'level_count', 'params' => { 'min' => 1 } }
    assert_load_error 'rule_params', [generic, family(rules: [bad])]
  end

  def test_min_cannot_exceed_max
    bad = { 'id' => 'r', 'kind' => 'soft', 'rule' => 'level_count', 'params' => { 'min' => 5, 'max' => 1 } }
    assert_load_error 'min_greater_than_max', [generic, family(rules: [bad])]
  end

  def test_feature_chance_is_decorative_only
    bad = { 'id' => 'r', 'kind' => 'soft', 'rule' => 'feature_chance', 'params' => { 'feature' => 'cornice', 'probability' => 0.5 } }
    assert_load_error 'chance_must_be_decorative', [generic, family(rules: [bad])]
  end

  def test_only_one_chance_per_feature
    one = { 'id' => 'r1', 'kind' => 'decorative', 'rule' => 'feature_chance', 'params' => { 'feature' => 'cornice', 'probability' => 0.5 } }
    two = one.merge('id' => 'r2')
    assert_load_error 'duplicate_feature_chance', [generic, family(rules: [one, two])]
  end

  def test_unknown_capability_blocks_active_leaf
    assert_load_error 'unknown_capability', [generic, family, leaf(requires: ['teleport'])]
  end

  def test_active_leaf_defaults_must_validate
    assert_load_error 'unknown_material', [generic, family, leaf(defaults: { 'materials' => { 'wall' => 'unobtainium' } })]
    assert_load_error 'out_of_range', [generic, family, leaf(defaults: { 'roof' => { 'type' => 'gable' } })]
  end

  # --- Sélection

  def test_fetch_exact_or_current_revision
    set = [generic, family, leaf(revision: 1), leaf(revision: 2, defaults: { 'seed' => 7 })]
    reg = registry_for(set)
    assert_equal 2, reg.fetch('leaf').value.revision
    assert_equal 1, reg.fetch('leaf', revision: 1).value.revision
    assert_equal 'missing_revision', reg.fetch('leaf', revision: 3).errors.first.params['reason']
    assert_equal 'unknown_profile', reg.fetch('nope').errors.first.params['reason']
  end

  def test_planned_cannot_be_selected
    reg = registry_for([generic, family, leaf(status: 'planned')])
    assert_equal 'not_selectable', reg.fetch('leaf').errors.first.params['reason']
    assert_equal 'not_selectable', reg.fetch('leaf', allow_internal: true).errors.first.params['reason']
    assert_empty reg.active_profiles
  end

  def test_internal_only_under_test_bench
    reg = registry
    assert_equal 'not_selectable', reg.fetch('generic').errors.first.params['reason']
    assert reg.fetch('generic', allow_internal: true).ok?
    assert_equal 'not_selectable', reg.fetch('ordered_facade').errors.first.params['reason']
  end
end
