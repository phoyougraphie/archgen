# frozen_string_literal: true

require 'json'

# Recette H17, à lancer sur un document neuf, panneaux fermés :
#   load '.../test/host/h17.rb'; ArchgenH17Probe.run
# Parcours rue et îlot : rue d'un côté, rue des deux côtés, îlot par interruption, îlot par
# porche, modifier, Annuler, enregistrer et rouvrir. Vrai outil, vrai panneau par son DOM.
# Le vrai copier-coller et le vrai geste souris se font à part. Rapport : tmp/h17.txt.
module ArchgenH17Probe
  REPO = File.expand_path('../..', __dir__)
  REPORT = File.join(REPO, 'tmp', 'h17.txt')
  COPY_REPORT = File.join(REPO, 'tmp', 'h17-copie.txt')
  SKP = File.join(REPO, 'tmp', 'h17.skp')
  PANEL = Archgen::UI::StreetPanel
  SP = Archgen::Adapters::SketchUp
  TOOL = SP::StreetTool
  INCH = 0.0254
  DICTIONARY = 'archgen.ensemble'
  DELAY_S = 1.3
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
        title: byId('title').textContent, status: byId('status').textContent, result: byId('result').textContent,
        create: byId('create').textContent, create_enabled: !byId('create').disabled,
        reload_shown: !byId('reload').hidden, warning_shown: !byId('replace-warning').hidden, access_shown: !byId('s-access-fields').hidden,
        summary_shown: !byId('summary').hidden, summary: byId('summary-list').textContent,
        profile: byId('s-profile').value, mode: byId('s-mode').value, depth: byId('s-depth').value, side: byId('s-side').value,
        access_count: byId('s-access-count').value, access_height: byId('s-access-height').value
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

  def root_at(origin)
    # Un clic dans la vue n'est précis qu'à un pixel : ici, environ un mètre.
    roots.find { |r| (r.transformation.origin.x * INCH - origin[0]).abs < 2.0 && (r.transformation.origin.y * INCH - origin[1]).abs < 2.0 }
  end

  def settings_of(root)
    JSON.parse(root.get_attribute(DICTIONARY, 'ensemble_json'))
  end

  def parcels_of(root)
    root.definition.entities.grep(Sketchup::ComponentInstance)
  end

  def deep_faces(entities, memo = {})
    entities.sum do |entity|
      case entity
      when Sketchup::Face then 1
      when Sketchup::Group then deep_faces(entity.entities, memo)
      when Sketchup::ComponentInstance then memo[entity.definition] ||= deep_faces(entity.definition.entities, memo)
      else 0
      end
    end
  end

  def frame
    view.camera = Sketchup::Camera.new(Geom::Point3d.new(120.m, 60.m, 700.m), Geom::Point3d.new(120.m, 60.m, 0), Geom::Vector3d.new(0, 1, 0))
  end

  def click_at(x_m, y_m)
    point = view.screen_coords(Geom::Point3d.new(x_m / INCH, y_m / INCH, 0))
    tool.onMouseMove(0, point.x, point.y, view)
    tool.onLButtonDown(0, point.x, point.y, view)
  end

  def type(text)
    tool.onUserText(text, view)
  end

  def trace_open(x, y, *typed)
    session.clear
    click_at(x, y)
    typed.each { |t| type(t) }
    tool.onCancel(0, view)
  end

  def trace_square(x, y, side)
    session.clear
    click_at(x, y)
    %W[#{side};0 #{side};90 #{side};180].each { |t| type(t) }
    first = session.points.first
    click_at(first[0], first[1])
  end

  # Faces réelles = plan annoncé, et comptes attendus, relus dans le modèle.
  def written_ok?(root, parcels, accesses, panel)
    stored = settings_of(root)
    computed = SP::EnsembleService.default.preview(tree: stored).value
    metrics = computed.plan['metrics']
    metrics['parcel_count'] == parcels && metrics['access_count'] == accesses && parcels_of(root).size == parcels &&
      deep_faces(root.definition.entities) == metrics['expanded_face_count'] && root.get_attribute(DICTIONARY, 'ensemble_digest') == computed.ensemble_digest &&
      panel['status'].include?("#{parcels} bâtiments créés")
  end

  def steps
    [
      ['Rue d’un côté : valeurs annoncées', lambda {
        set_input('s-profile', 'haussmann')
        trace_open(0.0, 0.0, '60;0')
      }, ->(p) { p['create_enabled'] && p['create'] == 'Créer ces 5 bâtiments' && p['result'].start_with?('5 bâtiments') && !p['access_shown'] }],
      ['Rue d’un côté : écrite', -> { click_dom('create') }, ->(p) { written_ok?(root_at([0.0, 0.0]), 5, 0, p) }],
      ['Rue des deux côtés : réglages', lambda {
        set_input('s-profile', 'toulousain')
        set_input('s-side', 'both')
        set_input('s-street', '14')
        trace_open(0.0, 40.0, '60;0')
      }, ->(p) { p['create'] == 'Créer ces 10 bâtiments' && p['side'] == 'both' }],
      ['Rue des deux côtés : écrite, façades à 14 m', -> { click_dom('create') }, lambda { |p|
        root = root_at([0.0, 40.0])
        settings_of(root).dig('layout', 'street_width_m') == 14.0 && written_ok?(root, 10, 0, p)
      }],
      ['Côté remis à gauche', -> { set_input('s-side', 'left') }, ->(_p) { session.side == 'left' }],
      ['Îlot par interruption : 3 accès annoncés', lambda {
        set_input('s-profile', 'brutalist')
        trace_square(100.0, 0.0, 40)
      }, ->(p) { session.closed? && p['access_shown'] && p['create_enabled'] && p['result'].include?('3 accès') && p['create'] == 'Créer ces 9 bâtiments' }],
      ['Îlot par interruption : écrit', -> { click_dom('create') }, ->(p) { written_ok?(root_at([100.0, 0.0]), 9, 3, p) }],
      ['Îlot par porche : 3 accès annoncés', lambda {
        set_input('s-profile', 'haussmann')
        set_input('s-mode', 'structural')
        set_input('s-lod', '1')
        trace_square(160.0, 0.0, 40)
      }, ->(p) { p['access_shown'] && p['create_enabled'] && p['result'].include?('3 accès') && p['create'] == 'Créer ces 12 bâtiments' }],
      ['Îlot par porche : écrit', -> { click_dom('create') }, ->(p) { written_ok?(root_at([160.0, 0.0]), 12, 3, p) }],
      ['Porche trop haut : refus expliqué, rien à créer', lambda {
        set_input('s-access-height', '4')
        trace_square(160.0, 60.0, 40)
      }, ->(p) { !p['create_enabled'] && p['summary_shown'] && p['summary'].include?('passage') && roots.size == 4 }],
      ['Nombre d’accès choisi', lambda {
        set_input('s-access-height', '2,7')
        set_input('s-access-count', '1')
      }, ->(p) { p['create_enabled'] && p['result'].include?('1 accès') }],
      ['Trace oubliée avant la suite', lambda {
        set_input('s-access-count', 'auto')
        click_dom('clear')
      }, ->(_p) { session.empty? }],
      ['Modifier sans sélection : refus expliqué', lambda {
        model.selection.clear
        PANEL.show('edit')
      }, ->(p) { p['title'] == 'Modifier un ensemble' && p['status'] == 'Aucun ensemble chargé' && p['reload_shown'] && !p['create_enabled'] && p['summary_shown'] }],
      ['Outil quitté en modification', -> {}, ->(_p) { tool.nil? }],
      ['Recharger l’îlot : réglages relus, rien à remplacer', lambda {
        @edited = root_at([160.0, 0.0])
        @edited_definition = @edited.definition
        @edited_matrix = @edited.transformation.to_a
        @edited_pid = @edited.persistent_id
        model.selection.clear
        model.selection.add(@edited)
        click_dom('reload')
      }, ->(p) { p['status'] == 'Révision 1' && p['profile'] == 'haussmann' && p['mode'] == 'structural' && p['depth'] == '9' && p['access_shown'] && !p['create_enabled'] && p['warning_shown'] && p['result'].include?('Aucun changement') }],
      ['Profondeur changée : remplacement proposé, pas d’écriture', -> { set_input('s-depth', '8') }, ->(p) { p['create_enabled'] && p['create'] == 'Remplacer cet ensemble' && @edited.definition == @edited_definition }],
      ['Quitter le champ ne désactive pas le bouton', -> { js("document.getElementById('s-depth').dispatchEvent(new Event('change',{bubbles:true}));") }, ->(p) { p['create_enabled'] }],
      ['Remplacer : même racine, même placement', -> { click_dom('create') }, lambda { |p|
        p['status'].include?('Révision 2') && roots.size == 4 && @edited.persistent_id == @edited_pid && @edited.transformation.to_a == @edited_matrix &&
          @edited.definition != @edited_definition && settings_of(@edited).dig('parcel', 'depth_m') == 8.0 && settings_of(@edited).dig('access', 'count') == 'auto'
      }],
      ['Annuler : tout revient en une fois', -> { Sketchup.undo }, ->(_p) { @edited.definition == @edited_definition && @edited.get_attribute(DICTIONARY, 'revision') == 1 && settings_of(@edited).dig('parcel', 'depth_m') == 9.0 }],
      ['Après Annuler : remplacer est refusé, cible périmée', lambda {
        set_input('s-depth', '7')
      }, ->(p) { p['create_enabled'] }],
      ['Refus sans écriture', -> { click_dom('create') }, ->(p) { p['status'] == 'Remplacement refusé' && p['summary_shown'] && @edited.definition == @edited_definition }],
      ['Recharger après le refus', -> { click_dom('reload') }, ->(p) { p['status'] == 'Révision 1' && !p['summary_shown'] }],
      ['Un bâtiment seul refusé en modification d’ensemble', lambda {
        built = SP::BuildingService.default.create(model: model, draft: { 'schema_version' => 1, 'profile' => { 'id' => 'haussmann' } })
        @lone = model.entities.grep(Sketchup::ComponentInstance).find { |i| i.persistent_id == built.value.persistent_id }
        model.selection.clear
        model.selection.add(@lone)
        click_dom('reload')
      }, ->(p) { p['status'] == 'Aucun ensemble chargé' && p['summary_shown'] }],
      ['Le panneau de bâtiment refuse l’ensemble', lambda {
        model.selection.clear
        model.selection.add(@edited)
      }, ->(_p) { SP::BuildingService.default.load_selection(model: model).errors.first&.params&.fetch('reason') == 'not_an_archgen_root' }],
      ['Enregistrer et rouvrir', lambda {
        @kept = roots.to_h { |r| [r.persistent_id, [r.get_attribute(DICTIONARY, 'ensemble_digest'), deep_faces(r.definition.entities)]] }
        model.save(SKP)
        Sketchup.open_file(SKP)
      }, ->(_p) { roots.size == 4 }],
      ['Après réouverture : mêmes faces, mêmes empreintes recalculées', -> {}, lambda { |_p|
        service = SP::EnsembleService.default
        roots.all? do |r|
          digest, faces = @kept.fetch(r.persistent_id)
          service.preview(tree: settings_of(r)).value.ensemble_digest == digest && deep_faces(r.definition.entities) == faces
        end
      }],
      ['Après réouverture : modifier reste possible', lambda {
        @edited = roots.find { |r| settings_of(r).dig('building', 'profile', 'id') == 'brutalist' }
        model.selection.clear
        model.selection.add(@edited)
        PANEL.show('edit')
      }, ->(p) { p['status'] == 'Révision 1' && p['profile'] == 'brutalist' }],
      ['Remplacer après réouverture', lambda {
        set_input('s-access-count', '2')
        UI.start_timer(0.8, false) { click_dom('create') }
      }, ->(_p) { @edited.get_attribute(DICTIONARY, 'revision') == 2 && parcels_of(@edited).size == 10 }],
      ['Retour au tracé depuis la modification', -> { PANEL.show('new') }, ->(p) { p['title'] == 'Tracer une rue' && p['status'] == 'Tracé actif' && !p['warning_shown'] && !tool.nil? }],
      ['Fermer', -> { dialog.close }, nil]
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
    PANEL.show('new')
    attach_probe
    log("H17 départ #{Time.now}, ARCHGEN #{Archgen::VERSION}")
    UI.start_timer(2.5, false) { advance }
    'recette lancee'
  end

  # --- Vrai copier-coller : Édition > Copier, Édition > Coller sur place.

  def prepare_copy
    tree = { 'trace' => { 'points_m' => [[0, 0], [40, 0], [40, 40], [0, 40]], 'closed' => true }, 'building' => { 'profile' => { 'id' => 'toulousain' } } }
    result = SP::EnsembleService.default.create(model: model, tree: tree, origin_m: [0.0, 0.0, 0.0])
    @original = model.entities.grep(Sketchup::ComponentInstance).find { |i| i.persistent_id == result.value.persistent_id }
    model.selection.clear
    model.selection.add(@original)
    File.binwrite(COPY_REPORT, "ATTENTE copie\n")
  end

  def copy_done?
    model.selection.length == 1 && model.selection.first != @original
  end

  def after_copy
    lines = []
    note = lambda { |label, ok| lines << "#{ok ? 'OK   ' : 'ECHEC'} #{label}" }
    copy = model.selection.first
    shared = @original.definition
    faces = deep_faces(shared.entities)
    note.call('Copie réelle : même définition', copy.definition == shared)
    note.call('Copie réelle : attributs recopiés', copy.get_attribute(DICTIONARY, 'ensemble_digest') == @original.get_attribute(DICTIONARY, 'ensemble_digest'))
    note.call('Copie réelle : autre racine', copy.persistent_id != @original.persistent_id)
    service = SP::EnsembleService.default
    loaded = service.load_selection(model: model)
    note.call('Copie réelle : relue', loaded.ok?)
    written = service.regenerate(model: model, target: loaded.value.target, changes: { 'parcel' => { 'depth_m' => 8.0 } })
    note.call('Copie régénérée', written.ok?)
    note.call('Original intact', @original.definition == shared && deep_faces(shared.entities) == faces)
    note.call('Copie isolée', copy.definition != shared)
    note.call('Réglages de l’original intacts', JSON.parse(@original.get_attribute(DICTIONARY, 'ensemble_json')).dig('parcel', 'depth_m') == 9.0)
    File.binwrite(COPY_REPORT, "#{lines.join("\n")}\nFIN\n")
  end
end
