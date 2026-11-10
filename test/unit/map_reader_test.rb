# frozen_string_literal: true

require_relative '../test_helper'

# U87 — Lecture des cartes et projection (docs/CARTOGRAPHIE_CONTRACT.md §1, AG-125).
class MapReaderTest < Minitest::Test
  include Archgen::Core

  OSM = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <osm version="0.6" generator="Overpass API">
      <note>The data included in this document is from www.openstreetmap.org.</note>
      <node id="1" lat="48.1100000" lon="-1.6800000"/>
      <node id="2" lat="48.1100000" lon="-1.6790000"/>
      <node id="3" lat="48.1105000" lon="-1.6790000"/>
      <node id="10" lat="48.1101000" lon="-1.6799000"/>
      <node id="11" lat="48.1101000" lon="-1.6797000"/>
      <node id="12" lat="48.1102000" lon="-1.6797000"/>
      <node id="13" lat="48.1102000" lon="-1.6799000"/>
      <way id="200">
        <nd ref="1"/><nd ref="2"/><nd ref="3"/>
        <tag k="highway" v="residential"/>
        <tag k="name" v="Rue d&apos;Antrain &amp; Cie"/>
        <tag k="maxspeed" v="30"/>
      </way>
      <way id="100">
        <nd ref="10"/><nd ref="11"/><nd ref="12"/><nd ref="13"/><nd ref="10"/>
        <tag k="building" v="yes"/>
        <tag k="building:levels" v="4"/>
      </way>
      <way id="300"><nd ref="1"/><nd ref="99"/><tag k="highway" v="service"/></way>
      <way id="400"><nd ref="1"/><nd ref="2"/><tag k="waterway" v="river"/></way>
      <relation id="5"><member type="way" ref="100" role="outer"/><tag k="type" v="multipolygon"/></relation>
    </osm>
  XML

  def read(text, format: 'osm', origin: nil)
    MapReader.call(text, format: format, origin: origin)
  end

  def test_osm_keeps_highways_and_buildings_with_closed_keys
    result = read(OSM)
    assert result.ok?, result.errors.map(&:to_h).inspect
    map = result.value
    assert_equal ['way/200'], map['ways'].map { |w| w['id'] }
    assert_equal({ 'highway' => 'residential', 'name' => "Rue d'Antrain & Cie" }, map['ways'][0]['tags'])
    assert_equal ['way/100'], map['buildings'].map { |b| b['id'] }
    assert_equal 4, map['buildings'][0]['ring_m'].size, 'anneau sans point répété'
    assert_equal({ 'missing_nodes' => 1, 'other' => 1, 'relation' => 1 }, map['skipped'])
  end

  def test_projection_is_metric_and_deterministic
    origin = [48.11, -1.68]
    map = read(OSM, origin: origin).value
    a, b, c = map['ways'][0]['points_m']
    assert_equal [0.0, 0.0], a
    # 0,001° de longitude à 48,11° : R · 0,001 · π/180 · cos(48,11°).
    assert_in_delta 6_371_008.8 * 0.001 * Math::PI / 180 * Math.cos(48.11 * Math::PI / 180), b[0], 0.001
    assert_in_delta 6_371_008.8 * 0.0005 * Math::PI / 180, c[1] - b[1], 0.001
    assert_equal map, read(OSM.dup, origin: origin).value
  end

  def test_two_kilometres_stay_within_a_thousandth_of_the_great_circle
    projection = MapProjection.new(48.11, -1.68)
    [[48.11 + 0.018, -1.68], [48.11, -1.68 + 0.027], [48.11 + 0.0127, -1.68 + 0.019]].each do |lat, lon|
      x, y = projection.call(lat, lon)
      planar = Math.hypot(x, y)
      phi1 = 48.11 * Math::PI / 180
      phi2 = lat * Math::PI / 180
      dphi = phi2 - phi1
      dlon = (lon + 1.68) * Math::PI / 180
      h = (Math.sin(dphi / 2)**2) + (Math.cos(phi1) * Math.cos(phi2) * (Math.sin(dlon / 2)**2))
      great = 2 * 6_371_008.8 * Math.asin(Math.sqrt(h))
      assert_operator great, :>, 1300
      assert_in_delta 0, (planar - great) / great, 0.001
    end
    back = projection.inverse(*projection.call(48.12, -1.67))
    assert_in_delta 48.12, back[0], 1e-6
    assert_in_delta(-1.67, back[1], 1e-6)
  end

  def test_origin_defaults_to_the_centre_of_what_is_read
    map = read(OSM).value
    assert_in_delta 48.11025, map['origin'][0], 1e-9
    assert_in_delta(-1.6795, map['origin'][1], 1e-9)
  end

  def test_dangerous_or_broken_files_are_refused
    xxe = %(<?xml version="1.0"?>\n<!DOCTYPE osm [<!ENTITY x SYSTEM "file:///c:/windows/win.ini">]>\n<osm><node id="1" lat="1" lon="1"/></osm>)
    error = read(xxe).errors.first
    assert_equal %w[map_file doctype], [error.params['reason'], error.params['reason_detail']]
    assert_equal 2, error.params['line']
    bad = read(OSM.sub('lat="48.1105000"', 'lat="148.1"')).errors.first
    assert_equal 'map_coordinates', bad.params['reason']
    assert_equal 6, bad.params['line']
    assert_equal 'map_empty', read('<osm version="0.6"></osm>').errors.first.params['reason']
    big = Object.new
    def big.bytesize = MapReader::MAX_BYTES + 1
    assert_equal 'too_large', MapReader.call(big, format: 'osm').errors.first.params['reason_detail']
  end

  def test_geojson_lines_and_polygons
    json = JSON.generate({ 'type' => 'FeatureCollection', 'features' => [
      { 'type' => 'Feature', 'id' => 'way/7', 'properties' => { 'highway' => 'footway', 'surface' => 'asphalt' },
        'geometry' => { 'type' => 'LineString', 'coordinates' => [[-1.68, 48.11], [-1.679, 48.11]] } },
      { 'type' => 'Feature', 'properties' => { 'building' => 'house', 'height' => '9' },
        'geometry' => { 'type' => 'Polygon', 'coordinates' => [[[-1.68, 48.11], [-1.6799, 48.11], [-1.6799, 48.1101], [-1.68, 48.1101], [-1.68, 48.11]]] } },
      { 'type' => 'Feature', 'properties' => { 'building' => 'yes' }, 'geometry' => { 'type' => 'MultiPolygon', 'coordinates' => [] } }
    ] })
    map = read(json, format: 'geojson', origin: [48.11, -1.68]).value
    assert_equal [{ 'highway' => 'footway' }], map['ways'].map { |w| w['tags'] }
    assert_equal({ 'building' => 'house', 'height' => '9' }, map['buildings'][0]['tags'])
    assert_equal 4, map['buildings'][0]['ring_m'].size
    assert_equal({ 'multipolygon' => 1 }, map['skipped'])
    assert_equal 'not_geojson', read('{"type":"Feature"}', format: 'geojson').errors.first.params['reason_detail']
  end
end
