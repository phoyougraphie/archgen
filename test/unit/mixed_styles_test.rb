# frozen_string_literal: true

require_relative '../test_helper'

# U63 : un style par bâtiment dans une rue (docs/VILLE_MIXTE_CONTRACT.md, AG-096, ADR-49).
class MixedStylesTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def settings(parcels = nil)
    tree = { 'seed' => 2, 'trace' => { 'points_m' => [[0, 0], [48, 0]], 'closed' => false }, 'building' => { 'profile' => { 'id' => 'haussmann' }, 'lod' => 1 } }
    tree['parcels'] = parcels if parcels
    r = Archgen::Composition.ensemble_intake.settings(tree)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def run_engine(value)
    EnsembleEngine.call(value, registry: registry, intake: TestData.intake, materials: TestData.materials)
  end

  def ids
    @ids ||= run_engine(settings).value['parcels'].map { |p| p['id'] }
  end

  def built(plan, id)
    plan['definitions'].fetch(plan['parcels'].find { |p| p['id'] == id }['definition_id'])
  end

  def roof_ids(built)
    built['nodes'].first['children'].find { |n| n['id'] == 'roof' }['children'].map { |n| n['id'] }
  end

  def test_one_parcel_takes_another_style_and_its_neighbours_do_not_change
    base = run_engine(settings).value
    mixed = run_engine(settings({ ids[1] => { 'style' => 'flamand' } }))
    assert mixed.ok?, mixed.errors.map(&:to_h).inspect
    flemish = built(mixed.value, ids[1])
    assert_includes roof_ids(flemish), 'roof/gable/front', 'pignon sur rue du Flamand'
    walls = flemish['nodes'].first['children'].find { |n| n['id'] == 'walls' }['children']
    assert_includes walls.flat_map { |w| w['primitive']['faces'].map { |f| f['material'] } }.uniq, 'red_brick'
    (ids - [ids[1]]).each { |id| assert_equal built(base, id), built(mixed.value, id), id }
  end

  def test_street_settings_still_apply_on_top_of_the_other_style
    value = settings({ ids[0] => { 'style' => 'toulousain', 'levels' => 4 } })
    r = run_engine(value.merge('building' => value['building'].merge('lod' => 0)))
    assert r.ok?, r.errors.map(&:to_h).inspect
    assert(built(r.value, ids[0])['definitions'].empty?, 'LOD de la rue gardé')
  end

  def test_unknown_style_is_refused_and_revision_is_pinned_by_the_service
    r = run_engine(settings({ ids[0] => { 'style' => 'atlantis' } }))
    refute r.ok?
    assert(r.errors.all? { |d| d.path.start_with?("/parcels/#{ids[0]}") })
    pinned = EnsembleParcels.pin_styles(settings({ ids[0] => { 'style' => 'flamand' } }), registry: registry)
    assert_equal 1, pinned['parcels'][ids[0]]['style_revision']
  end
end
