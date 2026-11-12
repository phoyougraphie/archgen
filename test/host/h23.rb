# frozen_string_literal: true

require 'json'

# Recette H23, à lancer sur un document neuf, panneaux fermés :
#   load '.../test/host/h23.rb'; ArchgenH23Probe.run
# Eau et littoral (EXT-13) par le service : rivière sur un terrain en vallée qui descend, avec une bosse
# (AG-053, copie entaillée, eau jamais remontante), canal horizontal (AG-051), côte à falaises (AG-052),
# Annuler et Rétablir, tracé à contre-pente refusé, enregistrement. Rapport : tmp/h23.txt.
module ArchgenH23Probe
  REPO = File.expand_path('../..', __dir__)
  REPORT = File.join(REPO, 'tmp', 'h23.txt')
  SKP = File.join(REPO, 'tmp', 'h23.skp')
  SP = Archgen::Adapters::SketchUp
  DICTIONARY = 'archgen.road'
  INCH = 0.0254
  DELAY_S = 1.2
  # Vallée le long de x, fond en y = 20, pente de 1,5 % vers +x, bosse de 0,6 m en x = 70.
  HEIGHT = ->(x, y) { 12.0 - (0.015 * x) + (0.04 * (y - 20).abs) + (0.6 * Math.exp(-((x - 70)**2) / 200.0)) }
  RIVER_ORIGIN = [10.0, 20.0, 0.0].freeze
  # Second terrain pour le canal (AG-054) : pente de 5 % en x, de y = 200 à 260 m.
  CANAL_HEIGHT = ->(x, _y) { 15.0 - (0.05 * x) }
  CANAL_ORIGIN = [10.0, 230.0, 0.0].freeze
  # Terrains du fleuve (pente de 0,5 %) et de la plage (plat à 5 m), AG-055.
  RIVER_FLAT_HEIGHT = ->(x, _y) { 8.0 - (0.005 * x) }
  BEACH_HEIGHT = ->(_x, _y) { 5.0 }

  module_function

  def model
    Sketchup.active_model
  end

  def service
    SP::RoadService.new(intake: Archgen::Composition.road_intake, bands: Archgen::Composition.road_bands,
                        items: Archgen::Composition.road_items, materials: Archgen::Composition.road_catalog,
                        material_revision: Archgen::Composition.road_materials.fetch('schema_version'))
  end

  def preset(id)
    Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def river(points = [[0, 0], [120, 0]])
    { 'trace' => { 'points_m' => points, 'radii_m' => [] }, 'profile' => preset('riviere'), 'ground' => {}, 'water' => { 'mode' => 'river', 'max_grade_percent' => 5 } }
  end

  def flat(id, points)
    { 'trace' => { 'points_m' => points, 'radii_m' => [] }, 'profile' => preset(id), 'water' => { 'mode' => 'flat' } }
  end

  def log(line)
    @lines << line
    File.write(REPORT, "#{@lines.join("\n")}\n")
    puts line
  end

  def check(label, ok, detail = nil)
    @failures += 1 unless ok
    log("#{ok ? 'OK   ' : 'ECHEC'} #{label}#{detail ? " -- #{detail}" : ''}")
  end

  # Terrain de test : grille triangulée de 200 × 140 m au pas de 4 m, dans un groupe.
  def build_terrain(name = 'Terrain H23', height = HEIGHT, nx = 50, ny = 35, x0 = -20, y0 = -50)
    model.start_operation(name, true)
    group = model.entities.add_group
    group.name = name
    mesh = Geom::PolygonMesh.new
    step = 4.0
    (0...nx).each do |i|
      (0...ny).each do |j|
        p = lambda { |a, b| x = x0 + (a * step); y = y0 + (b * step); Geom::Point3d.new(x.m, y.m, height.call(x, y).m) }
        mesh.add_polygon(p.call(i, j), p.call(i + 1, j), p.call(i + 1, j + 1))
        mesh.add_polygon(p.call(i, j), p.call(i + 1, j + 1), p.call(i, j + 1))
      end
    end
    group.entities.fill_from_mesh(mesh, true, Geom::PolygonMesh::NO_SMOOTH_OR_HIDE)
    model.commit_operation
    group
  end

  def roads
    model.entities.grep(Sketchup::ComponentInstance).select { |i| i.get_attribute(DICTIONARY, 'road_version') }
  end

  def copies
    model.entities.to_a.select { |e| e.respond_to?(:get_attribute) && e.get_attribute(SP::GroundCutter::DICTIONARY, 'terrain_pid') }
  end

  def deep_faces(entities, memo = {})
    entities.sum do |entity|
      case entity
      when Sketchup::Face then 1
      when Sketchup::Group then deep_faces(entity.entities, memo)
      when Sketchup::ComponentInstance then memo[entity.definition] ||= deep_faces(entity.definition.entities, memo)
      else 0
      end
    end
  end

  def water_group(road)
    road.definition.entities.grep(Sketchup::Group).find { |g| g.name == 'road/water' }
  end

  # Points de la surface de l'eau en repère du modèle, en mètres.
  def water_points(road)
    group = water_group(road)
    t = road.transformation * group.transformation
    group.entities.grep(Sketchup::Face).flat_map { |f| f.vertices.map { |v| (t * v.position).to_a.map { |c| c * INCH } } }.uniq
  end

  def counts
    [model.entities.size, model.definitions.size, model.materials.size, model.layers.size, @terrain.hidden?]
  end

  def written(result, road)
    faces = deep_faces(road.definition.entities)
    [faces, result.value.metrics['expanded_face_count']]
  end

  def steps
    [
      ['Refus : rivière tracée vers l’amont, rien d’écrit', lambda {
        @reference = SP::TerrainRef.new(document_key: model.guid, persistent_id: @terrain.persistent_id)
        @before = counts
        @up = service.create(model: model, tree: river([[0, 0], [-120, 0]]), origin_m: [130.0, 20.0, 0.0], terrain: @reference)
      }, lambda {
        @last = "#{@up.errors.map { |d| [d.code, d.params['reason'], d.params['value']] }.inspect}, #{@before == counts}"
        !@up.ok? && @up.errors.first.params['reason'] == 'river_upstream' && counts == @before
      }],
      ['Créer une rivière sur le terrain : une opération, faces égales au plan', lambda {
        @reference = SP::TerrainRef.new(document_key: model.guid, persistent_id: @terrain.persistent_id)
        t = Time.now
        @river = service.create(model: model, tree: river, origin_m: RIVER_ORIGIN, terrain: @reference)
        seconds = Time.now - t
        return false.tap { @last = @river.errors.map(&:to_h).inspect } unless @river.ok?

        road = roads.first
        m = @river.value.metrics
        faces, expected = written(@river, road)
        @last = format('%.2f s, racine z %.3f, faces %d/%d, chute %.3f m, pente %.2f %%, déblai %.2f, remblai %.2f',
                       seconds, road.transformation.to_a[14] * INCH, faces, expected, m['water_drop_m'], m['grade_max_percent'], m['cut_max_m'], m['fill_max_m'])
        faces == expected && m['water_drop_m'].positive?
      }],
      ['Eau horizontale en travers, jamais remontante, matière à 0,6 d’opacité', lambda {
        road = roads.first
        pts = water_points(road)
        by_x = pts.group_by { |x, _y, _z| x.round(3) }.sort.map { |_x, list| list.map { |p| p[2].round(4) }.uniq }
        level = by_x.map(&:first)
        material = water_group(road).entities.grep(Sketchup::Face).first.material
        @last = "#{by_x.size} sections, niveaux #{level.first.round(3)} → #{level.last.round(3)} m, opacité #{material&.alpha&.round(3)}, matière #{material&.name}"
        by_x.all? { |zs| zs.size == 1 } && level.each_cons(2).all? { |a, b| b <= a + 1e-6 } && material && (material.alpha - 0.6).abs < 0.01
      }],
      ['Original masqué et intact, copie unique entaillée', lambda {
        copy = copies.first
        faces = @terrain.entities.grep(Sketchup::Face).size
        @last = "original #{faces} faces (avant #{@original_faces}), masqué #{@terrain.hidden?}, copies #{copies.size}"
        @terrain.hidden? && faces == @original_faces && copies.size == 1 && copy.definition != @terrain.definition
      }],
      ['Annuler : rivière et copie disparaissent', -> { Sketchup.undo }, lambda {
        roads.empty? && copies.empty? && !@terrain.hidden?
      }],
      ['Rétablir : tout revient', -> { Sketchup.redo }, -> { roads.size == 1 && copies.size == 1 && @terrain.hidden? }],
      ['Canal horizontal hors du terrain : faces égales au plan, eau à −0,8 m', lambda {
        @canal = service.create(model: model, tree: flat('canal', [[0, 0], [80, 0]]), origin_m: [10.0, -90.0, 0.0])
        return false.tap { @last = @canal.errors.map(&:to_h).inspect } unless @canal.ok?

        road = roads.find { |r| (r.transformation.to_a[13] * INCH + 90).abs < 1e-6 }
        faces, expected = written(@canal, road)
        zs = water_points(road).map { |p| p[2].round(4) }.uniq
        @last = "faces #{faces}/#{expected}, niveaux d’eau #{zs.inspect}"
        faces == expected && zs == [-0.8]
      }],
      ['Côte à falaises : mer à −25 m, faces égales au plan', lambda {
        @coast = service.create(model: model, tree: flat('falaises', [[0, 0], [100, 0]]), origin_m: [10.0, -400.0, 0.0])
        return false.tap { @last = @coast.errors.map(&:to_h).inspect } unless @coast.ok?

        road = roads.find { |r| (r.transformation.to_a[13] * INCH + 400).abs < 1e-6 }
        faces, expected = written(@coast, road)
        zs = water_points(road).map { |p| p[2].round(4) }.uniq
        @last = "faces #{faces}/#{expected}, mer #{zs.inspect}"
        faces == expected && zs == [-25.0]
      }],
      ['Canal à écluses sur un second terrain : une opération, faces égales au plan, quatre écluses', lambda {
        reference = SP::TerrainRef.new(document_key: model.guid, persistent_id: @canal_terrain.persistent_id)
        tree = { 'trace' => { 'points_m' => [[0, 0], [260, 0]], 'radii_m' => [] }, 'profile' => preset('canal'), 'ground' => {}, 'water' => { 'mode' => 'canal' } }
        t = Time.now
        @canal_ground = service.create(model: model, tree: tree, origin_m: CANAL_ORIGIN, terrain: reference)
        seconds = Time.now - t
        return false.tap { @last = @canal_ground.errors.map(&:to_h).inspect } unless @canal_ground.ok?

        road = roads.find { |r| (r.transformation.to_a[13] * INCH - 230).abs < 1e-6 }
        faces, expected = written(@canal_ground, road)
        m = @canal_ground.value.metrics
        pts = water_points(road)
        by_x = pts.group_by { |x, _y, _z| x.round(3) }.sort.map { |_x, list| list.map { |p| p[2] }.min }
        gates = road.definition.entities.grep(Sketchup::Group).find { |g| g.name == 'road/locks' }
        gate_count = gates ? gates.entities.grep(Sketchup::Group).size : 0
        @last = format('%.2f s, faces %d/%d, écluses %d, chute %.2f m, portes %d, eau %.2f → %.2f m', seconds, faces, expected, m['lock_count'], m['water_drop_m'], gate_count, by_x.first, by_x.last)
        faces == expected && m['lock_count'] == 4 && gate_count == 8 && by_x.each_cons(2).all? { |a, b| b <= a + 1e-6 }
      }],
      ['Annuler le canal : son terrain réapparaît, les autres voies restent', -> { Sketchup.undo }, lambda {
        !@canal_terrain.hidden? && roads.size == 3
      }],
      ['Rétablir le canal', -> { Sketchup.redo }, -> { @canal_terrain.hidden? && roads.size == 4 }],
      ['Fleuve à un seul niveau sur un terrain : faces égales au plan, eau à un niveau', lambda {
        reference = SP::TerrainRef.new(document_key: model.guid, persistent_id: @flat_terrain.persistent_id)
        tree = { 'trace' => { 'points_m' => [[0, 0], [100, 0]], 'radii_m' => [] }, 'profile' => preset('fleuve'), 'ground' => {}, 'water' => { 'mode' => 'flat' } }
        result = service.create(model: model, tree: tree, origin_m: [10.0, -192.0, 0.0], terrain: reference)
        return false.tap { @last = result.errors.map(&:to_h).inspect } unless result.ok?

        road = roads.find { |r| (r.transformation.to_a[13] * INCH + 192).abs < 1e-6 }
        faces, expected = written(result, road)
        zs = water_points(road).map { |p| p[2].round(4) }.uniq
        @last = "faces #{faces}/#{expected}, racine #{(road.transformation.to_a[14] * INCH).round(3)} m, eau #{zs.inspect}, terrain masqué #{@flat_terrain.hidden?}"
        faces == expected && zs.size == 1 && @flat_terrain.hidden?
      }],
      ['Plage sur un terrain plat : pas de talus côté mer, mer à 3 m', lambda {
        reference = SP::TerrainRef.new(document_key: model.guid, persistent_id: @beach_terrain.persistent_id)
        tree = { 'trace' => { 'points_m' => [[0, 0], [100, 0]], 'radii_m' => [] }, 'profile' => preset('plage'), 'ground' => {}, 'water' => { 'mode' => 'flat', 'level_m' => 5 } }
        grid = service.survey(model: model, tree: tree, origin_m: [10.0, 450.0, 0.0], terrain: reference).value
        shown = service.preview(tree: tree, survey: grid).value.plan
        result = service.create(model: model, tree: tree, origin_m: [10.0, 450.0, 0.0], terrain: reference)
        return false.tap { @last = result.errors.map(&:to_h).inspect } unless result.ok?

        road = roads.find { |r| (r.transformation.to_a[13] * INCH - 450).abs < 1e-6 }
        faces, expected = written(result, road)
        zs = water_points(road).map { |p| p[2].round(4) }.uniq
        outline = shown['ground']['outline_m']
        half = shown['metrics']['width_m'] / 2
        open = outline.select { |_x, y| y.negative? }.all? { |_x, y| (y + half).abs < 1e-6 }
        @last = "faces #{faces}/#{expected}, mer #{zs.inspect}, côté mer sans talus #{open}"
        faces == expected && zs == [3.0] && open
      }],
      ['Enregistrer', -> { model.save(SKP) }, -> { File.exist?(SKP) && roads.size == 6 }]
    ]
  end

  def advance
    step = @queue.shift
    return finish unless step

    label, action, check_block = step
    if check_block.nil?
      @last = nil
      ok = begin
        action.call
      rescue StandardError => e
        @last = "#{e.class} #{e.message} #{e.backtrace.first(2).join(' | ')}"
        false
      end
      check(label, ok, @last)
      return UI.start_timer(DELAY_S, false) { advance }
    end
    begin
      action.call
    rescue StandardError => e
      check("action #{label}", false, "#{e.class} #{e.message}")
      return advance
    end
    UI.start_timer(DELAY_S, false) do
      @last = nil
      begin
        check(label, check_block.call, @last)
      rescue StandardError => e
        check(label, false, "#{e.class} #{e.message}")
      end
      advance
    end
  end

  def finish
    log("FIN #{@failures} echec(s), ARCHGEN #{Archgen::VERSION}, SketchUp #{Sketchup.version}, Ruby #{RUBY_VERSION}")
  end

  def run
    @lines = []
    @failures = 0
    model.options['UnitsOptions']['LengthUnit'] = 4
    log("H23 départ #{Time.now}, ARCHGEN #{Archgen::VERSION}")
    @terrain = build_terrain
    @original_faces = @terrain.entities.grep(Sketchup::Face).size
    @canal_terrain = build_terrain('Terrain H23 canal', CANAL_HEIGHT, 80, 15, -20, 200)
    @flat_terrain = build_terrain('Terrain H23 fleuve', RIVER_FLAT_HEIGHT, 40, 44, -20, -280)
    @beach_terrain = build_terrain('Terrain H23 plage', BEACH_HEIGHT, 40, 75, -20, 300)
    log("Terrain de test : #{@original_faces} faces")
    @queue = steps
    UI.start_timer(0.5, false) { advance }
    'recette lancee'
  end
end
