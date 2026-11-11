# frozen_string_literal: true

require 'fileutils'

# Contrôle hôte d'AG-143 : sur un document neuf,
#   load '.../test/host/ag143.rb'; ArchgenAG143Probe.run
# Villa à tourelle, maison de ville à lucarnes passantes, bandeaux et balconnets, maison à bow-window
# de rez-de-chaussée, rue mitoyenne de maisons de ville. Rapport tmp/ag143.txt, vues tmp/ag143/.
module ArchgenAG143Probe
  REPO = File.expand_path('../..', __dir__)
  IMAGES = File.join(REPO, 'tmp', 'ag143')
  REPORT = File.join(REPO, 'tmp', 'ag143.txt')
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

  def check(label, result)
    @failures += 1 unless result.ok?
    log("#{result.ok? ? 'OK   ' : 'ECHEC'} #{label}#{result.ok? ? '' : " : #{result.errors.map(&:to_h).first(3).inspect}"}")
    result.ok?
  end

  def building(label, draft, at)
    built = SP::BuildingService.default.create(model: model, draft: { 'schema_version' => 1, 'lod' => 1 }.merge(draft))
    return unless check(label, built)

    model.entities.to_a.last.transformation = Geom::Transformation.translation(Geom::Vector3d.new(*at.map { |c| c / INCH }))
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
    log("AG-143, ARCHGEN #{Archgen::VERSION}, SketchUp #{Sketchup.version}")
    building('villa à tourelle et lucarnes passantes', { 'profile' => { 'id' => 'baule_villa_toit' }, 'seed' => 4,
                                                          'materials' => { 'shutters' => 'painted_wood_blue', 'surrounds' => 'red_brick' },
                                                          'features' => { 'turret' => true, 'dormers' => true, 'wall_dormers' => true, 'string_courses' => true } }, [0, 0, 0])
    building('maison de ville à balconnets', { 'profile' => { 'id' => 'baule_maison_de_ville' }, 'seed' => 1, 'levels' => { 'count' => 3 },
                                              'materials' => { 'wall' => 'light_render', 'surrounds' => 'red_brick' }, 'features' => { 'balconettes' => true } }, [20, 0, 0])
    building('maison à bow-window de rez-de-chaussée', { 'profile' => { 'id' => 'baule_villa_toit' }, 'seed' => 2, 'features' => { 'shutters' => false, 'bow_window' => 'ground' } }, [36, 0, 0])
    street = SP::EnsembleService.default.create(model: model, origin_m: [0, -30, 0],
                                                tree: { 'seed' => 5, 'trace' => { 'points_m' => [[0, 0], [48, 0]], 'closed' => false },
                                                        'building' => { 'profile' => { 'id' => 'baule_maison_de_ville' }, 'lod' => 1 } })
    check('rue de maisons de ville', street)
    model.rendering_options['DisplayColorByLayer'] = false
    view('villa-tourelle', [-9, -15, 9], [5, 3, 6])
    view('maison-balconnets', [24, -13, 6], [24, 0, 5])
    view('bow-rdc', [41.5, -11, 3], [41.5, 0, 2])
    view('rue-maisons-de-ville', [24, -50, 8], [24, -30, 6])
    log(@failures.zero? ? 'Réussi : 0 échec' : "#{@failures} échec(s)")
    log('FIN')
  end
end
