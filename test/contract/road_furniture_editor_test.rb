# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter

# U86 — Mobilier dans l'éditeur de voie (docs/MOBILIER_CONTRACT.md §5, AG-124).
class RoadFurnitureEditorTest < Minitest::Test
  C = Archgen::Composition

  def setup
    @controller = Archgen::UI::RoadController.new(intake: C.road_profile_intake, bands: C.road_bands, items: C.road_items, presets: C.road_presets)
  end

  def init
    @controller.dispatch(JSON.generate('v' => 1, 'request_id' => 'r1', 'action' => 'init', 'payload' => {}))['result']
  end

  def test_catalogue_tells_the_panel_how_each_item_is_placed
    items = init['items'].to_h { |i| [i['kind'], i] }
    assert_equal %w[positions positions], items.values_at('bus_stop', 'sign').map { |i| i['repeat'] }
    assert_equal [3, 1, 10], items['bike_rack'].values_at('default_count', 'min_count', 'max_count')
    assert_nil items['bench']['default_count']
    assert_equal 8, items['sign']['variants'].size
  end

  def test_bus_stop_preset_gives_a_shelter_its_marking_a_sign_and_racks
    preset = C.road_presets.fetch('presets').find { |p| p['id'] == 'arret-bus' }
    assert_equal 'Rue avec arrêt de bus', preset.dig('profile', 'name')
    settings = C.road_intake.settings({ 'trace' => { 'points_m' => [[0, 0], [100, 0]], 'radii_m' => [] }, 'profile' => preset['profile'] })
    assert settings.ok?, settings.errors.map(&:to_h).inspect
    assert_empty settings.warnings.map(&:to_h)
    plan = Archgen::Core::RoadEngine.call(settings.value, bands: C.road_bands, items: C.road_items)
    assert plan.ok?, plan.errors.map(&:to_h).inspect
    ids = plan.value['definitions'].keys.map { |k| k.sub(Archgen::Geometry::RoadItems::PREFIX, '') }
    %w[bus_stop/shelter/2500 bus_marking/zigzag/10 sign/crossing/2300 bike_rack/hoop/750/4].each { |id| assert_includes ids, id }
  end

  def test_panel_offers_positions_direction_and_hoops
    js = read_utf8('archgen', 'ui', 'road_panel.js')
    ['Positions m', "'Sens'", "'Arceaux'", "'Pose'", 'positionsField', "it.kind === 'bus_stop'", "it.kind === 'sign'"].each do |text|
      assert_includes js, text
    end
    css = read_utf8('archgen', 'ui', 'road_panel.css')
    %w[s-glass s-sign-red s-sign-blue s-sign-white].each { |cls| assert_includes css, ".#{cls}" }
  end
end
