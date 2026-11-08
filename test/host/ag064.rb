# frozen_string_literal: true

require 'fileutils'

# Contrôle hôte d'AG-064, vitrage : sur un document neuf,
#   load '.../test/host/ag064.rb'; ArchgenAG064Probe.run
# Crée un Haussmannien (révision 2, vitré) et un bâtiment en révision 1, une rue vitrée,
# vérifie matière de verre, vitres et vantaux, une entrée d'Annuler. Rapport tmp/ag064.txt, vues tmp/ag064/.
module ArchgenAG064Probe
  REPO = File.expand_path('../..', __dir__)
  TMP = File.join(REPO, 'tmp')
  IMAGES = File.join(TMP, 'ag064')
  REPORT = File.join(TMP, 'ag064.txt')
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

  def draft(revision: nil, width: 12, mode: 'shell')
    profile = { 'id' => 'haussmann' }
    profile['revision'] = revision if revision
    { 'schema_version' => 1, 'profile' => profile, 'footprint' => { 'width_m' => width, 'depth_m' => 9 }, 'lod' => 1, 'mode' => mode }
  end

  # Toutes les définitions sous une racine, avec le nombre de faces par matière.
  def faces_by_material(entities, memo = Hash.new(0), seen = {})
    entities.each do |e|
      case e
      when Sketchup::Face then memo[e.material&.display_name.to_s] += 1
      when Sketchup::Group then faces_by_material(e.entities, memo, seen)
      when Sketchup::ComponentInstance then faces_by_material(e.definition.entities, memo, seen)
      end
    end
    memo
  end

  def glass_material
    model.materials.find { |m| m.get_attribute('archgen', 'catalog_id') == 'glass' } || model.materials.find { |m| m.display_name =~ /verre/i }
  end

  def view(name, eye, target)
    FileUtils.mkdir_p(IMAGES)
    camera = Sketchup::Camera.new(eye.map { |c| c / INCH }, target.map { |c| c / INCH }, [0, 0, 1])
    model.active_view.camera = camera
    path = File.join(IMAGES, "#{name}.png")
    model.active_view.write_image(path, 1400, 900, true)
    log("vue #{path}")
  end

  def run
    @lines = []
    @failures = 0
    log("AG-064 vitrage, ARCHGEN #{Archgen::VERSION}, SketchUp #{Sketchup.version}")
    service = SP::BuildingService.default
    before = model.entities.length

    glazed = service.create(model: model, draft: draft)
    check('Haussmannien révision 2 créé', glazed.ok?, glazed.ok? ? nil : glazed.errors.map(&:to_h).inspect)
    root = model.entities.to_a.last
    config = JSON.parse(root.get_attribute('archgen.building', 'config_json')) rescue {}
    check('révision 2, vitrage et verre enregistrés', config.dig('profile', 'revision') == 2 && config.dig('features', 'glazing') == true && config.dig('materials', 'glass') == 'glass', config['profile'].inspect)
    glass = glass_material
    check('matière de verre créée, translucide', glass && (glass.alpha - 0.35).abs < 1e-6, glass ? "#{glass.display_name} alpha #{glass.alpha.round(2)}" : 'absente')
    counts = faces_by_material(root.definition.entities)
    check('faces de verre écrites', counts.any? { |name, n| name == glass&.display_name && n.positive? }, counts.inspect)
    undo_entries = model.entities.length - before
    check('une racine ajoutée', undo_entries == 1, undo_entries.to_s)

    old = service.create(model: model, draft: draft(revision: 1, width: 10))
    check('révision 1 créée', old.ok?)
    old_root = model.entities.to_a.last
    old_counts = faces_by_material(old_root.definition.entities)
    check('révision 1 sans verre', old_counts.keys.none? { |name| name == glass&.display_name }, old_counts.inspect)

    # Annuler n'agit qu'entre deux appels Ruby : chaque pas attend son minuteur.
    steps = [
      -> { Sketchup.undo },
      -> { check('Annuler retire la révision 1 en une fois', model.entities.length == before + 1, model.entities.length.to_s) && Sketchup.undo },
      -> { check('Annuler retire le bâtiment vitré en une fois', model.entities.length == before, model.entities.length.to_s) && Sketchup.redo },
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
    glass = glass_material
    street = SP::EnsembleService.default.create(model: model, tree: { 'seed' => 2, 'trace' => { 'points_m' => [[0, 0], [48, 0]], 'closed' => false },
                                                                       'building' => { 'profile' => { 'id' => 'toulousain' }, 'lod' => 1 } }, origin_m: [0, 20, 0])
    check('rue Toulousaine créée', street.ok?, street.ok? ? nil : street.errors.map(&:to_h).inspect)
    street_root = model.entities.to_a.last
    stored = JSON.parse(street_root.get_attribute('archgen.ensemble', 'ensemble_json'))
    check('rue : révision 2 figée', stored.dig('building', 'profile') == { 'id' => 'toulousain', 'revision' => 2 }, stored.dig('building', 'profile').inspect)
    street_counts = faces_by_material(street_root.definition.entities)
    check('rue : faces de verre', street_counts[glass&.display_name.to_s].to_i.positive?, street_counts.inspect)

    model.rendering_options['DisplayColorByLayer'] = false
    view('facade', [6, -14, 6], [6, 0, 6])
    view('porte', [6.5, -4.5, 1.5], [6.5, 0, 1.4])
    view('rue', [24, 2, 14], [24, 28, 6])
    log(@failures.zero? ? 'Réussi : 0 échec' : "#{@failures} échec(s)")
    log('FIN')
  end
end
