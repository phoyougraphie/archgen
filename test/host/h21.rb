# frozen_string_literal: true

require 'json'

# Recette H21, à lancer sur un document neuf, panneaux fermés :
#   load '.../test/host/h21.rb'; ArchgenH21Probe.run
# Écrire un réseau de voies : quatre types de carrefour et le tram par le service, faces écrites,
# balises, refus et panne sans résidu, Annuler et Rétablir, régénération et copie isolée, panneau par
# son DOM (tracer, ajouter, régler, créer, modifier), enregistrer et rouvrir, charge d'une grille.
# Le vrai geste souris se fait à part. Rapport : tmp/h21.txt.
module ArchgenH21Probe
  REPO = File.expand_path('../..', __dir__)
  REPORT = File.join(REPO, 'tmp', 'h21.txt')
  SKP = File.join(REPO, 'tmp', 'h21.skp')
  KEPT = File.join(REPO, 'tmp', 'h21_kept.json')
  SP = Archgen::Adapters::SketchUp
  PANEL = Archgen::UI::NetworkPanel
  DICTIONARY = 'archgen.network'
  INCH = 0.0254
  DELAY_S = 1.2
  Injected = Class.new(StandardError)

  SNAPSHOT = <<~JS
    (function () {
      function q(s) { return document.querySelector(s); }
      sketchup.archgen_probe(JSON.stringify({
        title: q('#title').textContent, status: q('#status').textContent, metrics: q('#metrics').textContent,
        create: !q('#n-create').disabled, regenerate: !q('#n-regenerate').disabled, roads: q('#roads').textContent,
        types: Array.prototype.map.call(document.querySelectorAll('#junctions select'), function (s) { return s.value; }),
        diag: Array.prototype.map.call(document.querySelectorAll('#diag li'), function (l) { return l.textContent; })
      }));
    }());
  JS

  class FailingWriter
    def initialize
      @real = SP::GeometryWriter.new
    end

    def write(_plan, entities:, resources:)
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
    @service ||= SP::NetworkService.default
  end

  def preset(id)
    Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def road(id, points, profile = 'ville')
    { 'id' => id, 'road' => { 'trace' => { 'points_m' => points, 'radii_m' => Array.new(points.size - 2, 20) }, 'profile' => preset(profile) } }
  end

  def cross(type = nil, a: 'ville', b: 'ville', **opts)
    roads = [road('a', [[0, 0], [100, 0]], a), road('b', [[50, -50], [50, 50]], b)]
    tree = { 'roads' => roads }
    tree['junctions'] = [{ 'id' => 'a@50.0+b@50.0', 'type' => type }.merge(opts)] if type
    tree
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
    model.entities.grep(Sketchup::ComponentInstance).select { |i| i.get_attribute(DICTIONARY, 'network_version') }
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

  def create(tree, origin)
    t = Time.now
    result = service.create(model: model, tree: tree, origin_m: origin)
    [result, Time.now - t]
  end

  def written_ok?(result, origin)
    return false unless result.ok?

    root = roots.find { |r| r.persistent_id == result.value.persistent_id }
    faces = deep_faces(root.definition.entities)
    at = root.transformation.to_a.values_at(12, 13, 14).map { |c| (c * INCH).round(6) }
    tags = root.definition.entities.grep(Sketchup::Group).map { |g| g.layer.name }.uniq
    m = result.value.metrics
    @last = "faces #{faces}/#{m['expanded_face_count']}, #{m['junction_count']} carrefour(s), #{m['piece_count']} tronçons, origine #{at.inspect}, balises #{tags.join(', ')}"
    faces == m['expanded_face_count'] && at == origin.map { |c| c.round(6) } && tags.all? { |n| n.start_with?('ARCHGEN Voirie') }
  end

  def service_steps
    [
      ['Carrefour simple, rue × rue', lambda {
        r, = create(cross, [0.0, 0.0, 0.0])
        @simple = r.value&.persistent_id
        written_ok?(r, [0.0, 0.0, 0.0])
      }],
      ['Carrefour à feux, rue × boulevard', lambda {
        r, = create(cross('signals', b: 'boulevard'), [150.0, 0.0, 0.0])
        written_ok?(r, [150.0, 0.0, 0.0])
      }],
      ['Giratoire, rue tram et voitures × rue, tram à travers l’îlot', lambda {
        r, = create(cross('roundabout', a: 'mixte'), [300.0, 0.0, 0.0])
        written_ok?(r, [300.0, 0.0, 0.0])
      }],
      ['Double giratoire sur deux carrefours voisins', lambda {
        roads = [road('a', [[0, 0], [200, 0]]), road('b', [[60, -60], [60, 60]]), road('c', [[130, 0], [130, 60]])]
        tree = { 'roads' => roads, 'junctions' => [{ 'id' => 'a@130.0+c@0.0', 'type' => 'double_roundabout', 'pair' => 'a@60.0+b@60.0' }] }
        r, = create(tree, [0.0, 150.0, 0.0])
        written_ok?(r, [0.0, 150.0, 0.0])
      }],
      ['Refus : autoroute à niveau, rien n’est écrit', lambda {
        before = counts
        r, = create(cross(a: 'autoroute'), [0.0, 400.0, 0.0])
        @last = r.errors.map { |d| d.params['reason'] }.inspect
        !r.ok? && r.errors.first.params['reason'] == 'motorway_at_grade' && counts == before
      }],
      ['Panne au milieu de l’écriture : aucun résidu', lambda {
        before = counts
        failing = SP::NetworkService.new(intake: Archgen::Composition.road_network_intake, bands: Archgen::Composition.road_bands,
                                         items: Archgen::Composition.road_items, materials: Archgen::Composition.road_catalog,
                                         material_revision: 1, writer: FailingWriter.new)
        r = failing.create(model: model, tree: cross, origin_m: [0.0, 400.0, 0.0])
        @last = "#{r.errors.map { |d| d.params['reason'] }.inspect}, #{before.inspect} -> #{counts.inspect}"
        !r.ok? && r.errors.first.params['reason'] == 'write_failed' && counts == before
      }]
    ]
  end

  def async_steps
    [
      ['Annuler : le dernier réseau disparaît en une fois', lambda {
        @before_undo = roots.size
        Sketchup.undo
      }, -> { roots.size == @before_undo - 1 }],
      ['Rétablir : il revient', -> { Sketchup.redo }, -> { roots.size == @before_undo }],
      ['Régénérer le carrefour simple en giratoire : copie intacte', lambda {
        original = roots.find { |r| r.persistent_id == @simple }
        @copy = model.entities.add_instance(original.definition, original.transformation * Geom::Transformation.translation([0, -80.m, 0]))
        SP::NetworkRepository::KEYS.each { |k| @copy.set_attribute(DICTIONARY, k, original.get_attribute(DICTIONARY, k)) }
        @copy_definition = @copy.definition
        model.selection.clear
        model.selection.add(original)
        target = service.load_selection(model: model).value.target
        @regen = service.regenerate(model: model, target: target, changes: { 'junctions' => [{ 'id' => 'a@50.0+b@50.0', 'type' => 'roundabout' }] })
      }, lambda {
        original = roots.find { |r| r.persistent_id == @simple }
        @last = @regen.ok? ? "révision #{@regen.value.revision}" : @regen.errors.map(&:to_h).inspect
        @regen.ok? && @regen.value.revision == 2 && @copy.definition == @copy_definition && original.definition != @copy_definition &&
          deep_faces(original.definition.entities) == @regen.value.metrics['expanded_face_count']
      }],
      ['Annuler la régénération : le carrefour simple revient', -> { Sketchup.undo }, lambda {
        original = roots.find { |r| r.persistent_id == @simple }
        original.get_attribute(DICTIONARY, 'revision') == 1 && original.definition == @copy_definition
      }],
      ['Panneau : deux voies tracées, carrefour détecté', lambda {
        @roots_before = roots.size
        PANEL.show('trace')
        attach_probe
        c = PANEL.controller
        s = c.session
        add = lambda do |pts, preset|
          s.clear
          s.start(pts[0][0], pts[0][1], 0.0)
          pts.drop(1).each { |p| s.add(p) }
          s.finish
          c.dispatch(JSON.generate('v' => 1, 'request_id' => "p#{pts.hash.abs}", 'action' => 'add_road', 'payload' => { 'preset' => preset }))
        end
        UI.start_timer(1.5, false) do
          add.call([[0.0, -300.0], [120.0, -300.0]], 'ville')
          add.call([[60.0, -360.0], [60.0, -240.0]], 'mixte')
          PANEL.send_script("archgenNetworkRestart()")
        end
      }, :dom, ->(p) { p['create'] && p['types'] == ['simple'] && p['roads'].include?('v2') }],
      ['Panneau : régler un giratoire', lambda {
        PANEL.send_script("var s=document.querySelector('#junctions select'); s.value='roundabout'; s.dispatchEvent(new Event('change'))")
      }, :dom, ->(p) { p['types'] == ['roundabout'] && p['create'] && p['diag'].empty? }],
      ['Panneau : Créer le réseau', -> { PANEL.send_script("document.getElementById('n-create').click()") }, :dom,
       ->(p) { roots.size == @roots_before + 1 && p['status'].start_with?('Réseau créé, révision 1') }],
      ['Panneau : modifier le réseau créé, passer en carrefour à feux', lambda {
        @panel_root = model.selection.first
        PANEL.show('edit')
        UI.start_timer(2.5, false) do
          PANEL.send_script("var s=document.querySelector('#junctions select'); s.value='signals'; s.dispatchEvent(new Event('change'))")
        end
      }, :dom, ->(p) { p['title'] == 'Modifier le réseau sélectionné' && p['regenerate'] && p['types'] == ['signals'] }],
      ['Panneau : Remplacer ce réseau', -> { PANEL.send_script("document.getElementById('n-regenerate').click()") }, :dom,
       ->(p) { @panel_root.get_attribute(DICTIONARY, 'revision') == 2 && p['status'].start_with?('Réseau remplacé, révision 2') }],
      ['Fermer le panneau', -> { PANEL.instance_variable_get(:@dialog).close }, -> { true }],
      # Rouvrir le même fichier depuis une minuterie a figé SketchUp au premier passage : on enregistre
      # ici, on rouvre à la main (Fichier > fichiers récents), puis ArchgenH21Probe.verify_reopened.
      ['Enregistrer : empreintes notées pour la réouverture', lambda {
        kept = roots.to_h { |r| [r.persistent_id.to_s, [r.get_attribute(DICTIONARY, 'road_digest'), deep_faces(r.definition.entities)]] }
        File.write(KEPT, JSON.generate(kept))
        model.save(SKP)
      }, -> { File.exist?(SKP) && File.exist?(KEPT) }]
    ]
  end

  # Grille de n × n rues de longueur l, croisées tous les l / n : n² carrefours du type donné.
  def grid(n, length, type, profile = 'ville')
    step = length / (n + 1.0)
    roads = (1..n).map { |i| road("h#{i}", [[0, i * step], [length, i * step]], profile) } +
            (1..n).map { |i| road("v#{i}", [[i * step, 0], [i * step, length]], profile) }
    shift = roads.first['road']['trace']['points_m'].first
    roads.each { |r| r['road']['trace']['points_m'] = r['road']['trace']['points_m'].map { |x, y| [x - shift[0], y - shift[1]] } }
    tree = { 'roads' => roads }
    return tree unless type

    ids = service.preview(tree: tree).value.plan['junctions'].map { |j| j['id'] }
    tree.merge('junctions' => ids.map { |id| { 'id' => id, 'type' => type } })
  end

  def load_steps
    [[3, 600, nil], [3, 600, 'signals'], [3, 600, 'roundabout'], [5, 1000, 'roundabout']].map do |n, length, type|
      ["Charge : grille de #{n} × #{n} rues sur #{length} m, #{type || 'simple'}", lambda {
        r, seconds = create(grid(n, length, type), [2000.0, length * 1.0, 0.0])
        m = r.value&.metrics || {}
        timing = format('%.2f s, %d carrefours, %d objets, %d faces distinctes, %d faces au total',
                        seconds, m['junction_count'].to_i, m['item_count'].to_i, m['unique_face_count'].to_i, m['expanded_face_count'].to_i)
        ok = r.ok? && written_ok?(r, [2000.0, length * 1.0, 0.0])
        @last = r.ok? ? "#{timing} ; #{@last}" : r.errors.map(&:to_h).inspect[0, 400]
        ok
      }]
    end
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
      UI.start_timer(DELAY_S + 3.5, false) { PANEL.send_script(SNAPSHOT) }
    else
      UI.start_timer(DELAY_S + (label.start_with?('Enregistrer') ? 2.0 : 0), false) do
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
    @current = nil
    log("FIN #{@failures} echec(s), ARCHGEN #{Archgen::VERSION}, SketchUp #{Sketchup.version}, Ruby #{RUBY_VERSION}")
  end

  # Après réouverture à la main de tmp/h21.skp : chaque réseau relu, empreinte recalculée identique.
  def verify_reopened
    @lines = File.read(REPORT, encoding: 'utf-8').split("\n")
    @failures = 0
    kept = JSON.parse(File.read(KEPT))
    same = roots.all? do |r|
      digest, faces = kept.fetch(r.persistent_id.to_s)
      service.preview(tree: r.get_attribute(DICTIONARY, 'network_json')).value.road_digest == digest && deep_faces(r.definition.entities) == faces
    end
    check('Rouvrir : réseaux relus, empreintes recalculées identiques', same && roots.size == kept.size, "#{roots.size} réseaux relus sur #{kept.size}")
    finish
  end

  def run_steps(steps)
    steps.each do |label, block|
      @last = nil
      ok = begin
        block.call
      rescue StandardError => e
        @last = "#{e.class} #{e.message} #{e.backtrace.first(2).join(' | ')}"
        false
      end
      check(label, ok, @last)
    end
  end

  def run
    @lines = []
    @failures = 0
    model.options['UnitsOptions']['LengthUnit'] = 4
    log("H21 départ #{Time.now}, ARCHGEN #{Archgen::VERSION}")
    run_steps(service_steps)
    run_steps(load_steps)
    @queue = async_steps
    UI.start_timer(1.0, false) { advance }
    'recette lancee'
  end
end
