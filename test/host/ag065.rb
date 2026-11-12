# frozen_string_literal: true

require 'fileutils'

# Contrôle hôte d'AG-065, rez-de-chaussée commerçant : sur un document neuf,
#   load '.../test/host/ag065.rb'; ArchgenAG065Probe.run
# Crée un Haussmannien commerçant, vérifie hauteur, vitrines vitrées, bandeau, une entrée
# d'Annuler, puis un îlot Toulousain commerçant à porche. Rapport tmp/ag065.txt, vues tmp/ag065/.
module ArchgenAG065Probe
  REPO = File.expand_path('../..', __dir__)
  TMP = File.join(REPO, 'tmp')
  IMAGES = File.join(TMP, 'ag065')
  REPORT = File.join(TMP, 'ag065.txt')
  SP = Archgen::Adapters::SketchUp
  INCH = 0.0254

  module_function

  def model
    Sketchup.active_model
  end

  def log(line)
    @lines << line
    File.binwrite(REPORT, "#{@lines.join("\n")}\n")
  end

  def check(label, ok, detail = nil)
    @failures += 1 unless ok
    log("#{ok ? 'OK   ' : 'ECHEC'} #{label}#{detail ? " : #{detail}" : ''}")
    ok
  end

  def detail_keys
    model.definitions.filter_map { |d| d.attribute_dictionaries&.map { |dict| dict['key'] }&.compact&.first }
  end

  def faces_by_material(entities, memo = Hash.new(0))
    entities.each do |e|
      case e
      when Sketchup::Face then memo[e.material&.display_name.to_s] += 1
      when Sketchup::Group then faces_by_material(e.entities, memo)
      when Sketchup::ComponentInstance then faces_by_material(e.definition.entities, memo)
      end
    end
    memo
  end

  def view(name, eye, target)
    FileUtils.mkdir_p(IMAGES)
    model.active_view.camera = Sketchup::Camera.new(eye.map { |c| c / INCH }, target.map { |c| c / INCH }, [0, 0, 1])
    path = File.join(IMAGES, "#{name}.png")
    model.active_view.write_image(path, 1400, 900, true)
    log("vue #{path}")
  end

  def run
    @lines = []
    @failures = 0
    log("AG-065 commerce, ARCHGEN #{Archgen::VERSION}, SketchUp #{Sketchup.version}")
    before = model.entities.length
    draft = { 'schema_version' => 1, 'profile' => { 'id' => 'haussmann' }, 'footprint' => { 'width_m' => 14, 'depth_m' => 10 },
              'lod' => 1, 'mode' => 'shell', 'ground_floor' => 'shop' }
    built = SP::BuildingService.default.create(model: model, draft: draft)
    check('Haussmannien commerçant créé', built.ok?, built.ok? ? nil : built.errors.map(&:to_h).inspect)
    root = model.entities.to_a.last
    config = JSON.parse(root.get_attribute('archgen.building', 'config_json')) rescue {}
    check('commerce et hauteur de 4,5 m enregistrés', config['ground_floor'] == 'shop' && config.dig('shop', 'height_m') == 4.5, config.slice('ground_floor', 'shop').inspect)
    check('une racine ajoutée', model.entities.length == before + 1, (model.entities.length - before).to_s)
    shopfronts = detail_keys.grep(/shopfront/)
    check('définitions de vitrine, porte de chaque côté', shopfronts.size == 2, shopfronts.inspect)
    counts = faces_by_material(root.definition.entities)
    check('faces de verre écrites', counts.any? { |name, n| name =~ /verre/i && n.positive? }, counts.inspect)

    steps = [
      -> { Sketchup.undo },
      -> { check('Annuler retire le bâtiment en une fois', model.entities.length == before, model.entities.length.to_s) && Sketchup.redo },
      -> { check('Rétablir le rend', model.entities.length == before + 1, model.entities.length.to_s) && finish }
    ]
    chain(steps)
  end

  def chain(steps)
    return if steps.empty?

    UI.start_timer(1.0, false) do
      steps.first.call
      chain(steps.drop(1))
    end
  end

  def finish
    block = SP::EnsembleService.default.create(
      model: model, origin_m: [0, 25, 0],
      tree: { 'seed' => 1, 'trace' => { 'points_m' => [[0, 0], [40, 0], [40, 40], [0, 40]], 'closed' => true },
              'building' => { 'profile' => { 'id' => 'toulousain' }, 'lod' => 1, 'ground_floor' => 'shop' } }
    )
    check('îlot Toulousain commerçant créé', block.ok?, block.ok? ? nil : block.errors.map(&:to_h).inspect)
    root = model.entities.to_a.last
    stored = JSON.parse(root.get_attribute('archgen.ensemble', 'ensemble_json'))
    check('îlot : commerce enregistré', stored.dig('building', 'ground_floor') == 'shop', stored['building'].inspect)
    model.rendering_options['DisplayColorByLayer'] = false
    view('facade', [7, -16, 5], [7, 0, 4])
    view('vitrine', [3, -5, 2], [3, 0, 2])
    view('ilot', [20, 5, 18], [20, 45, 4])
    log(@failures.zero? ? 'Réussi : 0 échec' : "#{@failures} échec(s)")
    log('FIN')
  end
end
