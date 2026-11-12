# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter

# Contrat de l'écriture d'une voie sur un terrain (AG-049, étape 2), avec doubles : relevé refait
# avant d'écrire, racine à la cote du profil, copie entaillée le long du contour, une opération,
# panne sans résidu, régénération depuis l'original. La preuve native (intersection) est H22.
class RoadGroundServiceTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp

  ORIGIN = [10.0, 20.0, 0.0].freeze
  PLANE = ->(x, y) { 10 + (0.05 * (x - 10)) + (0.1 * (y - 20)) }

  # Relève une fonction de (x, y) du modèle ; compte les relevés et note allow_hidden.
  class FakeSurveyor
    attr_reader :calls
    attr_accessor :terrain

    def initialize(terrain)
      @terrain = terrain
      @calls = []
    end

    def survey_points(_model, reference, points, allow_hidden: false)
      @calls << [reference.persistent_id, allow_hidden]
      Archgen::Core::Result.ok(points.map { |x, y| @terrain.call(x, y) })
    end
  end

  # Entaille simulée : masque l'original, pose une copie, garde le contour reçu.
  class FakeCutter
    attr_reader :outlines, :removed
    attr_accessor :fail

    def initialize
      @outlines = []
      @removed = []
    end

    def entaille(model, terrain, outline)
      raise 'panne d’entaille' if @fail

      @outlines << outline
      terrain.hidden = true
      copy = model.add_instance(model.add_definition('copie'), FakeSketchUp::Host.identity)
      copy.set_attribute(Archgen::Adapters::SketchUp::GroundCutter::DICTIONARY, 'terrain_pid', terrain.persistent_id)
      copy
    end

    def remove(_model, persistent_id)
      @removed << persistent_id
    end
  end

  def preset(id)
    Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def tree
    { 'trace' => { 'points_m' => [[0, 0], [100, 0]], 'radii_m' => [] }, 'profile' => preset('ville'), 'ground' => {} }
  end

  def setup
    @model = FakeSketchUp::ServiceModel.new
    @terrain = @model.add_instance(@model.add_definition('terrain'), FakeSketchUp::Host.identity)
    @reference = TerrainRef.new(document_key: @model.guid, persistent_id: @terrain.persistent_id)
    @surveyor = FakeSurveyor.new(PLANE)
    @cutter = FakeCutter.new
    @service = RoadService.new(intake: Archgen::Composition.road_intake, bands: Archgen::Composition.road_bands,
                               items: Archgen::Composition.road_items, materials: Archgen::Composition.road_catalog,
                               material_revision: 1, host: FakeSketchUp::Host, surveyor: @surveyor, cutter: @cutter)
  end

  def roads
    @model.instances.select { |i| i.get_attribute('archgen.road', 'road_version') }
  end

  def digest
    Canonical.digest(@service.survey(model: @model, tree: tree, origin_m: ORIGIN, terrain: @reference).value)
  end

  def test_survey_projects_the_corridor_into_the_model
    grid = @service.survey(model: @model, tree: tree, origin_m: ORIGIN, terrain: @reference).value
    s = grid['s_m'].index(40.0)
    u = grid['u_m'].index(0.0)
    assert_in_delta PLANE.call(50.0, 20.0), grid['z_m'][s][u], 1e-6
  end

  def test_create_on_ground_is_one_operation_with_a_cut_copy
    result = @service.create(model: @model, tree: tree, origin_m: ORIGIN, terrain: @reference, survey_digest: digest)
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal 1, @model.operations.count { |op| op.first == :start }
    road = roads.first
    assert_in_delta 10.0, road.transform.to_a[14] * 0.0254, 1e-9
    assert @terrain.hidden
    outline = @cutter.outlines.first
    assert(outline.all? { |x, y| x.between?(10 - 1e-6, 110 + 1e-6) && (y - 20).abs > 6.5 - 1e-6 })
    attrs = %w[terrain_pid copy_pid survey_digest].map { |k| road.get_attribute(RoadService::GROUND_DICTIONARY, k) }
    assert_equal @terrain.persistent_id, attrs[0]
    refute_nil attrs[1]
    assert_equal digest, attrs[2]
  end

  def test_a_changed_terrain_or_no_terrain_writes_nothing
    shown = digest
    @surveyor.terrain = ->(x, y) { PLANE.call(x, y) + 0.2 }
    stale = @service.create(model: @model, tree: tree, origin_m: ORIGIN, terrain: @reference, survey_digest: shown)
    assert_equal 'terrain_changed', stale.errors.first.params['reason']
    missing = @service.create(model: @model, tree: tree, origin_m: ORIGIN)
    assert_equal 'terrain_missing', missing.errors.first.params['reason']
    assert_empty roads
    assert_empty @model.operations
  end

  def test_a_cut_failure_leaves_no_trace
    @cutter.fail = true
    before = @model.instances.size
    refute @service.create(model: @model, tree: tree, origin_m: ORIGIN, terrain: @reference).ok?
    assert_equal before, @model.instances.size
    assert_equal 1, @model.operations.count { |op| op.first == :abort }
  end

  def test_regenerate_resurveys_the_hidden_original_and_recuts
    assert @service.create(model: @model, tree: tree, origin_m: ORIGIN, terrain: @reference).ok?
    road = roads.first
    old_copy = road.get_attribute(RoadService::GROUND_DICTIONARY, 'copy_pid')
    @model.selection.replace([road])
    target = @service.load_selection(model: @model).value.target
    result = @service.regenerate(model: @model, target: target, changes: { 'profile' => preset('boulevard') })
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal [@terrain.persistent_id, true], @surveyor.calls.last
    assert_equal [old_copy], @cutter.removed
    refute_equal old_copy, road.get_attribute(RoadService::GROUND_DICTIONARY, 'copy_pid')
    assert_equal 2, @cutter.outlines.size
  end

  # AG-053 : une rivière sur un terrain qui descend vers l'aval, par le même service : une opération,
  # copie entaillée, surface de l'eau dans son groupe, sous la cote de la racine.
  def test_a_river_is_written_on_a_terrain_like_a_road
    @surveyor.terrain = ->(x, _y) { 30 - (0.01 * (x - 10)) }
    river = { 'trace' => { 'points_m' => [[0, 0], [100, 0]], 'radii_m' => [] }, 'profile' => preset('riviere'),
              'ground' => {}, 'water' => { 'mode' => 'river' } }
    result = @service.create(model: @model, tree: river, origin_m: ORIGIN, terrain: @reference)
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal 1, @model.operations.count { |op| op.first == :start }
    assert @terrain.hidden
    assert_equal 1, @cutter.outlines.size
    road = roads.first
    assert_in_delta 30.0, road.transform.to_a[14] * 0.0254, 1e-9
    names = road.definition.entities.to_a.select { |e| e.respond_to?(:name) }.map(&:name)
    assert_includes names, 'road/water'
    assert_includes names, 'road/earthwork'
  end
