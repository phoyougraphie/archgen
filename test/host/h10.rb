# frozen_string_literal: true

# Recette H10 scriptée, à lancer une seule fois dans la console sur un modèle vide, panneau fermé :
#   load '.../test/host/h10.rb'; ArchgenH10Probe.run
# Clique dans le vrai panneau par son DOM ; Annuler, Rétablir, enregistrer et Nouveau passent
# par l'API native, donc par les vrais observateurs. Rapport : tmp/h10.txt, modèle : tmp/h10.skp.
# Limite : un clic DOM n'est pas un clic souris (le double-clic réel est vérifié à la main).
module ArchgenH10Probe
  REPO = File.expand_path('../..', __dir__)
  REPORT = File.join(REPO, 'tmp', 'h10.txt')
  SAVED = File.join(REPO, 'tmp', 'h10.skp')
  DELAY_S = 2.0

  SNAPSHOT = <<~JS
    (function () {
      function byId(id) { return document.getElementById(id); }
      function shown(id) { return !byId(id).hidden; }
      var changes = byId('confirm-changes');
      sketchup.archgen_probe(JSON.stringify({
        title: byId('title').textContent, status: byId('status').textContent,
        write: byId('generate').textContent, write_enabled: !byId('generate').disabled,
        confirm: shown('confirm'), first_change: changes.firstChild ? changes.firstChild.textContent : '',
        change_count: changes.children.length, changes_top: changes.scrollTop,
        summary: shown('summary') ? byId('summary-list').textContent : '',
        profile: byId('f-profile').options[byId('f-profile').selectedIndex].text,
        width: byId('f-width').value, preview: byId('preview-summary').textContent,
        reload_shown: shown('reload'), new_shown: shown('new-building')
      }));
    })();
  JS

  module_function

  def dialog
    Archgen::UI::Panel.instance_variable_get(:@dialog)
  end

  def js(script)
    Archgen::UI::Panel.send_script(script)
  end

  def click(*ids)
    js(ids.map { |id| "document.getElementById('#{id}').click();" }.join)
  end

  def set_field(id, value)
    js("var f = document.getElementById('#{id}'); f.value = #{value.to_json}; f.dispatchEvent(new Event('input', {bubbles: true}));")
  end

  def choose_profile(label)
    js("var s = document.getElementById('f-profile'); s.value = Array.from(s.options).filter(function (o) { return o.text === #{label.to_json}; })[0].value; " \
       "s.dispatchEvent(new Event('change', {bubbles: true}));")
  end

  def roots
    Sketchup.active_model.entities.grep(Sketchup::ComponentInstance).select { |i| i.get_attribute('archgen.building', 'revision') }
  end

  def model_state
    list = roots
    first = list.first
    config = first && JSON.parse(first.get_attribute('archgen.building', 'config_json'))
    {
      roots: list.size, revision: first&.get_attribute('archgen.building', 'revision'),
      style: config && config['profile']['id'], width: config && config['footprint']['width_m'],
      pid: first&.persistent_id, selected: Sketchup.active_model.selection.length
    }
  end

  def attach_probe
    dialog.add_action_callback('archgen_probe') { |_context, text| receive(JSON.parse(text)) }
  end

  def steps
    [
      ['Générer, deux clics', -> { click('generate', 'generate') },
       ->(p, m) { m[:roots] == 1 && m[:revision] == 1 && p['title'].start_with?('Modifier') && p['write'] == 'Régénérer' && m[:selected] == 1 }],
      ['Passer au Brutaliste : aperçu seul', -> { choose_profile('Brutaliste') },
       ->(p, m) { m[:revision] == 1 && m[:style] == 'haussmann' && p['preview'].include?('sommet 16') && p['write_enabled'] }],
      ['Régénérer : confirmation', -> { click('generate') },
       ->(p, m) { p['confirm'] && p['first_change'].start_with?('Style') && p['changes_top'].zero? && m[:revision] == 1 }],
      ['Annuler la confirmation : brouillon gardé, aperçu frais', -> { click('confirm-no') },
       ->(p, m) { !p['confirm'] && p['profile'] == 'Brutaliste' && p['write_enabled'] && m[:revision] == 1 }],
      ['Régénérer de nouveau', -> { click('generate') }, ->(p, _m) { p['confirm'] }],
      ['Remplacer, deux clics', -> { @pid = model_state[:pid]; click('confirm-yes', 'confirm-yes') },
       ->(p, m) { m[:roots] == 1 && m[:revision] == 2 && m[:style] == 'brutalist' && m[:pid] == @pid && !p['confirm'] }],
      ['Annuler natif', -> { Sketchup.undo },
       ->(p, m) { m[:revision] == 1 && m[:style] == 'haussmann' && p['status'] == 'Cible périmée' && !p['write_enabled'] }],
      ['Recharger après Annuler', -> { click('reload') },
       ->(p, m) { p['profile'].start_with?('Haussmann') && p['write_enabled'] && m[:revision] == 1 && p['summary'].empty? }],
      ['Rétablir natif', -> { Sketchup.redo },
       ->(p, m) { m[:revision] == 2 && p['status'] == 'Cible périmée' && !p['write_enabled'] }],
      ['Recharger après Rétablir', -> { click('reload') },
       ->(p, m) { p['profile'] == 'Brutaliste' && p['write_enabled'] && m[:revision] == 2 && p['summary'].empty? }],
      ['Désélectionner', -> { Sketchup.active_model.selection.clear },
       ->(p, m) { !p['write_enabled'] && m[:selected].zero? }],
      ['Resélectionner puis recharger', lambda {
        Sketchup.active_model.selection.add(roots.first)
        click('reload')
      }, ->(p, m) { p['write_enabled'] && m[:selected] == 1 && p['summary'].empty? }],
      ['Saisir 13 m sans appliquer', -> { set_field('f-width', '13') },
       ->(p, m) { p['width'] == '13' && p['write_enabled'] && m[:width] == 12.0 }],
      ['Enregistrer : brouillon conservé', -> { Sketchup.active_model.save(SAVED) },
       ->(p, m) { p['width'] == '13' && p['write_enabled'] && m[:width] == 12.0 && m[:revision] == 2 }],
      ['Ouvrir la confirmation', -> { click('generate') }, ->(p, _m) { p['confirm'] }],
      ['Remplacer après expiration : refus', lambda {
        Archgen::UI::Panel.controller.confirmations.clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) + 121 }
        click('confirm-yes')
      }, ->(p, m) { m[:revision] == 2 && m[:width] == 12.0 && !p['summary'].empty? && !p['confirm'] && p['width'] == '13' }],
      ['Rétablir l\'heure, confirmer de nouveau', lambda {
        Archgen::UI::Panel.controller.confirmations.clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        click('generate')
      }, ->(p, _m) { p['confirm'] }],
      ['Remplacer : 13 m appliqué', -> { click('confirm-yes') },
       ->(p, m) { m[:revision] == 3 && m[:width] == 13.0 && p['write_enabled'] }],
      ['Enregistrer puis Fichier Nouveau', lambda {
        Sketchup.active_model.save(SAVED)
        Sketchup.file_new
      }, ->(p, m) { m[:roots].zero? && !p['write_enabled'] && p['new_shown'] }],
      ['Nouveau bâtiment dans le nouveau document', -> { click('new-building') },
       ->(p, m) { p['title'] == 'Nouveau bâtiment' && p['write_enabled'] && m[:roots].zero? && p['summary'].empty? }],
      ['Générer dans le nouveau document', -> { click('generate') },
       ->(p, m) { m[:roots] == 1 && m[:revision] == 1 && p['write'] == 'Régénérer' }],
      # La fermeture est asynchrone sous Windows : rouvrir à l'étape suivante.
      ['Fermer le panneau', -> { dialog.close }, nil],
      ['Rouvrir le panneau', lambda {
        Archgen::UI::Panel.show('new')
        attach_probe
        js('location.reload();')
      }, ->(p, m) { p['title'] == 'Nouveau bâtiment' && p['write_enabled'] && m[:roots] == 1 && !p['confirm'] }]
    ]
  end

  def log(line)
    @lines << line
    File.binwrite(REPORT, "#{@lines.join("\n")}\n")
    puts line
  end

  def receive(panel)
    label, check = @current
    state = model_state
    ok = check.call(panel, state)
    @failures += 1 unless ok
    log("#{ok ? 'OK   ' : 'ECHEC'} #{label}")
    log("      panneau #{panel.reject { |k, _| %w[reload_shown changes_top].include?(k) }}")
    log("      modele  #{state}")
    advance
  rescue StandardError => e
    log("ECHEC #{label} : #{e.class} #{e.message}")
    @failures += 1
    advance
  end

  def advance
    step = @queue.shift
    unless step
      log("FIN #{@total} etapes, #{@failures} echec(s), SketchUp #{Sketchup.version}, Ruby #{RUBY_VERSION}")
      return
    end
    label, action, check = step
    @current = [label, check]
    begin
      action.call
    rescue StandardError => e
      log("ECHEC action #{label} : #{e.class} #{e.message}")
      @failures += 1
    end
    UI.start_timer(DELAY_S, false) do
      if check
        js(SNAPSHOT)
      else
        log("FAIT  #{label}, visible #{dialog.visible?}")
        advance
      end
    end
  end

  # `last` rejoue seulement les dernières étapes, panneau déjà ouvert.
  def run_last(count)
    @lines = []
    @failures = 0
    @queue = steps.last(count)
    @total = @queue.size
    advance
    'recette lancee'
  end

  def run
    @lines = []
    @failures = 0
    @queue = steps
    @total = @queue.size
    # Rejeu dans la même session : repartir d'un document vide, sans invite d'enregistrement.
    if roots.any?
      Sketchup.active_model.save(SAVED)
      Sketchup.file_new
    end
    log("H10 sur #{Sketchup.active_model.entities.length} entites au depart")
    Archgen::UI::Panel.show('new')
    attach_probe
    js('location.reload();')
    UI.start_timer(3.0, false) { advance }
    'recette lancee'
  end
end
