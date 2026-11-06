# frozen_string_literal: true

require 'json'

# Recette H09 scriptée sur un document vierge, panneau fermé :
#   load '.../test/host/panel.rb'; load '.../test/host/h09.rb'; ArchgenH09Probe.run
# Agit sur le vrai panneau par son DOM et relit le panneau et le modèle après chaque étape.
# Rapport : tmp/h09.txt. Le clavier réel et la mise à l'échelle de Windows restent à contrôler
# à l'écran : un événement DOM n'en prouve rien.
module ArchgenH09Probe
  REPO = File.expand_path('../..', __dir__)
  REPORT = File.join(REPO, 'tmp', 'h09.txt')
  DELAY_S = 1.5

  SNAPSHOT = <<~JS
    (function () {
      function byId(id) { return document.getElementById(id); }
      var roof = Array.from(document.querySelectorAll('[data-roof]')).filter(function (n) { return !n.hidden && n.offsetParent !== null; });
      sketchup.archgen_probe(JSON.stringify({
        title: byId('title').textContent, status: byId('status').textContent, write_enabled: !byId('generate').disabled,
        summary: byId('summary').hidden ? '' : byId('summary-list').textContent, warnings: byId('warnings').textContent,
        preview: byId('preview-summary').textContent, profile: byId('f-profile').options[byId('f-profile').selectedIndex].text,
        width: byId('f-width').value, count: byId('f-count').value, lod: byId('f-lod').value, name: byId('f-name').value,
        roof_fields: roof.length, overflow: document.documentElement.scrollWidth > document.documentElement.clientWidth,
        labelled: Array.from(document.querySelectorAll('input, select')).every(function (n) { return n.type === 'hidden' || document.querySelector('label[for="' + n.id + '"]'); })
      }));
    })();
  JS

  module_function

  def dialog
    Archgen::UI::Panel.instance_variable_get(:@dialog)
  end

  # Directement vers le dialogue : la retenue des réponses ne doit pas toucher la sonde.
  def js(script)
    dialog.execute_script(script)
  end

  def set_field(id, value)
    js("var f = document.getElementById('#{id}'); f.value = #{value.to_json}; f.dispatchEvent(new Event('input', {bubbles: true}));")
  end

  def choose(id, value)
    js("document.getElementById('advanced').open = true; var s = document.getElementById('#{id}'); s.value = #{value.to_json}; s.dispatchEvent(new Event('change', {bubbles: true}));")
  end

  def choose_profile(label)
    js("var s = document.getElementById('f-profile'); s.value = Array.from(s.options).filter(function (o) { return o.text === #{label.to_json}; })[0].value; " \
       "s.dispatchEvent(new Event('change', {bubbles: true}));")
  end

  def click(id)
    js("document.getElementById('#{id}').click();")
  end

  def counters
    current = Sketchup.active_model
    [current.entities.length, current.definitions.count, current.materials.count, current.layers.count, current.modified?]
  end

  def steps
    [
      ['Menu Nouveau : aperçu calculé', -> {}, ->(p, same) { p['title'] == 'Nouveau bâtiment' && p['preview'].include?('sommet') && p['write_enabled'] && same }],
      ['Champs tous étiquetés', -> {}, ->(p, _) { p['labelled'] }],
      ['Virgule décimale', -> { set_field('f-width', '14,5') }, ->(p, same) { p['preview'].include?('14,5') && p['write_enabled'] && same }],
      ['Saisie invalide locale', -> { set_field('f-width', 'abc') }, ->(p, same) { !p['write_enabled'] && p['status'].start_with?('Saisie invalide') && same }],
      ['Saisie corrigée', -> { set_field('f-width', '12') }, ->(p, same) { p['write_enabled'] && p['preview'].include?('12') && same }],
      ['Refus du noyau expliqué', -> { set_field('f-wwidth', '10') }, ->(p, same) { !p['write_enabled'] && !p['summary'].empty? && same }],
      ['Retour aux valeurs du style', -> { click('reset') }, ->(p, same) { p['write_enabled'] && p['summary'].empty? && same }],
      ['Avertissement sans blocage', -> { choose('f-roof', 'flat') }, ->(p, same) { p['write_enabled'] && !p['warnings'].empty? && same }],
      ['Toit mansarde : 4 champs', -> { choose('f-roof', 'mansard') }, ->(p, _) { p['roof_fields'] == 4 }],
      ['Toit croupe : 2 champs', -> { choose('f-roof', 'hip') }, ->(p, _) { p['roof_fields'] == 2 }],
      ['Toit plat : 1 champ', -> { choose('f-roof', 'flat') }, ->(p, _) { p['roof_fields'] == 1 }],
      ['Saisir 14 m puis changer de style', lambda {
        click('reset')
        set_field('f-width', '14')
        UI.start_timer(0.6, false) { choose_profile('Toulousain (brique)') }
      }, ->(p, same) { p['profile'] == 'Toulousain (brique)' && p['width'] == '14' && p['count'] == '3' && same }],
      ['Réponses retenues : saisir 15 m', lambda {
        ArchgenPanelProbe.hold
        set_field('f-width', '15')
      }, nil],
      ['Réponses retenues : saisir 16 m', -> { set_field('f-width', '16') }, nil],
      ['Réponses rendues à l’envers : la dernière gagne', -> { ArchgenPanelProbe.release_reversed }, ->(p, same) { p['width'] == '16' && p['preview'].include?('16') && p['write_enabled'] && same }],
      ['Bâtiment à modifier', lambda {
        ArchgenPanelProbe.make_target
        @baseline = counters
        Archgen::UI::Panel.show('edit')
      }, ->(p, same) { p['title'].start_with?('Modifier') && p['width'] == '13' && p['profile'] == 'Toulousain (brique)' && p['lod'] == '1' && p['name'] == 'À modifier' && same }],
      ['Aperçu en édition sans mutation', -> { set_field('f-width', '9') }, ->(p, same) { p['width'] == '9' && p['write_enabled'] && same }],
      ['Sélection changée : cible périmée', -> { Sketchup.active_model.selection.clear }, ->(p, _) { !p['write_enabled'] && p['status'] == 'Cible périmée' }],
      ['Sélection rendue et rechargée', lambda {
        current = Sketchup.active_model
        current.selection.add(current.entities.grep(Sketchup::ComponentInstance).find { |i| i.get_attribute('archgen.building', 'revision') })
        click('reload')
      }, ->(p, same) { p['write_enabled'] && p['width'] == '13' && same }],
      ['Fenêtre étroite sans débordement', -> { ArchgenPanelProbe.narrow }, ->(p, _) { !p['overflow'] }],
      ['Zoom 150 % sans débordement', -> { ArchgenPanelProbe.zoom(1.5) }, ->(p, _) { !p['overflow'] }],
      ['Taille normale', lambda {
        ArchgenPanelProbe.zoom(1.0)
        ArchgenPanelProbe.wide
      }, ->(p, _) { !p['overflow'] }],
      ['Logique JS dans le moteur du panneau', -> { ArchgenPanelProbe.run_js_tests }, ->(p, _) { p['status'].match?(/\AJS \d+ controles, 0 echecs/) }]
    ]
  end

  def log(line)
    @lines << line
    File.binwrite(REPORT, "#{@lines.join("\n")}\n")
  end

  def receive(panel)
    label, check = @current
    same = counters == @baseline
    ok = check.call(panel, same)
    @failures += 1 unless ok
    log("#{ok ? 'OK   ' : 'ECHEC'} #{label}")
    log("      #{panel.slice('status', 'preview', 'width', 'profile', 'summary', 'warnings', 'roof_fields')} modèle intact #{same}") unless ok
    advance
  rescue StandardError => e
    @failures += 1
    log("ECHEC #{label} : #{e.class} #{e.message}")
    advance
  end

  def advance
    step = @queue.shift
    return finish unless step

    label, action, check = step
    @current = [label, check]
    begin
      action.call
    rescue StandardError => e
      @failures += 1
      log("ECHEC action #{label} : #{e.class} #{e.message}")
    end
    UI.start_timer(DELAY_S, false) do
      if check
        js(SNAPSHOT)
      else
        log("FAIT  #{label}")
        advance
      end
    end
  end

  def finish
    dialog.close
    log("FIN #{@failures} echec(s), SketchUp #{Sketchup.version}, Ruby #{RUBY_VERSION}")
  end

  def run
    @lines = []
    @failures = 0
    @queue = steps
    @baseline = counters
    Archgen::UI::Panel.show('new')
    dialog.add_action_callback('archgen_probe') { |_context, text| receive(JSON.parse(text)) }
    js('location.reload();')
    UI.start_timer(3.0, false) { advance }
    'recette lancee'
  end
end
