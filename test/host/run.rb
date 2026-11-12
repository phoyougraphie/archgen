# frozen_string_literal: true

# Sonde native de la recette H02. Script de développement, jamais chargé par le produit
# ni inclus dans le RBZ. À charger dans la console d'un modèle de test :
#   load 'C:/chemin/du/depot/test/host/run.rb'
#   ArchgenHostProbe.run('metres', 0)
# Elle ajoute de la géométrie au modèle courant : ne pas enregistrer ce modèle.
module ArchgenHostProbe
  REPO = File.expand_path('../..', __dir__)
  INCH = 0.0254
  TOLERANCE_M = 0.001
  STEP_X_M = 25.0
  FIRST_X_M = 25.0
  HOMONYM_MATERIAL = 'ARCHGEN Béton brut'
  HOMONYM_TAG = 'ARCHGEN Toiture'
  ROOFS = {
    'gable' => { 'type' => 'gable', 'overhang_m' => 0.3, 'pitch_deg' => 30.0 },
    'hip' => { 'type' => 'hip', 'overhang_m' => 0.3, 'pitch_deg' => 30.0 },
    'mansard' => { 'type' => 'mansard', 'overhang_m' => 0.15, 'pitch_deg' => 25.0, 'lower_pitch_deg' => 65.0, 'inset_m' => 0.9 }
  }.freeze
  NORMALS = { 'front' => [0, -1, 0], 'right' => [1, 0, 0], 'rear' => [0, 1, 0], 'left' => [-1, 0, 0] }.freeze

  class Report
    attr_reader :lines, :failures

    def initialize
      @lines = []
      @failures = 0
    end

    def note(text)
      @lines << text
    end

    def check(label, ok, detail = nil)
      @failures += 1 unless ok
      @lines << "#{ok ? 'OK  ' : 'ECHEC'} #{label}#{detail ? " : #{detail}" : ''}"
    end

    def near(label, expected, actual, tolerance = TOLERANCE_M)
      check(label, (expected - actual).abs <= tolerance, format('attendu %.5f, mesuré %.5f', expected, actual))
    end
  end

  module_function

  # y_offset_m sépare les passages dans un même modèle.
  def run(label, y_offset_m)
    model = Sketchup.active_model
    report = Report.new
    header(model, label, report)
    prepare_homonyms(model)
    resources = Archgen::Adapters::SketchUp::Resources.new(
      model, catalog: Archgen::Composition.materials.fetch('materials'),
             revision: Archgen::Composition.materials.fetch('schema_version')
    )
    active_before = model.active_layer
    started = model.start_operation("ARCHGEN : sonde H02 #{label}", true)
    report.check('start_operation', started)
    begin
      x = FIRST_X_M
      scenarios.each do |name, config|
        write_scenario(model, name, config, resources, [x, y_offset_m], report)
        x += STEP_X_M
      end
      model.commit_operation
    rescue StandardError => e
      model.abort_operation
      report.check('exception', false, "#{e.class}: #{e.message}")
    end
    report.check('Tag actif inchangé', model.active_layer == active_before)
    check_homonyms(model, report)
    model.active_view.zoom_extents
    finish(label, report)
  end

  def header(model, label, report)
    report.note("H02 #{label} - SketchUp #{Sketchup.version} Ruby #{RUBY_VERSION} #{Sketchup.platform}")
    report.note("Moteur #{Archgen::ENGINE_VERSION}, extension #{Archgen::VERSION}")
    report.note("LengthUnit #{model.options['UnitsOptions']['LengthUnit']} (0 pouces, 4 mètres)")
  end

  def scenarios
    intake = Archgen::Composition.intake
    shell = load_config(intake, 'rect-neutre-shell')
    structural = load_config(intake, 'rect-neutre-structural')
    list = { 'neutre-shell' => shell, 'neutre-structural' => structural }
    ROOFS.each do |type, roof|
      list["structural-#{type}"] = Archgen::Core::Merge.leaves(structural, 'roof' => { 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0 }.merge(roof))
    end
    list
  end

  def load_config(intake, name)
    intake.effective(File.read(File.join(REPO, 'examples', 'buildings', "#{name}.json"), mode: 'rb', encoding: 'UTF-8')).value
  end

  def prepare_homonyms(model)
    unless model.materials[HOMONYM_MATERIAL]
      user = model.materials.add(HOMONYM_MATERIAL)
      user.color = Sketchup::Color.new(255, 0, 0)
    end
    model.layers.add(HOMONYM_TAG) unless model.layers[HOMONYM_TAG]
  end

  def check_homonyms(model, report)
    user = model.materials[HOMONYM_MATERIAL]
    report.check('Matériau homonyme intact', user.color.red == 255 && user.color.green.zero? && user.get_attribute('archgen.resource', 'kind').nil?)
    tag = model.layers[HOMONYM_TAG]
    report.check('Tag homonyme intact', tag.get_attribute('archgen.resource', 'kind').nil?)
  end

  def write_scenario(model, name, data, resources, offset_m, report)
    report.note("--- #{name}")
    config = Archgen::Core::BuildingConfig.new(data)
    result = Archgen::Core::GeometryEngine.generate(config, materials: Archgen::Composition.materials.fetch('materials'))
    unless result.ok?
      report.check('plan', false, result.errors.map(&:to_h).inspect)
      return
    end
    plan = result.value
    definition = model.definitions.add("ARCHGEN sonde #{name}")
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    stats = Archgen::Adapters::SketchUp::GeometryWriter.new.write(plan, entities: definition.entities, resources: resources)
    report.note(format('Écriture %.0f ms, %d faces, %d groupes', (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000, stats.face_count, stats.group_count))
    origin = offset_m.map { |c| c / INCH } + [0.0]
    instance = model.entities.add_instance(definition, Geom::Transformation.translation(origin))
    instance.name = name
    check_counts(definition, plan, report)
    check_bounds(definition, plan, data, report)
    check_organisation(model, definition, data, report)
    check_walls(definition, data, report)
    check_edges(definition, stats, report)
    check_roof(definition, report)
    check_openings(model, plan, data, offset_m, report)
  end

  def group_named(entities, name)
    entities.grep(Sketchup::Group).find { |g| g.name == name }
  end

  def all_faces(entities)
    entities.grep(Sketchup::Face) + entities.grep(Sketchup::Group).flat_map { |g| all_faces(g.entities) }
  end

  def check_counts(definition, plan, report)
    report.check('Nombre de faces natives', all_faces(definition.entities).size == plan['metrics']['expanded_face_count'],
                 "#{all_faces(definition.entities).size} / #{plan['metrics']['expanded_face_count']}")
  end

  def check_bounds(definition, plan, data, report)
    bounds = definition.bounds
    overhang = data['roof']['overhang_m']
    metrics = plan['metrics']
    report.near('Largeur hors débord + débords', metrics['width_m'] + (2 * overhang), bounds.width * INCH)
    report.near('Profondeur + débords', metrics['depth_m'] + (2 * overhang), bounds.height * INCH)
    report.near('Sommet', metrics['roof_top_z_m'], bounds.max.z * INCH)
  end

  def check_organisation(model, definition, data, report)
    walls = group_named(definition.entities, 'walls')
    report.check('Tag du conteneur murs', walls.layer.get_attribute('archgen.resource', 'id') == 'walls', walls.layer.name)
    front = group_named(walls.entities, 'wall/front')
    untagged = model.layers[0]
    report.check('Groupe et faces de mur Untagged', front.layer == untagged && front.entities.grep(Sketchup::Face).all? { |f| f.layer == untagged })
    material = front.entities.grep(Sketchup::Face).first.material
    report.check('Matériau de mur', material&.get_attribute('archgen.resource', 'id') == data['materials']['wall'], material&.display_name)
    roof = group_named(definition.entities, 'roof')
    report.check('Tag toiture distinct du tag utilisateur', roof.layer.name != HOMONYM_TAG, roof.layer.name)
    pan = all_faces(roof.entities).find { |f| f.material&.get_attribute('archgen.resource', 'id') == data['materials']['roof'] }
    report.check('Matériau de toit distinct du matériau utilisateur', pan && pan.material.name != HOMONYM_MATERIAL, pan&.material&.display_name)
  end

  def check_walls(definition, data, report)
    walls = group_named(definition.entities, 'walls')
    NORMALS.each do |id, normal|
      group = group_named(walls.entities, "wall/#{id}")
      data['mode'] == 'structural' ? check_solid(group, id, report) : check_surface(group, id, normal, report)
    end
    check_reference_values(definition, walls, data, report)
    slabs = group_named(definition.entities, 'slabs')
    return report.check('Pas de dalle en Shell', slabs.nil?) unless data['mode'] == 'structural'

    report.check('Trois dalles', slabs.entities.grep(Sketchup::Group).size == 3)
    slabs.entities.grep(Sketchup::Group).each do |slab|
      report.check("#{slab.name} manifold", slab.manifold?)
      report.near("#{slab.name} volume m3", 19.63008, slab.volume * (INCH**3), 0.001)
    end
  end

  # ADR-15 : seules les arêtes entre deux faces coplanaires de même matériau sont masquées.
  def check_edges(definition, stats, report)
    edges = all_edges(definition.entities)
    wrong = edges.count { |edge| edge.hidden? != grid_edge?(edge) }
    hidden = edges.count(&:hidden?)
    report.check('Arêtes de grille masquées, contours visibles', wrong.zero?, "#{hidden} masquées sur #{edges.size}, #{wrong} erronées")
    report.check('Compte des arêtes masquées', hidden == stats.hidden_edge_count, "#{hidden} / #{stats.hidden_edge_count}")
  end

  def all_edges(entities)
    entities.grep(Sketchup::Edge) + entities.grep(Sketchup::Group).flat_map { |g| all_edges(g.entities) }
  end

  def grid_edge?(edge)
    faces = edge.faces
    faces.size == 2 && faces[0].material == faces[1].material && faces[0].normal.samedirection?(faces[1].normal)
  end

  def check_surface(group, id, normal, report)
    faces = group.entities.grep(Sketchup::Face)
    aligned = faces.all? { |f| f.normal.x.round(6) == normal[0] && f.normal.y.round(6) == normal[1] && f.normal.z.round(6) == normal[2] }
    report.check("Normales extérieures #{id}", aligned, "#{faces.size} faces")
  end

  def check_solid(group, id, report)
    report.check("Mur #{id} manifold", group.manifold?)
    report.check("Volume positif #{id}", group.volume.positive?)
  end

  # Valeurs étalons du contrat, seulement sur le toit plat de référence.
  def check_reference_values(_definition, walls, data, report)
    if data['mode'] == 'shell'
      { 'front' => 119.00, 'rear' => 119.04 }.each do |id, area|
        group = group_named(walls.entities, "wall/#{id}")
        report.near("Aire #{id} m2", area, group.entities.grep(Sketchup::Face).sum(&:area) * (INCH**2), 0.001)
      end
    else
      report.near('Volume front m3', 27.82272, group_named(walls.entities, 'wall/front').volume * (INCH**3), 0.001)
    end
  end

  def check_roof(definition, report)
    roof = group_named(definition.entities, 'roof')
    pans = roof.entities.grep(Sketchup::Group).select { |g| g.name.start_with?('roof/') && !g.name.start_with?('roof/gable') }
    upward = pans.flat_map { |g| g.entities.grep(Sketchup::Face) }.all? { |f| f.normal.z.positive? }
    report.check('Pans de toit vers le haut', upward, "#{pans.size} pans")
    roof.entities.grep(Sketchup::Group).select { |g| g.name.start_with?('roof/gable') }.each do |gable|
      face = gable.entities.grep(Sketchup::Face).first
      expected = gable.name.end_with?('right') ? 1.0 : -1.0
      report.check("Pignon #{gable.name} vers l'extérieur", (face.normal.x - expected).abs < 1e-6)
    end
  end

  # Un rayon normal au centre de chaque baie traverse le mur ; un rayon témoin s'y arrête.
  def check_openings(model, plan, data, offset_m, report)
    depth = data['structure']['wall_m']
    blocked = []
    plan['openings'].each do |opening|
      u = (opening['u_min_m'] + opening['u_max_m']) / 2.0
      z = (opening['z_min_m'] + opening['z_max_m']) / 2.0
      distance = first_hit_m(model, opening['facade_id'], u, z, data, offset_m)
      blocked << opening['id'] if distance && distance < depth + 0.05 + 0.01
    end
    report.check('Baies traversantes', blocked.empty?, "#{plan['openings'].size} rayons, bloquées : #{blocked.join(', ')}")
    witness = first_hit_m(model, 'front', 0.5, 1.0, data, offset_m)
    report.check('Rayon témoin arrêté par le mur', witness && (witness - 0.05).abs < 0.002, witness.inspect)
    threshold = door_threshold_hit(model, plan, data, offset_m)
    report.check('Pas de seuil de porte', threshold.nil? || threshold > depth + 0.06, threshold.inspect)
  end

  def door_threshold_hit(model, plan, data, offset_m)
    door = plan['openings'].find { |o| o['kind'] == 'door' }
    first_hit_m(model, 'front', (door['u_min_m'] + door['u_max_m']) / 2.0, 0.01, data, offset_m)
  end

  def first_hit_m(model, facade, u, z, data, offset_m)
    width = data['footprint']['width_m']
    depth = data['footprint']['depth_m']
    origin, direction = case facade
                        when 'front' then [[u, -0.05], [0, 1, 0]]
                        when 'right' then [[width + 0.05, u], [-1, 0, 0]]
                        when 'rear' then [[width - u, depth + 0.05], [0, -1, 0]]
                        else [[-0.05, depth - u], [1, 0, 0]]
                        end
    start = Geom::Point3d.new((origin[0] + offset_m[0]) / INCH, (origin[1] + offset_m[1]) / INCH, z / INCH)
    hit = model.raytest([start, Geom::Vector3d.new(*direction)], true)
    hit ? start.distance(hit[0]) * INCH : nil
  end

  def finish(label, report)
    report.note("RESULTAT #{report.failures.zero? ? 'REUSSI' : "#{report.failures} ECHEC(S)"}")
    dir = File.join(REPO, 'tmp')
    Dir.mkdir(dir) unless File.directory?(dir)
    path = File.join(dir, "h02-#{label}.txt")
    File.binwrite(path, "#{report.lines.join("\n")}\n")
    puts report.lines.last
    puts path
    report.failures
  end
end
