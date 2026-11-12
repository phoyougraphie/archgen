# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_terrain'

Archgen::Loader.load_adapter

# Contrat du relevé avec doubles : logique d'appel et refus. La preuve native est H13.
class TerrainSurveyorTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp

  NEUTRAL = { 'schema_version' => 1, 'profile' => { 'id' => 'generic' }, 'name' => 'A', 'mode' => 'shell' }.freeze
  IDENTITY = FakeSketchUp::IDENTITY
  INCH = 0.0254

  Point = FakeTerrain::Point
  Layer = FakeTerrain::Layer
  Solid = FakeTerrain::Solid
  Host = FakeTerrain::Host
  RayModel = FakeTerrain::RayModel

  def setup
    @model = RayModel.new
    @terrain = Solid.new(777, @model)
    @model.solids << @terrain
    @service = BuildingService.new(registry: registry, intake: TestData.intake, materials: TestData.materials, material_revision: 1,
                                   allow_internal: true, host: Host)
    created = @service.create(model: @model, draft: NEUTRAL)
    raise created.errors.map(&:to_h).inspect unless created.ok?

    @root = created.value
    @instance = @model.instances.first
    @model.selection.replace([@terrain])
    @ref = @service.retain_terrain(model: @model).value
    @model.selection.replace([@instance])
    @model.ray_answer = ->(origin) { [Point.new(origin.to_a[0], origin.to_a[1], 100.0 / INCH), [@terrain]] }
    @operations = @model.operations.size
    @mutations = @model.mutation_count
  end

  def registry
    StyleRegistry.load(TestData.profiles, schema: TestData.schemas['profile'], config_validator: SchemaValidator.new(TestData.schemas['config']),
                                          capabilities: StyleRegistry::KNOWN_CAPABILITIES, materials: TestData.materials).value
  end

  def survey(site = {}, terrain: @ref)
    @service.survey_site(model: @model, target: @root.target, terrain: terrain, site: site)
  end

  def assert_nothing_written
    assert_equal @operations, @model.operations.size, 'aucune opération'
    assert_equal @mutations, @model.mutation_count, 'aucune écriture'
    assert_empty @terrain.attrs, 'rien n’est marqué sur le terrain'
  end

  def assert_refused(result, code, path, reason = nil)
    refute result.ok?, 'attendu un refus'
    assert_nil result.value
    found = result.errors.find { |d| d.code == code && d.path == path }
    assert found, result.errors.map(&:to_h).inspect
    assert_equal reason, found.params['reason'] if reason
    found
  end

  # --- Une face à l'altitude exacte du terrain (trouvé en H18)

  def obstacle_then(&after)
    other = Solid.new(888, @model)
    lambda do |origin|
      x, y, z = origin.to_a
      next [Point.new(x, y, 150.0 / INCH), [other]] if z > 150.0 / INCH

      after.call(x * INCH, y, x, y)
    end
  end

  def test_a_ray_lost_after_an_obstacle_is_cast_again_beside_the_node
    @model.ray_answer = obstacle_then do |x_m, y, x, _|
      (x_m - x_m.floor) < 0.0005 ? nil : [Point.new(x, y, 100.0 / INCH), [@terrain]]
    end
    result = survey
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert(result.value.grid.to_h['z_m'].flatten.all? { |z| (z - 100.0).abs < 1e-6 })
  end

  def test_a_real_hole_under_an_obstacle_stays_a_hole_after_two_more_rays
    @model.ray_answer = obstacle_then { nil }
    assert_refused survey, 'E_SITE_SURVEY', '/site/survey', 'missing_points'
    nodes = 7 * 6
    assert_equal nodes * 3 * 2, @model.ray_count
  end

  def test_a_hole_without_any_obstacle_is_not_cast_again
    @model.ray_answer = ->(_origin) { nil }
    assert_refused survey, 'E_SITE_SURVEY', '/site/survey', 'missing_points'
    assert_equal 7 * 6, @model.ray_count
  end

  # --- Retenir le terrain

  def test_retained_terrain_names_document_and_entity
    assert_equal [@model.guid, 777], [@ref.document_key, @ref.persistent_id]
  end

  def retain_with(selection)
    @model.selection.replace(selection)
    @service.retain_terrain(model: @model)
  end

  def test_selection_must_be_one_entity
    assert_refused retain_with([]), 'E_SITE_TERRAIN', '/site/terrain', 'terrain_selection'
    assert_refused retain_with([@terrain, @instance]), 'E_SITE_TERRAIN', '/site/terrain', 'terrain_selection'
  end

  def test_loose_face_is_refused_with_the_advice_to_group
    assert_refused retain_with([FakeSketchUp::Face.new([[0, 0, 0], [1, 0, 0], [0, 1, 0]])]), 'E_SITE_TERRAIN', '/site/terrain', 'terrain_kind'
  end

  def test_building_cannot_be_the_terrain
    assert_refused retain_with([@instance]), 'E_SITE_TERRAIN', '/site/terrain', 'terrain_is_building'
  end

  def test_nested_and_hidden_terrains_are_refused
    @terrain.parent = :un_groupe
    assert_refused retain_with([@terrain]), 'E_SITE_TERRAIN', '/site/terrain', 'terrain_nested'
    @terrain.parent = @model
    @terrain.hidden = true
    assert_refused retain_with([@terrain]), 'E_SITE_TERRAIN', '/site/terrain', 'terrain_hidden'
    @terrain.hidden = false
    @terrain.layer = Layer.new(false)
    assert_refused retain_with([@terrain]), 'E_SITE_TERRAIN', '/site/terrain', 'terrain_hidden'
  end

  def test_retaining_from_an_edit_context_is_refused
    @model.active_path = [:groupe]
    assert_refused retain_with([@terrain]), 'E_TARGET_STALE', '/model', 'nested_edit_context'
  end

  def test_every_terrain_reason_has_a_message
    TerrainSurveyor::REASONS.each { |reason| assert Archgen::UI::Messages::REASONS.key?(reason), reason }
  end

  # --- Relevé

  def test_survey_gives_grid_assise_and_digest_without_writing
    result = survey
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_in_delta 100.0, result.value.assise['platform_z_m']
    assert_equal result.value.grid.digest, result.value.survey_digest
    assert_equal 7 * 6, @model.ray_count, 'un rayon par nœud'
    assert_nothing_written
  end

  def test_rays_go_down_from_above_the_terrain
    survey
    origin, direction = @model.rays.first
    assert_in_delta 201.0 / INCH, origin.to_a[2]
    assert_equal [0.0, 0.0, -1.0], direction
  end

  def test_rays_follow_the_position_of_the_root
    turn = IDENTITY.dup
    turn[0] = 0.0
    turn[1] = 1.0
    turn[4] = -1.0
    turn[5] = 0.0
    turn[12] = 100.0
    turn[13] = 200.0
    @instance.transformation = FakeSketchUp::Transformation.new(turn)
    survey
    corner = @model.rays.find { |ray, _| (ray.to_a[0] - (100.0 - ((9.0 + TerrainSurveyor::RAY_OFFSET_M) / INCH))).abs < 1e-6 && (ray.to_a[1] - (200.0 + ((12.0 + TerrainSurveyor::RAY_OFFSET_M) / INCH))).abs < 1e-6 }
    refute_nil corner, 'le point (12, 9) du bâtiment, tourné de 90°'
  end

  def test_settings_change_the_grid
    assert_equal 7 * 6, survey.value.grid.xs.size * survey.value.grid.ys.size
    denser = survey({ 'survey' => { 'step_m' => 1 } }).value.grid
    assert_equal 13 * 10, denser.xs.size * denser.ys.size
  end

  def test_rays_never_run_in_the_plane_of_a_wall
    survey
    origins = @model.rays.map { |ray, _| ray.to_a.first(2) }
    [0.0, 12.0 / INCH].each { |wall| assert(origins.none? { |x, _y| (x - wall).abs < 1e-6 }, 'plan x') }
    [0.0, 9.0 / INCH].each { |wall| assert(origins.none? { |_x, y| (y - wall).abs < 1e-6 }, 'plan y') }
    assert_in_delta TerrainSurveyor::RAY_OFFSET_M / INCH, origins.first.first, 1e-9
  end

  def test_obstacle_is_crossed_by_restarting_from_its_impact
    tree = Solid.new(888, @model)
    @model.ray_answer = lambda do |origin|
      if origin.to_a[2] > 150.0 / INCH
        [Point.new(origin.to_a[0], origin.to_a[1], 150.0 / INCH), [tree]]
      else
        [Point.new(origin.to_a[0], origin.to_a[1], 100.0 / INCH), [@terrain]]
      end
    end
    result = survey
    assert_in_delta 100.0, result.value.assise['platform_z_m']
    assert_equal 2 * 7 * 6, @model.ray_count
  end

  def test_hit_inside_a_nested_group_counts_when_the_path_starts_on_the_terrain
    @model.ray_answer = ->(origin) { [Point.new(origin.to_a[0], origin.to_a[1], 100.0 / INCH), [@terrain, :groupe_interne, :face]] }
    assert survey.ok?
  end

  def test_endless_obstacles_are_refused_and_located
    tree = Solid.new(888, @model)
    @model.ray_answer = ->(origin) { [Point.new(origin.to_a[0], origin.to_a[1], origin.to_a[2] - 1.0), [tree]] }
    found = assert_refused survey, 'E_SITE_SURVEY', '/site/survey', 'too_many_obstacles'
    assert_equal 42, found.params['count']
    assert_equal SiteAssise::MAX_LISTED_POINTS, found.params['points'].size
    assert_equal TerrainSurveyor::MAX_PASSES * 42, @model.ray_count
  end

  def test_ray_escaping_gives_a_null_and_a_located_refusal
    @model.ray_answer = lambda do |origin|
      origin.to_a[0].abs < 0.1 && origin.to_a[1].abs < 0.1 ? nil : [Point.new(origin.to_a[0], origin.to_a[1], 100.0 / INCH), [@terrain]]
    end
    found = assert_refused survey, 'E_SITE_SURVEY', '/site/survey', 'missing_points'
    assert_equal [[0.0, 0.0]], found.params['points']
  end

  def test_terrain_read_again_at_each_survey
    @terrain.hidden = true
    assert_refused survey, 'E_SITE_TERRAIN', '/site/terrain', 'terrain_hidden'
    @terrain.hidden = false
    @terrain.valid = false
    assert_refused survey, 'E_SITE_TERRAIN', '/site/terrain', 'terrain_missing'
    @terrain.valid = true
    @model.solids.clear
    assert_refused survey, 'E_SITE_TERRAIN', '/site/terrain', 'terrain_missing'
    assert_equal 0, @model.ray_count
  end

  def test_other_document_or_forged_reference_is_refused
    other = TerrainRef.new(document_key: 'autre', persistent_id: 777)
    assert_refused survey({}, terrain: other), 'E_SITE_TERRAIN', '/site/terrain', 'terrain_other_document'
    assert_refused survey({}, terrain: 777), 'E_SITE_TERRAIN', '/site/terrain', 'terrain_missing'
    assert_equal 0, @model.ray_count
  end

  def test_tilted_root_is_refused_before_any_ray
    tilted = IDENTITY.dup
    tilted[5] = 0.0
    tilted[6] = 1.0
    tilted[9] = -1.0
    tilted[10] = 0.0
    @instance.transformation = FakeSketchUp::Transformation.new(tilted)
    assert_refused survey, 'E_SITE_TRANSFORM', '/site/placement', 'not_horizontal'
    assert_equal 0, @model.ray_count
  end

  def test_target_is_verified_first
    @model.selection.clear
    assert_refused survey, 'E_TARGET_STALE', '/target', 'selection_changed'
    assert_equal 0, @model.ray_count
  end

  def test_budget_and_settings_are_refused_before_any_ray
    assert_refused survey({ 'evil' => 1 }), 'E_SCHEMA', '/site/evil'
    assert_equal 0, @model.ray_count
    edit = @service.regenerate(model: @model, target: @root.target, draft: { 'schema_version' => 1, 'footprint' => { 'width_m' => 60.0, 'depth_m' => 60.0 }, 'facade' => { 'front_bays' => 4 } })
    assert edit.ok?, edit.errors.map(&:to_h).inspect
    found = @service.survey_site(model: @model, target: edit.value.target, terrain: @ref, site: { 'survey' => { 'step_m' => 0.5 } })
    assert_refused found, 'E_SITE_BUDGET', '/site/survey/step_m', 'survey_points'
    assert_equal 0, @model.ray_count
  end

  def test_relief_beyond_the_limit_is_refused_after_the_survey
    @model.ray_answer = ->(origin) { [Point.new(origin.to_a[0], origin.to_a[1], (100.0 + (origin.to_a[0] * INCH)) / INCH), [@terrain]] }
    assert_refused survey, 'E_SITE_RELIEF', '/site/platform'
    assert_nothing_written
  end

  def test_same_terrain_gives_the_same_digest
    assert_equal survey.value.survey_digest, survey.value.survey_digest
  end

  def test_digest_changes_with_the_terrain
    before = survey.value.survey_digest
    @model.ray_answer = ->(origin) { [Point.new(origin.to_a[0], origin.to_a[1], 101.0 / INCH), [@terrain]] }
    refute_equal before, survey.value.survey_digest
  end
end
