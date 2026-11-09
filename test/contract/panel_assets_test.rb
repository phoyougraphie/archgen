# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/fake_sketchup'
require 'open3'

Archgen::Loader.load_adapter

# Garde-fous statiques du panneau et couverture du catalogue de messages.
class PanelAssetsTest < Minitest::Test
  UI_DIR = %w[archgen ui].freeze

  def html_files
    Dir.glob(repo_path(*UI_DIR, '*.html'))
  end

  # SketchUp oublie ce rappel à la fermeture : il doit être rattaché à chaque affichage (H14).
  def test_closing_callback_is_attached_before_each_display
    source = File.read(repo_path(*UI_DIR, 'panel.rb'), encoding: 'UTF-8')
    body = source[/def self\.attach_and_show.*?\n      end/m]
    assert_includes body, 'set_on_closed'
    refute_includes source[/def self\.build.*?\n      end/m], 'set_on_closed'
  end

  def test_every_dialog_is_local_with_a_restrictive_policy
    html_files.each do |path|
      html = File.read(path, encoding: 'UTF-8')
      assert_match(/Content-Security-Policy/, html, path)
      assert_match(/default-src 'none'/, html, path)
      refute_match(%r{(src|href)="https?://}, html, path)
      refute_match(/<script(?![^>]*\bsrc=)/, html, 'pas de script inline')
      refute_match(/<style/, html, 'pas de style inline')
      refute_match(/\son[a-z]+="/, html, 'pas de gestionnaire inline')
      refute_match(/\sstyle="/, html, 'pas d’attribut style')
    end
  end

  def test_panel_script_never_injects_markup_or_evaluates
    %w[panel.js panel_logic.js street_panel.js road_panel.js network_panel.js].each do |name|
      source = read_utf8(*UI_DIR, name)
      refute_match(/\.innerHTML|\.outerHTML|insertAdjacentHTML|document\.write|\beval\(|new Function/, source, name)
      refute_match(%r{https?://(?!www\.w3\.org/2000/svg)}, source, name)
      refute_match(/\bfetch\(|XMLHttpRequest|WebSocket/, source, name)
    end
  end

  def test_every_field_has_a_label_and_a_known_path
    html = read_utf8(*UI_DIR, 'panel.html')
    ids = html.scan(/<(?:input|select)[^>]*\bid="([^"]+)"/).flatten
    labels = html.scan(/<label for="([^"]+)"/).flatten
    assert_empty ids - labels, 'chaque champ a son libellé'
    paths = html.scan(/data-path="([^"]+)"/).flatten
    schema = JSON.parse(read_utf8('schemas', 'building-draft.v1.schema.json'))
    paths.each do |path|
      node = path.split('/').drop(1).reduce(schema) { |s, key| s.fetch('properties').fetch(key) }
      refute_nil node, path
      assert Archgen::UI::Messages.field_label(path), "libellé de message pour #{path}"
    end
  end

  def test_every_terrain_field_has_a_known_path_and_message
    html = read_utf8(*UI_DIR, 'panel.html')
    paths = html.scan(/data-site-path="([^"]+)"/).flatten
    assert_equal 6, paths.size
    schema = JSON.parse(read_utf8('schemas', 'site-settings.v1.schema.json'))
    paths.each do |path|
      refute_nil path.split('/').drop(1).reduce(schema) { |s, key| s.fetch('properties').fetch(key) }, path
      assert Archgen::UI::Messages.field_label("/site#{path}"), "libellé de message pour #{path}"
    end
  end

  def test_every_street_field_has_a_label
    html = read_utf8(*UI_DIR, 'street_panel.html')
    ids = html.scan(/<(?:input|select)[^>]*\bid="([^"]+)"/).flatten
    labels = html.scan(/<label for="([^"]+)"/).flatten
    assert_equal 33, ids.size, '8 champs de variété depuis AG-063, 4 de détails depuis AG-067, 1 de réglages propres depuis AG-069, 3 depuis AG-073'
    assert_empty ids - labels
  end

  # Défaut trouvé au vrai geste : taper une valeur puis cliquer Créer ne faisait rien.
  def test_leaving_a_street_field_does_not_disable_the_button
    source = read_utf8(*UI_DIR, 'street_panel.js')
    refute_match(/querySelectorAll\('input, select'\)/, source)
    assert_match(/querySelectorAll\('input:not\(\[data-site\]\)'\)\)\.forEach\(function \(input\) \{\n\s+input\.addEventListener\('input', requestPreview\);\n\s+\}\);/, source)
  end

  # Défauts vus au vrai geste : la section Terrain en colonnes, et un pied qui mangeait la place.
  def test_terrain_section_uses_the_full_width_and_the_footer_stays_short
    html = read_utf8(*UI_DIR, 'street_panel.html')
    assert_match(/id="site-hint" class="hint wide"/, html)
    assert_equal 2, html.scan('class="actions wide"').size
    footer = html[/<div class="street-footer">.*?<\/main>/m]
    refute_includes footer, 'replace-warning'
  end

  def test_street_panel_starts_without_anything_to_create
    html = read_utf8(*UI_DIR, 'street_panel.html')
    assert_match(/id="create"[^>]* disabled/, html)
    assert_match(/id="replace-warning"[^>]* hidden/, html)
    assert_match(/id="status"[^>]*aria-live="polite"/, html)
  end

  def test_status_region_is_announced
    assert_match(/id="status"[^>]*aria-live="polite"/, read_utf8(*UI_DIR, 'panel.html'))
  end

  def test_write_button_starts_disabled_until_a_preview_is_ready
    assert_match(/id="generate"[^>]* disabled/, read_utf8(*UI_DIR, 'panel.html'))
  end

  def test_replacement_warning_is_the_contract_text
    assert_includes read_utf8('docs', 'REGENERATION.md'), Archgen::UI::Messages::REPLACE_WARNING
  end

  def test_every_notice_reason_is_written
    %w[undo redo selection document].each { |reason| assert Archgen::UI::Messages::NOTICES.key?(reason), reason }
  end

  def test_bridge_literal_escapes_line_separators
    json = %({"a":"x\u2028y\u2029z</script>"})
    Archgen::Loader.load_internal('ui/panel')
    literal = Archgen::UI::Panel.literal(json)
    refute_includes literal, "\u2028"
    refute_includes literal, "\u2029"
    assert_includes literal, '\\u2028'
    assert_equal '"', literal[0]
  end

  # --- Catalogue : aucune raison émise par le noyau ne tombe sur le message par défaut

  def runtime_sources
    Dir.glob(repo_path('archgen', '{core,geometry,adapters,ui}', '**', '*.rb')).reject { |p| p.end_with?('style_registry.rb') }
  end

  def emitted_reasons
    runtime_sources.flat_map do |path|
      source = File.read(path, encoding: 'UTF-8')
      source.scan(/reason: '(\w+)'/).flatten +
        source.scan(/\b(?:stale|failure|invalid|clearance|fail)\((?:[^,()]*, )*'([a-z_]+)'/).flatten +
        source.scan(/roof_error\('\w+', '(\w+)'/).flatten
    end.uniq
  end

  def test_every_emitted_reason_has_a_message
    missing = emitted_reasons - Archgen::UI::Messages::REASONS.keys - %w[E_SCHEMA E_WRITE]
    assert_empty missing
    assert_operator emitted_reasons.size, :>, 40, 'le relevé doit réellement trouver les raisons'
  end

  def test_registry_runtime_reasons_have_messages
    %w[unknown_profile missing_revision not_selectable missing_capability].each do |reason|
      assert Archgen::UI::Messages::REASONS.key?(reason), reason
    end
  end

  def test_every_budget_metric_has_a_message
    Archgen::Core::Budget::CHECKS.each_key { |key| assert Archgen::UI::Messages::REASONS.key?(key), key }
  end

  def test_every_rule_has_a_message_except_decorative_chance
    (Archgen::Core::StyleRegistry::RULE_PARAMS.keys - ['feature_chance']).each do |rule|
      assert Archgen::UI::Messages::RULES.key?(rule), rule
    end
  end

  def test_message_interpolation_uses_french_decimals
    diagnostic = Archgen::Core::Diagnostic.error('E_ROOF_GEOMETRY', '/roof/inset_m', reason: 'no_remaining_span', limit: 4.3)
    assert_equal 'Le retrait du brisis est trop grand pour cette emprise. Maximum : 4,3 m.', Archgen::UI::Messages.text(diagnostic)
    wall = Archgen::Core::Diagnostic.error('E_BUDGET', '/levels', reason: 'wall_top', limit: 60.0)
    assert_includes Archgen::UI::Messages.text(wall), '60 m'
  end

  def test_unknown_reason_falls_back_without_exposing_data
    diagnostic = Archgen::Core::Diagnostic.error('E_SCHEMA', '/x', reason: 'jamais_vu', secret: 'C:/Users/x')
    assert_equal Archgen::UI::Messages::DEFAULT, Archgen::UI::Messages.text(diagnostic)
  end

  # --- Logique JS : exécutée sous Node quand il est disponible

  def test_panel_logic_under_node
    skip 'Node absent : logique JS vérifiée dans le navigateur, voir docs/recette/H09.md' unless system('node --version', out: File::NULL, err: File::NULL)

    output, status = Open3.capture2e('node', repo_path('test', 'js', 'panel_logic_test.js'))
    assert status.success?, output
  end
end
