# frozen_string_literal: true

require 'json'

# Recette H22, à lancer sur un document neuf, panneaux fermés :
#   load '.../test/host/h22.rb'; ArchgenH22Probe.run
# Voie sur un terrain (AG-049, ADR-38) : terrain de test en pente et bosse, voie posée par le service,
# copie entaillée réelle (intersection SketchUp), original masqué et intact, Annuler et Rétablir,
# régénération, panne sans résidu, enregistrement. Rapport : tmp/h22.txt.
module ArchgenH22Probe
  REPO = File.expand_path('../..', __dir__)
  REPORT = File.join(REPO, 'tmp', 'h22.txt')
  SKP = File.join(REPO, 'tmp', 'h22.skp')
  SP = Archgen::Adapters::SketchUp
  DICTIONARY = 'archgen.road'
  GROUND = SP::RoadService::GROUND_DICTIONARY
  INCH = 0.0254
  DELAY_S = 1.2
  Injected = Class.new(StandardError)
  # Terrain : pente de 4 % en x, 6 % en y, bosse de 1,5 m.
  HEIGHT = ->(x, y) { 2.0 + (0.04 * x) + (0.06 * y) + (1.5 * Math.exp(-(((x - 70)**2) + ((y - 30)**2)) / 400.0)) }

  # Coupe la copie puis tombe en panne : rien ne doit rester.
  class FailingCutter < SP::GroundCutter
    def entaille(model, terrain, outline)
      super
      raise Injected, 'panne injectée après l’entaille'
    end
  end

  module_function

  def model
    Sketchup.active_model
  end

  def service(cutter: nil)
    SP::RoadService.new(intake: Archgen::Composition.road_intake, bands: Archgen::Composition.road_bands,
                        items: Archgen::Composition.road_items, materials: Archgen::Composition.road_catalog,
                        material_revision: Archgen::Composition.road_materials.fetch('schema_version'), cutter: cutter)
  end

  def preset(id)
    Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def tree(id = 'ville')
    { 'trace' => { 'points_m' => [[0, 0], [70, 0], [120, 40]], 'radii_m' => [40] }, 'profile' => preset(id), 'ground' => {} }
  end

  ORIGIN = [10.0, 10.0, 0.0].freeze

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
  def build_terrain
    model.start_operation('H22 terrain', true)
    group = model.entities.add_group
    group.name = 'Terrain H22'
    mesh = Geom::PolygonMesh.new
    step = 4.0
    (0...50).each do |i|
      (0...35).each do |j|
        p = lambda { |a, b| x = -20 + (a * step); y = -40 + (b * step); Geom::Point3d.new(x.m, y.m, HEIGHT.call(x, y).m) }
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

  def inside?(x, y, ring)
    inside = false
    j = ring.size - 1
    ring.each_with_index do |p, i|
      q = ring[j]
      inside = !inside if ((p[1] > y) != (q[1] > y)) && (x < (((q[0] - p[0]) * (y - p[1])) / (q[1] - p[1])) + p[0])
      j = i
    end
    inside
  end

  def counts
    [model.entities.size, model.definitions.size, model.materials.size, model.layers.size, @terrain.hidden?]
  end

  def steps
    [
      ['Créer une rue de ville sur le terrain : une opération, racine à la cote du profil', lambda {
        reference = SP::TerrainRef.new(document_key: model.guid, persistent_id: @terrain.persistent_id)
        @reference = reference
        grid = service.survey(model: model, tree: tree, origin_m: ORIGIN, terrain: reference)
        @digest = Archgen::Core::Canonical.digest(grid.value)
        t = Time.now
        @result = service.create(model: model, tree: tree, origin_m: ORIGIN, terrain: reference, survey_digest: @digest)
        @seconds = Time.now - t
        return false.tap { @last = @result.errors.map(&:to_h).inspect } unless @result.ok?

        road = roads.first
        m = @result.value.metrics
        z = road.transformation.to_a[14] * INCH
        faces = deep_faces(road.definition.entities)
        @last = format('%.2f s, racine z %.3f (profil %.3f), faces %d/%d, pente %.2f %%, déblai %.2f, remblai %.2f, talus %d faces',
                       @seconds, z, m['origin_z_m'], faces, m['expanded_face_count'], m['grade_max_percent'], m['cut_max_m'], m['fill_max_m'], m['earthwork_face_count'])
        (z - m['origin_z_m']).abs < 1e-6 && faces == m['expanded_face_count']
      }],
      ['Original masqué, intact ; copie unique entaillée', lambda {
        copy = copies.first
        original_faces = @terrain.entities.grep(Sketchup::Face).size
        copy_faces = copy.entities.grep(Sketchup::Face).size
        @last = "original #{original_faces} faces (avant #{@original_faces}), masqué #{@terrain.hidden?} ; copie #{copy_faces} faces, définition propre #{copy.definition != @terrain.definition}"
        @terrain.hidden? && original_faces == @original_faces && copies.size == 1 && copy.definition != @terrain.definition &&
          !copy.hidden? && copy_faces.positive? && copy.name == SP::GroundCutter::NAME
      }],
      ['Entaille : aucune face de la copie dans le contour, le terrain autour garde ses faces', lambda {
        road = roads.first
        origin = road.transformation.to_a.values_at(12, 13).map { |c| c * INCH }
        plan = service.preview(tree: tree, survey: service.survey(model: model, tree: tree, origin_m: ORIGIN, terrain: @reference, allow_hidden: true).value).value.plan
        ring = plan['ground']['outline_m'].map { |x, y| [x + origin[0], y + origin[1]] }
        copy = copies.first
        t = copy.transformation
        centers = copy.entities.grep(Sketchup::Face).map do |f|
          v = f.outer_loop.vertices.map { |vx| t * vx.position }
          [v.sum(&:x) * INCH / v.size, v.sum(&:y) * INCH / v.size]
        end
        inside = centers.count { |x, y| inside?(x, y, ring) }
        near = centers.count { |x, y| ring.any? { |px, py| Math.hypot(px - x, py - y) < 6 } }
        @last = "#{inside} faces au centre dans le contour, #{near} faces à moins de 6 m du contour, contour #{ring.size} points"
        inside.zero? && near.positive?
      }],
      ['Annuler : voie et copie disparaissent, original visible', -> { Sketchup.undo }, lambda {
        @last = "voies #{roads.size}, copies #{copies.size}, masqué #{@terrain.hidden?}"
        roads.empty? && copies.empty? && !@terrain.hidden?
      }],
      ['Rétablir : tout revient', -> { Sketchup.redo }, lambda {
        roads.size == 1 && copies.size == 1 && @terrain.hidden?
      }],
      ['Régénérer en boulevard : nouvelle copie, ancienne effacée, original toujours relevé', lambda {
        road = roads.first
        @old_copy = road.get_attribute(GROUND, 'copy_pid')
        model.selection.clear
        model.selection.add(road)
        target = service.load_selection(model: model).value.target
        @regen = service.regenerate(model: model, target: target, changes: { 'profile' => preset('boulevard') })
      }, lambda {
        road = roads.first
        @last = @regen.ok? ? "révision #{@regen.value.revision}, talus #{@regen.value.metrics['earthwork_face_count']} faces" : @regen.errors.map(&:to_h).inspect
        @regen.ok? && copies.size == 1 && copies.first.persistent_id != @old_copy && road.get_attribute(GROUND, 'copy_pid') == copies.first.persistent_id &&
          deep_faces(road.definition.entities) == @regen.value.metrics['expanded_face_count']
      }],
      ['Annuler la régénération : la copie d’avant revient', -> { Sketchup.undo }, lambda {
        copies.size == 1 && copies.first.persistent_id == @old_copy && roads.first.get_attribute(DICTIONARY, 'revision') == 1
      }],
      ['Annuler la création : terrain d’origine seul', -> { Sketchup.undo }, -> { roads.empty? && copies.empty? && !@terrain.hidden? }],
      ['Panne après l’entaille : aucun résidu, original intact', lambda {
        @before = counts
        @failed = service(cutter: FailingCutter.new).create(model: model, tree: tree, origin_m: ORIGIN, terrain: @reference)
      }, lambda {
        @last = "#{@failed.errors.map { |d| d.params['reason'] }.inspect}, #{@before.inspect} -> #{counts.inspect}"
        !@failed.ok? && counts == @before && !@terrain.hidden?
      }],
      ['Refus : terrain changé depuis le relevé', lambda {
        @stale = service.create(model: model, tree: tree, origin_m: ORIGIN, terrain: @reference, survey_digest: 'faux')
      }, -> { !@stale.ok? && @stale.errors.first.params['reason'] == 'terrain_changed' && roads.empty? }],
      ['Recréer puis enregistrer', lambda {
        @kept = service.create(model: model, tree: tree, origin_m: ORIGIN, terrain: @reference)
        model.save(SKP)
      }, -> { @kept.ok? && File.exist?(SKP) && roads.size == 1 && copies.size == 1 }]
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
    log("H22 départ #{Time.now}, ARCHGEN #{Archgen::VERSION}")
    @terrain = build_terrain
    @original_faces = @terrain.entities.grep(Sketchup::Face).size
    log("Terrain de test : #{@original_faces} faces")
    @queue = steps
    UI.start_timer(0.5, false) { advance }
    'recette lancee'
  end
end
