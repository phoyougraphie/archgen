# frozen_string_literal: true

require 'json'

# Recette H16, à lancer sur un document neuf, panneau de rue fermé :
#   load '.../test/host/h16.rb'; ArchgenH16Probe.run
# Pilote le vrai outil, avec le vrai InputPoint et le vrai rayon de vue, et le vrai panneau par
# son DOM. Rapport : tmp/h16.txt. Limite : ces appels ne sont pas des gestes de souris ; le vrai
# geste est fait à part, à l'écran. Le dernier mot du rapport est « FIN ».
module ArchgenH16Probe
  REPO = File.expand_path('../..', __dir__)
  REPORT = File.join(REPO, 'tmp', 'h16.txt')
  WORK = File.join(REPO, 'tmp', 'h16-travail.skp')
  PANEL = Archgen::UI::StreetPanel
  TOOL = Archgen::Adapters::SketchUp::StreetTool
  INCH = 0.0254
  DICTIONARY = 'archgen.ensemble'
  DELAY_S = 1.2
  MILLIMETRE = 0.001
  METERS = 4

  module_function

  def model
    Sketchup.active_model
  end

  def view
    model.active_view
  end

  def dialog
    PANEL.instance_variable_get(:@dialog)
  end

  def tool
    PANEL.instance_variable_get(:@tool)
  end

  def session
    PANEL.controller.session
  end

  def js(script)
    PANEL.send_script(script)
  end

  def click_dom(id)
    js("document.getElementById(#{id.to_json}).click();")
  end

  def set_input(id, value)
    js("(function(){var e=document.getElementById(#{id.to_json});e.value=#{value.to_json};e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));}());")
  end

  SNAPSHOT = <<~JS
    (function () {
      function byId(id) { return document.getElementById(id); }
      sketchup.archgen_probe(JSON.stringify({
        status: byId('status').textContent, result: byId('result').textContent,
        create: byId('create').textContent, create_enabled: !byId('create').disabled, clear_enabled: !byId('clear').disabled,
        resume_shown: !byId('resume').hidden, side: byId('s-side').value, street_shown: !byId('s-street-field').hidden,
        summary_shown: !byId('summary').hidden, summary: byId('summary-list').textContent, warnings: byId('warnings').textContent,
        profile: byId('s-profile').value, profiles: byId('s-profile').options.length
      }));
    }());
  JS

  def log(line)
    @lines << line
    File.binwrite(REPORT, "#{@lines.join("\n")}\n")
  end

  def check(label, ok, detail = nil)
    @failures += 1 unless ok
    log("#{ok ? 'OK   ' : 'ECHEC'} #{label}#{detail ? " : #{detail}" : ''}")
  end

  def roots
    model.entities.grep(Sketchup::ComponentInstance).select { |i| i.get_attribute(DICTIONARY, 'ensemble_version') }
  end

  # Clic réel de l'outil au pixel qui correspond à ce point du sol.
  def click_at(x_m, y_m)
    point = view.screen_coords(Geom::Point3d.new(x_m / INCH, y_m / INCH, 0))
    tool.onMouseMove(0, point.x, point.y, view)
    tool.onLButtonDown(0, point.x, point.y, view)
  end

  def type(text)
    tool.onUserText(text, view)
  end

  def key(code)
    tool.onKeyDown(code, 1, 0, view)
  end

  def relative
    first = session.points.first
    session.points.map { |x, y| [x - first[0], y - first[1]] }
  end

  def near?(actual, expected)
    actual.size == expected.size && actual.zip(expected).all? { |(x, y), (u, v)| Math.hypot(x - u, y - v) <= MILLIMETRE }
  end

  # Chaque étape : action, puis contrôle du panneau et du modèle après le délai.
  def steps
    [
      ['Ouverture : outil actif, rien à créer', -> {}, ->(p) { p['status'] == 'Tracé actif' && !p['create_enabled'] && !p['clear_enabled'] && p['result'] == 'Aucun tracé.' && p['profiles'] == 3 }],
      ['Départ : point posé, pas d’écriture', lambda {
        @entities = model.entities.length
        @definitions = model.definitions.length
        click_at(10.0, 5.0)
      }, ->(p) { session.points.size == 1 && p['clear_enabled'] && !p['create_enabled'] && p['result'] == 'Tracé en cours.' && unchanged? }],
      ['Saisie 40;0 : segment exact au millimètre', -> { type('40;0') }, ->(p) { near?(relative, [[0, 0], [40, 0]]) && !p['create_enabled'] && p['result'].include?('Tracé en cours') && unchanged? }],
      ['Saisie 30;90 en mètres', -> { type('30;90') }, ->(_p) { near?(relative, [[0, 0], [40, 0], [40, 30]]) && unchanged? }],
      ['Parcelles dessinées, sans écriture', -> {}, ->(_p) { PANEL.controller.overlay[:rings].to_a.size > 3 && unchanged? && roots.empty? }],
      ['Saisie illisible : refusée, tracé intact', -> { type('abc') }, ->(_p) { session.points.size == 3 }],
      ['Saisie avec unité : 10m', lambda {
        type('10m;90')
      }, ->(_p) { near?(relative, [[0, 0], [40, 0], [40, 30], [40, 40]]) }],
      ['Ctrl : à droite, le panneau suit', -> { key(TOOL::KEY_CTRL) }, ->(p) { session.side == 'right' && p['side'] == 'right' && !p['street_shown'] }],
      ['Ctrl : des deux côtés, largeur de rue visible', -> { key(TOOL::KEY_CTRL) }, ->(p) { session.side == 'both' && p['side'] == 'both' && p['street_shown'] }],
      ['Ctrl : retour à gauche', -> { key(TOOL::KEY_CTRL) }, ->(p) { session.side == 'left' && p['side'] == 'left' }],
      ['Panneau : à droite, l’outil suit', -> { set_input('s-side', 'right') }, ->(_p) { session.side == 'right' }],
      ['Panneau : retour à gauche', -> { set_input('s-side', 'left') }, ->(_p) { session.side == 'left' }],
      ['Flèche droite : axe rouge bloqué', lambda {
        key(TOOL::KEY_RIGHT)
      }, ->(_p) { session.axis_lock == 'red' }],
      ['Clic bloqué : Y conservé', -> { click_at(90.0, 57.0) }, ->(_p) { (relative.last[1] - 40.0).abs <= MILLIMETRE && session.axis_lock.nil? }],
      ['Alt : quart de tour', lambda {
        key(TOOL::KEY_ALT)
        click_at(92.0, 90.0)
      }, ->(_p) { Math.hypot(relative.last[0] - relative[-2][0], 0.0) <= MILLIMETRE }],
      ['Alt : relâché', -> { key(TOOL::KEY_ALT) }, ->(_p) { !session.lock_90 }],
      ['Échap : tracé terminé, créer possible', -> { tool.onCancel(0, view) }, ->(p) { session.state == 'ready' && p['create_enabled'] && p['create'].start_with?('Créer ces ') && !p['summary_shown'] }],
      ['Changer le style recalcule, sans écriture', -> { set_input('s-profile', 'toulousain') }, ->(p) { p['create_enabled'] && p['profile'] == 'toulousain' && unchanged? }],
      ['Saisie invalide : créer bloqué', -> { set_input('s-depth', 'abc') }, ->(p) { !p['create_enabled'] && p['result'].include?('nombre') }],
      ['Profondeur hors limites : refus expliqué', -> { set_input('s-depth', '2') }, ->(p) { !p['create_enabled'] && p['summary_shown'] }],
      ['Profondeur corrigée', -> { set_input('s-depth', '9') }, ->(p) { p['create_enabled'] && !p['summary_shown'] }],
      ['Double clic sur Créer : un seul ensemble', lambda {
        @expected = PANEL.controller.state['result']['metrics']
        @origin = session.origin_m
        @points = session.relative_points
        click_dom('create')
        click_dom('create')
      }, lambda { |p|
        roots.size == 1 && session.empty? && p['status'].include?('bâtiments créés') && !p['create_enabled'] && model.selection.first == roots.first
      }],
      ['Racine au premier point, parcelles conformes', -> {}, lambda { |_p|
        root = roots.first
        o = root.transformation.origin
        Math.hypot((o.x * INCH) - @origin[0], (o.y * INCH) - @origin[1]) <= MILLIMETRE &&
          root.definition.entities.grep(Sketchup::ComponentInstance).size == @expected['parcel_count'] &&
          JSON.parse(root.get_attribute(DICTIONARY, 'ensemble_json')).dig('trace', 'points_m') == @points &&
          JSON.parse(root.get_attribute(DICTIONARY, 'ensemble_json')).dig('building', 'profile', 'id') == 'toulousain'
      }],
      ['Annuler : tout part en une fois', -> { Sketchup.undo }, ->(_p) { roots.empty? && model.entities.length == @entities }],
      ['Rétablir', -> { Sketchup.redo }, ->(_p) { roots.size == 1 }],
      ['L’outil reste actif pour une autre rue', -> { click_at(0.0, -40.0) }, ->(p) { session.points.size == 1 && p['status'] == 'Tracé actif' }],
      ['Segment trop court : refus expliqué', lambda {
        type('3;0')
        tool.onCancel(0, view)
      }, ->(p) { session.state == 'ready' && !p['create_enabled'] && p['summary_shown'] && p['summary'].include?('minimum') && p['result'].include?('ne peut pas') }],
      ['Effacer le tracé', -> { click_dom('clear') }, ->(p) { session.empty? && p['result'] == 'Aucun tracé.' && !p['summary_shown'] }],
      ['Forme fermée, porche trop haut : parcelles visibles, refus expliqué', lambda {
        set_input('s-access-height', '6')
        click_at(0.0, -80.0)
        type('40;0')
        type('40;90')
        type('40;180')
        first = session.points.first
        click_at(first[0], first[1])
      }, ->(p) { session.closed? && !p['create_enabled'] && p['summary_shown'] && p['summary'].include?('passage') && PANEL.controller.overlay[:refused] && PANEL.controller.overlay[:rings].size >= 12 }],
      ['Échap efface un tracé terminé', lambda {
        set_input('s-access-height', '2,7')
        tool.onCancel(0, view)
      }, ->(p) { session.empty? && !p['summary_shown'] }],
      ['Quitter l’outil : le panneau le dit', -> { model.select_tool(nil) }, ->(p) { p['status'] == 'Outil inactif' && p['resume_shown'] }],
      ['Reprendre le tracé', -> { click_dom('resume') }, ->(p) { p['status'] == 'Tracé actif' && !p['resume_shown'] && !tool.nil? }],
      ['Changer de document oublie le tracé', lambda {
        click_at(0.0, 0.0)
        type('30;0')
        @before_new = session.points.size
        model.save(WORK)
        Sketchup.file_new
        model.options['UnitsOptions']['LengthUnit'] = METERS
        frame
      }, ->(p) { @before_new == 2 && session.empty? && p['result'] == 'Aucun tracé.' }],
      ['Unités en pouces : la saisie les suit', lambda {
        model.options['UnitsOptions']['LengthUnit'] = 0
        click_at(0.0, 0.0)
        type('100;0')
        model.options['UnitsOptions']['LengthUnit'] = METERS
      }, ->(_p) { near?(relative, [[0, 0], [100 * INCH, 0]]) }],
      ['Fermer le panneau quitte l’outil et oublie le tracé', -> { dialog.close }, nil],
      ['Rouvrir, puis tracer et créer', lambda {
        PANEL.show
        attach_probe
      }, nil],
      ['Après réouverture : tracé vide, outil actif', -> {}, ->(p) { session.empty? && p['result'] == 'Aucun tracé.' && p['status'] == 'Tracé actif' }],
      ['Deuxième création après réouverture', lambda {
        PANEL.show
        click_at(0.0, 0.0)
        type('36;0')
        tool.onCancel(0, view)
      }, ->(p) { p['create_enabled'] }],
      ['Créer écrit vraiment', -> { click_dom('create') }, ->(_p) { roots.size == 1 && session.empty? }],
      ['Fermer de nouveau', -> { dialog.close }, nil]
    ]
  end

  # Vue de dessus : tous les points visés restent à l'écran, à une précision utile.
  def frame
    view.camera = Sketchup::Camera.new(Geom::Point3d.new(40.m, -10.m, 400.m), Geom::Point3d.new(40.m, -10.m, 0), Geom::Vector3d.new(0, 1, 0))
  end

  def unchanged?
    model.entities.length == @entities && model.definitions.length == @definitions
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
      check(label, false, "#{e.class} #{e.message}")
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
      check("action #{label}", false, "#{e.class} #{e.message} #{e.backtrace.first(2).join(' | ')}")
    end
    @current = [label, check_block]
    if check_block
      UI.start_timer(DELAY_S, false) { js(SNAPSHOT) }
    else
      log("FAIT  #{label}")
      UI.start_timer(DELAY_S * 2, false) { advance }
    end
  end

  def finish
    log("FIN #{@failures} echec(s), ARCHGEN #{Archgen::VERSION}, SketchUp #{Sketchup.version}, Ruby #{RUBY_VERSION}")
  end

  def run
    @lines = []
    @failures = 0
    model.options['UnitsOptions']['LengthUnit'] = METERS
    frame
    @queue = steps
    PANEL.show
    attach_probe
    log("H16 départ #{Time.now}, ARCHGEN #{Archgen::VERSION}")
    UI.start_timer(2.5, false) { advance }
    'recette lancee'
  end
end