end

# Parcours du panneau sur un terrain (défaut vu au vrai geste, H22 : la création recalculait
# l'aperçu sans le relevé et refusait en silence).
class RoadGroundPanelTest < Minitest::Test
  include Archgen::Adapters::SketchUp

  def setup
    @model = FakeSketchUp::ServiceModel.new
    @terrain = @model.add_instance(@model.add_definition('terrain'), FakeSketchUp::Host.identity)
    @cutter = RoadGroundServiceTest::FakeCutter.new
    service = RoadService.new(intake: Archgen::Composition.road_intake, bands: Archgen::Composition.road_bands,
                              items: Archgen::Composition.road_items, materials: Archgen::Composition.road_catalog,
                              material_revision: 1, host: FakeSketchUp::Host,
                              surveyor: RoadGroundServiceTest::FakeSurveyor.new(RoadGroundServiceTest::PLANE), cutter: @cutter)
    @session = Archgen::Core::TraceSession.new
    @controller = Archgen::UI::RoadController.new(
      intake: Archgen::Composition.road_profile_intake, bands: Archgen::Composition.road_bands, items: Archgen::Composition.road_items,
      presets: Archgen::Composition.road_presets, service: service, session: @session, model_provider: -> { @model }
    )
    @controller.instance_variable_set(:@terrain, TerrainRef.new(document_key: @model.guid, persistent_id: @terrain.persistent_id))
    @counter = 0
  end

  def call(action, payload = {})
    @counter += 1
    @controller.dispatch(JSON.generate('v' => 1, 'request_id' => "g#{@counter}", 'action' => action, 'payload' => payload))
  end

  def payload
    profile = Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == 'ville' }.fetch('profile')
    { 'profile' => profile, 'road' => { 'radius_m' => 20, 'axis' => 'center', 'on_ground' => true } }
  end

  def test_survey_then_create_writes_the_road_on_the_ground
    @session.start(10.0, 20.0, 0.0)
    @session.add([110.0, 20.0])
    @session.finish
    before = call('preview', payload)
    refute before['result']['road']['ok'], 'sans relevé, la voie attend'
    surveyed = call('survey_ground', payload)
    assert surveyed['ok'], surveyed['diagnostics'].inspect
    road = surveyed['result']['road']
    assert road['ok'], road['diagnostics'].inspect
    assert_in_delta 5.0, road['metrics']['grade_max_percent'], 1e-6
    created = call('create', payload.merge('road_digest' => road['road_digest']))
    assert created['ok'], created['diagnostics'].inspect
    assert_equal 1, @cutter.outlines.size
    assert @terrain.hidden
  end
end
