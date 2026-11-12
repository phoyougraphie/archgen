# frozen_string_literal: true

# Sonde native de la recette H09, chargée dans la console pendant que le panneau est ouvert.
#   ArchgenPanelProbe.snapshot            relève le modèle
#   ArchgenPanelProbe.hold                retient les réponses envoyées au panneau
#   ArchgenPanelProbe.release_reversed    les rend de la plus récente à la plus ancienne
#   ArchgenPanelProbe.compare             compare le modèle au relevé
#   ArchgenPanelProbe.make_target         crée et sélectionne un bâtiment à modifier
#   ArchgenPanelProbe.run_js_tests        exécute test/js dans le moteur du panneau
module ArchgenPanelProbe
  REPO = File.expand_path('../..', __dir__)
  REPORT = File.join(REPO, 'tmp', 'h09.txt')
  @held = []
  @lines = []

  module_function

  def state
    model = Sketchup.active_model
    {
      entities: model.entities.length,
      definitions: model.definitions.count,
      materials: model.materials.count,
      layers: model.layers.count,
      selection: model.selection.length,
      modified: model.modified?
    }
  end

  # Relevé lisible de la recette H10 : racines ARCHGEN, révisions, définitions de bâtiment.
  def roots(label)
    model = Sketchup.active_model
    list = model.entities.grep(Sketchup::ComponentInstance).select { |i| i.get_attribute('archgen.building', 'revision') }
    detail = list.map do |i|
      config = JSON.parse(i.get_attribute('archgen.building', 'config_json'))
      "#{i.name} rev#{i.get_attribute('archgen.building', 'revision')} #{config['profile']['id']} #{config['footprint']['width_m']}x#{config['footprint']['depth_m']} pid#{i.persistent_id}"
    end
    selected = model.selection.map { |e| e.respond_to?(:persistent_id) ? e.persistent_id : e.class }
    line = "#{label} : #{list.size} racine(s) [#{detail.join(' | ')}] selection #{selected} modifie #{model.modified?}"
    @lines << line
    File.binwrite(File.join(REPO, 'tmp', 'h10.txt'), "#{@lines.join("\n")}\n")
    puts line
  end

  def place
    Archgen::UI::Panel.instance_variable_get(:@dialog).set_position(300, 20)
  end

  # La prochaine confirmation consommée sera vue comme expirée ; `clock_back` rétablit l'heure.
  def expire_confirmations
    real = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    Archgen::UI::Panel.controller.confirmations.clock = -> { real.call + 121 }
    puts 'horloge avancee de 121 s'
  end

  def clock_back
    Archgen::UI::Panel.controller.confirmations.clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    puts 'horloge retablie'
  end

  # Fenêtre étroite ; le zoom CSS émule une mise à l'échelle de 150 %, sans changer Windows.
  def narrow
    Archgen::UI::Panel.instance_variable_get(:@dialog).set_size(420, 640)
  end

  def wide
    Archgen::UI::Panel.instance_variable_get(:@dialog).set_size(1000, 760)
  end

  def zoom(factor)
    Archgen::UI::Panel.send_script("document.body.style.zoom = #{factor.to_f}")
  end

  def snapshot
    @before = state
    puts "releve #{@before}"
  end

  def compare(label)
    same = state == @before
    @lines << "#{same ? 'OK  ' : 'ECHEC'} #{label} : #{state}"
    File.binwrite(REPORT, "#{@lines.join("\n")}\n")
    puts "#{label} : #{same ? 'modele intact' : 'MODELE MODIFIE'}"
  end

  # Remplace l'envoi vers le panneau par une file, le temps du test.
  def hold
    held = @held
    panel = Archgen::UI::Panel
    panel.singleton_class.send(:alias_method, :send_script_direct, :send_script) unless panel.respond_to?(:send_script_direct)
    panel.define_singleton_method(:send_script) { |script| held << script }
    puts 'reponses retenues'
  end

  def release_reversed
    panel = Archgen::UI::Panel
    panel.singleton_class.send(:alias_method, :send_script, :send_script_direct)
    count = @held.size
    @held.reverse_each { |script| panel.send_script(script) }
    @held.clear
    puts "#{count} reponses rendues dans l'ordre inverse"
  end

  def make_target
    service = Archgen::Adapters::SketchUp::BuildingService.default
    draft = { 'schema_version' => 1, 'profile' => { 'id' => 'toulousain' }, 'name' => 'À modifier', 'lod' => 1, 'footprint' => { 'width_m' => 13.0 } }
    result = service.create(model: Sketchup.active_model, draft: draft)
    entity = Sketchup.active_model.find_entity_by_persistent_id(result.value.persistent_id)
    Sketchup.active_model.selection.clear
    Sketchup.active_model.selection.add(entity)
    puts "cible #{result.ok?}"
  end

  def run_js_tests
    source = File.read(File.join(REPO, 'test', 'js', 'panel_logic_test.js'), encoding: 'UTF-8')
    report = "; document.getElementById('status').textContent = 'JS ' + ArchgenLogicReport.count + ' controles, ' + " \
             "ArchgenLogicReport.failures.length + ' echecs ' + ArchgenLogicReport.failures.join(' | ');"
    Archgen::UI::Panel.send_script(source + report)
  end
end
