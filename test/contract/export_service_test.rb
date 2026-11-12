# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_export
Archgen::Loader.load_adapter

# U81 — Commande d'export glTF avec doubles (docs/DECOR_JEU_CONTRACT.md §4, AG-118). La preuve native est H38.
class ExportServiceTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp

  STREET = {
    'trace' => { 'points_m' => [[0, 0], [48, 0]], 'closed' => false },
    'building' => { 'profile' => { 'id' => 'haussmann' } }
  }.freeze

  # Système de fichiers en mémoire.
  class Files
    attr_reader :written

    def initialize(existing = [])
      @existing = existing
      @written = {}
    end

    def exist?(path) = @existing.include?(path) || @written.key?(path)

    def write(path, bytes)
      @written[path] = bytes
    end
  end

  def registry = Archgen::Composition.registry.value
  def materials = Archgen::Composition.materials.fetch('materials')

  def setup
    @model = FakeSketchUp::ServiceModel.new
    @files = Files.new
    @buildings = BuildingService.new(registry: registry, intake: Archgen::Composition.intake, materials: materials, material_revision: 1,
                                     host: FakeSketchUp::Host)
    @ensembles = EnsembleService.new(registry: registry, intake: Archgen::Composition.intake, ensemble_intake: Archgen::Composition.ensemble_intake,
                                     materials: materials, material_revision: 1, host: FakeSketchUp::Host)
    @service = ExportService.new(buildings: @buildings, ensembles: @ensembles, materials: Archgen::Composition.site_materials, files: @files)
  end

  def snapshot
    [@model.definition_list.size, @model.instances.size, @model.operations.size, @model.materials.count]
  end

  def select(entity)
    @model.selection.replace([entity])
  end

  def json(bytes)
    JSON.parse(bytes[20, bytes[12, 4].unpack1('V')])
  end

  def building_root(draft)
    created = @buildings.create(model: @model, draft: draft)
    assert created.ok?, created.errors.map(&:to_h).inspect
    @model.instances.find { |i| i.get_attribute('archgen.building', 'config_json') }
  end

  def test_a_building_gives_three_files_and_leaves_the_model_intact
    root = building_root({ 'schema_version' => 1, 'profile' => { 'id' => 'haussmann' }, 'name' => 'Maison', 'mode' => 'shell', 'lod' => 1 })
    select(root)
    before = snapshot
    result = @service.export(model: @model, path: 'C:/export/maison_LOD0.glb')
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal before, snapshot, 'export sans écriture ni opération'
    assert_equal %w[C:/export/maison_LOD0.glb C:/export/maison_LOD1.glb C:/export/maison_LOD2.glb], @files.written.keys
    counts = result.value.files.map { |f| f['triangles'] }
    assert counts.each_cons(2).all? { |a, b| b < a }, counts.inspect
    lod0 = json(@files.written['C:/export/maison_LOD0.glb'])
    assert(lod0['nodes'].any? { |n| n['name'].start_with?('UCX_') })
  end

  def test_a_street_puts_each_house_and_shares_repeated_plans
    created = @ensembles.create(model: @model, tree: STREET, origin_m: [0.0, 0.0, 0.0])
    assert created.ok?, created.errors.map(&:to_h).inspect
    root = @model.instances.find { |i| i.get_attribute('archgen.ensemble', 'ensemble_version') }
    select(root)
    before = snapshot
    result = @service.export(model: @model, path: 'C:/export/rue.glb')
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal before, snapshot
    assert_equal 'street', result.value.kind
    assert_includes result.value.notes, 'street_ground_excluded'
    plan = @ensembles.export_source(model: @model).value['plan']
    lod0 = json(@files.written.fetch('C:/export/rue_LOD0.glb'))
    roots = lod0['scenes'][0]['nodes'].map { |i| lod0['nodes'][i]['name'] }
    plan['parcels'].each { |parcel| assert_includes roots, parcel['id'] }
    assert_equal plan['parcels'].size, roots.count { |n| n.start_with?('UCX_') }
    lod2 = json(@files.written.fetch('C:/export/rue_LOD2.glb'))
    assert_equal plan['definitions'].size, lod2['meshes'].size, 'un volume par plan de maison distinct'
  end

  def test_road_or_nothing_selected_is_refused
    road = FakeSketchUp::Instance.allocate
    def road.get_attribute(dictionary, key) = dictionary == 'archgen.road' && key == 'road_version' ? 1 : nil
    @model.selection.replace([road])
    assert_equal 'export_unsupported', @service.export(model: @model, path: 'x.glb').errors.first.params['reason']
    @model.selection.replace([])
    assert_equal 'export_selection', @service.export(model: @model, path: 'x.glb').errors.first.params['reason']
    assert_empty @files.written
  end

  def test_paths_and_existing_neighbours
    assert_equal({ 'LOD0' => 'a/b_LOD0.glb', 'LOD1' => 'a/b_LOD1.glb', 'LOD2' => 'a/b_LOD2.glb' }, ExportService.paths('a/b_LOD0.glb'))
    assert_equal ExportService.paths('a/b'), ExportService.paths('a/b.GLB')
    service = ExportService.new(buildings: nil, ensembles: nil, materials: {}, files: Files.new(%w[a/b_LOD0.glb a/b_LOD2.glb]))
    assert_equal ['a/b_LOD2.glb'], service.existing('a/b_LOD0.glb')
  end
end
