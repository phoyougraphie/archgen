# frozen_string_literal: true

require_relative '../test_helper'
Archgen::Loader.load_internal('ui/commands')

# U103 : accès direct (AG-145, ADR-70) : une liste de commandes pour le menu et la barre d'outils,
# « Modifier la sélection » qui reconnaît la racine sélectionnée, icônes livrées.
class CommandsTest < Minitest::Test
  C = Archgen::UI::Commands
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

  def model(item, active_path: nil)
    Model.new(Selection.new([item].compact), active_path)
  end

  def root(dictionary, key)
    Root.new({ dictionary => { key => '{}' } })
  end

  def test_selection_kind_recognises_each_archgen_root
    assert_equal :building, C.selection_kind(model(root('archgen.building', 'config_json')))
    assert_equal :ensemble, C.selection_kind(model(root('archgen.ensemble', 'ensemble_json')))
    assert_equal :road, C.selection_kind(model(root('archgen.road', 'road_json')))
    assert_equal :network, C.selection_kind(model(root('archgen.network', 'network_json')))
    assert_nil C.selection_kind(model(Root.new({})))
    assert_nil C.selection_kind(model(nil))
    assert_nil C.selection_kind(model(root('archgen.building', 'config_json'), active_path: [:open]))
    assert_nil C.selection_kind(nil)
  end

  def test_edit_and_export_follow_the_selection
    empty = model(nil)
    refute C.enabled?(:edit, empty)
    refute C.enabled?(:export, empty)
    assert C.enabled?(:new_building, empty)
    road = model(root('archgen.road', 'road_json'))
    assert C.enabled?(:edit, road)
    refute C.enabled?(:export, road), 'une voie ne s’exporte pas pour un moteur de jeu'
    assert C.enabled?(:export, model(root('archgen.ensemble', 'ensemble_json')))
  end

  def test_every_entry_has_texts_an_icon_and_an_action
    ids = C::ENTRIES.map(&:id)
    assert_equal ids.uniq, ids
    assert_equal 9, ids.size
    C::ENTRIES.each do |entry|
      [entry.menu, entry.tooltip, entry.status].each { |text| refute_empty text.to_s, entry.id.to_s }
      path = C.icon(entry.icon)
      assert File.file?(path), path
      svg = File.read(path, encoding: 'UTF-8')
      assert_match(/\A<svg [^>]*viewBox="0 0 24 24"/, svg)
      refute_match(/<script|href=|url\(/i, svg, 'icône sans script ni ressource externe')
    end
    assert_equal %i[create edit map export], C::ENTRIES.map(&:group).uniq
  end
end
