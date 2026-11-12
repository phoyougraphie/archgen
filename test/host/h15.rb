# frozen_string_literal: true

require 'json'
require 'fileutils'

# Recette H15, à lancer sur un document neuf, panneau fermé :
#   load '.../test/host/h15.rb'; ArchgenH15Probe.run
# Écrit de vrais ensembles par le service réel, les relit dans le modèle et mesure la charge.
# Rapport : tmp/h15.txt, vues dans tmp/h15/. Le dernier mot du rapport est « FIN ».
# Tant que les accès de cour n'existent pas (AG-034), les formes fermées restent refusées :
# la recette porte sur des rues ouvertes, angles compris.
module ArchgenH15Probe
  REPO = File.expand_path('../..', __dir__)
  TMP = File.join(REPO, 'tmp')
  IMAGES = File.join(TMP, 'h15')
  REPORT = File.join(TMP, 'h15.txt')
  SKP = File.join(TMP, 'h15.skp')
  WORK = File.join(TMP, 'h15-travail.skp')
  LOAD_SKP = File.join(TMP, 'h15-charge.skp')
  SP = Archgen::Adapters::SketchUp
  CORE = Archgen::Core
  INCH = 0.0254
  DICTIONARY = 'archgen.ensemble'
  DELAY_S = 1.5
  WORLD_TOLERANCE_M = 0.001
  ORIGIN = [5.0, 7.0, 0.0].freeze
  U_STREET = [[0, 0], [40, 0], [40, 40], [0, 40]].freeze

  module_function

  def model
    Sketchup.active_model
  end

  def service
    @service ||= SP::EnsembleService.default
  end

  def tree(profile: 'haussmann', points: U_STREET, mode: 'structural', lod: 1, **rest)
    { 'trace' => { 'points_m' => points, 'closed' => false }, 'building' => { 'profile' => { 'id' => profile }, 'mode' => mode, 'lod' => lod } }.merge(rest.transform_keys(&:to_s))
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

  def roots
    model.entities.grep(Sketchup::ComponentInstance).select { |i| i.get_attribute(DICTIONARY, 'ensemble_version') }
  end

  def counts
    { definitions: model.definitions.length, materials: model.materials.length, layers: model.layers.length, entities: model.entities.length }
  end

  def parcels_of(instance)
    instance.definition.entities.grep(Sketchup::ComponentInstance)
  end

  # Faces réelles, instances comprises : une définition partagée compte à chaque usage.
  def deep_faces(entities, memo = {})
    entities.sum do |entity|
      case entity
      when Sketchup::Face then 1
      when Sketchup::Group then deep_faces(entity.entities, memo)
      when Sketchup::ComponentInstance
        memo[entity.definition] ||= deep_faces(entity.definition.entities, memo)
      else 0
      end
    end
  end

  def world_wall_vertices(root)
    parcels_of(root).to_h do |parcel|
      walls = parcel.definition.entities.grep(Sketchup::Group).find { |g| g.name == 'walls' }
      points = walls.entities.grep(Sketchup::Group).flat_map do |wall|
        wall.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq.map { |v| root.transformation * parcel.transformation * walls.transformation * wall.transformation * v.position }
      end
      [parcel.name, points]
    end
  end

  def ring_gaps(root, settings, origin)
    layout = Archgen::Geometry::ParcelLayout.call(settings).value
    world = world_wall_vertices(root)
    layout['parcels'].flat_map do |parcel|
      parcel['ring_m'].map do |x, y|
        target = [(x + origin[0]) / INCH, (y + origin[1]) / INCH, origin[2] / INCH]
        world.fetch(parcel['id']).map { |p| Math.sqrt(((p.x - target[0])**2) + ((p.y - target[1])**2) + ((p.z - target[2])**2)) * INCH }.min
      end
    end
  end

  # --- Étapes

  def stage_create
    before = counts
    @tree = tree
    result = service.create(model: model, tree: @tree, origin_m: ORIGIN)
    return check('Création', false, result.errors.map(&:to_h).inspect) unless result.ok?

    @summary = result.value
    root = roots.first
    metrics = @summary.metrics
    check('Une seule racine', roots.size == 1)
    check('Une instance par parcelle', parcels_of(root).size == metrics['parcel_count'], "#{metrics['parcel_count']} parcelles, #{metrics['definition_count']} définitions")
    check('Définitions partagées', parcels_of(root).map(&:definition).uniq.size == metrics['definition_count'])
    check('Faces réelles = plan', deep_faces(root.definition.entities) == metrics['expanded_face_count'], "#{metrics['expanded_face_count']} faces")
    check('Racine au premier point', (root.transformation.origin.x * INCH - ORIGIN[0]).abs < 1e-6 && (root.transformation.origin.y * INCH - ORIGIN[1]).abs < 1e-6)
    gaps = ring_gaps(root, CORE::EnsembleEngine.then { @settings = Archgen::Composition.ensemble_intake.settings(@tree).value }, ORIGIN)
    check('Angles des trapèzes dans le modèle', gaps.max <= WORLD_TOLERANCE_M, format('écart max %.4f mm', gaps.max * 1000))
    tags = parcels_of(root).first.definition.entities.grep(Sketchup::Group).map { |g| g.layer.name }.uniq
    check('Tags sur les conteneurs', tags.include?('ARCHGEN Murs') && tags.include?('ARCHGEN Toiture'), tags.join(', '))
    check('Racine et parcelles sans tag', root.layer == model.layers[0] && parcels_of(root).all? { |p| p.layer == model.layers[0] })
    kinds = parcels_of(root).map { |p| p.definition.get_attribute('archgen.definition', 'kind') }.uniq
    check('Définitions marquées parcel', kinds == ['parcel'], kinds.join(', '))
    check('Parcelles sans attribut de bâtiment', parcels_of(root).none? { |p| p.get_attribute('archgen.building', 'metadata_version') })
    @after_create = counts
    @before_create = before
    Sketchup.undo
  end

  def stage_after_undo
    check('Annuler retire tout en une fois', roots.empty? && model.entities.length == @before_create[:entities])
    check('Annuler ramène définitions, matériaux et tags', counts == @before_create, "#{@before_create} / #{counts}")
    Sketchup.redo
  end

  def stage_after_redo
    check('Rétablir ramène l’ensemble', roots.size == 1 && counts == @after_create)
    root = roots.first
    check('Faces après Rétablir', deep_faces(root.definition.entities) == @summary.metrics['expanded_face_count'])
  end

  class FailingWriter
    def initialize(real, after:)
      @real = real
      @left = after
    end

    def write(*args, **options)
      raise 'panne injectée' if @left.zero?

      @left -= 1
      @real.write(*args, **options)
    end

    def mark_definition(*args, **options)
      @real.mark_definition(*args, **options)
    end
  end

  def stage_faults
    before = counts
    { 'première définition' => 0, 'deuxième définition' => 1, 'troisième définition' => 2 }.each do |label, after|
      writer = FailingWriter.new(SP::GeometryWriter.new, after: after)
      result = SP::EnsembleService.default(writer: writer).create(model: model, tree: tree(profile: 'toulousain'), origin_m: [100.0, 0.0, 0.0])
      check("Panne sur la #{label} : refus", !result.ok? && result.errors.first.params['reason'] == 'write_failed', result.errors.map(&:to_h).first.to_s)
      check("Panne sur la #{label} : sans résidu", counts == before, "#{before} / #{counts}")
    end
    check('Racine existante intacte après les pannes', roots.size == 1 && roots.first.persistent_id == @summary.persistent_id)
  end

  def stage_regenerate
    root = roots.first
    model.selection.clear
    model.selection.add(root)
    loaded = service.load_selection(model: model)
    return check('Relecture de la sélection', false, loaded.errors.map(&:to_h).inspect) unless loaded.ok?

    @definition_before = root.definition
    matrix = root.transformation.to_a
    pid = root.persistent_id
    result = service.regenerate(model: model, target: loaded.value.target, changes: { 'parcel' => { 'depth_m' => 10.0 } })
    return check('Régénération', false, result.errors.map(&:to_h).inspect) unless result.ok?

    check('Régénérer garde la racine', roots.size == 1 && roots.first.persistent_id == pid)
    check('Régénérer garde le placement', roots.first.transformation.to_a == matrix)
    check('Définition fraîche', roots.first.definition != @definition_before)
    check('Révision 2', result.value.revision == 2)
    check('Réglage enregistré', JSON.parse(roots.first.get_attribute(DICTIONARY, 'ensemble_json')).dig('parcel', 'depth_m') == 10.0)
    Sketchup.undo
  end

  def stage_regenerate_undone
    root = roots.first
    check('Annuler ramène la définition d’origine', root.definition == @definition_before)
    check('Annuler ramène la révision 1', root.get_attribute(DICTIONARY, 'revision') == 1)
  end

  # Copie simulée : même définition et attributs recopiés. Le vrai geste est couvert en H17.
  def stage_copy
    original = roots.first
    model.start_operation('Copie de contrôle', true)
    @copy = model.entities.add_instance(original.definition, Geom::Transformation.translation([120.m, 0, 0]))
    SP::EnsembleRepository::KEYS.each { |key| @copy.set_attribute(DICTIONARY, key, original.get_attribute(DICTIONARY, key)) }
    model.commit_operation
    shared = original.definition
    faces = deep_faces(shared.entities)
    model.selection.clear
    model.selection.add(@copy)
    target = service.load_selection(model: model).value.target
    result = service.regenerate(model: model, target: target, changes: { 'parcel' => { 'depth_m' => 8.0 } })
    check('Régénérer la copie', result.ok?, result.errors.map(&:to_h).first.to_s)
    check('Original intact', original.definition == shared && deep_faces(shared.entities) == faces)
    check('Copie isolée', @copy.definition != shared)
    check('Attributs de l’original intacts', JSON.parse(original.get_attribute(DICTIONARY, 'ensemble_json')).dig('parcel', 'depth_m') == 9.0)
  end

  def stage_refusals
    original = roots.find { |r| r != @copy }
    parcel = parcels_of(original).first
    model.selection.clear
    model.selection.add(original)
    target = service.load_selection(model: model).value.target
    check('Parcelle refusée comme racine', service_read_instance(parcel) == 'not_at_model_root', service_read_instance(parcel).to_s)
    building = SP::BuildingService.default
    check('Service de bâtiment refuse la racine', building.load_selection(model: model).errors.first&.params&.fetch('reason') == 'not_an_archgen_root')
    check('Racine refusée comme terrain', building.retain_terrain(model: model).errors.first&.params&.fetch('reason') == 'terrain_is_building')

    original.locked = true
    check('Racine verrouillée refusée', reason_of(service.regenerate(model: model, target: target)) == 'target_locked')
    original.locked = false

    model.start_operation('Échelle de contrôle', true)
    saved = original.transformation
    original.transformation = saved * Geom::Transformation.scaling(2.0)
    model.commit_operation
    check('Racine mise à l’échelle refusée', reason_of(service.regenerate(model: model, target: target)) == 'non_rigid_transform')
    Sketchup.undo
  end

  def stage_versions
    original = roots.find { |r| r != @copy }
    model.selection.clear
    model.selection.add(original)
    target = service.load_selection(model: model).value.target
    model.start_operation('Version de contrôle', true)
    engine = original.get_attribute(DICTIONARY, 'engine_version')
    original.set_attribute(DICTIONARY, 'engine_version', (engine.to_i + 1).to_s)
    model.commit_operation
    target = service.load_selection(model: model).value.target
    check('Moteur plus récent : refus', reason_of(service.regenerate(model: model, target: target)) == 'newer_engine')
    Sketchup.undo
  end

  def stage_explode
    @exploded_count = parcels_of(@copy).size
    model.start_operation('Éclatement de contrôle', true)
    pieces = @copy.explode
    model.commit_operation
    instances = pieces.to_a.grep(Sketchup::ComponentInstance)
    check('Racine éclatée : une instance par parcelle', instances.size == @exploded_count, instances.size.to_s)
    model.selection.clear
    model.selection.add(instances.first)
    check('Pièce éclatée : pas un ensemble', reason_of(service.load_selection(model: model)) == 'not_an_ensemble_root')
    check('Pièce éclatée : pas un bâtiment', reason_of(SP::BuildingService.default.load_selection(model: model)) == 'not_an_archgen_root')
    Sketchup.undo
  end

  def stage_save
    root = roots.find { |r| r != @copy && r.valid? } || roots.first
    @stored = root.get_attribute(DICTIONARY, 'ensemble_digest')
    @stored_pid = root.persistent_id
    @stored_faces = deep_faces(root.definition.entities)
    check('Enregistrer', model.save(SKP))
    Sketchup.open_file(SKP)
  end

  def stage_reopened
    root = roots.find { |r| r.persistent_id == @stored_pid }
    return check('Racine retrouvée après réouverture', false) unless root

    check('Racine retrouvée après réouverture', true)
    check('Faces après réouverture', deep_faces(root.definition.entities) == @stored_faces)
    model.selection.clear
    model.selection.add(root)
    loaded = service.load_selection(model: model)
    check('Réglages relus', loaded.ok?, loaded.errors.map(&:to_h).first.to_s)
    again = service.preview(tree: loaded.value.settings)
    check('Même empreinte recalculée', again.value.ensemble_digest == @stored, @stored[0, 12])
    result = service.regenerate(model: model, target: loaded.value.target, changes: { 'seed' => 2 })
    check('Régénérable après réouverture', result.ok?, result.errors.map(&:to_h).first.to_s)
  end

  def stage_lone_building
    building = SP::BuildingService.default
    result = building.create(model: model, draft: { 'schema_version' => 1, 'profile' => { 'id' => 'haussmann' } })
    check('Bâtiment seul toujours créé', result.ok?, result.errors.map(&:to_h).first.to_s)
    instance = model.entities.grep(Sketchup::ComponentInstance).find { |i| i.persistent_id == result.value.persistent_id }
    model.selection.clear
    model.selection.add(instance)
    check('Bâtiment seul : pas un ensemble', reason_of(service.load_selection(model: model)) == 'not_an_ensemble_root')
    check('Bâtiment seul relu', building.load_selection(model: model).ok?)
  end

  def service_read_instance(entity)
    reason_of(SP::EnsembleRepository.new.read_instance(model, entity))
  end

  def reason_of(result)
    result.errors.first&.params&.fetch('reason', nil)
  end

  # --- Vues : regarder sans piloter l'écran

  def fresh
    model.save(WORK) if model.modified? || !model.path.empty?
    Sketchup.file_new
  end

  VIEWS = {
    'haussmann-coude' => { profile: 'haussmann', points: [[0, 0], [40, 0], [40, 40]], parcel: nil },
    'toulousain-u' => { profile: 'toulousain', points: U_STREET, parcel: nil },
    'brutaliste-deux-cotes' => { profile: 'brutalist', points: [[0, 0], [60, 0], [60, 48]], layout: { 'side' => 'both', 'street_width_m' => 14 } },
    'haussmann-rentrant' => { profile: 'haussmann', points: [[0, 0], [40, 0], [40, -40]], parcel: nil },
    'haussmann-120' => { profile: 'haussmann', points: [[0, 0], [40, 0], [20, 34.641016]], parcel: nil }
  }.freeze

  def view_stages
    VIEWS.flat_map do |name, spec|
      [
        lambda {
          fresh
          options = spec.reject { |k, v| v.nil? || %i[profile points].include?(k) }
          built = tree(profile: spec[:profile], points: spec[:points], **options)
          result = service.create(model: model, tree: built, origin_m: [0.0, 0.0, 0.0])
          check("Vue #{name} créée", result.ok?, result.errors.map(&:to_h).first.to_s)
        },
        -> { shoot(name) }
      ]
    end
  end

  def shoot(name)
    FileUtils.mkdir_p(IMAGES)
    view = model.active_view
    box = model.bounds
    centre = box.center
    size = box.diagonal
    { 'dessus' => [centre.offset(Geom::Vector3d.new(0, -size * 0.05, size * 1.1)), Geom::Vector3d.new(0, 1, 0)],
      'face' => [centre.offset(Geom::Vector3d.new(size * 0.55, -size * 0.75, size * 0.55)), Geom::Vector3d.new(0, 0, 1)],
      'cour' => [centre.offset(Geom::Vector3d.new(-size * 0.55, size * 0.75, size * 0.55)), Geom::Vector3d.new(0, 0, 1)] }.each do |label, (eye, up)|
      view.camera = Sketchup::Camera.new(eye, centre, up)
      view.zoom_extents
      path = File.join(IMAGES, "#{name}-#{label}.png")
      view.write_image(path, 1400, 900, true)
      check("Image #{name} #{label}", File.size?(path).to_i.positive?)
    end
  end

  # --- Charge

  def zigzag(segments)
    points = [[0.0, 0.0]]
    segments.times do |index|
      length = 30.0 + (index * 1.7)
      angle = index.even? ? 0.5 : -0.5
      points << [(points.last[0] + (length * Math.cos(angle))).round(3), (points.last[1] + (length * Math.sin(angle))).round(3)]
    end
    points
  end

  LOADS = {
    '12 parcelles' => { points: [[0, 0], [144, 0]] },
    '50 parcelles' => { points: [[0, 0], [600, 0]] },
    '200 parcelles' => { points: [[0, 0], [1200, 0], [1200, 1200]] },
    'zigzag, définitions variées' => { points: nil }
  }.freeze

  def load_stages
    LOADS.flat_map do |label, spec|
      %w[haussmann brutalist].map do |profile|
        lambda {
          fresh
          load_case(label, profile, spec[:points] || zigzag(20))
        }
      end
    end
  end

  def load_case(label, profile, points)
    built = tree(profile: profile, points: points)
    before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = service.create(model: model, tree: built, origin_m: [0.0, 0.0, 0.0])
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - before) * 1000).round
    return log("MESURE charge #{profile}, #{label} : refus #{result.errors.first.to_h}") unless result.ok?

    metrics = result.value.metrics
    check("Charge #{profile}, #{label} : faces réelles", deep_faces(roots.first.definition.entities) == metrics['expanded_face_count'])
    undo_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    model.save(LOAD_SKP)
    save_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - undo_start) * 1000).round
    log("MESURE charge #{profile}, #{label} : #{metrics['parcel_count']} parcelles, #{metrics['definition_count']} définitions, #{metrics['unique_face_count']} faces uniques, #{metrics['expanded_face_count']} étendues, écriture #{elapsed} ms, enregistrement #{save_ms} ms, fichier #{File.size(LOAD_SKP)} octets")
  end

  # --- Déroulé

  def stages
    [-> { stage_create }, -> { stage_after_undo }, -> { stage_after_redo }, -> { stage_faults }, -> { stage_regenerate }, -> { stage_regenerate_undone },
     -> { stage_copy }, -> { stage_refusals }, -> { stage_versions }, -> { stage_explode }, -> { stage_save }, -> { stage_reopened }, -> { stage_lone_building }] + view_stages + load_stages
  end

  def advance
    stage = @queue.shift
    return finish unless stage

    begin
      stage.call
    rescue Exception => e # rubocop:disable Lint/RescueException
      @failures += 1
      log("ECHEC étape : #{e.class} #{e.message} #{e.backtrace.first(3).join(' | ')}")
    end
    UI.start_timer(DELAY_S, false) { advance }
  end

  def finish
    log("FIN #{@failures} echec(s), ARCHGEN #{Archgen::VERSION}, SketchUp #{Sketchup.version}, Ruby #{RUBY_VERSION}")
  end

  def run
    @lines = []
    @failures = 0
    @service = nil
    @queue = stages
    log("H15 départ #{Time.now}, ARCHGEN #{Archgen::VERSION}, code #{Sketchup.extensions['ARCHGEN'].extension_path}")
    advance
    'recette lancee'
  end
end
