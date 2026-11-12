# frozen_string_literal: true

require_relative '../test_helper'

Archgen::Loader.load_export

# U79 — UV et matériaux PBR de l'export glTF (docs/DECOR_JEU_CONTRACT.md §2, AG-116).
class GltfMaterialsTest < Minitest::Test
  include Archgen::Core
  Writer = Archgen::Adapters::Gltf::GlbWriter

  def plan(name, **blocks)
    base = TestData.intake.effective(TestData.building(name)).value
    result = GeometryEngine.generate(BuildingConfig.new(Merge.leaves(base, blocks.transform_keys(&:to_s))), materials: TestData.materials)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def gltf(built)
    result = Writer.building(built, name: 'maison', materials: TestData.materials)
    assert result.ok?, result.errors.map(&:to_h).inspect
    bytes = result.value['bytes']
    json_length = bytes[12, 4].unpack1('V')
    { json: JSON.parse(bytes[20, json_length]), bin: bytes[28 + json_length..] }
  end

  def rows(doc, index, width)
    accessor = doc[:json]['accessors'][index]
    view = doc[:json]['bufferViews'][accessor['bufferView']]
    doc[:bin][view['byteOffset'], view['byteLength']].unpack('e*').each_slice(width).to_a
  end

  def mesh(doc, name)
    doc[:json]['meshes'].find { |m| m['name'] == name } || flunk("maillage #{name} absent")
  end

  def material(doc, name)
    doc[:json]['materials'].find { |m| m['name'] == name } || flunk("matériau #{name} absent")
  end

  def pairs(doc, primitive)
    rows(doc, primitive['attributes']['POSITION'], 3).zip(rows(doc, primitive['attributes']['TEXCOORD_0'], 2))
  end

  def linear(hex)
    hex.delete_prefix('#').scan(/../).map do |pair|
      c = pair.to_i(16) / 255.0
      c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
    end
  end

  def test_front_wall_uv_are_metres_along_the_facade
    doc = gltf(plan('rect-neutre-shell'))
    primitive = mesh(doc, 'wall/front')['primitives'].first
    pairs(doc, primitive).each do |position, uv|
      assert_in_delta position[0], uv[0], 1e-4, 'u = x'
      assert_in_delta(-position[1], uv[1], 1e-4, 'v = −hauteur')
    end
  end

  def test_roof_pan_uv_follow_the_plan_view
    doc = gltf(plan('toulousain'))
    roof = doc[:json]['meshes'].select { |m| m['name'].start_with?('roof') }
    refute_empty roof
    roof.each do |m|
      m['primitives'].each do |primitive|
        normals = rows(doc, primitive['attributes']['NORMAL'], 3)
        pairs(doc, primitive).zip(normals).each do |(position, uv), normal|
          next unless normal[1].abs >= [normal[0].abs, normal[2].abs].max

          assert_in_delta position[0], uv[0], 1e-4
          assert_in_delta position[2], uv[1], 1e-4
        end
      end
    end
  end

  def test_pbr_defaults_glass_metal_and_double_sided_surfaces
    shell = gltf(plan('rect-neutre-shell'))
    plaster = material(shell, 'lime_plaster (double face)')
    assert plaster['doubleSided']
    factors = plaster['pbrMetallicRoughness']
    assert_equal [0.0, 0.85], [factors['metallicFactor'], factors['roughnessFactor']]
    linear('#E7DDCA').each_with_index { |c, i| assert_in_delta c, factors['baseColorFactor'][i], 1e-6 }
    assert_equal 1.0, factors['baseColorFactor'][3]

    structural = gltf(plan('rect-neutre-structural'))
    walls = structural[:json]['meshes'].select { |m| m['name'].start_with?('wall/') }
    refute_empty walls
    walls.flat_map { |m| m['primitives'] }.each do |primitive|
      refute structural[:json]['materials'][primitive['material']]['doubleSided'], 'un mur solide est simple face'
    end

    glazed = gltf(plan('rect-neutre-shell', lod: 1, features: { 'glazing' => true }, materials: { 'glass' => 'glass' }))
    glass = glazed[:json]['materials'].find { |m| m['name'].start_with?('glass') } || flunk('verre absent')
    assert_equal 'BLEND', glass['alphaMode']
    assert_equal [0.35, 0.05], [glass['pbrMetallicRoughness']['baseColorFactor'][3], glass['pbrMetallicRoughness']['roughnessFactor']]
    zinc = gltf(plan('haussmann-12x9'))[:json]['materials'].find { |m| m['name'].start_with?('zinc') } || flunk('zinc absent')
    assert_equal [0.9, 0.5], [zinc['pbrMetallicRoughness']['metallicFactor'], zinc['pbrMetallicRoughness']['roughnessFactor']]
  end

  def test_tinted_material_keeps_its_variant_name_and_colour
    built = plan('rect-neutre-shell', facade: { 'tint' => 2 })
    used = []
    Geo.walk(built['nodes']) { |n| n['primitive']&.fetch('faces', [])&.each { |f| used << f['material'] } }
    tinted = used.uniq.find { |id| id.include?('~') } || flunk('aucune teinte dans le plan')
    doc = gltf(built)
    entry = Tint.entry(TestData.materials, tinted)
    found = doc[:json]['materials'].find { |m| m['name'].start_with?(tinted) }
    linear(entry['srgb']).each_with_index { |c, i| assert_in_delta c, found['pbrMetallicRoughness']['baseColorFactor'][i], 1e-6 }
  end

  def test_unknown_material_is_refused_with_its_piece
    built = JSON.parse(JSON.generate(plan('rect-neutre-shell')))
    leaf = nil
    Geo.walk(built['nodes']) { |n| leaf ||= n if n['primitive'] && n['primitive']['type'] != 'instance' }
    leaf['primitive']['faces'][0]['material'] = 'inconnu'
    error = Writer.building(built, name: 'maison', materials: TestData.materials).errors.first
    assert_equal ['E_EXPORT', 'export_material', leaf['id']], [error.code, error.params['reason'], error.params['id']]
  end

  def test_catalogue_pbr_keys_stay_between_zero_and_one
    TestData.materials.each do |id, entry|
      %w[roughness metallic alpha].each do |key|
        next unless entry.key?(key)

        assert entry[key].is_a?(Numeric) && entry[key].between?(0, 1), "#{id}.#{key}"
      end
    end
  end
end
