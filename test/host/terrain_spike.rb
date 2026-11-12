# frozen_string_literal: true

# Sonde de faisabilité d'EXT-10, à lancer une fois dans la console sur un modèle de test :
#   load '.../test/host/terrain_spike.rb'; ArchgenTerrainSpike.run
# Mesure ce que raytest fait vraiment sur un terrain imbriqué et pivoté. Rapport : tmp/terrain-spike.txt.
# Le produit n'en dépend pas ; les réponses fixent docs/TERRAIN_CONTRACT.md.
module ArchgenTerrainSpike
  REPO = File.expand_path('../..', __dir__)
  REPORT = File.join(REPO, 'tmp', 'terrain-spike.txt')
  SIZE_M = 60
  STEP_M = 1
  GRID = 121
  ABOVE_M = 500.0
  DOWN = Geom::Vector3d.new(0, 0, -1)
  OFFSET_M = [100.0, 50.0, 7.0].freeze
  TURN_DEG = 20.0

  module_function

  def m(value)
    value.m
  end

  def height(x, y)
    (0.08 * x) + (0.03 * y) + (1.5 * Math.sin(x / 7.0) * Math.cos(y / 9.0))
  end

  def log(line)
    @lines << line
    File.binwrite(REPORT, "#{@lines.join("\n")}\n")
  end

  def timed
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    value = yield
    [value, ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)]
  end

  def build_terrain(model)
    outer = model.entities.add_group
    outer.name = 'Terrain spike'
    inner = outer.entities.add_group
    mesh = Geom::PolygonMesh.new
    points = {}
    (0..SIZE_M).step(STEP_M) do |x|
      (0..SIZE_M).step(STEP_M) do |y|
        points[[x, y]] = mesh.add_point(Geom::Point3d.new(m(x), m(y), m(height(x, y))))
      end
    end
    (0...SIZE_M).step(STEP_M) do |x|
      (0...SIZE_M).step(STEP_M) do |y|
        a = points[[x, y]]
        b = points[[x + STEP_M, y]]
        c = points[[x + STEP_M, y + STEP_M]]
        d = points[[x, y + STEP_M]]
        mesh.add_polygon(a, b, c)
        mesh.add_polygon(a, c, d)
      end
    end
    inner.entities.add_faces_from_mesh(mesh, Geom::PolygonMesh::HIDE_BASED_ON_INDEX)
    outer.transformation = Geom::Transformation.translation(OFFSET_M.map { |v| m(v) }) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, TURN_DEG.degrees)
    outer
  end

  def world(outer, x, y, z = 0.0)
    Geom::Point3d.new(m(x), m(y), m(z)).transform(outer.transformation)
  end

  def ray_at(outer, x, y)
    point = world(outer, x, y)
    [Geom::Point3d.new(point.x, point.y, m(ABOVE_M)), DOWN]
  end

  def describe(hit)
    return 'rien' unless hit

    path = hit[1]
    "z=#{(hit[0].z.to_f * 0.0254).round(6)} chemin=#{path.map { |e| e.class.name.split('::').last }.join('>')}"
  end

  def vertices_exact(outer)
    worst = 0.0
    misses = 0
    (0..SIZE_M).step(5) do |x|
      (0..SIZE_M).step(5) do |y|
        hit = Sketchup.active_model.raytest(ray_at(outer, x, y), true)
        next misses += 1 unless hit

        worst = [worst, ((hit[0].z.to_f * 0.0254) - (height(x, y) + OFFSET_M[2])).abs].max
      end
    end
    log("MESURE sommets : écart max #{worst.round(9)} m, rayons sans impact #{misses}")
  end

  def timing(outer)
    model = Sketchup.active_model
    kinds = Hash.new(0)
    _, ms = timed do
      GRID.times do |i|
        GRID.times do |j|
          hit = model.raytest(ray_at(outer, 0.5 * i * SIZE_M / 60.0, 0.5 * j * SIZE_M / 60.0), true)
          kinds[hit ? hit[1].last.class.name : 'rien'] += 1
        end
      end
    end
    log("MESURE #{GRID}x#{GRID} rayons : #{ms} ms, derniers éléments #{kinds}")
  end

  # Un obstacle au-dessus du terrain : faut-il repartir sous son impact ?
  def obstacle(model, outer)
    x = 30.25
    y = 30.25
    base = world(outer, x, y, height(x, y) + 3.0)
    tree = model.entities.add_group
    tree.name = 'Arbre spike'
    size = m(1.0)
    face = tree.entities.add_face([base.x - size, base.y - size, base.z], [base.x + size, base.y - size, base.z],
                                  [base.x + size, base.y + size, base.z], [base.x - size, base.y + size, base.z])
    face.pushpull(size)
    first = model.raytest(ray_at(outer, x, y), true)
    log("Obstacle, premier impact : #{describe(first)} ; sur l'arbre #{first && first[1].first == tree}")
    passes = 0
    point = first
    while point && point[1].first != outer && passes < 12
      passes += 1
      point = model.raytest([point[0], DOWN], true)
    end
    log("Obstacle, reprise sous l'impact : #{passes} reprises, #{describe(point)} ; sur le terrain #{point && point[1].first == outer}")
    same = model.raytest([first[0], DOWN], true)
    log("Reprise au point exact : #{describe(same)} ; même élément #{same && first && same[1].last == first[1].last}")
    tree.erase!
  end

  def hole(model, outer)
    x = 10.25
    y = 10.75
    hit = model.raytest(ray_at(outer, x, y), true)
    log("Avant le trou : #{describe(hit)} ; dernier élément #{hit[1].last.class}")
    face = hit[1].last
    return log('Trou non testé : impact hors face') unless face.is_a?(Sketchup::Face)

    face.erase!
    log("Dans le trou : #{describe(model.raytest(ray_at(outer, x, y), true))}")
  end

  def hidden(model, outer)
    x = 40.25
    y = 20.25
    ray = ray_at(outer, x, y)
    log("Visible, wysiwyg vrai : #{describe(model.raytest(ray, true))}")
    outer.hidden = true
    log("Groupe masqué, wysiwyg vrai : #{describe(model.raytest(ray, true))}")
    log("Groupe masqué, wysiwyg faux : #{describe(model.raytest(ray, false))}")
    outer.hidden = false
    tag = model.layers.add('Tag spike')
    outer.layer = tag
    tag.visible = false
    log("Tag masqué, wysiwyg vrai : #{describe(model.raytest(ray, true))}")
    log("Tag masqué, wysiwyg faux : #{describe(model.raytest(ray, false))}")
    tag.visible = true
    outer.layer = model.layers[0]
  end

  def reversed(model, outer)
    x = 15.25
    y = 45.75
    hit = model.raytest(ray_at(outer, x, y), true)
    face = hit[1].last
    return log('Face inversée non testée : impact hors face') unless face.is_a?(Sketchup::Face)

    before = face.normal.z.round(3)
    face.reverse!
    after = model.raytest(ray_at(outer, x, y), true)
    log("Face inversée, nz #{before} → #{face.normal.z.round(3)} : #{describe(after)}")
  end

  # Poser une racine à l'altitude d'une plateforme : transformation et définition dans une opération.
  def lift(model)
    service = Archgen::Adapters::SketchUp::BuildingService.default(allow_internal: true)
    draft = { 'schema_version' => 1, 'profile' => { 'id' => 'generic' }, 'name' => 'Spike', 'mode' => 'shell' }
    created = service.create(model: model, draft: draft)
    root = model.find_entity_by_persistent_id(created.value.persistent_id)
    moved = Geom::Transformation.translation([m(3), m(4), 0]) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, 30.degrees)
    model.start_operation('Placement spike', true)
    root.transformation = moved
    model.commit_operation
    before = [root.persistent_id, root.transformation.to_a, root.definition.name]
    fresh = model.definitions.add('Spike remplacement')
    fresh.entities.add_face([0, 0, 0], [m(1), 0, 0], [m(1), m(1), 0])
    model.start_operation('Assise spike', true)
    root.definition = fresh
    root.transformation = Geom::Transformation.translation([0, 0, m(2.5)]) * root.transformation
    model.commit_operation
    z = (root.transformation.origin.z.to_f * 0.0254).round(6)
    log("Assise : même PID #{root.persistent_id == before[0]}, z #{z}, nouvelle définition #{root.definition == fresh}")
    Sketchup.undo
    log("Assise, après Annuler : même PID #{root.persistent_id == before[0]}, même placement #{root.transformation.to_a == before[1]}, même définition #{root.definition.name == before[2]}")
  end

  def run
    @lines = []
    model = Sketchup.active_model
    log("Spike #{Sketchup.version} Ruby #{RUBY_VERSION} #{Sketchup.platform}")
    outer, ms = timed { build_terrain(model) }
    faces = outer.entities.grep(Sketchup::Group).first.entities.grep(Sketchup::Face).size
    log("MESURE terrain : #{faces} faces, construit en #{ms} ms")
    vertices_exact(outer)
    timing(outer)
    log("Centre de cellule : #{describe(model.raytest(ray_at(outer, 12.5, 12.5), true))}")
    obstacle(model, outer)
    hole(model, outer)
    hidden(model, outer)
    reversed(model, outer)
    lift(model)
    log('FIN')
  rescue StandardError => e
    log("ECHEC #{e.class} #{e.message} #{e.backtrace.first(3).join(' | ')}")
    log('FIN')
  end
end
