# frozen_string_literal: true

require 'json'

# Recette H14, à lancer sur un modèle neuf, panneau fermé :
#   load '.../test/host/survey.rb'; load '.../test/host/h14.rb'; ArchgenH14Probe.run
# Parcours Terrain dans le vrai panneau par son DOM ; sélection, Annuler et Rétablir par l'API, donc
# par les vrais observateurs. Puis charge sur un terrain de 100 000 faces. Rapport : tmp/h14.txt.
# Limite : un clic DOM n'est pas un clic souris.
module ArchgenH14Probe
  REPO = File.expand_path('../..', __dir__)
  TMP = File.join(REPO, 'tmp')
  REPORT = File.join(TMP, 'h14.txt')
  SKP = File.join(TMP, 'h14.skp')
  LOAD_SKP = File.join(TMP, 'h14-charge.skp')
  SP = Archgen::Adapters::SketchUp
  TERRAIN = ArchgenSurveyProbe
  INCH = 0.0254
  DELAY_S = 1.8
  CYCLE_S = 2.0
  LOAD_CELLS = 224
  LOAD_SIZE_M = 224.0

  SNAPSHOT = <<~JS
    (function () {
      function byId(id) { return document.getElementById(id); }
      function shown(id) { return !byId(id).hidden; }
      function on(id) { return !byId(id).disabled; }
      sketchup.archgen_probe(JSON.stringify({
        title: byId('title').textContent, status: byId('status').textContent, write_enabled: on('generate'),
        terrain_shown: shown('terrain'), site_state: byId('site-state').textContent,
        retain: on('site-retain'), survey: on('site-survey'), adapt: on('site-adapt'), remove: on('site-remove'), ratio_shown: shown('site-ratio'),
        summary: shown('summary') ? byId('summary-list').textContent : '', site_summary: byId('site-summary').textContent,
        site_warnings: byId('site-warnings').textContent, confirm: shown('confirm'),
        confirm_message: byId('confirm-message').textContent, confirm_lines: byId('confirm-changes').textContent,
        earthwork: byId('f-earthwork').value, offset: byId('f-offset').value, offset_invalid: byId('f-offset').classList.contains('is-invalid'),
        offset_error: (byId('f-offset').closest('.field').querySelector('.error') || {}).textContent || '', width: byId('f-width').value,
        reload: shown('reload')
      }));
    })();
  JS

  module_function

  def model
    Sketchup.active_model
  end

  def dialog
    Archgen::UI::Panel.instance_variable_get(:@dialog)
  end

  def js(script)
    Archgen::UI::Panel.send_script(script)
  end

  def click(*ids)
    js(ids.map { |id| "document.getElementById('#{id}').click();" }.join)
  end

  def set_input(id, value)
    js("var f = document.getElementById('#{id}'); f.value = #{value.to_json}; f.dispatchEvent(new Event('input', {bubbles: true}));")
  end

  def set_select(id, value)
    js("var s = document.getElementById('#{id}'); s.value = #{value.to_json}; s.dispatchEvent(new Event('change', {bubbles: true}));")
  end

  def roots
    model.entities.grep(Sketchup::ComponentInstance).select { |i| i.get_attribute('archgen.building', 'revision') }
  end

  def root
    roots.first
  end

  def terrain
    model.entities.grep(Sketchup::Group).find { |g| g.name == 'Terrain H13' }
  end

  def select(entity)
    model.selection.clear
    model.selection.add(entity)
  end

  def model_state
    r = root
    return { roots: 0 } unless r

    {
      roots: roots.size, revision: r.get_attribute('archgen.building', 'revision'), z: (r.transformation.to_a[14] * INCH).round(4),
      site: !r.attribute_dictionary('archgen.site').nil?, width: JSON.parse(r.get_attribute('archgen.building', 'config_json'))['footprint']['width_m'],
      earthwork: r.get_attribute('archgen.site', 'site_json')&.then { |text| JSON.parse(text)['earthwork'] }, selected: model.selection.length
    }
  end

  def move_root_onto_terrain
    place = Geom::Point3d.new(TERRAIN.m(24.0), TERRAIN.m(22.0), 0).transform(terrain.transformation)
    model.start_operation('Placement H14', true)
    root.transformation = Geom::Transformation.translation([place.x, place.y, 0]) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, 30.degrees)
    model.commit_operation
  end

  def steps
    [
      ['Mode Nouveau : pas de section Terrain', -> {}, ->(p, m) { !p['terrain_shown'] && p['title'] == 'Nouveau bâtiment' && m[:roots].zero? }],
      ['Générer : section Terrain visible, rien à relever', -> { click('generate') },
       ->(p, m) { p['terrain_shown'] && p['site_state'] == 'Aucun terrain retenu.' && !p['survey'] && !p['adapt'] && !p['remove'] && p['retain'] && m[:revision] == 1 }],
      ['Bâtiment placé sur le terrain', -> { move_root_onto_terrain }, ->(p, m) { p['write_enabled'] && m[:revision] == 1 }],
      ['Retenir le bâtiment : refusé et expliqué', -> { click('site-retain') }, ->(p, m) { p['summary'].include?('ne peut pas servir de terrain') && p['site_state'] == 'Aucun terrain retenu.' && m[:revision] == 1 }],
      ['Sélectionner le terrain : cible périmée', -> { select(terrain) }, ->(p, _m) { !p['write_enabled'] && p['status'] == 'Cible périmée' && p['retain'] && !p['survey'] && p['site_state'].start_with?('Rechargez') }],
      ['Retenir ce terrain', -> { click('site-retain') }, ->(p, _m) { p['site_state'].start_with?('Terrain retenu') && p['summary'].include?('Sélectionnez de nouveau le bâtiment') && !p['survey'] }],
      ['Resélectionner et recharger : terrain gardé', lambda {
        select(root)
        click('reload')
      }, ->(p, _m) { p['site_state'].start_with?('Terrain retenu') && p['survey'] && !p['adapt'] && p['write_enabled'] && p['summary'].empty? }],
      ['Décalage invalide : relever bloqué', -> { set_input('f-offset', 'abc') }, ->(p, m) { p['offset_invalid'] && !p['survey'] && m[:revision] == 1 }],
      ['Décalage hors limites : refusé sous le champ', lambda {
        set_input('f-offset', '5')
        click('site-survey')
      }, ->(p, m) { p['offset_error'].include?('maximale') && p['offset_invalid'] && !p['adapt'] && m[:revision] == 1 }],
      ['Décalage corrigé, relever', lambda {
        set_input('f-offset', '0')
        click('site-survey')
      }, ->(p, m) { p['status'] == 'Relevé prêt' && p['site_summary'].include?('Altitude de la plateforme') && p['site_warnings'].include?('aucun escalier') && p['adapt'] && m[:revision] == 1 && !m[:site] }],
      ['Adapter : confirmation avec les valeurs', -> { click('site-adapt') }, ->(p, m) { p['confirm'] && p['confirm_message'].include?('Le terrain n’est pas modifié') && p['confirm_lines'].include?('Remblai maximal') && m[:revision] == 1 }],
      ['Annuler la confirmation : aucune écriture', -> { click('confirm-no') }, ->(p, m) { !p['confirm'] && !p['adapt'] && p['survey'] && m[:revision] == 1 && !m[:site] }],
      ['Relever de nouveau', -> { click('site-survey') }, ->(p, _m) { p['adapt'] && p['status'] == 'Relevé prêt' }],
      ['Adapter, puis Remplacer en deux clics', lambda {
        click('site-adapt')
        click('confirm-yes', 'confirm-yes')
      }, lambda { |p, m|
        @platform = m[:z]
        m[:revision] == 2 && m[:site] && m[:z] > 5.0 && m[:roots] == 1 && p['site_state'] == 'Ce bâtiment est adapté au terrain.' && p['remove'] && !p['confirm'] && p['status'].start_with?('Bâtiment adapté au terrain')
      }],
      ['Annuler natif : tout revient', -> { Sketchup.undo }, ->(p, m) { m[:revision] == 1 && !m[:site] && m[:z].abs < 1e-3 && p['status'] == 'Cible périmée' && !p['survey'] && !p['remove'] && p['site_state'].start_with?('Terrain retenu') }],
      ['Recharger après Annuler', -> { click('reload') }, ->(p, m) { m[:revision] == 1 && p['site_state'].start_with?('Terrain retenu') && p['survey'] }],
      ['Rétablir natif', -> { Sketchup.redo }, ->(p, m) { m[:revision] == 2 && m[:site] && p['status'] == 'Cible périmée' }],
      ['Recharger après Rétablir', -> { click('reload') }, ->(p, m) { m[:site] && p['site_state'] == 'Ce bâtiment est adapté au terrain.' && p['remove'] }],
      ['Régénérer à 14 m : confirmation qui parle de l’assise', lambda {
        set_input('f-width', '14')
        UI.start_timer(1.0, false) { click('generate') }
      }, ->(p, m) { p['confirm'] && p['confirm_message'].include?('Son assise est conservée') && m[:revision] == 2 }],
      ['Remplacer : assise suivie', -> { click('confirm-yes') }, ->(p, m) { m[:revision] == 3 && m[:width] == 14.0 && m[:site] && p['site_state'] == 'Ce bâtiment est adapté au terrain.' }],
      ['Déplacer le bâtiment puis recharger : assise périmée', lambda {
        model.start_operation('Déplacement H14', true)
        root.transform!(Geom::Transformation.translation([TERRAIN.m(3.0), TERRAIN.m(2.0), 0]))
        model.commit_operation
        select(root)
        click('reload')
      }, ->(p, _m) { p['site_state'].start_with?('Assise périmée') && p['survey'] }],
      ['Relever sans retenir : terrain enregistré', -> { click('site-survey') }, ->(p, _m) { p['status'] == 'Relevé prêt' && p['adapt'] }],
      ['Passer au talus : pente affichée, relevé oublié', -> { set_select('f-earthwork', 'embankment') }, ->(p, _m) { p['ratio_shown'] && !p['adapt'] && p['site_summary'].empty? }],
      ['Relever avec un talus', -> { click('site-survey') }, ->(p, _m) { p['site_summary'].include?('Emprise du talus') && p['adapt'] }],
      ['Confirmation expirée : refus sans écriture', lambda {
        Archgen::UI::Panel.controller.site_confirmations.clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) + 121 }
        click('site-adapt')
        click('confirm-yes')
      }, ->(p, m) { m[:revision] == 3 && m[:earthwork] == 'plinth' && p['summary'].include?('expiré') }],
      ['Heure rétablie, relever, adapter, remplacer', lambda {
        Archgen::UI::Panel.controller.site_confirmations.clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        click('site-survey')
        UI.start_timer(0.8, false) do
          click('site-adapt')
          click('confirm-yes')
        end
      }, ->(p, m) { m[:revision] == 4 && m[:earthwork] == 'embankment' && p['site_state'] == 'Ce bâtiment est adapté au terrain.' && p['earthwork'] == 'embankment' }],
      ['Enregistrer : réglages et assise gardés', -> { model.save(SKP) }, ->(p, m) { p['write_enabled'] && p['site_state'] == 'Ce bâtiment est adapté au terrain.' && p['survey'] && m[:site] && p['earthwork'] == 'embankment' }],
      ['Relever après enregistrement', -> { click('site-survey') }, ->(p, _m) { p['status'] == 'Relevé prêt' }],
      ['Terrain masqué : relever refusé', lambda {
        terrain.hidden = true
        click('site-survey')
      }, ->(p, m) { p['summary'].include?('masqué') && !p['adapt'] && m[:revision] == 4 }],
      ['Terrain affiché, retirer : confirmation', lambda {
        terrain.hidden = false
        click('site-remove')
      }, ->(p, m) { p['confirm'] && p['confirm_message'].include?('Son altitude ne change pas') && m[:site] }],
      ['Annuler le retrait', -> { click('confirm-no') }, ->(p, m) { !p['confirm'] && m[:site] && m[:revision] == 4 }],
      ['Retirer pour de bon', lambda {
        @before_remove = model_state[:z]
        click('site-remove')
        UI.start_timer(0.8, false) { click('confirm-yes') }
      }, ->(p, m) { !m[:site] && m[:revision] == 5 && m[:z] == @before_remove && !p['remove'] && p['status'].start_with?('Assise retirée') }],
      ['Fermer le panneau', -> { dialog.close }, nil]
    ]
  end

  def log(line)
    @lines << line
    File.binwrite(REPORT, "#{@lines.join("\n")}\n")
  end

  def attach_probe
    dialog.add_action_callback('archgen_probe') { |_context, text| receive(JSON.parse(text)) }
  end

  def receive(panel)
    label, check = @current
    state = model_state
    ok = check.call(panel, state)
    @failures += 1 unless ok
    log("#{ok ? 'OK   ' : 'ECHEC'} #{label}")
    log("      panneau #{panel.reject { |k, _| %w[title reload].include?(k) }}\n      modele  #{state}") unless ok
    advance
  rescue StandardError => e
    @failures += 1
    log("ECHEC #{label} : #{e.class} #{e.message}")
    advance
  end

  def advance
    step = @queue.shift
    return UI.start_timer(DELAY_S, false) { session_cycle(2) } unless step

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

  def timed
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    value = yield
    [value, ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round]
  end

  # La fermeture vide la mémoire des réponses à chaque ouverture, pas seulement à la première.
  def session_cycle(remaining)
    return load_test if remaining.zero?

    Archgen::UI::Panel.show('new')
    UI.start_timer(CYCLE_S, false) do
      memory = Archgen::UI::Panel.controller.instance_variable_get(:@mutations)
      memory['temoin'] = {}
      dialog.close
      UI.start_timer(CYCLE_S, false) do
        ok = !memory.key?('temoin')
        @failures += 1 unless ok
        log("#{ok ? 'OK   ' : 'ECHEC'} Fermeture #{3 - remaining} : réponses mémorisées oubliées")
        session_cycle(remaining - 1)
      end
    end
  end

  # Terrain de 100 352 triangles : le relevé et l'écriture restent-ils utilisables ?
  def load_test
    model.save(SKP)
    Sketchup.file_new
    build = nil
    outer, build = timed { build_large_terrain }
    faces = outer.entities.grep(Sketchup::Face).size
    log("MESURE charge : terrain de #{faces} faces construit en #{build} ms")
    service = SP::BuildingService.default(allow_internal: true)
    ref = SP::TerrainRef.new(document_key: model.guid, persistent_id: outer.persistent_id)
    [
      ['Haussmann 12 x 9, soubassement, pas de 2 m', { 'profile' => { 'id' => 'haussmann' }, 'name' => 'Charge', 'lod' => 1, 'footprint' => { 'width_m' => 12.0, 'depth_m' => 9.0 } }, {}],
      ['Haussmann 12 x 9, talus, pas de 2 m', { 'profile' => { 'id' => 'haussmann' }, 'name' => 'Charge', 'lod' => 1, 'footprint' => { 'width_m' => 12.0, 'depth_m' => 9.0 } }, { 'earthwork' => 'embankment' }],
      ['Haussmann 12 x 9, soubassement, pas de 0,5 m', { 'profile' => { 'id' => 'haussmann' }, 'name' => 'Charge', 'lod' => 1, 'footprint' => { 'width_m' => 12.0, 'depth_m' => 9.0 } }, { 'survey' => { 'step_m' => 0.5 } }],
      ['Plus grand bâtiment, soubassement, pas de 2 m', { 'profile' => { 'id' => 'toulousain' }, 'name' => 'Charge', 'mode' => 'structural', 'lod' => 1, 'footprint' => { 'width_m' => 60.0, 'depth_m' => 60.0 },
                                                          'levels' => { 'count' => 15, 'height_m' => 4.0 }, 'facade' => { 'front_bays' => 12, 'side_bays' => 12, 'margin_m' => 0.6, 'window_width_m' => 1.2, 'window_height_m' => 1.8, 'door_width_m' => 1.0 } }, {}],
      ['Plus grand bâtiment, talus, pas de 2 m', { 'profile' => { 'id' => 'toulousain' }, 'name' => 'Charge', 'mode' => 'structural', 'lod' => 1, 'footprint' => { 'width_m' => 60.0, 'depth_m' => 60.0 },
                                                   'levels' => { 'count' => 15, 'height_m' => 4.0 }, 'facade' => { 'front_bays' => 12, 'side_bays' => 12, 'margin_m' => 0.6, 'window_width_m' => 1.2, 'window_height_m' => 1.8, 'door_width_m' => 1.0 } }, { 'earthwork' => 'embankment' }]
    ].each { |label, draft, site| load_case(service, ref, label, { 'schema_version' => 1 }.merge(draft), site) }
    model.save(LOAD_SKP)
    log("MESURE charge : fichier de #{File.size(LOAD_SKP)} octets")
    finish
  rescue StandardError => e
    @failures += 1
    log("ECHEC charge : #{e.class} #{e.message} #{e.backtrace.first(3).join(' | ')}")
    finish
  end

  def load_case(service, ref, label, draft, site)
    created = service.create(model: model, draft: draft)
    return log("ECHEC #{label} : création #{created.errors.map(&:to_h)}") unless created.ok?

    instance = model.find_entity_by_persistent_id(created.value.persistent_id)
    model.start_operation('Placement charge', true)
    instance.transformation = Geom::Transformation.translation([TERRAIN.m(LOAD_SIZE_M / 2.0), TERRAIN.m(LOAD_SIZE_M / 2.0), 0])
    model.commit_operation
    select(instance)
    target = service.load_selection(model: model).value.target
    preview, survey_ms = timed { service.preview_site(model: model, target: target, terrain: ref, site: site) }
    unless preview.ok?
      @failures += 1
      return log("ECHEC #{label} : aperçu #{preview.errors.map(&:to_h).first}")
    end
    grid = preview.value.survey.grid
    written, write_ms = timed { service.adapt_to_site(model: model, target: target, terrain: ref, site: site, survey_digest: preview.value.survey.survey_digest) }
    ok = written.ok?
    @failures += 1 unless ok
    log("#{ok ? 'OK   ' : 'ECHEC'} #{label} : #{grid.xs.size * grid.ys.size} nœuds, aperçu #{survey_ms} ms, adaptation #{write_ms} ms, #{preview.value.site_plan['metrics']['site_face_count']} faces d’assise#{ok ? '' : " #{written.errors.map(&:to_h).first}"}")
    model.start_operation('Retrait charge', true)
    instance.erase!
    model.commit_operation
  end

  def build_large_terrain
    outer = model.entities.add_group
    outer.name = 'Terrain H14'
    step = LOAD_SIZE_M / LOAD_CELLS
    mesh = Geom::PolygonMesh.new((LOAD_CELLS + 1)**2, 2 * (LOAD_CELLS**2))
    points = Array.new(LOAD_CELLS + 1) do |i|
      Array.new(LOAD_CELLS + 1) do |j|
        x = i * step
        y = j * step
        mesh.add_point(Geom::Point3d.new(TERRAIN.m(x), TERRAIN.m(y), TERRAIN.m(TERRAIN.height(x / 4.0, y / 4.0))))
      end
    end
    LOAD_CELLS.times do |i|
      LOAD_CELLS.times do |j|
        mesh.add_polygon(points[i][j], points[i + 1][j], points[i + 1][j + 1])
        mesh.add_polygon(points[i][j], points[i + 1][j + 1], points[i][j + 1])
      end
    end
    outer.entities.add_faces_from_mesh(mesh, Geom::PolygonMesh::HIDE_BASED_ON_INDEX)
    outer
  end

  def finish
    log("FIN #{@failures} echec(s), ARCHGEN #{Archgen::VERSION}, SketchUp #{Sketchup.version}, Ruby #{RUBY_VERSION}")
  end

  def run
    @lines = []
    @failures = 0
    TERRAIN.build_terrain.tap { |outer| outer.name = 'Terrain H13' }
    @queue = steps
    Archgen::UI::Panel.show('new')
    attach_probe
    js('location.reload();')
    UI.start_timer(3.0, false) { advance }
    'recette lancee'
  end
end
