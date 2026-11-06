# frozen_string_literal: true

require 'json'

# Recette H13, partie relevé (AG-024), à lancer une fois sur un modèle neuf :
#   load '.../test/host/survey.rb'; ArchgenSurveyProbe.run
# Passe par le service réel et le vrai raytest, sur un terrain imbriqué et pivoté dont l'altitude
# est connue partout. Rapport : tmp/h13-releve.txt. Le modèle de test est enregistré dans tmp/.
module ArchgenSurveyProbe
  REPO = File.expand_path('../..', __dir__)
  REPORT = File.join(REPO, 'tmp', 'h13-releve.txt')
  SKP = File.join(REPO, 'tmp', 'h13-releve.skp')
  SP = Archgen::Adapters::SketchUp
  INCH = 0.0254
  SIZE_M = 60
  TOLERANCE_M = 0.001
  OFFSET_M = [100.0, 50.0, 7.0].freeze
  TURN_DEG = 20.0
  ROOT_AT = [24.0, 22.0].freeze
  ROOT_TURN_DEG = 30.0
  STEP_DELAY_S = 1.2
  DRAFT = { 'schema_version' => 1, 'profile' => { 'id' => 'generic' }, 'name' => 'Relevé', 'mode' => 'shell',
            'footprint' => { 'width_m' => 12.0, 'depth_m' => 9.0 } }.freeze

  module_function

  def model
    Sketchup.active_model
  end

  def service
    @service ||= SP::BuildingService.default(allow_internal: true)
  end

  def log(line)
    @lines << line
    File.binwrite(REPORT, "#{@lines.join("\n")}\n")
  end

  def check(label, ok, detail = nil)
    @failures += 1 unless ok
    log("#{ok ? 'OK   ' : 'ECHEC'} #{label}#{detail.nil? ? '' : " : #{detail}"}")
    ok
  end

  def m(value)
    value / INCH
  end

  def timed
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    value = yield
    [value, ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)]
  end

  def height(x, y)
    (0.06 * x) + (0.03 * y) + (0.9 * Math.sin(x / 7.0) * Math.cos(y / 9.0))
  end

  def build_terrain
    outer = model.entities.add_group
    outer.name = 'Terrain H13'
    inner = outer.entities.add_group
    mesh = Geom::PolygonMesh.new
    points = {}
    (0..SIZE_M).each { |x| (0..SIZE_M).each { |y| points[[x, y]] = mesh.add_point(Geom::Point3d.new(m(x), m(y), m(height(x, y)))) } }
    (0...SIZE_M).each do |x|
      (0...SIZE_M).each do |y|
        mesh.add_polygon(points[[x, y]], points[[x + 1, y]], points[[x + 1, y + 1]])
        mesh.add_polygon(points[[x, y]], points[[x + 1, y + 1]], points[[x, y + 1]])
      end
    end
    inner.entities.add_faces_from_mesh(mesh, Geom::PolygonMesh::HIDE_BASED_ON_INDEX)
    outer.transformation = Geom::Transformation.translation(OFFSET_M.map { |v| m(v) }) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, TURN_DEG.degrees)
    outer
  end

  # Altitude exacte du maillage : plan du triangle qui contient le point.
  def exact_altitude(local_x, local_y)
    i = local_x.floor
    j = local_y.floor
    fx = local_x - i
    fy = local_y - j
    a = height(i, j)
    c = height(i + 1, j + 1)
    z = if fy <= fx
          a + (fx * (height(i + 1, j) - a)) + (fy * (c - height(i + 1, j)))
        else
          a + (fy * (height(i, j + 1) - a)) + (fx * (c - height(i, j + 1)))
        end
    z + OFFSET_M[2]
  end

  # Point (x, y) du bâtiment, dans le repère du terrain, en mètres.
  def terrain_coordinates(root, x_m, y_m)
    world = Geom::Point3d.new(m(x_m), m(y_m), 0).transform(root.transformation)
    local = world.transform(@terrain.transformation.inverse)
    [local.x.to_f * INCH, local.y.to_f * INCH]
  end

  def select_only(entity)
    model.selection.clear
    model.selection.add(entity)
  end

  def inventory
    [model.entities.length, model.definitions.length, model.materials.count, model.layers.count]
  end

  def reason_of(result)
    result.errors.first&.params&.fetch('reason', nil)
  end

  def prepare
    @terrain = build_terrain
    created = service.create(model: model, draft: DRAFT)
    raise created.errors.map(&:to_h).inspect unless created.ok?

    @root = model.find_entity_by_persistent_id(created.value.persistent_id)
    place = Geom::Point3d.new(m(ROOT_AT[0]), m(ROOT_AT[1]), m(height(*ROOT_AT))).transform(@terrain.transformation)
    model.start_operation('Placement H13', true)
    @root.transformation = Geom::Transformation.translation(place.to_a) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, ROOT_TURN_DEG.degrees)
    model.commit_operation
    log("MESURE terrain : #{@terrain.entities.grep(Sketchup::Group).first.entities.grep(Sketchup::Face).size} faces ; extension #{Archgen::VERSION}, code #{Sketchup.extensions['ARCHGEN'].extension_path}")
  end

  def target
    select_only(@root)
    service.load_selection(model: model).value.target
  end

  def retain_refusals
    model.selection.clear
    check('Aucune sélection : refusé', reason_of(service.retain_terrain(model: model)) == 'terrain_selection')
    select_only(@root)
    check('Un bâtiment : refusé', reason_of(service.retain_terrain(model: model)) == 'terrain_is_building')
    model.selection.clear
    model.selection.add([@root, @terrain])
    check('Deux entités : refusé', reason_of(service.retain_terrain(model: model)) == 'terrain_selection')
    model.start_operation('Face libre H13', true)
    face = model.entities.add_face([m(-30), m(-30), 0], [m(-28), m(-30), 0], [m(-28), m(-28), 0])
    model.commit_operation
    select_only(face)
    check('Une face libre : refusé', reason_of(service.retain_terrain(model: model)) == 'terrain_kind')
    select_only(@terrain)
    retained = service.retain_terrain(model: model)
    check('Terrain retenu', retained.ok?, retained.errors.map(&:to_h).inspect)
    @ref = retained.value
    inner = @terrain.entities.grep(Sketchup::Group).first
    nested = SP::TerrainRef.new(document_key: model.guid, persistent_id: inner.persistent_id)
    check('Référence à une entité imbriquée : refusée', reason_of(service.survey_site(model: model, target: target, terrain: nested, site: {})) == 'terrain_nested')
    other = SP::TerrainRef.new(document_key: 'autre', persistent_id: @ref.persistent_id)
    check('Autre document : refusé', reason_of(service.survey_site(model: model, target: target, terrain: other, site: {})) == 'terrain_other_document')
  end

  def survey(site = {}, root_target: target)
    service.survey_site(model: model, target: root_target, terrain: @ref, site: site)
  end

  # Le cœur de la preuve : chaque nœud est comparé à l'altitude exacte du maillage.
  def altitudes(label, site)
    result, ms = timed { survey(site) }
    return check("#{label} : relevé", false, result.errors.map(&:to_h).inspect) unless result.ok?

    grid = result.value.grid
    worst = 0.0
    compared = 0
    grid.ys.each_with_index do |y, j|
      grid.xs.each_with_index do |x, i|
        z = grid.z(i, j)
        next if z.nil?

        local = terrain_coordinates(@root, x, y)
        next unless local.all? { |v| v.between?(0.0, SIZE_M - 1e-6) }

        worst = [worst, (z - exact_altitude(*local)).abs].max
        compared += 1
      end
    end
    check("#{label} : altitudes à ±1 mm sur #{compared} nœuds", worst <= TOLERANCE_M && compared.positive?, "écart max #{(worst * 1000).round(4)} mm")
    log("MESURE #{label} : #{grid.xs.size}x#{grid.ys.size} nœuds en #{ms} ms ; plateforme #{result.value.assise['platform_z_m']}, relief #{result.value.assise['relief_m']}, remblai #{result.value.assise['fill_max_m']}")
    result.value
  end

  def writes_nothing
    before = inventory
    modified = model.modified?
    first = survey
    second = survey
    check('Relevé : mêmes entités, définitions, matériaux et tags', before == inventory, "#{before} / #{inventory}")
    check('Relevé : état « modifié » inchangé', modified == model.modified?)
    check('Deux relevés : même empreinte', first.ok? && first.value.survey_digest == second.value.survey_digest)
    check('Rien n’est écrit sur le terrain', @terrain.attribute_dictionaries.nil? || @terrain.attribute_dictionaries.count.zero?)
  end

  def core_in_host(result)
    config = BuildingConfigReader.call(@root)
    plan = Archgen::Core::GeometryEngine.generate(config, materials: Archgen::Composition.materials['materials']).value
    planned = lambda do |value|
      Archgen::Geometry::SitePlanner.call(plan: plan, config: config.to_h, grid: value.grid, settings: value.settings, assise: value.assise,
                                          materials: Archgen::Composition.site_materials)
    end
    plinth = planned.call(result)
    check('Noyau dans le Ruby de SketchUp : plan de soubassement', plinth.ok?, plinth.errors.map(&:to_h).inspect)
    embankment_survey = survey({ 'earthwork' => 'embankment' })
    if check('Relevé avec marge du talus', embankment_survey.ok?, embankment_survey.errors.map(&:to_h).inspect)
      embankment = planned.call(embankment_survey.value)
      check('Noyau dans le Ruby de SketchUp : plan de talus', embankment.ok?, embankment.errors.map(&:to_h).inspect)
      log("MESURE talus : #{embankment.value['metrics']['site_face_count']} faces, emprise #{embankment.value['metrics']['embankment_reach_m']} m") if embankment.ok?
    end
    log("MESURE soubassement : #{plinth.value['metrics']['site_face_count']} faces, seuil #{plinth.value['metrics']['door_gap_m']} m") if plinth.ok?
    log("Avertissements : #{plinth.warnings.map(&:code).join(', ')}")
  end

  module BuildingConfigReader
    module_function

    def call(root)
      SP::BuildingService.default(allow_internal: true).load_building(model: Sketchup.active_model, persistent_id: root.persistent_id).value.config
    end
  end

  # Un arbre au-dessus d'un nœud : l'altitude ne doit pas bouger.
  def obstacle
    before = survey.value.grid
    corner = Geom::Point3d.new(m(6.0), m(3.6), 0).transform(@root.transformation)
    local = terrain_coordinates(@root, 6.0, 3.6)
    z = m(exact_altitude(*local) + 3.0)
    size = m(1.0)
    model.start_operation('Arbre H13', true)
    tree = model.entities.add_group
    face = tree.entities.add_face([corner.x - size, corner.y - size, z], [corner.x + size, corner.y - size, z],
                                  [corner.x + size, corner.y + size, z], [corner.x - size, corner.y + size, z])
    face.pushpull(size)
    model.commit_operation
    after = survey
    check('Obstacle au-dessus d’un nœud : relevé identique', after.ok? && after.value.survey_digest == before.digest,
          after.ok? ? nil : after.errors.map(&:to_h).inspect)
    model.start_operation('Retrait arbre H13', true)
    tree.erase!
    model.commit_operation
  end

  def tilted
    keep = @root.transformation
    model.start_operation('Inclinaison H13', true)
    @root.transformation = keep * Geom::Transformation.rotation(ORIGIN, X_AXIS, 10.degrees)
    model.commit_operation
    check('Racine inclinée : refusée', reason_of(survey) == 'not_horizontal')
    model.start_operation('Redressement H13', true)
    @root.transformation = keep
    model.commit_operation
  end

  def hidden_terrain
    t = target
    @terrain.hidden = true
    check('Terrain masqué : refusé', reason_of(survey({}, root_target: t)) == 'terrain_hidden')
    @terrain.hidden = false
    tag = model.layers.add('Tag H13')
    @terrain.layer = tag
    tag.visible = false
    check('Tag du terrain masqué : refusé', reason_of(survey({}, root_target: t)) == 'terrain_hidden')
    tag.visible = true
    @terrain.layer = model.layers[0]
  end

  def nested_context
    t = target
    model.active_path = [@terrain]
    check('Terrain ouvert en édition : relevé refusé', reason_of(survey({}, root_target: t)) == 'nested_edit_context')
    check('Terrain ouvert en édition : retenir refusé', reason_of(service.retain_terrain(model: model)) == 'nested_edit_context')
    model.active_path = nil
    select_only(@root)
  end

  # Trou sous le premier angle du bâtiment : le relevé réel doit le signaler à cet endroit.
  def hole
    corner = Geom::Point3d.new(0, 0, 0).transform(@root.transformation)
    ray = [Geom::Point3d.new(corner.x, corner.y, @terrain.bounds.max.z + m(1)), Geom::Vector3d.new(0, 0, -1)]
    model.start_operation('Trou H13', true)
    # Le rayon touche d'abord le bâtiment : seul ce qui appartient au terrain est effacé.
    40.times do
      hit = model.raytest(ray, true)
      break unless hit

      hit[1].first == @terrain ? hit[1].last.erase! : ray = [hit[0], ray[1]]
    end
    model.commit_operation
    result = survey
    check('Trou sous l’emprise : refusé', reason_of(result) == 'missing_points', reason_of(result))
    check('Trou : position relevée', result.errors.first&.params&.fetch('points', [])&.include?([0.0, 0.0]), result.errors.first&.params&.fetch('points', nil).inspect)
  end

  def sentinel_step
    model.start_operation('Sentinelle H13', true)
    @root.set_attribute('autre.extension', 'cle', 'valeur')
    model.commit_operation
    survey
    survey({ 'earthwork' => 'embankment' })
    Sketchup.undo
  end

  def sentinel_check
    check('Annuler après deux relevés retire la sentinelle : aucune ligne ajoutée', @root.get_attribute('autre.extension', 'cle').nil?)
  end

  def timings
    [%w[plinth 2], %w[plinth 1], %w[embankment 2]].each do |earthwork, step|
      site = { 'earthwork' => earthwork, 'survey' => { 'step_m' => step.to_f } }
      result, ms = timed { survey(site) }
      nodes = result.ok? ? result.value.grid.xs.size * result.value.grid.ys.size : 0
      log("MESURE temps #{earthwork} pas #{step} : #{nodes} nœuds en #{ms} ms#{result.ok? ? '' : " ; #{reason_of(result)}"}")
    end
  end

  def steps
    [
      -> { prepare },
      -> { retain_refusals },
      -> { @plinth = altitudes('Soubassement, pas de 2 m', {}) },
      -> { altitudes('Soubassement, pas de 1 m', { 'survey' => { 'step_m' => 1 } }) },
      -> { altitudes('Talus, avec marge', { 'earthwork' => 'embankment' }) },
      -> { writes_nothing },
      -> { core_in_host(@plinth) },
      -> { obstacle },
      -> { tilted },
      -> { hidden_terrain },
      -> { nested_context },
      -> { timings },
      -> { sentinel_step },
      -> { sentinel_check },
      -> { hole }
    ]
  end

  def advance
    step = @queue.shift
    return finish unless step

    begin
      step.call
    rescue StandardError => e
      @failures += 1
      log("ECHEC exception #{e.class} #{e.message} #{e.backtrace.first(3).join(' | ')}")
    end
    UI.start_timer(STEP_DELAY_S, false) { advance }
  end

  def finish
    model.save(SKP)
    log("FIN #{@failures} echec(s), SketchUp #{Sketchup.version}, Ruby #{RUBY_VERSION}, moteur #{Archgen::ENGINE_VERSION}")
  end

  def run
    @lines = []
    @failures = 0
    @queue = steps
    advance
    'recette lancee'
  end
end
