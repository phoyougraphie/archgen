# frozen_string_literal: true

require 'json'

# Recette H24, à lancer sur un document neuf, panneaux fermés :
#   load '.../test/host/h24.rb'; ArchgenH24Probe.run
# Ponts (AG-057 à AG-059) par le service de réseau : poutre sur une rivière, arc, voûte, pont sur une
# voie ferrée, pont entre deux rues ; Annuler, Rétablir, régénération poutre → arc, relecture, enregistrement.
# Rapport : tmp/h24.txt.
module ArchgenH24Probe
  REPO = File.expand_path('../..', __dir__)
  REPORT = File.join(REPO, 'tmp', 'h24.txt')
  SKP = File.join(REPO, 'tmp', 'h24.skp')
  SP = Archgen::Adapters::SketchUp
  DICTIONARY = 'archgen.network'
  INCH = 0.0254
  DELAY_S = 1.2

  module_function

  def model
    Sketchup.active_model
  end

  def service
    SP::NetworkService.default
  end

  def preset(id)
    Archgen::Composition.road_presets.fetch('presets').find { |p| p['id'] == id }.fetch('profile')
  end

  def road(id, points, profile, water: false)
    entry = { 'id' => id, 'road' => { 'trace' => { 'points_m' => points, 'radii_m' => [] }, 'profile' => preset(profile) } }
    entry['road']['water'] = { 'mode' => 'flat' } if water
    entry
  end

  # half : demi-longueur de la rue ; une voûte haute demande des rampes plus longues.
  def river_tree(junction = nil, half: 200)
    tree = { 'roads' => [road('riviere', [[0, 0], [200, 0]], 'riviere', water: true), road('rue', [[100, -half], [100, half]], 'ville')] }
    tree['junctions'] = [{ 'id' => "riviere@100.0+rue@#{half}.0" }.merge(junction)] if junction
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

  def networks
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

  def groups(root)
    root.definition.entities.grep(Sketchup::Group).map(&:name)
  end

  # Écrit un réseau à l'origine donnée ; vérifie faces, groupes, nombre de ponts et genre.
  def write(label, tree, origin, kind)
    t = Time.now
    result = service.create(model: model, tree: tree, origin_m: origin)
    seconds = Time.now - t
    return false.tap { @last = result.errors.map(&:to_h).inspect } unless result.ok?

    root = networks.find { |n| (n.transformation.to_a[12] * INCH - origin[0]).abs < 1e-6 && (n.transformation.to_a[13] * INCH - origin[1]).abs < 1e-6 }
    m = result.value.metrics
    faces = deep_faces(root.definition.entities)
    stored = JSON.parse(root.get_attribute(DICTIONARY, 'network_json'))
    again = service.preview(tree: stored)
    junction = again.value.plan['junctions'].first
    @last = format('%s : %.2f s, faces %d/%d, ponts %d, genre %s, tablier %.2f m, portée %.1f m, groupes %s',
                   label, seconds, faces, m['expanded_face_count'], m['bridge_count'].to_i, junction['bridge_kind'], junction['deck_m'], junction['span_m'],
                   groups(root).grep(%r{road/(bridges|water)}).inspect)
    faces == m['expanded_face_count'] && m['bridge_count'] == 1 && junction['bridge_kind'] == kind && again.value.road_digest == result.value.road_digest &&
      groups(root).include?('road/bridges')
  end

  def steps
    [
      ['Poutre sur une rivière : pont d’office, une opération', -> { write('poutre', river_tree, [0.0, 0.0, 0.0], 'beam') }],
      ['Annuler : le réseau disparaît', -> { Sketchup.undo }, -> { networks.empty? }],
      ['Rétablir : il revient', -> { Sketchup.redo }, -> { networks.size == 1 }],
      ['Régénérer en arc : même racine, révision 2', lambda {
        model.selection.clear
        model.selection.add(networks.first)
        target = service.load_selection(model: model).value.target
        @regen = service.regenerate(model: model, target: target, changes: { 'junctions' => [{ 'id' => 'riviere@100.0+rue@200.0', 'type' => 'bridge', 'bridge_kind' => 'arch' }] })
      }, lambda {
        root = networks.first
        @last = @regen.ok? ? "révision #{@regen.value.revision}, faces #{deep_faces(root.definition.entities)}/#{@regen.value.metrics['expanded_face_count']}" : @regen.errors.map(&:to_h).inspect
        @regen.ok? && networks.size == 1 && deep_faces(root.definition.entities) == @regen.value.metrics['expanded_face_count']
      }],
      ['Voûte sur la rivière, hauteur libre 9,6 m', -> { write('voûte', river_tree({ 'type' => 'bridge', 'bridge_kind' => 'vault', 'clearance_m' => 9.6 }, half: 300), [0.0, 500.0, 0.0], 'vault') }],
      ['Voûte refusée à la hauteur libre par défaut : rien d’écrit, hauteur annoncée', lambda {
        before = networks.size
        r = service.create(model: model, tree: river_tree({ 'type' => 'bridge', 'bridge_kind' => 'vault' }), origin_m: [0.0, 1000.0, 0.0])
        @last = r.errors.map { |d| [d.params['reason'], d.params['needed_m']] }.inspect
        !r.ok? && r.errors.first.params['reason'] == 'bridge_clearance' && networks.size == before
      }],
      ['Pont sur une voie ferrée', lambda {
        tree = { 'roads' => [road('fer', [[0, 0], [200, 0]], 'fer'), road('rue', [[100, -250], [100, 250]], 'ville')],
                 'junctions' => [{ 'id' => 'fer@100.0+rue@250.0', 'type' => 'bridge' }] }
        write('voie ferrée', tree, [500.0, 0.0, 0.0], 'beam')
      }],
      ['Pont entre deux rues, voie portée nommée', lambda {
        tree = { 'roads' => [road('a', [[0, 0], [400, 0]], 'ville'), road('b', [[200, -200], [200, 200]], 'ville')],
                 'junctions' => [{ 'id' => 'a@200.0+b@200.0', 'type' => 'bridge', 'over' => 'b' }] }
        write('deux rues', tree, [500.0, 600.0, 0.0], 'beam')
      }],
      ['Enregistrer', -> { model.save(SKP) }, -> { File.exist?(SKP) && networks.size == 4 }]
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
    log("H24 départ #{Time.now}, ARCHGEN #{Archgen::VERSION}")
    @queue = steps
    UI.start_timer(0.5, false) { advance }
    'recette lancee'
  end
end
