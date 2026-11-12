# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'
require 'tmpdir'

Archgen::Loader.load_adapter

# U104 : recettes (AG-148, ADR-71) : réglages enregistrés sous un nom sur ce poste, remplacés,
# effacés ; noms et tailles bornés ; une valeur illisible n'est jamais perdue ; un fichier par
# genre, relu par une nouvelle instance ; les coupes enregistrées apparaissent dans le réseau.
class RecipesTest < Minitest::Test
  R = Archgen::UI::Recipes
  ROAD = { 'road_profile_version' => 1, 'bands' => [{ 'type' => 'lane', 'width_m' => 3.5 }] }.freeze

  def setup
    @store = R::MemoryStore.new
    @recipes = R.new('street', store: @store)
  end

  def reason(result)
    result.diagnostics.first.params['reason']
  end

  def test_save_list_replace_and_delete
    assert @recipes.save('  Rue  de bourg ', { 'seed' => 1 }).ok?
    assert @recipes.save('avenue', { 'seed' => 2 }).ok?
    assert_equal ['avenue', 'Rue de bourg'], @recipes.list.map { |r| r['name'] }
    assert @recipes.save('Rue de bourg', { 'seed' => 3 }).ok?
    assert_equal 2, @recipes.list.size
    assert_equal({ 'seed' => 3 }, @recipes.find('Rue de bourg')['data'])
    assert_equal ['avenue'], @recipes.delete('Rue de bourg').value.map { |r| r['name'] }
    assert_equal 'recipe_unknown', reason(@recipes.delete('Rue de bourg'))
  end

  def test_kinds_are_kept_apart
    @recipes.save('a', { 'x' => 1 })
    assert_empty R.new('road', store: @store).list
    assert_raises(ArgumentError) { R.new('script', store: @store) }
  end

  def test_names_data_and_count_are_bounded
    ['', '   ', 'x' * 61, "a\u0007b", 12, nil].each { |name| assert_equal 'recipe_name', reason(@recipes.save(name, { 'a' => 1 })), name.inspect }
    [nil, {}, [], 'texte'].each { |data| assert_equal 'recipe_data', reason(@recipes.save('n', data)), data.inspect }
    assert_equal 'recipe_too_large', reason(@recipes.save('gros', { 'x' => 'a' * 70_000 }))
    R::MAX_COUNT.times { |i| assert @recipes.save("r#{i}", { 'i' => i }).ok? }
    assert_equal 'recipe_full', reason(@recipes.save('une de trop', { 'i' => 0 }))
    assert @recipes.save('r3', { 'i' => 33 }).ok?, 'remplacer reste possible quand la liste est pleine'
  end

  def test_unreadable_value_is_copied_before_being_replaced
    @store.write('recipes_street', '{pas du json')
    assert_empty @recipes.list
    assert @recipes.save('neuve', { 'a' => 1 }).ok?
    assert_equal '{pas du json', @store.read('recipes_street_illisible')
    assert_equal ['neuve'], @recipes.list.map { |r| r['name'] }
  end

  def test_file_store_keeps_quotes_and_accents_and_survives_a_new_instance
    Dir.mktmpdir do |directory|
      name = 'Façade « 1900 » "à guillemets" #{system}'
      assert R.new('building', store: R::FileStore.new(directory)).save(name, { 'note' => 'é\\"' }).ok?
      assert_equal ['recipes_building.json'], Dir.children(directory)
      again = R.new('building', store: R::FileStore.new(directory))
      assert_equal [name], again.list.map { |r| r['name'] }
      assert_equal 'é\\"', again.list.first['data']['note']
      assert_empty R.new('road', store: R::FileStore.new(directory)).list
    end
  end

  def test_a_failed_write_is_refused_and_keeps_the_list
    store = R::MemoryStore.new
    def store.write(*) = raise(Errno::EACCES)
    result = R.new('road', store: store).save('a', { 'b' => 1 })
    assert_equal 'recipe_write', reason(result)
  end

  def test_road_controller_saves_and_lists_recipes
    controller = Archgen::UI::RoadController.new(
      intake: Archgen::Composition.road_profile_intake, bands: Archgen::Composition.road_bands,
      items: Archgen::Composition.road_items, presets: Archgen::Composition.road_presets,
      recipes: R.new('road', store: @store)
    )
    call = ->(action, payload) { controller.dispatch(JSON.generate('v' => 1, 'request_id' => 'r1', 'action' => action, 'payload' => payload)) }
    assert_equal [], call.('init', {})['result']['recipes']
    saved = call.('save_recipe', { 'name' => 'Ma rue', 'data' => ROAD })
    assert saved['ok'], saved.inspect
    assert_equal ['Ma rue'], saved['result']['recipes'].map { |r| r['name'] }
    refused = call.('save_recipe', { 'name' => '', 'data' => ROAD })
    assert_equal 'Donnez à la recette un nom de 1 à 60 caractères.', refused['diagnostics'].first['message']
    assert_equal false, call.('save_recipe', { 'name' => 'x', 'data' => ROAD, 'code' => 'eval' })['ok'], 'clé inconnue refusée'
    assert call.('delete_recipe', { 'name' => 'Ma rue' })['ok']
    assert_equal [], call.('init', {})['result']['recipes']
  end

  def test_controller_without_store_refuses_to_save
    controller = Archgen::UI::RoadController.new(
      intake: Archgen::Composition.road_profile_intake, bands: Archgen::Composition.road_bands,
      items: Archgen::Composition.road_items, presets: Archgen::Composition.road_presets
    )
    response = controller.dispatch(JSON.generate('v' => 1, 'request_id' => 'r1', 'action' => 'save_recipe', 'payload' => { 'name' => 'a', 'data' => ROAD }))
    assert_equal 'recipe_unavailable', response['diagnostics'].first['params']['reason']
  end

  def test_network_offers_saved_road_recipes
    R.new('road', store: @store).save('Ma coupe', ROAD)
    controller = Archgen::UI::NetworkController.new(
      presets: Archgen::Composition.road_presets, catalog: Archgen::Composition.road_catalog, recipes: R.new('road', store: @store)
    )
    init = controller.dispatch(JSON.generate('v' => 1, 'request_id' => 'n1', 'action' => 'init', 'payload' => {}))['result']
    assert_equal({ 'label' => 'Mes coupes', 'ids' => ['mine:Ma coupe'] }, init['families'].last)
    assert_includes init['presets'], { 'id' => 'mine:Ma coupe', 'name' => 'Ma coupe' }
  end
end
