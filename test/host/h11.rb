# frozen_string_literal: true

require 'csv'
require 'json'

# Recette H11 et rejeu LOD 1, à lancer dans la console sur un modèle vide, panneau fermé :
#   load '.../test/host/faults.rb'; load '.../test/host/h11.rb'; ArchgenH11Probe.run
# Chaque passage laisse la main à SketchUp par un minuteur. Le déroulement s'écrit dans
# tmp/h11.txt, les mesures dans tmp/h11.csv. Le dernier mot du rapport est « FIN ».
# Le chronomètre passe par des sous-classes de la garde et du writer : le produit n'a aucun crochet.
module ArchgenH11Probe
  REPO = File.expand_path('../..', __dir__)
  TMP = File.join(REPO, 'tmp')
  REPORT = File.join(TMP, 'h11.txt')
  MEASURES = File.join(TMP, 'h11.csv')
  GROWTH = File.join(TMP, 'h11-croissance.skp')
  SP = Archgen::Adapters::SketchUp
  CORE = Archgen::Core
  WARMUPS = 3
  PASSES = 20
  REGENERATIONS = 20
  UNDO_DELAY_S = 1.0
  TARGETS_S = { 'plan' => 0.150, 'ecriture' => 2.0, 'soutenue' => 5.0 }.freeze

  # La fixture de référence du contrat, telle quelle : seul le mode varie.
  HAUSSMANN = JSON.parse(File.read(File.join(REPO, 'examples', 'buildings', 'haussmann-12x9.json'), mode: 'rb', encoding: 'UTF-8')).freeze
  SUSTAINED = { 'schema_version' => 1, 'profile' => { 'id' => 'generic' }, 'name' => 'H11 soutenue', 'mode' => 'structural', 'lod' => 1,
                'footprint' => { 'width_m' => 24.0, 'depth_m' => 18.0 }, 'levels' => { 'count' => 10 },
                'facade' => { 'front_bays' => 8, 'side_bays' => 4 },
                'roof' => { 'type' => 'flat', 'overhang_m' => 0.0, 'pitch_deg' => 0.0, 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0 } }.freeze
  LARGEST = { 'schema_version' => 1, 'profile' => { 'id' => 'toulousain' }, 'name' => 'H11 maximum', 'mode' => 'structural', 'lod' => 1,
              'footprint' => { 'width_m' => 60.0, 'depth_m' => 60.0 }, 'levels' => { 'count' => 15, 'height_m' => 4.0 },
              'facade' => { 'front_bays' => 12, 'side_bays' => 12, 'margin_m' => 0.6, 'window_width_m' => 1.2, 'window_height_m' => 1.8, 'door_width_m' => 1.0 } }.freeze

  def self.clock
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Relève les instants de start_operation et de commit_operation.
  class TimedGuard < SP::TransactionGuard
    attr_reader :started, :commit_began, :committed

    private

    def start(model, name)
      @started = ArchgenH11Probe.clock
      super
    end

    def commit(model)
      @commit_began = ArchgenH11Probe.clock
      super.tap { @committed = ArchgenH11Probe.clock }
    end
  end

  class TimedWriter < SP::GeometryWriter
    attr_reader :seconds

    def write(*args, **options)
      begin_at = ArchgenH11Probe.clock
      super.tap { @seconds = ArchgenH11Probe.clock - begin_at }
    end
  end

  module_function

  def model
    Sketchup.active_model
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

  def measure(row)
    @rows << row
    CSV.open(MEASURES, 'wb') do |csv|
      csv << %w[scenario mode lod p50_ms p95_ms max_ms cible_ms calcul_p95_ms ecriture_p95_ms commit_p95_ms faces_uniques faces_etendues definitions materiaux]
      @rows.each { |r| csv << r }
    end
  end

  def millis(value)
    (value * 1000).round(1)
  end

  def p95(values)
    values.sort[PASSES - 2]
  end

  def timed_service(writer: TimedWriter.new)
    service = SP::BuildingService.default(allow_internal: true, writer: writer)
    guard = TimedGuard.new
    service.instance_variable_set(:@guard, guard)
    [service, guard, writer]
  end

  # Modèle réinitialisé entre deux passages, sans invite d'enregistrement.
  def reset_model
    current = model
    current.selection.clear
    current.start_operation('H11 remise à zéro', true)
    current.entities.clear!
    current.commit_operation
    current.definitions.purge_unused
    current.materials.purge_unused
    current.layers.purge_unused
    current.definitions.length.zero? && current.entities.length.zero?
  end

  # Enchaîne les blocs par minuteur : SketchUp reste vivant entre deux passages.
  def chain(blocks, delay = 0.05, &done)
    @queue = blocks.dup
    @done = done
    tick(delay)
  end

  def tick(delay)
    block = @queue.shift
    return @done.call unless block

    UI.start_timer(delay, false) do
      begin
        block.call
      rescue Exception => e # rubocop:disable Lint/RescueException
        check('Exception', false, "#{e.class} #{e.message} #{e.backtrace.first(3).join(' | ')}")
      end
      tick(delay)
    end
  end

  # --- Plan pur, dans le Ruby de l'hôte

  def plan_blocks
    [%w[shell 0], %w[structural 0], %w[shell 1], %w[structural 1]].map do |mode, lod|
      lambda {
        intake = Archgen::Composition.intake
        registry = Archgen::Composition.registry.value
        materials = Archgen::Composition.materials.fetch('materials')
        draft = HAUSSMANN.merge('mode' => mode, 'lod' => lod.to_i)
        config = CORE::ConfigResolver.resolve(draft, registry: registry, intake: intake, allow_internal: true).value
        validation = []
        times = Array.new(WARMUPS + PASSES) do
          begin_at = clock
          plan = CORE::GeometryEngine.generate(config, materials: materials).value
          elapsed = clock - begin_at
          validate_at = clock
          CORE::PlanValidator.call(plan, materials: materials)
          validation << clock - validate_at
          elapsed
        end.drop(WARMUPS)
        plan = CORE::GeometryEngine.generate(config, materials: materials).value
        value = p95(times)
        check("Plan #{mode} LOD #{lod} p95 #{millis(value)} ms (validation seule p95 #{millis(p95(validation.drop(WARMUPS)))} ms)", value <= TARGETS_S['plan'])
        measure(['plan haussmann 12x9', mode, lod, millis(times.sort[PASSES / 2]), millis(value), millis(times.max), millis(TARGETS_S['plan']), '', '', '',
                 plan['metrics']['unique_face_count'], plan['metrics']['expanded_face_count'], '', ''])
      }
    end
  end

  # --- Écriture native : du start_operation au commit

  def write_blocks(label, draft, target_key, passes: WARMUPS + PASSES)
    samples = []
    blocks = Array.new(passes) do |index|
      lambda {
        reset_model
        service, guard, writer = timed_service
        call_at = clock
        result = service.create(model: model, draft: draft)
        raise "#{label} refusé : #{result.errors.map(&:to_h)}" unless result.ok?

        samples << { total: guard.committed - guard.started, calcul: guard.started - call_at, ecriture: writer.seconds,
                     commit: guard.committed - guard.commit_began, index: index, metrics: result.value.metrics,
                     definitions: model.definitions.length, materials: model.materials.count }
      }
    end
    blocks << -> { report_writes(label, draft, target_key, samples) }
  end

  def report_writes(label, draft, target_key, samples)
    kept = samples.drop(WARMUPS)
    totals = kept.map { |s| s[:total] }
    value = p95(totals)
    last = samples.last
    check("#{label} p95 #{millis(value)} ms sur #{kept.size} passages (max #{millis(totals.max)} ms)", value <= TARGETS_S[target_key])
    measure([label, draft['mode'], draft['lod'], millis(totals.sort[PASSES / 2]), millis(value), millis(totals.max), millis(TARGETS_S[target_key]),
             millis(p95(kept.map { |s| s[:calcul] })), millis(p95(kept.map { |s| s[:ecriture] })), millis(p95(kept.map { |s| s[:commit] })),
             last[:metrics]['unique_face_count'], last[:metrics]['expanded_face_count'], last[:definitions], last[:materials]])
  end

  # Pire cas accepté par le schéma : un seul passage, sans cible au contrat.
  def largest_block
    lambda {
      reset_model
      service, guard, writer = timed_service
      call_at = clock
      result = service.create(model: model, draft: LARGEST)
      unless check('Plus grand plan accepté : écrit', result.ok?, result.errors.map(&:to_h).inspect)
        return
      end

      log(format('MESURE plus grand plan : calcul %d ms, écriture %d ms, commit %d ms, %d faces étendues, %d définitions',
                 millis(guard.started - call_at), millis(writer.seconds), millis(guard.committed - guard.commit_began),
                 result.value.metrics['expanded_face_count'], model.definitions.length))
      measure(['plus grand plan', LARGEST['mode'], LARGEST['lod'], '', millis(guard.committed - guard.started), '', '',
               millis(guard.started - call_at), millis(writer.seconds), millis(guard.committed - guard.commit_began),
               result.value.metrics['unique_face_count'], result.value.metrics['expanded_face_count'], model.definitions.length, model.materials.count])
      reset_model
    }
  end

  # --- Croissance : 20 régénérations de même géométrie, même SKP, même session

  # model.definitions compte aussi la définition de chaque groupe : seuls les composants comptent ici.
  def building?(definition)
    definition.get_attribute('archgen.definition', 'kind') == 'building'
  end

  def frame_names
    model.definitions.reject { |d| d.group? || d.image? || building?(d) }.map(&:name).sort
  end

  def frame_instances
    root = model.entities.grep(Sketchup::ComponentInstance).first
    root ? deep_instances(root.definition.entities) : 0
  end

  def growth_blocks
    draft = HAUSSMANN.merge('mode' => 'structural')
    service = SP::BuildingService.default(allow_internal: true)
    state = {}
    prepare = lambda {
      reset_model
      created = service.create(model: model, draft: draft)
      raise created.errors.map(&:to_h).inspect unless created.ok?

      instance = model.find_entity_by_persistent_id(created.value.persistent_id)
      model.selection.clear
      model.selection.add(instance)
      model.save(GROWTH)
      state[:initial] = File.size(GROWTH)
      state[:instance] = instance
      state[:frames] = frame_names
      state[:frames_used] = frame_instances
      log("MESURE SKP initial #{state[:initial]} octets, #{state[:frames].size} définitions de cadres, #{model.definitions.length} définitions dont groupes")
    }
    regenerations = Array.new(REGENERATIONS) do |index|
      lambda {
        target = service.load_selection(model: model).value.target
        result = service.regenerate(model: model, target: target, draft: { 'schema_version' => 1 })
        raise "régénération #{index} : #{result.errors.map(&:to_h)}" unless result.ok?

        state[:digest] ||= result.value.plan_digest
        check("Régénération #{index + 1} : même plan", result.value.plan_digest == state[:digest]) unless result.value.plan_digest == state[:digest]
      }
    end
    finish = lambda {
      all = model.definitions.length
      model.save(GROWTH)
      final = File.size(GROWTH)
      growth = final - state[:initial]
      buildings = model.definitions.count { |d| building?(d) }
      check("Croissance SKP #{growth} octets (#{state[:initial]} → #{final}), plafond 10 Mo", growth <= 10_000_000)
      check("Révision #{REGENERATIONS + 1}", state[:instance].get_attribute('archgen.building', 'revision') == REGENERATIONS + 1)
      check("Définitions de cadres stables (#{frame_names.size} pour #{state[:frames].size})", frame_names == state[:frames])
      check('Toujours autant de cadres posés dans le bâtiment courant', deep_instances(state[:instance].definition.entities) == state[:frames_used])
      check("Une définition de bâtiment par révision, conservée (#{buildings})", buildings == REGENERATIONS + 1)
      log("MESURE après #{REGENERATIONS} régénérations : #{frame_names.size} définitions de cadres, #{buildings} de bâtiment, #{all} dont groupes, #{model.materials.count} matériaux")
      measure(['croissance 20 regenerations', 'structural', 1, '', '', '', '', '', '', '', '', '', frame_names.size, model.materials.count])
      log("MESURE SKP final #{final} octets, croissance #{growth} octets")
    }
    orphan = lambda {
      before = ArchgenFaultProbe.record(state[:instance])
      target = service.load_selection(model: model).value.target
      failing = SP::BuildingService.default(allow_internal: true, writer: ArchgenFaultProbe::FaultAfterPieces.new(5))
      result = failing.regenerate(model: model, target: target, draft: { 'schema_version' => 1, 'materials' => { 'roof' => 'zinc' } })
      check('Échec pendant la croissance : refusé', !result.ok? && result.errors.first.code == 'E_WRITE')
      after = ArchgenFaultProbe.record(state[:instance])
      check('Échec : aucune ressource orpheline', before == after, ArchgenFaultProbe.diff(before, after))
    }
    [prepare, *regenerations, finish, orphan]
  end

  # --- Annuler et Rétablir en LOD 1, par opérations successives

  def undo_steps(profile)
    service = SP::BuildingService.default(allow_internal: true)
    draft = { 'schema_version' => 1, 'profile' => { 'id' => profile }, 'name' => "LOD1 #{profile}", 'mode' => 'structural', 'lod' => 1 }
    state = {}
    meta = ->(i) { SP::ComponentRepository::KEYS.map { |k| i.get_attribute('archgen.building', k) } }
    root = -> { model.entities.grep(Sketchup::ComponentInstance).first }
    [
      lambda {
        reset_model
        state[:empty] = [model.definitions.length, model.materials.count, model.layers.count]
        created = service.create(model: model, draft: draft)
        raise created.errors.map(&:to_h).inspect unless created.ok?

        state[:created] = [model.definitions.length, model.materials.count, model.layers.count]
        state[:meta] = meta.call(root.call)
        check("#{profile} : cadres partagés en LOD 1", frame_instances > frame_names.size && !frame_names.empty?, "#{frame_instances} cadres pour #{frame_names.size} définitions")
        Sketchup.undo
      },
      lambda {
        check("#{profile} : Annuler une création retire tout", root.call.nil? && [model.definitions.length, model.materials.count, model.layers.count] == state[:empty],
              [model.definitions.length, model.materials.count, model.layers.count].inspect)
        Sketchup.redo
      },
      lambda {
        check("#{profile} : Rétablir redonne la même racine", root.call && meta.call(root.call) == state[:meta])
        check("#{profile} : Rétablir redonne les mêmes ressources", [model.definitions.length, model.materials.count, model.layers.count] == state[:created],
              [model.definitions.length, model.materials.count, model.layers.count].inspect)
        instance = root.call
        model.selection.clear
        model.selection.add(instance)
        state[:definition] = instance.definition
        state[:pid] = instance.persistent_id
        target = service.load_selection(model: model).value.target
        result = service.regenerate(model: model, target: target, draft: { 'schema_version' => 1, 'footprint' => { 'width_m' => 14.0 } })
        check("#{profile} : régénération LOD 1", result.ok?, result.errors.map(&:to_h).inspect)
        state[:meta2] = meta.call(instance)
        state[:definition2] = definition_state(instance)
        Sketchup.undo
      },
      lambda {
        instance = root.call
        check("#{profile} : Annuler une régénération rend définition et métadonnées", instance.definition == state[:definition] && meta.call(instance) == state[:meta])
        check("#{profile} : même PID après Annuler", instance.persistent_id == state[:pid])
        check("#{profile} : cadres encore posés après Annuler", deep_instances(instance.definition.entities).positive?)
        Sketchup.redo
      },
      lambda {
        instance = root.call
        check("#{profile} : Rétablir rend les métadonnées", meta.call(instance) == state[:meta2])
        # L'objet Ruby de la définition n'est pas un repère après un Rétablir : on compare son contenu.
        check("#{profile} : Rétablir rend la définition", definition_state(instance) == state[:definition2],
              "#{definition_state(instance)} attendu #{state[:definition2]} même objet #{instance.definition.equal?(state[:definition_object])}")
        check("#{profile} : même PID après Rétablir", instance.persistent_id == state[:pid])
        check("#{profile} : largeur 14 m après Rétablir", JSON.parse(instance.get_attribute('archgen.building', 'config_json'))['footprint']['width_m'] == 14.0)
      }
    ]
  end

  def definition_state(instance)
    definition = instance.definition
    [definition.persistent_id, definition.get_attribute('archgen.definition', 'plan_digest'), deep_faces(definition.entities), deep_instances(definition.entities)]
  end

  def deep_faces(entities)
    entities.sum do |entity|
      case entity
      when Sketchup::Face then 1
      when Sketchup::Group then deep_faces(entity.entities)
      when Sketchup::ComponentInstance then deep_faces(entity.definition.entities)
      else 0
      end
    end
  end

  def deep_instances(entities)
    entities.sum do |entity|
      case entity
      when Sketchup::ComponentInstance then 1
      when Sketchup::Group then deep_instances(entity.entities)
      else 0
      end
    end
  end

  # --- Pannes natives en LOD 1

  def lod1_fault_blocks
    [
      lambda {
        reset_model
        ArchgenFaultProbe.lod = 1
        ArchgenFaultProbe.h06_prepare
      },
      lambda {
        ArchgenFaultProbe.h06_faults
        Sketchup.undo
      },
      lambda {
        ArchgenFaultProbe.h06_sentinel_was_last
        Sketchup.redo
      },
      lambda {
        ArchgenFaultProbe.h06_clean_regeneration
        Sketchup.undo
      },
      lambda {
        ArchgenFaultProbe.h06_after_undo
        reset_model
        ArchgenFaultProbe.h07_targets
      },
      lambda {
        ArchgenFaultProbe.h07_document
        ArchgenFaultProbe.lod = 0
      }
    ]
  end

  def summarize_fault_reports
    %w[h06-preparation h06-pannes h06-sentinelle h06-saine h06-annuler h07-cibles h07-document].each do |name|
      path = File.join(TMP, "#{name}.txt")
      next check("Rapport #{name} présent", false) unless File.exist?(path)

      lines = File.read(path, encoding: 'UTF-8').lines
      failures = lines.grep(/\AECHEC/)
      failures.each { |line| log("  #{name} #{line.strip}") }
      check("Rapport #{name} : #{lines.grep(/\AOK/).size} contrôles", failures.empty?, failures.empty? ? nil : "#{failures.size} échec(s)")
    end
  end

  def run
    @lines = []
    @rows = []
    @failures = 0
    Dir.mkdir(TMP) unless File.directory?(TMP)
    File.delete(MEASURES) if File.exist?(MEASURES)
    log("H11 SketchUp #{Sketchup.version} Ruby #{RUBY_VERSION} #{Sketchup.platform} moteur #{Archgen::ENGINE_VERSION}")
    log("Départ : #{model.entities.length} entités, #{model.definitions.length} définitions, modèle #{model.path.empty? ? 'neuf' : 'enregistré'}")
    measures = plan_blocks +
               write_blocks('ecriture haussmann 12x9', HAUSSMANN.merge('mode' => 'shell'), 'ecriture') +
               write_blocks('ecriture haussmann 12x9', HAUSSMANN.merge('mode' => 'structural'), 'ecriture') +
               write_blocks('soutenue 24x18', SUSTAINED, 'soutenue') +
               write_blocks('soutenue 24x18 toulousain', SUSTAINED.merge('profile' => { 'id' => 'toulousain' }), 'soutenue') +
               [largest_block]
    chain(measures) do
      log('--- mesures terminées')
      chain(growth_blocks) do
        log('--- croissance terminée')
        undo = %w[haussmann toulousain brutalist].flat_map { |profile| undo_steps(profile) }
        chain(undo, UNDO_DELAY_S) do
          log('--- Annuler et Rétablir LOD 1 terminés')
          chain(lod1_fault_blocks, UNDO_DELAY_S) do
            summarize_fault_reports
            log("FIN #{@failures} echec(s)")
          end
        end
      end
    end
    'recette lancee'
  end
end
