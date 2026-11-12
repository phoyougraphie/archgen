# frozen_string_literal: true

require 'fileutils'

# Contrôle hôte d'AG-144 : sur un document neuf,
#   load '.../test/host/ag144.rb'; ArchgenAG144Probe.run
# Chapelle, église romane, église gothique, cathédrale. Rapport tmp/ag144.txt, vues tmp/ag144/.
module ArchgenAG144Probe
  REPO = File.expand_path('../..', __dir__)
  IMAGES = File.join(REPO, 'tmp', 'ag144')
  REPORT = File.join(REPO, 'tmp', 'ag144.txt')
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

  def building(label, id, at)
    built = SP::BuildingService.default.create(model: model, draft: { 'schema_version' => 1, 'lod' => 1, 'profile' => { 'id' => id } })
    @failures += 1 unless built.ok?
    log("#{built.ok? ? 'OK   ' : 'ECHEC'} #{label}#{built.ok? ? '' : " : #{built.errors.map(&:to_h).first(3).inspect}"}")
    model.entities.to_a.last.transformation = Geom::Transformation.translation(Geom::Vector3d.new(*at.map { |c| c / INCH })) if built.ok?
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
    log("AG-144, ARCHGEN #{Archgen::VERSION}, SketchUp #{Sketchup.version}")
    building('chapelle', 'chapelle', [0, 0, 0])
    building('église romane', 'eglise_romane', [30, 0, 0])
    building('église gothique', 'eglise_gothique', [70, 0, 0])
    building('cathédrale', 'cathedrale', [130, 0, 0])
    model.rendering_options['DisplayColorByLayer'] = false
    view('chapelle', [-12, -14, 8], [3.5, 7, 4])
    view('eglise-romane', [20, -20, 12], [35.5, 13, 6])
    view('eglise-gothique', [55, -28, 18], [77, 17, 10])
    view('eglise-gothique-chevet', [100, 70, 22], [77, 25, 8])
    view('cathedrale', [105, -45, 30], [141, 29, 15])
    view('cathedrale-dessus', [175, 90, 80], [141, 29, 10])
    log(@failures.zero? ? 'Réussi : 0 échec' : "#{@failures} échec(s)")
    log('FIN')
  end
end
