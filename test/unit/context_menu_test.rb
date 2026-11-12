# frozen_string_literal: true

require_relative '../test_helper'
Archgen::Loader.load_internal('ui/context_menu')

# U62 : clic droit « Modifier » (docs/VILLE_MIXTE_CONTRACT.md, AG-095).
class ContextMenuTest < Minitest::Test
  Root = Struct.new(:attributes) do
    def get_attribute(dictionary, key)
      attributes.dig(dictionary, key)
    end
  end
  Selection = Struct.new(:items) do
    def length = items.size
    def first = items.first
  end
  Model = Struct.new(:selection, :active_path)

  def entries(item, active_path: nil)
    Archgen::UI::ContextMenu.entries(Model.new(Selection.new([item].compact), active_path))
  end

  def test_a_building_root_offers_to_edit_it
    assert_equal [['Modifier ce bâtiment', :edit_building], ['Exporter pour un moteur de jeu…', :export_game]], entries(Root.new({ 'archgen.building' => { 'config_json' => '{}' } }))
  end

  def test_a_street_root_offers_to_edit_the_street
    assert_equal [['Modifier cette rue', :edit_street], ['Exporter pour un moteur de jeu…', :export_game]], entries(Root.new({ 'archgen.ensemble' => { 'ensemble_json' => '{}' } }))
  end

  # AG-145 : une voie ou un réseau se rouvre aussi au clic droit, sans export.
  def test_a_road_or_network_root_offers_to_edit_it
    assert_equal [['Modifier cette voie', :edit_road]], entries(Root.new({ 'archgen.road' => { 'road_json' => '{}' } }))
    assert_equal [['Modifier ce réseau', :edit_network]], entries(Root.new({ 'archgen.network' => { 'network_json' => '{}' } }))
  end

  def test_anything_else_offers_nothing
    assert_empty entries(Root.new({}))
    assert_empty entries(nil)
    assert_empty entries(Root.new({ 'archgen.building' => { 'config_json' => '{}' } }), active_path: [:open_group])
  end
end
