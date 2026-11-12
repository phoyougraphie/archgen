# frozen_string_literal: true

require 'fileutils'
require 'json'

# Contrôle hôte d'AG-135 à AG-139 : sur un document neuf,
#   load '.../test/host/ag139.rb'; ArchgenAG139Probe.run
# Front de mer (attique, verre, balcons d'angle), villa en U à bow-window, maison en L, rue de maisons
# isolées en T. Rapport tmp/ag139.txt, vues tmp/ag139/.
module ArchgenAG139Probe
  REPO = File.expand_path('../..', __dir__)
  TMP = File.join(REPO, 'tmp')
  IMAGES = File.join(TMP, 'ag139')
  REPORT = File.join(TMP, 'ag139.txt')
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

  def place(at)
    root = model.entities.to_a.last
    root.transformation = Geom::Transformation.translation(Geom::Vector3d.new(*at.map { |c| c / INCH }))
  end

  def building(label, draft, at)
    built = SP::BuildingService.default.create(model: model, draft: { 'schema_version' => 1, 'lod' => 1, 'mode' => 'shell' }.merge(draft))
    place(at) if check(label, built)
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
    log("AG-139, ARCHGEN #{Archgen::VERSION}, SketchUp #{Sketchup.version}")
    building('front de mer, balcons d’angle', { 'profile' => { 'id' => 'baule_front_de_mer' }, 'facade' => { 'side_bays' => 2 }, 'features' => { 'balcony_wrap' => true } }, [0, 0, 0])
    building('villa en U à bow-window', { 'profile' => { 'id' => 'baule_villa' }, 'levels' => { 'count' => 3 }, 'features' => { 'bow_window' => 'center' },
                                          'wing' => { 'position' => 'both', 'width_m' => 3.5, 'depth_m' => 5, 'levels' => 2 } }, [40, 0, 0])
    building('maison moderne en L', { 'profile' => { 'id' => 'maison_moderne' }, 'wing' => { 'position' => 'left', 'width_m' => 5, 'depth_m' => 6, 'levels' => 1 } }, [62, 0, 0])
    street = SP::EnsembleService.default.create(
      model: model, origin_m: [0, -40, 0],
      tree: { 'seed' => 2, 'trace' => { 'points_m' => [[0, 0], [64, 0]], 'closed' => false },
              'parcel' => { 'target_width_m' => 16, 'depth_m' => 25, 'bay_width_m' => 3, 'detached' => { 'side_gap_m' => 3, 'front_setback_m' => 5, 'building_depth_m' => 10 } },
              'building' => { 'profile' => { 'id' => 'maison_moderne' }, 'lod' => 1, 'wing' => { 'position' => 'center', 'width_m' => 4, 'depth_m' => 5, 'levels' => 1 } } }
    )
    check('rue de maisons isolées en T', street)
    model.rendering_options['DisplayColorByLayer'] = false
    view('front-de-mer', [-14, -22, 14], [11, 7, 11])
    view('front-de-mer-attique', [11, -10, 30], [11, 4, 22])
    view('villa-face', [45, -16, 6], [45, 5, 5])
    view('villa-arriere', [56, 32, 14], [45, 10, 4])
    view('maison-L', [80, 26, 12], [68, 8, 2])
    view('rue-isolees', [32, -78, 30], [32, -40, 2])
    log(@failures.zero? ? 'Réussi : 0 échec' : "#{@failures} échec(s)")
    log('FIN')
  end
end
