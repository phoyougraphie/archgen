# frozen_string_literal: true

require_relative '../test_helper'

# U03 : RNG, canonicalisation et quantification.
class DeterministicRandomTest < Minitest::Test
  include Archgen::Core

  GOLDEN = {
    'opening/front/0/0' => 'cd855d0e3d78c',
    'opening/rear/3/3' => '3b73a509759c3',
    'feature/cornice' => '8ecd39cb81f48'
  }.freeze

  def test_golden_prefixes_for_seed_42
    GOLDEN.each { |key, hex| assert_equal hex, DeterministicRandom.hex(42, key), key }
  end

  def test_unit_is_integer_over_two_pow_52
    GOLDEN.each do |key, hex|
      assert_in_delta hex.to_i(16) / (2**52).to_f, DeterministicRandom.unit(42, key), 0.0
    end
  end

  def test_unit_stays_in_half_open_range
    2000.times do |i|
      value = DeterministicRandom.unit(i, "k/#{i}")
      assert_operator value, :>=, 0.0
      assert_operator value, :<, 1.0
    end
  end

  def test_independent_of_traversal_order
    keys = %w[front right rear left].product([0, 1, 2]).map { |s, l| DeterministicRandom.opening_key(s, l, 0) }
    forward = keys.to_h { |k| [k, DeterministicRandom.unit(42, k)] }
    backward = keys.reverse.to_h { |k| [k, DeterministicRandom.unit(42, k)] }
    assert_equal forward, backward
  end

  def test_changing_seed_or_key_changes_the_draw
    refute_equal DeterministicRandom.unit(42, 'a'), DeterministicRandom.unit(43, 'a')
    refute_equal DeterministicRandom.unit(42, 'a'), DeterministicRandom.unit(42, 'b')
  end

  def test_semantic_key_format
    assert_equal 'opening/front/2/3/u', DeterministicRandom.opening_key('front', 2, 3)
    assert_equal 'feature/cornice', DeterministicRandom.feature_key('cornice')
  end

  def test_invalid_inputs_refused
    assert_raises(ArgumentError) { DeterministicRandom.unit(-1, 'a') }
    assert_raises(ArgumentError) { DeterministicRandom.unit(2**32, 'a') }
    assert_raises(ArgumentError) { DeterministicRandom.unit(1, 'clé') }
  end

  # --- Canonicalisation

  def test_same_hash_for_reordered_keys
    assert_equal Canonical.digest('a' => 1, 'b' => { 'c' => 2.5, 'd' => [1, 2] }),
                 Canonical.digest('b' => { 'd' => [1, 2], 'c' => 2.5 }, 'a' => 1)
  end

  def test_array_order_is_significant
    refute_equal Canonical.digest('a' => [1, 2]), Canonical.digest('a' => [2, 1])
  end

  def test_negative_zero_is_canonicalized
    assert_equal Canonical.dump('a' => 0.0), Canonical.dump('a' => -0.0)
  end

  def test_non_finite_refused
    assert_raises(ArgumentError) { Canonical.dump('a' => Float::NAN) }
    assert_raises(ArgumentError) { Canonical.dump('a' => Float::INFINITY) }
  end

  def test_foreign_types_refused
    assert_raises(ArgumentError) { Canonical.dump(a: 1) }
    assert_raises(ArgumentError) { Canonical.dump('a' => Object.new) }
  end

  def test_utf8_output_is_stable
    assert_equal '{"nom":"Bâtiment"}', Canonical.dump('nom' => 'Bâtiment')
  end

  # --- Quantification

  def test_quantization_half_away_from_zero_and_no_negative_zero
    assert_equal 1.000001, Quant.q(1.0000005)
    assert_equal(-1.000001, Quant.q(-1.0000005))
    assert_equal 0.0, Quant.q(-0.0000001)
    assert_equal 1.0 / 0.0, 1.0 / Quant.q(-0.0)
  end
end
