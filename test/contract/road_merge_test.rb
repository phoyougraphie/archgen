# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter

# U68 : carrefours depuis « Tracer une voie » (docs/CARREFOURS_DALLE_CONTRACT.md, AG-102).
class RoadMergeTest < Minitest::Test
  include Archgen::Adapters::SketchUp

  def preset(id)
    Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def tree(points)
    { 'trace' => { 'points_m' => points, 'radii_m' => Array.new([points.size - 2, 0].max, 20) }, 'profile' => preset('ville') }
  end

  def setup
    @model = FakeSketchUp::ServiceModel.new
    @service = RoadService.new(intake: Archgen::Composition.road_intake, bands: Archgen::Composition.road_bands, items: Archgen::Composition.road_items,
                               materials: Archgen::Composition.road_catalog, material_revision: 1, host: FakeSketchUp::Host)
  end

  def create(points, origin)
    result = @service.create(model: @model, tree: tree(points), origin_m: origin)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result
  end

  def roots(dictionary)
    @model.instances.select { |i| i.get_attribute(dictionary, dictionary == 'archgen.road' ? 'road_json' : 'network_json') }
  end

  def test_a_road_apart_stays_a_road
    create([[0, 0], [100, 0]], [0.0, 0.0, 0.0])
    create([[0, 0], [100, 0]], [0.0, 40.0, 0.0])
    assert_equal 2, roots('archgen.road').size
    assert_empty roots('archgen.network')
  end

  def test_a_road_ending_on_another_makes_a_network_with_a_t_in_one_operation
    create([[0, 0], [100, 0]], [0.0, 0.0, 0.0])
    starts = @model.operations.count { |op| op.first == :start }
    result = create([[0, 0], [0, 50]], [50.0, 4.0, 0.0])
    assert_equal starts + 1, @model.operations.count { |op| op.first == :start }, 'une seule opération'
    assert_empty roots('archgen.road'), 'la voie touchée est remplacée'
    network = JSON.parse(roots('archgen.network').first.get_attribute('archgen.network', 'network_json'))
    assert_equal 2, network['roads'].size
    assert(result.diagnostics.any? { |d| d.params['reason'] == 'roads_merged' })
  end

  def test_a_road_at_another_level_is_refused_without_writing
    create([[0, 0], [100, 0]], [0.0, 0.0, 0.0])
    count = @model.instances.size
    result = @service.create(model: @model, tree: tree([[0, 0], [0, 50]]), origin_m: [50.0, 0.0, 2.0])
    refute result.ok?
    assert_equal ['network_merge_levels'], result.errors.map { |d| d.params['reason'] }
    assert_equal count, @model.instances.size
  end
end
