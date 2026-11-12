# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter

# U91 — Import d'une carte et téléchargement OpenStreetMap, avec doubles (docs/CARTOGRAPHIE_CONTRACT.md §5, AG-129).
# La preuve native est H40.
class MapImportTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp
  C = Archgen::Composition
  ORIGIN = [48.11, -1.68].freeze

  def projection = MapProjection.new(*ORIGIN)

  # Deux rues en croix et deux bâtiments rectangulaires, en coordonnées géographiques.
  def osm
    node = ->(id, x, y) { lat, lon = projection.inverse(x, y); %(<node id="#{id}" lat="#{lat.round(8)}" lon="#{lon.round(8)}"/>) }
    nodes = [node.(1, -80, 0), node.(2, 0, 0), node.(3, 80, 0), node.(4, 0, -80), node.(5, 0, 80),
             node.(11, 10, 8), node.(12, 22, 8), node.(13, 22, 18), node.(14, 10, 18),
             node.(21, -30, 8), node.(22, -18, 8), node.(23, -18, 17), node.(24, -30, 17)]
    ways = [%(<way id="100"><nd ref="1"/><nd ref="2"/><nd ref="3"/><tag k="highway" v="residential"/></way>),
            %(<way id="101"><nd ref="4"/><nd ref="2"/><nd ref="5"/><tag k="highway" v="residential"/></way>),
            %(<way id="200"><nd ref="11"/><nd ref="12"/><nd ref="13"/><nd ref="14"/><nd ref="11"/><tag k="building" v="yes"/><tag k="building:levels" v="3"/></way>),
            %(<way id="201"><nd ref="21"/><nd ref="22"/><nd ref="23"/><nd ref="24"/><nd ref="21"/><tag k="building" v="yes"/></way>)]
    %(<?xml version="1.0"?>\n<osm version="0.6">\n#{(nodes + ways).join("\n")}\n</osm>)
  end

  def asc
    l = MapTerrain::Lambert93.call(*ORIGIN)
    n = 120
    x0 = l[:east] - 120
    y0 = l[:north] - 120
    rows = Array.new(n) { Array.new(n, '42.0').join(' ') }
    "ncols #{n}\nnrows #{n}\nxllcorner #{x0}\nyllcorner #{y0}\ncellsize 2\nNODATA_value -99999\n#{rows.join("\n")}"
  end

  def setup
    @model = FakeSketchUp::ServiceModel.new
    registry = C.registry.value
    buildings = BuildingService.new(registry: registry, intake: C.intake, materials: C.materials.fetch('materials'), material_revision: 1, host: FakeSketchUp::Host)
    networks = NetworkService.new(intake: C.road_network_intake, bands: C.road_bands, items: C.road_items, materials: C.road_catalog,
                                  material_revision: 1, host: FakeSketchUp::Host)
    @service = MapImportService.new(buildings: buildings, networks: networks, host: FakeSketchUp::Host)
  end

  def preview(**opts)
    result = @service.preview(map_bytes: osm, format: 'osm', origin: ORIGIN, style: 'haussmann', source: { 'kind' => 'file' }, **opts)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def snapshot = [@model.definition_list.size, @model.instances.size, @model.materials.count, @model.layers.count]

  def test_preview_counts_everything_and_writes_nothing
    before = snapshot
    value = preview(terrain_bytes: asc, ign: true, mode: 'networks')
    assert_equal before, snapshot
    assert_empty @model.operations
    assert_equal({ 'networks' => 1, 'roads' => 2, 'buildings' => 2 }, value.counts.slice('networks', 'roads', 'buildings'))
    assert_operator value.counts['terrain_faces'], :>, 0
    assert_in_delta 42.0, value.terrain['metrics']['z_origin_m'], 1e-6
    assert_equal ['© les contributeurs d’OpenStreetMap, ODbL', 'IGN, Licence Ouverte 2.0'], value.attribution
    assert_match(/\A\h{64}\z/, value.source['sha256'])
  end

  def test_import_is_one_operation_with_editable_roots_terrain_and_marker
    value = preview(terrain_bytes: asc, mode: 'networks')
    result = @service.import(model: @model, preview: value)
    assert result.ok?, result.errors.map(&:to_h).inspect
    assert_equal 1, @model.operations.count { |op| op.first == :start }
    assert_equal 'ARCHGEN : importer une carte', @model.operations.find { |op| op.first == :start }[1]
    buildings = @model.instances.select { |i| i.get_attribute('archgen.building', 'config_json') }
    assert_equal 2, buildings.size
    assert_equal 1, @model.instances.count { |i| i.get_attribute('archgen.network', 'network_json') }
    terrain = @model.instances.find { |i| i.name == 'ARCHGEN Terrain' }
    assert_equal 'terrain', terrain.get_attribute('archgen.map', 'kind')
    marker = @model.instances.find { |i| i.name == 'ARCHGEN Carte' }
    assert_equal '© les contributeurs d’OpenStreetMap, ODbL', marker.get_attribute('archgen.map', 'attribution')
    assert_equal ORIGIN[0], marker.get_attribute('archgen.map', 'origin_lat')
    # Chaque bâtiment est placé à son coin de façade, en pouces.
    origins = buildings.map { |b| b.transformation.to_a.values_at(12, 13).map { |v| (v * 0.0254).round(3) } }
    assert(origins.all? { |x, y| y.between?(7.9, 18.1) && x.between?(-30.1, 22.1) }, origins.inspect)
  end

  def test_simple_mode_lays_every_street_flat_and_turns_with_the_frame
    value = preview
    assert_empty value.networks
    assert_equal 2, value.counts['streets']
    angle = -1.14 * Math::PI / 180
    frame = [Math.cos(angle), Math.sin(angle), 0.0, 0.0, -Math.sin(angle), Math.cos(angle), 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]
    result = @service.import(model: @model, preview: value, frame: frame)
    assert result.ok?, result.errors.map(&:to_h).inspect
    streets = @model.instances.find { |i| i.name == 'ARCHGEN Rues' }
    assert_equal 'streets', streets.get_attribute('archgen.map', 'kind')
    assert_in_delta Math.cos(angle), streets.transformation.to_a[0], 1e-9
    building = @model.instances.find { |i| i.get_attribute('archgen.building', 'config_json') }
    m = building.transformation.to_a
    assert_in_delta 1.0, Math.hypot(m[0], m[1]), 1e-9, 'rotation sans échelle'
  end

  def test_failure_during_import_leaves_the_model_intact
    value = preview
    before = snapshot
    @model.fail_insert = true
    @model.abort_restores = true
    result = @service.import(model: @model, preview: value)
    refute result.ok?
    assert_equal before, snapshot
  end

  def test_layers_can_be_left_out
    value = preview(layers: %w[buildings])
    assert_empty value.networks
    assert_equal 2, value.buildings.size
  end

  def test_overpass_request_is_fixed_and_sends_only_the_area
    box = OverpassClient.bbox(*ORIGIN, 1000)
    s, w, n, e = box
    assert_in_delta 1000, (n - s) * Math::PI / 180 * MapProjection::EARTH_RADIUS_M, 1
    request = OverpassClient.request(box)
    assert_equal 'https://overpass-api.de/api/interpreter', request['url']
    assert_equal({ 'User-Agent' => "ARCHGEN/#{Archgen::VERSION}", 'Content-Type' => 'application/x-www-form-urlencoded' }, request['headers'])
    decoded = URI.decode_www_form_component(request['body'].delete_prefix('data='))
    assert_includes decoded, %(way["highway"](#{s},#{w},#{n},#{e}))
    assert_includes decoded, '[timeout:25]'
    assert_equal OverpassClient::HOSTS, %w[https://overpass-api.de/api/interpreter https://overpass.kumi.systems/api/interpreter]
    assert_equal 'size', OverpassClient.size_problem(5000).params['reason_detail']
    assert_nil OverpassClient.size_problem(500)
  end

  def controller(confirm: true)
    @sent = []
    @saved = {}
    ports = { georef: -> { nil }, pick: ->(_k) { 'C:/x.osm' }, read: ->(_p) { osm }, confirm: ->(_t) { confirm },
              fetch: ->(request, &done) { @sent << request; done.call(200, osm) },
              save: ->(name, bytes) { @saved[name] = bytes; "C:/plans/#{name}" }, model: -> { @model } }
    Archgen::UI::MapController.new(service: @service, registry: C.registry.value, ports: ports).tap { |c| c.on_downloaded = ->(r) { @downloaded = r } }
  end

  def call(ctrl, action, payload = {})
    ctrl.dispatch(JSON.generate('v' => 1, 'request_id' => 'r1', 'action' => action, 'payload' => payload))
  end

  def test_panel_downloads_only_after_confirmation_then_previews_and_imports
    refused = controller(confirm: false)
    assert_equal false, call(refused, 'download', 'lat' => ORIGIN[0], 'lon' => ORIGIN[1], 'size_m' => 500)['result']['started']
    assert_empty @sent
    ctrl = controller
    started = call(ctrl, 'download', 'lat' => ORIGIN[0], 'lon' => ORIGIN[1], 'size_m' => 500)
    assert started['result']['started']
    assert_equal 1, @sent.size
    assert @downloaded['ok']
    path = @downloaded['result']['path']
    assert_match(/_osm_\d{8}\.osm\z/, path)
    assert_equal 'download', @downloaded['result']['source']['kind']
    preview = call(ctrl, 'preview', 'map_path' => path, 'lat' => ORIGIN[0], 'lon' => ORIGIN[1], 'style' => 'haussmann',
                                    'layers' => %w[roads buildings], 'source' => @downloaded['result']['source'])
    assert preview['ok'], preview['diagnostics'].inspect
    assert_equal 2, preview['result']['counts']['buildings']
    imported = call(ctrl, 'import')
    assert imported['ok'], imported['diagnostics'].inspect
    source = JSON.parse(@model.instances.find { |i| i.name == 'ARCHGEN Carte' }.get_attribute('archgen.map', 'source_json'))
    assert_equal 'overpass-api.de', source['host']
    assert_equal 'invalid_envelope', call(ctrl, 'preview', 'evil' => 1)['diagnostics'].first['params']['reason']
    assert_equal 'size', call(ctrl, 'download', 'lat' => 48.0, 'lon' => -1.0, 'size_m' => 9000)['diagnostics'].first['params']['reason_detail']
  end

  def test_overpass_responses_are_judged
    assert OverpassClient.check(200, '<osm/>').ok?
    assert_equal 'quota', OverpassClient.check(429, '').errors.first.params['reason_detail']
    assert_equal 'status', OverpassClient.check(504, 'x').errors.first.params['reason_detail']
    assert_equal 'empty', OverpassClient.check(200, '').errors.first.params['reason_detail']
    assert_equal 'rennes_osm_20261111.osm', OverpassClient.file_name('C:/plans/rennes.skp', Time.new(2026, 11, 11))
  end
end
