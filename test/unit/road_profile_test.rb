# frozen_string_literal: true

require_relative '../test_helper'

# U23 : coupe de voirie, catalogues fermés et préréglages (docs/VOIRIE_CONTRACT.md).
class RoadProfileTest < Minitest::Test
  include Archgen::Core

  BAND_TYPES = %w[lane hard edge parking tram_lane tram rail cycle sidewalk path track median verge plant ditch bank].freeze
  ITEM_KINDS = %w[tree lamp bollard pole hedge fence guard].freeze
  PRESETS = %w[autoroute nationale campagne rural boulevard ville mixte tram fer verte pieton].freeze
  STEP = 0.001

  def intake
    @intake ||= Archgen::Composition.road_profile_intake
  end

  def bands
    intake.bands
  end

  def items
    intake.items
  end

  def profile(*bands_list)
    { 'road_profile_version' => 1, 'bands' => bands_list }
  end

  def band(type, width = nil, items = nil)
    out = { 'type' => type, 'width_m' => width || bands.fetch(type)['default_width_m'] }
    out['items'] = items if items
    out
  end

  def accepted(tree)
    result = intake.profile(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result
  end

  def assert_refused(tree, code, path, reason = nil)
    result = intake.profile(tree)
    refute result.ok?, "attendu un refus sur #{path}"
    assert_nil result.value
    found = result.errors.find { |d| d.code == code && d.path == path && (reason.nil? || d.params['reason'] == reason) }
    assert found, result.errors.map(&:to_h).inspect
    found
  end

  # --- Catalogues

  def test_band_catalogue_is_the_closed_list_of_the_contract
    assert_equal BAND_TYPES.sort, bands.keys.sort
    bands.each do |type, entry|
      assert entry['min_width_m'].positive?, type
      assert entry['default_width_m'].between?(entry['min_width_m'], entry['max_width_m']), type
      assert_includes %w[flat ditch bank], entry['shape'], type
      assert_includes %w[none embedded platform ballast], entry['rails'], type
      assert_includes [true, false], entry['accepts_items'], type
    end
    assert_in_delta 1.435, Archgen::Composition.road_bands['rail_gauge_m'], 1e-12
  end

  def test_item_catalogue_is_the_closed_list_of_the_contract
    assert_equal ITEM_KINDS.sort, items.keys.sort
    items.each do |kind, entry|
      assert entry['variants'].key?(entry['default_variant']), kind
      assert entry['default_height_m'].between?(entry['min_height_m'], entry['max_height_m']), kind
      assert_includes %w[spaced continuous], entry['repeat'], kind
      assert entry['default_spacing_m'] >= entry['min_spacing_m'], kind if entry['repeat'] == 'spaced'
    end
    assert_equal %w[tree], items.select { |_, e| e['height_variation'] }.keys
  end

  # --- Préréglages

  def test_the_eleven_presets_are_valid_without_warning
    presets = Archgen::Composition.road_presets.fetch('presets')
    assert_equal PRESETS, presets.map { |p| p['id'] }
    presets.each do |preset|
      result = accepted(preset.fetch('profile'))
      assert_empty result.diagnostics, preset['id']
      assert result.value.frozen?
      assert_equal preset.dig('profile', 'name'), result.value['name']
    end
  end

  def test_presets_cover_every_band_type
    used = Archgen::Composition.road_presets.fetch('presets').flat_map { |p| p.dig('profile', 'bands').map { |b| b['type'] } }.uniq
    assert_equal [], BAND_TYPES - used
  end

  # --- Limites et premier dépassement

  def test_each_band_type_accepts_its_limits_and_refuses_the_first_step_beyond
    BAND_TYPES.each do |type|
      entry = bands.fetch(type)
      accepted(profile(band(type, entry['min_width_m'])))
      accepted(profile(band(type, entry['max_width_m'])))
      low = assert_refused(profile(band(type, entry['min_width_m'] - STEP)), 'E_ROAD_BAND', '/bands/0/width_m', 'width_range')
      assert_equal entry['min_width_m'], low.params['min']
      assert_refused(profile(band(type, entry['max_width_m'] + STEP)), 'E_ROAD_BAND', '/bands/0/width_m', 'width_range')
    end
  end

  def test_each_item_kind_accepts_its_height_limits_and_refuses_beyond
    ITEM_KINDS.each do |kind|
      entry = items.fetch(kind)
      [entry['min_height_m'], entry['max_height_m']].each do |h|
        accepted(profile(band('plant', 2, [{ 'kind' => kind, 'height_m' => h }])))
      end
      [entry['min_height_m'] - STEP, entry['max_height_m'] + STEP].each do |h|
        assert_refused(profile(band('plant', 2, [{ 'kind' => kind, 'height_m' => h }])), 'E_ROAD_ITEM', '/bands/0/items/0/height_m', 'height_range')
      end
    end
  end

  def test_spacing_has_a_minimum_and_belongs_only_to_repeated_items
    accepted(profile(band('sidewalk', 3, [{ 'kind' => 'tree', 'spacing_m' => 1 }])))
    assert_refused(profile(band('sidewalk', 3, [{ 'kind' => 'tree', 'spacing_m' => 1 - STEP }])), 'E_ROAD_ITEM', '/bands/0/items/0/spacing_m', 'spacing_range')
    assert_refused(profile(band('verge', 1, [{ 'kind' => 'hedge', 'spacing_m' => 0 }])), 'E_ROAD_ITEM', '/bands/0/items/0/spacing_m', 'continuous_item')
  end

  def test_height_variation_is_for_trees_and_stays_within_the_height_range
    accepted(profile(band('plant', 3, [{ 'kind' => 'tree', 'height_m' => 10, 'height_variation' => 0.3 }])))
    assert_refused(profile(band('plant', 3, [{ 'kind' => 'lamp', 'height_variation' => 0.1 }])), 'E_ROAD_ITEM', '/bands/0/items/0/height_variation', 'variation_unavailable')
    assert_refused(profile(band('plant', 3, [{ 'kind' => 'tree', 'height_m' => 25, 'height_variation' => 0.3 }])), 'E_ROAD_ITEM', '/bands/0/items/0/height_variation', 'variation_range')
    assert_refused(profile(band('plant', 3, [{ 'kind' => 'tree', 'height_variation' => 0.31 }])), 'E_SCHEMA', '/bands/0/items/0/height_variation', 'maximum')
  end

  # --- Refus du registre fermé

  def test_unknown_band_type_item_kind_and_variant_are_refused
    assert_refused(profile(band('lane'), { 'type' => 'canal', 'width_m' => 3 }), 'E_ROAD_BAND', '/bands/1/type', 'unknown_type')
    assert_refused(profile(band('sidewalk', 3, [{ 'kind' => 'bench' }])), 'E_ROAD_ITEM', '/bands/0/items/0/kind', 'unknown_kind')
    found = assert_refused(profile(band('sidewalk', 3, [{ 'kind' => 'lamp', 'variant' => 'neon' }])), 'E_ROAD_ITEM', '/bands/0/items/0/variant', 'unknown_variant')
    assert_includes found.params['allowed'], 'heritage'
  end

  def test_nothing_stands_in_a_ditch
    assert_refused(profile(band('ditch', 1.5, [{ 'kind' => 'tree' }])), 'E_ROAD_ITEM', '/bands/0/items/0', 'band_accepts_no_items')
  end

  def test_schema_refusals
    assert_refused(profile(band('lane').merge('colour' => 'red')), 'E_SCHEMA', '/bands/0/colour', 'unknown_key')
    assert_refused(profile, 'E_SCHEMA', '/bands', 'min_items')
    assert_refused(profile(*Array.new(33) { band('lane') }), 'E_SCHEMA', '/bands', 'max_items')
    assert_refused(profile(band('plant', 3, Array.new(7) { { 'kind' => 'tree' } })), 'E_SCHEMA', '/bands/0/items', 'max_items')
    assert_refused(profile(band('lane')).merge('road_profile_version' => 2), 'E_VERSION', '/road_profile_version', 'unsupported_road_profile')
    assert_refused(profile(band('lane')).merge('name' => ''), 'E_SCHEMA', '/name', 'min_length')
    assert_refused({ 'bands' => [{ 'type' => 'lane' }] }, 'E_SCHEMA', '/bands/0/width_m', 'required')
    accepted(profile(*Array.new(32) { band('lane') }))
  end

  def test_errors_of_several_bands_are_all_reported_in_path_order
    result = intake.profile(profile(band('lane', 1), band('sidewalk', 3, [{ 'kind' => 'tree', 'height_m' => 50 }]), band('cycle', 9)))
    assert_equal %w[/bands/0/width_m /bands/1/items/0/height_m /bands/2/width_m], result.errors.map(&:path)
  end

  def test_strict_json_text_is_accepted_and_duplicates_refused
    accepted('{"bands":[{"type":"lane","width_m":3.5}]}')
    result = intake.profile('{"bands":[{"type":"lane","width_m":3.5,"width_m":3}]}')
    refute result.ok?
    assert_equal 'E_SCHEMA', result.errors.first.code
  end

  # --- Valeurs effectives

  def test_effective_profile_fills_item_defaults_and_keeps_order
    value = accepted(profile(band('sidewalk', 3, [{ 'kind' => 'tree' }, { 'kind' => 'hedge' }]), band('lane', 3))).value
    assert_equal(%w[sidewalk lane], value['bands'].map { |b| b['type'] })
    tree, hedge = value['bands'][0]['items']
    assert_equal({ 'kind' => 'tree', 'variant' => 'round', 'height_m' => 9.0, 'spacing_m' => 9.0, 'height_variation' => 0.0 }, tree)
    assert_equal({ 'kind' => 'hedge', 'variant' => 'hedge', 'height_m' => 1.2 }, hedge)
    assert_equal [], value['bands'][1]['items']
    assert_equal 1, value['road_profile_version']
    refute value.key?('name')
  end

  def test_same_input_gives_the_same_canonical_profile
    tree = profile(band('sidewalk', 2.5), band('lane', 3.0000004))
    first = accepted(tree).value
    assert_equal Canonical.dump(first), Canonical.dump(accepted(JSON.parse(JSON.generate(tree))).value)
    assert_equal 3.0, first['bands'][1]['width_m']
  end

  # --- Avertissements

  def test_a_low_crown_over_a_lane_is_a_warning_on_the_item
    result = accepted(profile(band('lane', 3.5), band('sidewalk', 2, [{ 'kind' => 'tree', 'variant' => 'round', 'height_m' => 10 }])))
    warning = result.warnings.find { |d| d.code == 'W_ROAD_CLEARANCE' }
    assert warning, result.diagnostics.map(&:to_h).inspect
    assert_equal '/bands/1/items/0', warning.path
    assert_equal 0, warning.params['band']
    assert_equal 4.5, warning.params['clearance_m']
  end

  def test_a_high_crown_or_a_footpath_gives_no_clearance_warning
    assert_empty accepted(profile(band('lane', 3.5), band('verge', 1, [{ 'kind' => 'tree', 'variant' => 'wide', 'height_m' => 14 }]))).warnings
    assert_empty accepted(profile(band('path', 2), band('plant', 1, [{ 'kind' => 'tree', 'height_m' => 10 }]))).warnings
  end

  def test_height_variation_can_bring_a_crown_down_over_a_lane
    base = { 'kind' => 'tree', 'variant' => 'wide', 'height_m' => 11 }
    assert_empty accepted(profile(band('lane', 3.5), band('verge', 1, [base]))).warnings
    varied = accepted(profile(band('lane', 3.5), band('verge', 1, [base.merge('height_variation' => 0.1)])))
    assert_equal ['W_ROAD_CLEARANCE'], varied.warnings.map(&:code)
  end

  def test_composition_warnings_do_not_block
    rail = accepted(profile(band('rail'), band('lane')))
    assert_equal [%w[/bands/0 rail_next_to_carriageway]], rail.warnings.map { |d| [d.path, d.params['reason']] }
    ditch = accepted(profile(band('lane'), band('ditch')))
    assert_equal [%w[/bands/0 ditch_next_to_carriageway]], ditch.warnings.map { |d| [d.path, d.params['reason']] }
    assert_empty accepted(profile(band('lane'), band('verge'), band('ditch'))).warnings
  end

  # Ces deux raisons passent par une variable : le relevé des messages du panneau ne les voit pas.
  def test_composition_reasons_have_a_message
    Archgen::Loader.load_internal('ui/messages')
    %w[rail_next_to_carriageway ditch_next_to_carriageway].each do |reason|
      assert Archgen::UI::Messages::REASONS.key?(reason), reason
    end
  end
end
