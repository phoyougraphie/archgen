# frozen_string_literal: true

require 'json'

# Recette H20, à lancer sur un document neuf, panneaux fermés :
#   load '.../test/host/h20.rb'; ArchgenH20Probe.run
# Écrire une voie : création par le service (coupes variées, droite, courbe, onglet), faces écrites,
# balises, Annuler et Rétablir, panne sans résidu, régénération, copie isolée, panneau par son DOM,
# enregistrer et rouvrir, charge sur 100 m, 1 km et 2 km. Le vrai geste souris se fait à part.
# Rapport : tmp/h20.txt.
module ArchgenH20Probe
  REPO = File.expand_path('../..', __dir__)
  REPORT = File.join(REPO, 'tmp', 'h20.txt')
  SKP = File.join(REPO, 'tmp', 'h20.skp')
  SP = Archgen::Adapters::SketchUp
  PANEL = Archgen::UI::RoadPanel
  DICTIONARY = 'archgen.road'
  INCH = 0.0254
  DELAY_S = 1.2
  Injected = Class.new(StandardError)

  SNAPSHOT = <<~JS
    (function () {
      function q(s) { return document.querySelector(s); }
      sketchup.archgen_probe(JSON.stringify({
        title: q('#title').textContent, status: q('#status').textContent, result: q('#road-result').textContent,
        create: !q('#road-create').disabled, label: q('#road-create').textContent, box: !q('#road-box').hidden,
        diag: Array.prototype.map.call(document.querySelectorAll('#road-diag li'), function (l) { return l.textContent; })
      }));
    }());
  JS

  # Panne au milieu de l'écriture : la surface est écrite, puis tout s'arrête.
  class FailingWriter
    def initialize
      @real = SP::GeometryWriter.new
    end

    def write(plan, entities:, resources:)
      group = entities.add_group
      group.entities.add_face(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, 0, 0), Geom::Point3d.new(100, 100, 0))
      raise Injected, 'panne injectée'
    end

    def mark_definition(*args, **opts)
      @real.mark_definition(*args, **opts)
    end
  end

  module_function

  def model
    Sketchup.active_model
  end

  def service
    @service ||= SP::RoadService.default
  end

  def preset(id)
    Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def tree(id, points, radii, axis: 'center')
    { 'trace' => { 'points_m' => points, 'radii_m' => radii }, 'axis' => axis, 'profile' => preset(id) }
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

  def roots
    model.entities.grep(Sketchup::ComponentInstance).select { |i| i.get_attribute(DICTIONARY, 'road_version') }
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

  def counts
    [model.entities.size, model.definitions.size, model.materials.size, model.layers.size]
  end

  def create(id, points, radii, origin, axis: 'center')
    t = Time.now
    result = service.create(model: model, tree: tree(id, points, radii, axis: axis), origin_m: origin)
    [result, Time.now - t]
  end

  # Une voie écrite : faces réelles égales au plan, racine à l'origine, balises par famille.
  def written_ok?(result, origin)
    return false unless result.ok?

    root = roots.find { |r| r.persistent_id == result.value.persistent_id }
    faces = deep_faces(root.definition.entities)
    at = root.transformation.to_a.values_at(12, 13, 14).map { |c| (c * INCH).round(6) }
    tags = root.definition.entities.grep(Sketchup::Group).map { |g| g.layer.name }.uniq
    @last = "faces #{faces}/#{result.value.metrics['expanded_face_count']}, origine #{at.inspect}, balises #{tags.join(', ')}"
    faces == result.value.metrics['expanded_face_count'] && at == origin.map { |c| c.round(6) } && tags.all? { |n| n.start_with?('ARCHGEN Voirie') }
  end

  def service_steps
    [
      ['Rue de ville en courbe, R 20 m', lambda {
        r, = create('ville', [[0, 0], [80, 0], [80, 60]], [20], [0.0, 0.0, 0.0])
        @ville = r.value&.persistent_id
        written_ok?(r, [0.0, 0.0, 0.0])
      }],
      ['Boulevard planté à l’onglet', lambda {
        r, = create('boulevard', [[0, 0], [120, 0], [120, 90]], [0], [0.0, 150.0, 0.0])
        written_ok?(r, [0.0, 150.0, 0.0])
      }],
      ['Rue tram et voitures, axe sur le bord gauche', lambda {
        r, = create('mixte', [[0, 0], [100, 0], [160, 60]], [30], [200.0, 0.0, 0.0], axis: 'left')
        written_ok?(r, [200.0, 0.0, 0.0])
      }],
      ['Voie ferrée double en courbe', lambda {
        r, = create('fer', [[0, 0], [150, 0], [150, 120]], [60], [200.0, 150.0, 0.0])
        written_ok?(r, [200.0, 150.0, 0.0])
      }],
      ['Autoroute et route de campagne', lambda {
        a, = create('autoroute', [[0, 0], [300, 0], [500, 150]], [400], [0.0, 400.0, 0.0])
        b, = create('campagne', [[0, 0], [200, 0], [260, 120], [400, 120]], [60, 60], [0.0, 650.0, 0.0])
        written_ok?(a, [0.0, 400.0, 0.0]) && written_ok?(b, [0.0, 650.0, 0.0])
      }],
      ['Définitions partagées : une par forme, quel que soit le nombre d’objets', lambda {
        road_defs = model.definitions.select { |d| d.get_attribute('archgen.resource', 'key').to_s.start_with?('road1/') }
        keys = road_defs.map { |d| d.get_attribute('archgen.resource', 'key') }
        @last = "#{road_defs.size} définitions : #{keys.sort.join(', ')}"
        keys.uniq.size == keys.size && road_defs.size.between?(5, 30)
      }],
      ['Refus : rayon trop petit, rien n’est écrit', lambda {
        before = counts
        r, = create('boulevard', [[0, 0], [80, 0], [80, 60]], [5], [0.0, 900.0, 0.0])
        !r.ok? && r.errors.first.params['reason'] == 'radius_too_small' && counts == before
      }],
      ['Panne au milieu de l’écriture : aucun résidu', lambda {
        before = counts
        failing = SP::RoadService.new(intake: Archgen::Composition.road_intake, bands: Archgen::Composition.road_bands, items: Archgen::Composition.road_items,
                                      materials: Archgen::Composition.road_catalog, material_revision: 1, writer: FailingWriter.new)
        r = failing.create(model: model, tree: tree('ville', [[0, 0], [50, 0]], []), origin_m: [0.0, 900.0, 0.0])
        @last = "#{r.errors.map { |d| d.params['reason'] }.inspect}, #{before.inspect} -> #{counts.inspect}"
        !r.ok? && r.errors.first.params['reason'] == 'write_failed' && counts == before
      }]
    ]
  end

  def async_steps
    [
      ['Annuler : la dernière voie disparaît en une fois', lambda {
        @before_undo = roots.size
        Sketchup.undo
      }, -> { roots.size == @before_undo - 1 }],
      ['Rétablir : elle revient', -> { Sketchup.redo }, -> { roots.size == @before_undo }],
      ['Régénérer la rue de ville en rue tram : copie intacte', lambda {
        original = roots.find { |r| r.persistent_id == @ville }
        @copy = model.entities.add_instance(original.definition, original.transformation * Geom::Transformation.translation([0, -40.m, 0]))
        Archgen::Adapters::SketchUp::RoadRepository::KEYS.each { |k| @copy.set_attribute(DICTIONARY, k, original.get_attribute(DICTIONARY, k)) }
        @copy_definition = @copy.definition
        model.selection.clear
        model.selection.add(original)
        target = service.load_selection(model: model).value.target
        @regen = service.regenerate(model: model, target: target, changes: { 'profile' => preset('mixte') })
      }, lambda {
        original = roots.find { |r| r.persistent_id == @ville }
        @last = @regen.ok? ? "révision #{@regen.value.revision}" : @regen.errors.map(&:to_h).inspect
        @regen.ok? && @regen.value.revision == 2 && @copy.definition == @copy_definition && original.definition != @copy_definition &&
          deep_faces(original.definition.entities) == @regen.value.metrics['expanded_face_count']
      }],
      ['Annuler la régénération : la rue de ville revient', -> { Sketchup.undo }, lambda {
        original = roots.find { |r| r.persistent_id == @ville }
        original.get_attribute(DICTIONARY, 'revision') == 1 && original.definition == @copy_definition
      }],
      ['Panneau : tracer, aperçu, créer', lambda {
        @roots_before = roots.size
        PANEL.show('trace')
        attach_probe
        UI.start_timer(1.5, false) do
          session = PANEL.controller.session
          session.clear
          session.start(0.0, -200.0, 0.0)
          session.add([60.0, -200.0])
          session.add([60.0, -150.0])
          session.finish
          PANEL.send_script("archgenRoadTrace('{}')")
        end
      }, :dom, ->(p) { p['box'] && p['create'] && p['result'].start_with?('Voie de') }],
      ['Panneau : Créer la voie', -> { PANEL.send_script("document.getElementById('road-create').click()") }, :dom,
       ->(p) { roots.size == @roots_before + 1 && p['status'].start_with?('Voie créée, révision 1') && PANEL.controller.session.empty? }],
      ['Panneau : modifier la voie créée', lambda {
        @panel_root = model.selection.first
        PANEL.show('edit')
        UI.start_timer(1.0, false) { PANEL.send_script("document.getElementById('road-reload').click()") }
        UI.start_timer(2.5, false) { PANEL.send_script("document.querySelector('[data-preset=\"boulevard\"]').click()") }
      }, :dom, ->(p) { p['title'] == 'Modifier la voie' && p['create'] && p['label'] == 'Remplacer cette voie' }],
      ['Panneau : Remplacer cette voie', -> { PANEL.send_script("document.getElementById('road-create').click()") }, :dom,
       ->(p) { @panel_root.get_attribute(DICTIONARY, 'revision') == 2 && p['status'].start_with?('Voie remplacée, révision 2') }],
      ['Fermer le panneau', -> { PANEL.instance_variable_get(:@dialog).close }, -> { true }],
      ['Enregistrer et rouvrir : voies relues, empreintes recalculées identiques', lambda {
        @kept = roots.to_h { |r| [r.persistent_id, [r.get_attribute(DICTIONARY, 'road_digest'), deep_faces(r.definition.entities)]] }
        model.save(SKP)
        Sketchup.open_file(SKP)
      }, lambda {
        same = roots.all? do |r|
          digest, faces = @kept.fetch(r.persistent_id)
          service.preview(tree: r.get_attribute(DICTIONARY, 'road_json')).value.road_digest == digest && deep_faces(r.definition.entities) == faces
        end
        @last = "#{roots.size} voies relues"
        same && roots.size == @kept.size
      }]
    ]
  end

  def load_steps
    [[100, 'boulevard'], [1000, 'boulevard'], [2000, 'boulevard'], [1000, 'fer'], [2000, 'fer']].map do |length, id|
      ["Charge : #{id}, #{length} m en S", lambda {
        points = [[0, 0], [length * 0.4, 0], [length * 0.6, length * 0.15], [length, length * 0.15]]
        radius = [200, length * 0.25].min
        r, seconds = create(id, points, [radius, radius], [1500.0, length * 1.0, 0.0])
        m = r.value&.metrics || {}
        timing = format('%.2f s, %d objets dont %d traverses, %d faces distinctes, %d faces au total, %d définitions',
                        seconds, m['item_count'].to_i, m['sleeper_count'].to_i, m['unique_face_count'].to_i, m['expanded_face_count'].to_i, m['definition_count'].to_i)
        ok = r.ok? && written_ok?(r, [1500.0, length * 1.0, 0.0])
        @last = r.ok? ? "#{timing} ; #{@last}" : r.errors.map(&:to_h).inspect
        ok
      }]
    end
  end

  # Rejoue la charge seule, sur le document ouvert.
  def run_load
    @lines = []
    @failures = 0
    log("H20 charge #{Time.now}, ARCHGEN #{Archgen::VERSION}")
    load_steps.each do |label, block|
      @last = nil
      ok = begin
        block.call
      rescue StandardError => e
        @last = "#{e.class} #{e.message}"
        false
      end
      check(label, ok, @last)
    end
    finish
  end

  def attach_probe
    PANEL.instance_variable_get(:@dialog).add_action_callback('archgen_probe') { |_c, text| receive(JSON.parse(text)) }
  end

  def receive(panel)
    return unless @current&.first

    label, check_block = @current
    @current = nil
    begin
      check(label, check_block.call(panel), panel.inspect[0, 400])
    rescue StandardError => e
      check(label, false, "#{e.class} #{e.message}")
    end
    advance
  end

  def advance
    step = @queue.shift
    return finish unless step

    label, action, kind, check_block = step
    check_block, kind = kind, nil unless kind == :dom
    begin
      action.call
    rescue Exception => e # rubocop:disable Lint/RescueException
      check("action #{label}", false, "#{e.class} #{e.message}")
      return advance
    end
    if kind == :dom
      @current = [label, check_block]
      UI.start_timer(DELAY_S + 3.0, false) { PANEL.send_script(SNAPSHOT) }
    else
      UI.start_timer(DELAY_S + (label.start_with?('Enregistrer') ? 4.0 : 0), false) do
        begin
          @last = nil
          ok = check_block.call
          check(label, ok, @last)
        rescue StandardError => e
          check(label, false, "#{e.class} #{e.message}")
        end
        advance
      end
    end
  end

  def finish
    log("FIN #{@failures} echec(s), ARCHGEN #{Archgen::VERSION}, SketchUp #{Sketchup.version}, Ruby #{RUBY_VERSION}")
  end

  def run
    @lines = []
    @failures = 0
    model.options['UnitsOptions']['LengthUnit'] = 4
    log("H20 départ #{Time.now}, ARCHGEN #{Archgen::VERSION}")
    service_steps.each do |label, block|
      @last = nil
      ok = begin
        block.call
      rescue StandardError => e
        @last = "#{e.class} #{e.message} #{e.backtrace.first(2).join(' | ')}"
        false
      end
      check(label, ok, @last)
    end
    load_steps.each do |label, block|
      @last = nil
      ok = begin
        block.call
      rescue StandardError => e
        @last = "#{e.class} #{e.message}"
        false
      end
      check(label, ok, @last)
    end
    @queue = async_steps
    UI.start_timer(1.0, false) { advance }
    'recette lancee'
  end
end
