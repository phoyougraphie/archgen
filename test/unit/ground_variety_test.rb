# frozen_string_literal: true

require_relative '../test_helper'

# U64 : rez-de-chaussée moins répétitifs (docs/VILLE_MIXTE_CONTRACT.md, AG-097).
class GroundVarietyTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def plan(ground, parcels: nil, seed: 4)
    tree = { 'seed' => seed, 'trace' => { 'points_m' => [[0, 0], [120, 0]], 'closed' => false },
             'building' => { 'profile' => { 'id' => 'toulousain' }, 'lod' => 0 }, 'variety' => { 'ground' => ground } }
    tree['parcels'] = parcels if parcels
    settings = Archgen::Composition.ensemble_intake.settings(tree)
    assert settings.ok?, settings.errors.map(&:to_h).inspect
    r = EnsembleEngine.call(settings.value, registry: registry, intake: TestData.intake, materials: TestData.materials)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def door_bays(value)
    value['parcels'].map do |p|
      built = value['definitions'].fetch(p['definition_id'])
      built['openings'].find { |o| o['kind'] == 'door' }&.fetch('bay_index')
    end
  end

  def test_entry_is_drawn_per_parcel_and_reproducible
    value = plan({ 'entry' => true })
    assert_operator door_bays(value).compact.uniq.size, :>, 1, 'portes à des travées différentes'
    assert_equal door_bays(value), door_bays(plan({ 'entry' => true }))
  end

  def test_shop_share_draws_shops_and_an_own_setting_wins
    value = plan({ 'shop_share' => 0.5 })
    shops = value['parcels'].map { |p| value['definitions'].fetch(p['definition_id'])['openings'].any? { |o| o['kind'] == 'shopfront' } }
    assert_includes shops, true
    assert_includes shops, false
    assert_equal shops.count(true), value['variety']['shops']
    first = value['parcels'].find.with_index { |_, i| shops[i] }['id']
    forced = plan({ 'shop_share' => 0.5 }, parcels: { first => { 'ground_floor' => 'dwelling' } })
    built = forced['definitions'].fetch(forced['parcels'].find { |p| p['id'] == first }['definition_id'])
    refute(built['openings'].any? { |o| o['kind'] == 'shopfront' }, 'le réglage propre passe devant le tirage')
  end

  def test_window_widths_vary_between_parcels
    value = plan({ 'widths' => true })
    widths = value['parcels'].map do |p|
      w = value['definitions'].fetch(p['definition_id'])['openings'].find { |o| o['kind'] == 'window' }
      (w['u_max_m'] - w['u_min_m']).round(2)
    end
    assert_operator widths.uniq.size, :>, 1
  end
end
