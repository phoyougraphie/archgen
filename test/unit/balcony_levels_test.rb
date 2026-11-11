# frozen_string_literal: true

require_relative '../test_helper'

# U95 : balcons à tous les étages (AG-133, ADR-61). « all » pose un balcon au plancher de chaque
# étage au-dessus du rez-de-chaussée ; « noble », la valeur par défaut, garde les niveaux 2 et 5 et
# n'est pas écrite dans la configuration.
class BalconyLevelsTest < Minitest::Test
  include Archgen::Core

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def resolve(draft)
    ConfigResolver.resolve({ 'schema_version' => 1 }.merge(draft), registry: registry, intake: TestData.intake)
  end

  def balconies(plan)
    found = []
    walk = lambda do |node|
      case node
      when Hash
        found << node['id'] if node['category'] == 'balcony' && node['id'].to_s.match?(%r{\Abalcony/\d+\z})
        node.each_value { |v| walk.call(v) }
      when Array then node.each { |v| walk.call(v) }
      end
    end
    walk.call(plan)
    found.uniq.sort
  end

  def build(draft)
    config = resolve(draft)
    assert config.ok?, config.errors.map(&:to_h).inspect
    built = GeometryEngine.generate(config.value, materials: TestData.materials)
    assert built.ok?, built.errors.map(&:to_h).inspect
    [config.value.to_h, built.value]
  end

  def test_front_de_mer_has_a_balcony_on_every_floor
    config, plan = build('profile' => { 'id' => 'baule_front_de_mer' }, 'lod' => 1)
    assert_equal 'all', config['features']['balcony_levels']
    assert_equal (1..7).map { |i| "balcony/#{i}" }.sort, balconies(plan)
  end

  def test_noble_keeps_levels_two_and_five_and_is_not_written
    config, plan = build('profile' => { 'id' => 'baule_front_de_mer' }, 'lod' => 1, 'features' => { 'balcony_levels' => 'noble' })
    refute config['features'].key?('balcony_levels')
    assert_equal %w[balcony/2 balcony/5], balconies(plan)
  end
end
