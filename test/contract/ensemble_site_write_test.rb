# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_terrain'

Archgen::Loader.load_adapter

# Contrat de l'étagement d'un ensemble, avec doubles. La preuve native est H18.
class EnsembleSiteWriteTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp

  INCH = FakeTerrain::INCH
  SITE = 'archgen.site'
  ENSEMBLE = 'archgen.ensemble'
  Injected = Class.new(StandardError)
  TREE = {
    'trace' => { 'points_m' => [[0, 0], [48, 0]], 'closed' => false },
    'building' => { 'profile' => { 'id' => 'brutalist' } }
  }.freeze
  ORIGIN = [10.0, 20.0, 100.0].freeze

  def service(**ports)
    EnsembleService.new(registry: Archgen::Composition.registry.value, intake: Archgen::Composition.intake, ensemble_intake: Archgen::Composition.ensemble_intake,
                        materials: Archgen::Composition.materials.fetch('materials'), material_revision: 1, host: FakeTerrain::Host, **ports)
  end

  # Sol à 5 % selon le X du modèle.
  def slope_answer(gradient = 0.05)
    lambda do |origin|
      x, y, = origin.to_a
      [FakeTerrain::Point.new(x, y, (100.0 + (gradient * x * INCH)) / INCH), [@terrain]]
    end
  end

  def setup
    @model = FakeTerrain::RayModel.new
    @terrain = FakeTerrain::Solid.new(777, @model)
    @model.solids << @terrain
    @service = service
    created = @service.create(model: @model, tree: TREE, origin_m: ORIGIN)
    raise created.errors.map(&:to_h).inspect unless created.ok?

    @root = @model.instances.find { |i| i.get_attribute(ENSEMBLE, 'ensemble_version') }
    # Le double ne reporte pas le placement d'insertion : la racine est mise à sa place à la main.
    @root.transformation = FakeSketchUp::Host.transformation([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, ORIGIN[0] / INCH, ORIGIN[1] / INCH, ORIGIN[2] / INCH, 1])
    @target = created.value.target
    @model.selection.replace([@terrain])
    @ref = @service.retain_terrain(model: @model).value
    @model.selection.replace([@root])
    @model.ray_answer = slope_answer
  end

  def adapted(site = {})
    result = @service.adapt_to_site(model: @model, target: @target, terrain: @ref, site: site)
    assert result.ok?, result.errors.map(&:to_h).inspect
    @target = result.value.target
    result
  end

  def nested(root = @root)
    root.definition.entities.select { |e| e.is_a?(FakeSketchUp::Instance) }
  end

  def buildings(root = @root)
    nested(root).reject { |i| i.name.end_with?('/assise') }
  end

  def assises(root = @root)
    nested(root).select { |i| i.name.end_with?('/assise') }
  end

  def starts
    @model.operations.count { |op| op.first == :start }
  end

  def level(instance)
    instance.transform.to_a[14] * INCH
  end

  def snapshot
    [@model.definition_list.size, @model.instances.size, @model.materials.count, @model.layers.count, @root.definition, @root.attrs.dup, @root.transformation.to_a]
  end

  def assert_refused(result, code, reason = nil)
    refute result.ok?, 'attendu un refus'
    found = result.errors.find { |d| d.code == code }
    assert found, result.errors.map(&:to_h).inspect
    assert_equal reason, found.params['reason'] if reason
    found
  end

  # --- Aperçu

  def test_preview_writes_nothing_and_opens_no_operation
    before = snapshot
    operations = starts
    result = @service.preview_site(model: @model, target: @target, terrain: @ref, site: {})
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal before, snapshot
    assert_equal operations, starts
    assert_operator @model.ray_count, :>, 0
  end

  def test_rays_follow_the_root_placement_and_the_parcel
    @service.preview_site(model: @model, target: @target, terrain: @ref, site: {})
    xs = @model.rays.map { |ray| ray[0].to_a[0] * INCH }
    assert_in_delta 10.0, xs.min, 0.01
    assert_in_delta 58.0, xs.max, 0.01
  end

  def test_rotated_root_surveys_along_its_own_axes
    angle = Math::PI / 2.0
    @root.transformation = FakeSketchUp::Host.transformation([Math.cos(angle), Math.sin(angle), 0, 0, -Math.sin(angle), Math.cos(angle), 0, 0, 0, 0, 1, 0, 10.0 / INCH, 20.0 / INCH, 100.0 / INCH, 1])
    @service.preview_site(model: @model, target: @target, terrain: @ref, site: {})
    ys = @model.rays.map { |ray| ray[0].to_a[1] * INCH }
    assert_in_delta 20.0, ys.min, 0.01
    assert_in_delta 68.0, ys.max, 0.01
  end

  def test_tilted_root_is_refused
    @root.transformation = FakeSketchUp::Host.transformation([1, 0, 0, 0, 0, 0.8, 0.6, 0, 0, -0.6, 0.8, 0, 0, 0, 0, 1])
    assert_refused @service.preview_site(model: @model, target: @target, terrain: @ref, site: {}), 'E_SITE_TRANSFORM'
  end

  def test_embankment_is_refused_before_any_ray
    result = @service.preview_site(model: @model, target: @target, terrain: @ref, site: { 'earthwork' => 'embankment' })
    assert_refused result, 'E_STREET_SITE', 'embankment_in_row'
    assert_equal 0, @model.ray_count
  end

  # --- Écrire

  def test_adapt_is_one_operation_and_the_root_does_not_move
    before = @root.transformation.to_a
    operations = starts
    summary = adapted
    assert_equal operations + 1, starts
    assert_equal 'ARCHGEN : adapter au terrain', @model.operations.reverse.find { |op| op.first == :start }[1]
    assert_equal before, @root.transformation.to_a
    assert_equal 2, summary.value.revision
  end

  def test_parcels_stand_on_their_own_platforms
    adapted
    levels = buildings.map { |i| level(i) }
    assert_equal 4, levels.size
    levels.each_with_index do |value, index|
      # Le point haut d'une parcelle est son bord aval du tracé, à X = 10 + 12 × (i + 1) ; la racine est à 100 m.
      assert_in_delta 0.05 * (10.0 + (12.0 * (index + 1))), value, 0.002
    end
    assert_equal levels, assises.map { |i| level(i) }
  end

  def test_buildings_stay_shared_and_keep_their_parcel_names
    before = buildings.map(&:name)
    adapted
    assert_equal before, buildings.map(&:name)
    assert_equal 1, buildings.map(&:definition).uniq.size
    assert_equal before.map { |n| "#{n}/assise" }, assises.map(&:name)
  end

  def test_the_ensemble_plan_and_its_digest_do_not_change
    digest = @root.get_attribute(ENSEMBLE, 'ensemble_digest')
    adapted
    assert_equal digest, @root.get_attribute(ENSEMBLE, 'ensemble_digest')
  end

  def test_site_attributes_are_stored_on_the_root_only
    adapted
    assert_equal 1, @root.get_attribute(SITE, 'site_version')
    assert_equal 777, @root.get_attribute(SITE, 'terrain_pid')
    assert_match(/\A\h{64}\z/, @root.get_attribute(SITE, 'site_digest'))
    assert(nested.none? { |i| i.get_attribute(SITE, 'site_version') })
  end

  def test_the_terrain_is_not_touched
    attrs = @terrain.attrs.dup
    adapted
    assert_equal attrs, @terrain.attrs
    assert_equal 0, @terrain.attrs.size
  end

  def test_a_changed_terrain_is_refused_without_writing
    digest = @service.preview_site(model: @model, target: @target, terrain: @ref, site: {}).value.site_digest
    @model.ray_answer = slope_answer(0.06)
    before = snapshot
    result = @service.adapt_to_site(model: @model, target: @target, terrain: @ref, site: {}, site_digest: digest)
    assert_refused result, 'E_TARGET_STALE', 'terrain_changed'
    assert_equal before, snapshot
  end

  def test_a_refused_parcel_refuses_everything
    @model.ray_answer = lambda do |origin|
      x, y, = origin.to_a
      x * INCH > 40.0 ? nil : [FakeTerrain::Point.new(x, y, 100.0 / INCH), [@terrain]]
    end
    before = snapshot
    result = @service.adapt_to_site(model: @model, target: @target, terrain: @ref, site: {})
    found = assert_refused result, 'E_SITE_SURVEY'
    assert_match %r{\A/parcels/}, found.path
    assert_equal before, snapshot
  end

  class FailingWriter
    def initialize(inner, on:)
      @inner = inner
      @on = on
    end

    def write(*args, **options)
      @inner.write(*args, **options)
    end

    def mark_definition(*args, **options)
      @inner.mark_definition(*args, **options)
    end

    def write_site(*)
      raise Injected, 'panne' if @on == :site

      @inner.write_site(*)
    end
  end

  def test_a_failure_while_writing_an_assise_leaves_no_residue
    writer = FailingWriter.new(GeometryWriter.new(host: FakeTerrain::Host), on: :site)
    failing = service(writer: writer)
    before = snapshot
    result = failing.adapt_to_site(model: @model, target: @target, terrain: @ref, site: {})
    assert_refused result, 'E_WRITE', 'write_failed'
    assert_equal before, snapshot
    assert_nil @root.get_attribute(SITE, 'site_version')
  end

  # --- Garder, retirer, copier

  def test_replacing_keeps_the_assise_and_surveys_again
    adapted
    rays = @model.ray_count
    result = @service.regenerate(model: @model, target: @target, changes: { 'parcel' => { 'depth_m' => 10 } })
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_operator @model.ray_count, :>, rays
    assert_equal 4, assises.size
    assert_operator level(buildings.last), :>, level(buildings.first)
    assert_equal 1, @root.get_attribute(SITE, 'site_version')
  end

  def test_replacing_is_refused_when_the_terrain_is_gone
    adapted
    @model.solids.delete(@terrain)
    before = snapshot
    result = @service.regenerate(model: @model, target: @target, changes: { 'parcel' => { 'depth_m' => 10 } })
    refute result.ok?
    assert_equal before, snapshot
    assert_equal 1, @root.get_attribute(SITE, 'site_version')
  end

  def test_removing_brings_parcels_back_to_zero
    adapted
    transform = @root.transformation.to_a
    result = @service.remove_site(model: @model, target: @target)
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal 'ARCHGEN : retirer l’assise', @model.operations.reverse.find { |op| op.first == :start }[1]
    assert_equal [], assises
    assert(buildings.all? { |i| level(i).zero? })
    assert_nil @root.get_attribute(SITE, 'site_version')
    assert_equal transform, @root.transformation.to_a
  end

  def test_removing_nothing_is_refused
    assert_refused @service.remove_site(model: @model, target: @target), 'E_TARGET_STALE', 'site_absent'
  end

  def test_status_says_when_the_root_moved_also_in_z
    assert_nil @service.site_status(model: @model, target: @target).value
    adapted
    assert_equal false, @service.site_status(model: @model, target: @target).value['moved']
    moved = @root.transformation.to_a.dup
    moved[14] += 10.0
    @root.transformation = FakeSketchUp::Host.transformation(moved)
    assert_equal true, @service.site_status(model: @model, target: @target).value['moved']
  end

  def test_a_future_site_version_is_not_writable
    adapted
    @root.set_attribute(SITE, 'site_version', 99)
    assert_refused @service.preview_site(model: @model, target: @target, terrain: @ref, site: {}), 'E_VERSION'
    assert_refused @service.regenerate(model: @model, target: @target, changes: { 'parcel' => { 'depth_m' => 10 } }), 'E_VERSION'
    assert_refused @service.remove_site(model: @model, target: @target), 'E_VERSION'
  end

  def test_an_old_ensemble_stays_valid_without_site
    result = @service.regenerate(model: @model, target: @target, changes: { 'parcel' => { 'depth_m' => 10 } })
    assert result.ok?
    assert_equal [], assises
    assert_equal 0, @model.ray_count
  end
end
