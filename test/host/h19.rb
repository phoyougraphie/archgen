# frozen_string_literal: true

require 'json'

# Recette H19, à lancer sur un document neuf, panneaux fermés :
#   load '.../test/host/h19.rb'; ArchgenH19Probe.run
# Éditeur de coupe de voirie, vrai panneau par son DOM : onze préréglages, échelle mesurée à
# l'écran, refus, ajout, miroir, élément, réouverture ; le modèle ne change jamais.
# Le vrai geste souris se fait à part. Rapport : tmp/h19.txt.
module ArchgenH19Probe
  REPO = File.expand_path('../..', __dir__)
  REPORT = File.join(REPO, 'tmp', 'h19.txt')
  PANEL = Archgen::UI::RoadPanel
  DELAY_S = 1.0
  PRESETS = %w[autoroute nationale campagne rural boulevard ville mixte tram fer verte pieton].freeze
  # Mesure indépendante de chaque objet (hauteur, largeur, pose au sol ou sur les rails).
  SCALE_PROBE = File.read(File.join(__dir__, 'road_scale_probe.js'), encoding: 'UTF-8').strip.delete_suffix(';')
  CATALOGUE_SETUP = File.read(File.join(__dir__, 'road_catalogue_setup.js'), encoding: 'UTF-8')

  SNAPSHOT = <<~JS
    (function () {
      function q(s) { return document.querySelector(s); }
      function all(s) { return Array.prototype.slice.call(document.querySelectorAll(s)); }
      var bar = q('[data-scale-m]');
      var head = q('[data-person-head]');
      var parts = head ? Array.prototype.slice.call(head.parentNode.querySelectorAll('.s-person')) : [];
      var top = Math.min.apply(null, parts.map(function (p) { return p.getBoundingClientRect().top; }));
      var bottom = Math.max.apply(null, parts.map(function (p) { return p.getBoundingClientRect().bottom; }));
      var hits = all('#section [data-band]');
      var pxPerM = bar ? bar.getBoundingClientRect().width / Number(bar.getAttribute('data-scale-m')) : 0;
      sketchup.archgen_probe(JSON.stringify({
        status: q('#status').textContent, sum: q('#sum').textContent, count: q('#count').textContent,
        presets: all('#presets button').length, pressed: (q('#presets [aria-pressed="true"]') || {}).textContent || null,
        bands: all('#bands > li select[aria-label^="Type"]').map(function (s) { return s.value; }),
        widths: all('#bands > li input[aria-label^="Largeur"]').map(function (i) { return i.value; }),
        row_errors: all('.road-row-error').map(function (p) { return p.textContent; }),
        invalid_rows: all('#bands > li.is-invalid').length,
        diag: all('#diag li').map(function (l) { return l.textContent; }),
        stale: q('#section').classList.contains('road-stale'),
        person_m: parts.length && pxPerM ? (bottom - top) / pxPerM : null,
        // La zone de saisie du personnage descend jusqu'au sol : l'écart avec les pieds doit être nul.
        feet_gap_m: parts.length && pxPerM ? (head.parentNode.querySelector('.s-hit').getBoundingClientRect().bottom - bottom) / pxPerM : null,
        band_m: hits.map(function (h) { return h.getBoundingClientRect().width / pxPerM; }),
        svg_nodes: all('#section *').length + all('#plan *').length,
        kinds: all('#section [data-kind]').map(function (g) { return g.getAttribute('data-kind') + '/' + g.getAttribute('data-variant'); }),
        scale: JSON.parse(__SCALE_PROBE__)
      }));
    }());
  JS
    .sub('__SCALE_PROBE__') { SCALE_PROBE }

  module_function

  def model
    Sketchup.active_model
  end

  def dialog
    PANEL.instance_variable_get(:@dialog)
  end

  def js(script)
    dialog.execute_script(script)
  end

  def click(selector)
    js("document.querySelector(#{selector.to_json}).click();")
  end

  def set_input(selector, value)
    js("(function(){var e=document.querySelector(#{selector.to_json});e.value=#{value.to_json};e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));}());")
  end

  def log(line)
    @lines << line
    File.write(REPORT, "#{@lines.join("\n")}\n")
    puts line
  end

  def check(label, ok, detail = nil)
    @failures += 1 unless ok
    log("#{ok ? 'OK   ' : 'ECHEC'} #{label}#{detail ? " -- #{detail}" : ''}")
  end

  # Ce que le modèle compte : un éditeur de coupe n'y touche jamais.
  def model_print
    [model.entities.size, model.definitions.size, model.materials.size, model.layers.size, model.modified?]
  end

  def near(value, expected, tolerance)
    value && (value - expected).abs <= tolerance
  end

  def steps
    out = [['Ouverture : onze préréglages, rue de ville acceptée', -> {}, lambda { |p|
      p['presets'] == 11 && p['status'] == 'Coupe acceptée' && p['pressed'] == 'Rue de ville' && p['bands'].size == 5
    }]]
    PRESETS.each do |id|
      out << ["Préréglage #{id} accepté, dessiné, chaque objet à l’échelle", -> { click("[data-preset=\"#{id}\"]") }, lambda { |p|
        @measured += p['scale']['count']
        p['status'] == 'Coupe acceptée' && p['svg_nodes'] > 40 && p['diag'] == ['Aucun refus ni alerte.'] && p['scale']['failures'].empty?
      }]
    end
    out << ['Catalogue complet composé au panneau, chaque variante à l’échelle', -> { js(CATALOGUE_SETUP) }, lambda { |p|
      @measured += p['scale']['count']
      expected = %w[lamp/single lamp/double lamp/ped lamp/heritage lamp/high hedge/hedge fence/mesh fence/fence guard/guard guard/concrete
                    bollard/bollard tree/columnar tree/wide tree/conifer pole/pole]
      p['status'] == 'Coupe acceptée' && (expected - p['kinds']).empty? && p['scale']['failures'].empty?
    }]
    out + [
      ['Échelle à l’écran : personnage de 1,75 m, bandes à leur largeur (tram en site propre)', -> { click('[data-preset="tram"]') }, lambda { |p|
        expected = [3, 2, 3.2, 3.2, 3.2, 3.2, 2, 3]
        @scale = format('personnage %.3f m, pieds à %.3f m du sol ; bandes %s', p['person_m'].to_f, p['feet_gap_m'].to_f, p['band_m'].map { |w| format('%.3f', w) }.join(' '))
        near(p['person_m'], 1.75, 0.02) && near(p['feet_gap_m'], 0, 0.02) && p['band_m'].zip(expected).all? { |w, e| near(w, e, 0.02) }
      }],
      ['Largeur de 9 m refusée sur sa bande, coupe grisée', -> { set_input('[aria-label="Largeur de la bande 3, en mètres"]', '9') }, lambda { |p|
        p['status'].start_with?('Coupe refusée') && p['invalid_rows'] == 1 && p['stale'] &&
          p['row_errors'] == ['Cette bande mesure 9 m : choisissez une largeur de 2,5 à 4,5 m.']
      }],
      ['Saisie illisible jamais envoyée', -> { set_input('[aria-label="Largeur de la bande 3, en mètres"]', 'abc') }, lambda { |p|
        p['status'] == 'Saisie à corriger' && p['diag'].include?('Saisissez un nombre valide.')
      }],
      ['Largeur à virgule acceptée, préréglage quitté', -> { set_input('[aria-label="Largeur de la bande 3, en mètres"]', '3,5') }, lambda { |p|
        p['status'] == 'Coupe acceptée' && p['pressed'].nil? && p['sum'].start_with?('emprise 23,1 m')
      }],
      ['Ajouter une bande après la sélection', lambda {
        click('#bands > li[data-i="0"]')
        UI.start_timer(0.4, false) do
          set_input('#add-type', 'plant')
          click('#add-band')
        end
      }, ->(p) { p['bands'].size == 9 && p['bands'][1] == 'plant' && p['status'] == 'Coupe acceptée' }],
      ['Miroir', -> { click('#mirror') }, ->(p) { p['bands'][7] == 'plant' && p['bands'].first == 'sidewalk' }],
      ['Ajouter un lampadaire sur la bande plantée', lambda {
        click('#bands > li[data-i="7"]')
        UI.start_timer(0.4, false) do
          set_input('[aria-label="Élément à ajouter sur la bande 8"]', 'lamp')
          click('[aria-label="Ajouter cet élément sur la bande 8"]')
        end
      }, ->(p) { p['count'].include?('4 × lampadaire') && p['status'] == 'Coupe acceptée' }],
      ['Fermer', -> { dialog.close }, nil],
      # SketchUp n'expose à la page que les rappels connus à son chargement : rattacher la sonde tout de suite.
      ['Rouvrir : la dernière coupe acceptée revient', lambda {
        PANEL.show
        attach_probe
      }, ->(p) { p['bands'].size == 9 && p['bands'][7] == 'plant' && p['pressed'].nil? }]
    ]
  end

  def attach_probe
    dialog.add_action_callback('archgen_probe') { |_context, text| receive(JSON.parse(text)) }
  end

  def receive(panel)
    label, check_block = @current
    return unless check_block

    begin
      ok = check_block.call(panel)
      check(label, ok, ok ? nil : panel.to_s)
    rescue StandardError => e
      check(label, false, "#{e.class} #{e.message} #{e.backtrace.first(2).join(' | ')}")
    end
    advance
  end

  def advance
    step = @queue.shift
    return finish unless step

    label, action, check_block = step
    begin
      action.call
    rescue Exception => e # rubocop:disable Lint/RescueException
      check("action #{label}", false, "#{e.class} #{e.message}")
    end
    @current = [label, check_block]
    if check_block
      extra = if label.start_with?('Catalogue') then 13
              elsif label.start_with?('Rouvrir', 'Ajouter') then 1.5
              else 0
              end
      UI.start_timer(DELAY_S + extra, false) { js(SNAPSHOT) }
    else
      log("FAIT  #{label}")
      UI.start_timer(DELAY_S * 2, false) { advance }
    end
  end

  def finish
    log("Mesure : #{@scale}") if @scale
    log("Objets mesurés à l’échelle : #{@measured}")
    check('Modèle inchangé : entités, définitions, matériaux, balises, état modifié', model_print == @before, "#{@before.inspect} -> #{model_print.inspect}")
    log("FIN #{@failures} echec(s), ARCHGEN #{Archgen::VERSION}, SketchUp #{Sketchup.version}, Ruby #{RUBY_VERSION}")
  end

  def run
    @lines = []
    @failures = 0
    @measured = 0
    @before = model_print
    @queue = steps
    PANEL.show
    attach_probe
    log("H19 départ #{Time.now}, ARCHGEN #{Archgen::VERSION}, modèle #{@before.inspect}")
    UI.start_timer(2.0, false) { advance }
    'recette lancee'
  end
end
