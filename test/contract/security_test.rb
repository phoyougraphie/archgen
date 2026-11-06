# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'

Archgen::Loader.load_adapter
# Le module n'appelle l'hôte qu'à l'ouverture du panneau.
require_relative '../../archgen/ui/panel'

# Cas adverses U12 et règles de docs/SECURITY_PERFORMANCE.md : le pont, les attributs d'un
# SKP modifié et le code livré. La preuve native de la tenue du document est H06-H07.
class SecurityTest < Minitest::Test
  include Archgen::Core
  include Archgen::Adapters::SketchUp

  DRAFT = { 'schema_version' => 1, 'profile' => { 'id' => 'haussmann', 'revision' => 1 } }.freeze
  HOSTILE_TOKENS = [12, 1.5, true, [], {}, ['x'], { 'a' => 1 }, '', 'x' * 5000, " ", '<script>', '../../etc/passwd'].freeze
  FORBIDDEN_RUBY = /\b(Marshal|YAML|Psych|Net::|TCPSocket|URI\.open|OpenURI|instance_eval|class_eval|module_eval|ObjectSpace|Kernel\.(?:system|exec|spawn)|IO\.popen|Open3)\b|(?<![\w.])(eval|system|exec|spawn|rand|srand|fork)\s*[( ]|File\.(?:write|binwrite|delete|unlink|rename)|FileUtils|Dir\.(?:mkdir|rmdir)/
  FORBIDDEN_JS = /\b(innerHTML|outerHTML|insertAdjacentHTML|document\.write|eval|Function|XMLHttpRequest|fetch|WebSocket|importScripts|localStorage|sessionStorage)\b\s*[(=]|https?:\/\//

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def model
    @model ||= FakeSketchUp::ServiceModel.new
  end

  def service
    @service ||= BuildingService.new(registry: registry, intake: TestData.intake, materials: TestData.materials,
                                     material_revision: 1, host: FakeSketchUp::Host)
  end

  def controller
    @controller ||= Archgen::UI::DialogController.new(service: service, registry: registry, materials: TestData.materials,
                                                      model_provider: -> { model })
  end

  def request(action, payload = {}, id: 'r1')
    controller.dispatch(JSON.generate('v' => 1, 'request_id' => id, 'action' => action, 'payload' => payload))
  end

  def mutation_count
    model.operations.size
  end

  def assert_refused_without_writing(response)
    before = mutation_count
    assert_equal false, response['ok'], response.inspect
    assert_nil response['result']
    assert_equal before, mutation_count
    assert JSON.generate(response), 'toujours sérialisable'
  end

  def created_target
    response = request('generate', { 'draft' => DRAFT }, id: 'creation')
    assert response['ok'], response.inspect
    response['result']['target_token']
  end

  # --- Pont : jetons de tout type

  def test_hostile_target_token_never_raises_nor_writes
    created_target
    HOSTILE_TOKENS.each_with_index do |token, i|
      next if token.nil?

      before = mutation_count
      preview = request('preview', { 'draft' => DRAFT, 'target_token' => token }, id: "p#{i}")
      regenerate = request('regenerate', { 'draft' => DRAFT, 'target_token' => token, 'confirmation_token' => 'x' }, id: "w#{i}")
      assert_equal false, preview['ok'], token.inspect
      assert_equal false, regenerate['ok'], token.inspect
      assert_equal before, mutation_count, token.inspect
    end
  end

  def test_hostile_confirmation_token_never_raises_nor_writes
    token = created_target
    preview = request('preview', { 'draft' => DRAFT, 'target_token' => token }, id: 'apercu')
    assert preview['ok']
    HOSTILE_TOKENS.each_with_index do |confirmation, i|
      assert_refused_without_writing request('regenerate', { 'draft' => DRAFT, 'target_token' => token, 'confirmation_token' => confirmation }, id: "c#{i}")
    end
  end

  def test_missing_tokens_are_refused
    token = created_target
    assert_refused_without_writing request('regenerate', { 'draft' => DRAFT }, id: 'sans-cible')
    assert_refused_without_writing request('regenerate', { 'draft' => DRAFT, 'target_token' => token }, id: 'sans-confirmation')
  end

  def test_hostile_draft_values_are_refused_without_writing
    [
      DRAFT.merge('schema_version' => 2),
      DRAFT.merge('mode' => 'interior'),
      DRAFT.merge('profile' => { 'id' => '../../evil', 'revision' => 1 }),
      DRAFT.merge('profile' => { 'id' => 'generic' }),
      DRAFT.merge('materials' => { 'wall' => 'http://evil/x.png' }),
      DRAFT.merge('footprint' => { 'width_m' => 60.001 }),
      DRAFT.merge('levels' => { 'count' => 16 }),
      DRAFT.merge('levels' => { 'count' => 'beaucoup' }),
      DRAFT.merge('facade' => { 'front_bays' => 1_000_000_000 }),
      DRAFT.merge('name' => 'x' * 4000),
      DRAFT.merge('rule' => 'system("calc")')
    ].each_with_index do |draft, i|
      assert_refused_without_writing request('generate', { 'draft' => draft }, id: "g#{i}")
    end
  end

  def test_nesting_beyond_limit_is_refused_by_the_envelope
    draft = 12.times.inject({}) { |inner, _| { 'a' => inner } }
    response = controller.dispatch(%({"v":1,"request_id":"r","action":"preview","payload":{"draft":#{JSON.generate(draft, max_nesting: false)}}}))
    assert_equal false, response['ok']
    assert_equal 'too_deep', response['diagnostics'].first['params']['reason']
  end

  def test_refusal_never_echoes_a_token
    token = created_target
    response = request('regenerate', { 'draft' => DRAFT, 'target_token' => token, 'confirmation_token' => 'secret-de-test' }, id: 'x')
    refute_includes JSON.generate(response), 'secret-de-test'
  end

  # --- Pont : répétitions et mémoire bornée

  def test_replay_of_a_mutation_writes_once_even_after_many_others
    first = request('generate', { 'draft' => DRAFT }, id: 'une')
    assert first['ok']
    count = model.instances.size
    30.times { assert_equal first, request('generate', { 'draft' => DRAFT }, id: 'une') }
    assert_equal count, model.instances.size
  end

  def test_remembered_mutations_stay_bounded
    100.times { |i| request('generate', { 'draft' => DRAFT.merge('mode' => 'interdit') }, id: "m#{i}") }
    remembered = controller.instance_variable_get(:@mutations)
    assert_operator remembered.size, :<=, Archgen::UI::DialogController::MAX_REMEMBERED_MUTATIONS
  end

  def test_target_tokens_stay_bounded
    tokens = Archgen::UI::TargetTokens.new
    target = TargetRef.new(document_key: model.guid, persistent_id: 1, definition_id: 1, revision: 1, config_digest: 'x')
    issued = Array.new(200) { tokens.issue(target, model: model) }
    refute tokens.resolve(issued.first, model: model).ok?, 'le plus ancien jeton est oublié'
    assert tokens.resolve(issued.last, model: model).ok?
  end

  # --- Pont : littéral JS

  def test_literal_escapes_line_separators_and_stays_one_line
    literal = Archgen::UI::Panel.literal(JSON.generate('name' => "a b c\n</script>"))
    refute_includes literal, " "
    refute_includes literal, " "
    refute_includes literal, "\n"
    assert_equal "a b c\n</script>", JSON.parse(JSON.parse(literal))['name']
  end

  # --- Attributs d'un SKP modifié : lire n'écrit jamais, et un refus est localisé

  def tampered(key, value)
    created_target
    instance = model.instances.first
    model.selection.replace([instance])
    instance.set_attribute('archgen.building', key, value)
    instance
  end

  def test_tampered_config_is_refused_at_load
    good = nil
    {
      'non_json' => 'pas du json',
      'vide' => '',
      'tableau' => '[]',
      'profondeur' => "#{'[' * 100_000}#{']' * 100_000}",
      'trop_grand' => "{\"name\":\"#{'x' * 70_000}\"}"
    }.each do |label, value|
      @model = nil
      @service = nil
      @controller = nil
      tampered('config_json', value)
      before = mutation_count
      response = request('load_selection', {}, id: label)
      assert_equal false, response['ok'], label
      assert_equal 'E_SCHEMA', response['diagnostics'].first['code'], label
      assert_equal before, mutation_count, label
      good = response
    end
    assert good
  end

  def test_tampered_geometry_in_a_well_formed_config_is_refused
    created_target
    instance = model.instances.first
    config = JSON.parse(instance.get_attribute('archgen.building', 'config_json'))
    {
      '/footprint/width_m' => config.merge('footprint' => config['footprint'].merge('width_m' => 1000.0)),
      '/evil' => config.merge('evil' => 1),
      '/mode' => config.merge('mode' => 'interior')
    }.each do |path, altered|
      instance.set_attribute('archgen.building', 'config_json', JSON.generate(altered))
      model.selection.replace([instance])
      response = request('load_selection', {}, id: path)
      assert_equal false, response['ok'], path
      assert_equal path, response['diagnostics'].first['path']
    end
  end

  def test_config_altered_after_loading_blocks_the_regeneration
    token = created_target
    preview = request('preview', { 'draft' => DRAFT, 'target_token' => token }, id: 'apercu')
    instance = model.instances.first
    config = JSON.parse(instance.get_attribute('archgen.building', 'config_json'))
    instance.set_attribute('archgen.building', 'config_json', JSON.generate(config.merge('name' => 'Autre')))
    before = model.definition_list.size
    response = request('regenerate', { 'draft' => DRAFT, 'target_token' => token, 'confirmation_token' => preview['result']['confirmation']['token'] }, id: 'w')
    assert_equal false, response['ok']
    assert_equal 'config_changed', response['diagnostics'].first['params']['reason']
    assert_equal before, model.definition_list.size
  end

  # --- Code livré

  def shipped(pattern)
    Dir.glob(repo_path('archgen', '**', pattern)) + (pattern == '*.rb' ? [repo_path('archgen.rb')] : [])
  end

  def code_lines(path)
    File.read(path, encoding: 'UTF-8').lines.reject { |line| line.strip.start_with?('#', '//', '*') }
  end

  def test_shipped_ruby_uses_no_dangerous_call
    offenders = shipped('*.rb').flat_map do |path|
      code_lines(path).select { |line| FORBIDDEN_RUBY.match?(line) }.map { |line| "#{path}: #{line.strip}" }
    end
    assert_empty offenders
  end

  def test_shipped_scripts_use_no_dangerous_call
    offenders = shipped('*.js').flat_map do |path|
      # L'espace de noms SVG est un identifiant, jamais chargé.
      lines = code_lines(path).map { |line| line.sub('http://www.w3.org/2000/svg', '') }
      lines.select { |line| FORBIDDEN_JS.match?(line) }.map { |line| "#{path}: #{line.strip}" }
    end
    assert_empty offenders
  end

  def test_core_never_names_the_host
    core = Dir.glob(repo_path('archgen', '{core,geometry}', '**', '*.rb'))
    refute_empty core
    offenders = core.flat_map do |path|
      code_lines(path).select { |line| /\b(Sketchup|Geom::|UI::|Length)\b/.match?(line) }.map { |line| "#{path}: #{line.strip}" }
    end
    assert_empty offenders
  end

  def test_no_console_output_in_shipped_code
    offenders = shipped('*.rb').flat_map do |path|
      code_lines(path).select { |line| /(?<![\w.])(puts|print|pp|warn)\s/.match?(line) }.map { |line| "#{path}: #{line.strip}" }
    end
    assert_empty offenders, 'aucun journal hors du mode développement : chemins et JSON ne doivent pas sortir'
  end
end
