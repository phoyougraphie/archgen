# frozen_string_literal: true

require 'fileutils'

# Contrôle hôte d'AG-140 à AG-142 : sur un document neuf,
#   load '.../test/host/ag142.rb'; ArchgenAG142Probe.run
# Rue mitoyenne de maisons de ville, rue de villas isolées, rue de villas à quatre pans, villa en U.
# Rapport tmp/ag142.txt, vues tmp/ag142/.
module ArchgenAG142Probe
  REPO = File.expand_path('../..', __dir__)
  IMAGES = File.join(REPO, 'tmp', 'ag142')
  REPORT = File.join(REPO, 'tmp', 'ag142.txt')
  SP = Archgen::Adapters::SketchUp
  INCH = 0.0254
  ISOLE = { 'target_width_m' => 16, 'depth_m' => 22, 'bay_width_m' => 3, 'detached' => { 'side_gap_m' => 3, 'front_setback_m' => 5, 'building_depth_m' => 9 } }.freeze

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
  end

  def street(label, profile, origin, parcel: nil, length: 64)
    tree = { 'seed' => 11, 'trace' => { 'points_m' => [[0, 0], [length, 0]], 'closed' => false }, 'building' => { 'profile' => { 'id' => profile }, 'lod' => 1 } }
    tree['parcel'] = parcel if parcel
    check(label, SP::EnsembleService.default.create(model: model, origin_m: origin, tree: tree))
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
    log("AG-142, ARCHGEN #{Archgen::VERSION}, SketchUp #{Sketchup.version}")
    street('rue mitoyenne de maisons de ville', 'baule_maison_de_ville', [0, 0, 0], length: 48)
    street('rue de villas isolées', 'baule_villa', [0, -40, 0], parcel: ISOLE, length: 80)
    street('rue de villas à quatre pans', 'baule_villa_toit', [0, -80, 0], parcel: ISOLE, length: 80)
    built = SP::BuildingService.default.create(model: model, draft: { 'schema_version' => 1, 'lod' => 1, 'profile' => { 'id' => 'baule_villa', 'revision' => 1 }, 'levels' => { 'count' => 3 },
                                                                      'wing' => { 'position' => 'both', 'width_m' => 3.5, 'depth_m' => 5, 'levels' => 2 } })
    check('villa en U', built)
    model.entities.to_a.last.transformation = Geom::Transformation.translation(Geom::Vector3d.new(70 / INCH, 0, 0)) if built.ok?
    model.rendering_options['DisplayColorByLayer'] = false
    view('maisons-de-ville', [24, -16, 7], [24, 0, 5])
    view('villas-isolees', [40, -64, 9], [40, -40, 5])
    view('villas-quatre-pans', [40, -104, 10], [40, -80, 4])
    view('villa-U-arriere', [76, 30, 12], [75, 8, 6])
    log(@failures.zero? ? 'Réussi : 0 échec' : "#{@failures} échec(s)")
    log('FIN')
  end
end
