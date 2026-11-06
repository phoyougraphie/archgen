# frozen_string_literal: true

require 'json'

# Recette de sortie V0.1 sur le RBZ installé, à lancer dans la console, panneau fermé :
#   load '.../test/host/v01.rb'; ArchgenFinalProbe.run
# Enchaîne H02 à H12 par les sondes existantes, chacune dans un document neuf, et écrit
# tmp/v01.txt. La ligne « ATTENTE copier-coller » demande le vrai geste : Édition > Copier,
# puis Édition > Coller sur place. Le dernier mot du rapport est « FIN ».
# Les documents de travail sont enregistrés dans tmp/ : aucun autre fichier n'est touché.
module ArchgenFinalProbe
  REPO = File.expand_path('../..', __dir__)
  HOST = File.join(REPO, 'test', 'host')
  TMP = File.join(REPO, 'tmp')
  REPORT = File.join(TMP, 'v01.txt')
  WORK = File.join(TMP, 'v01-travail.skp')
  RESUME = File.join(TMP, 'v01-reprise.skp')
  RESUME_REPORT = File.join(TMP, 'v01-reprise.txt')
  STEP_DELAY_S = 1.2
  POLL_S = 1.0
  LONG_TIMEOUT_S = 600
  COPY_TIMEOUT_S = 300
  METERS = 4
  INCHES = 0
  REPORTS = %w[h02-metres h02-pouces h03-creation h03-annuler h03-retablir h04-sauvegarde h04-reouverture h05 h08 h09 h10
               v01-reprise h11 h06-preparation h06-pannes h06-sentinelle h06-saine h06-annuler h07-cibles h07-document h12/sketchup
               h13-releve h13-ecriture h15 h16 h17 h17-copie h18 h14].freeze

  module_function

  def model
    Sketchup.active_model
  end

  def log(line)
    @lines << line
    File.binwrite(REPORT, "#{@lines.join("\n")}\n")
  end

  # Document neuf, sans invite : le précédent part dans tmp/.
  def fresh(unit: nil)
    model.save(WORK) if model.modified? || !model.path.empty?
    Sketchup.file_new
    model.options['UnitsOptions']['LengthUnit'] = unit if unit
  end

  def finished?(relative)
    path = File.join(TMP, relative)
    File.exist?(path) && File.mtime(path) >= @started && File.read(path, encoding: 'UTF-8').lines.last.to_s.start_with?('FIN')
  end

  def stages
    h02 + h03_h04 + h05 + resume + rest
  end

  def h02
    [
      ['H02 mètres', lambda {
        fresh(unit: METERS)
        ArchgenHostProbe.run('metres', 0)
      }],
      ['H02 pouces', lambda {
        fresh(unit: INCHES)
        ArchgenHostProbe.run('pouces', 0)
      }]
    ]
  end

  def h03_h04
    probe = ArchgenCreationProbe
    [
      ['H03 préparation et création', lambda {
        fresh
        probe.h03_setup
        probe.h03_create
        Sketchup.undo
      }],
      ['H03 après Annuler', lambda {
        probe.h03_after_undo
        Sketchup.redo
      }],
      ['H03 après Rétablir', -> { probe.h03_after_redo }],
      ['H04 enregistrer et rouvrir', lambda {
        probe.h04_save
        probe.h04_open
      }],
      ['H04 contrôle', -> { probe.h04_check }]
    ]
  end

  def h05
    probe = ArchgenRegenerationProbe
    [
      ['H05 préparation', lambda {
        fresh
        probe.prepare
        @root = model.selection.first
        log('ATTENTE copier-coller')
      }, -> { model.selection.length == 1 && model.selection.first != @root }, COPY_TIMEOUT_S],
      ['H05 copie', -> { probe.after_copy }],
      ['H05 régénérer A', lambda {
        probe.regenerate_a
        Sketchup.undo
      }],
      ['H05 après Annuler', lambda {
        probe.after_undo
        Sketchup.redo
      }],
      ['H05 après Rétablir', -> { probe.after_redo }],
      ['H05 style de la copie', -> { probe.regenerate_b }],
      ['H05 refus', -> { probe.refusals }]
    ]
  end

  # Recette de sortie du PRD : reprise après une régénération, enregistrée puis rouverte.
  def resume
    [
      ['Reprise : enregistrer', lambda {
        @kept = roots.to_h { |i| [i.persistent_id, metadata(i)] }
        model.save(RESUME)
        Sketchup.open_file(RESUME)
      }],
      ['Reprise : contrôle', -> { check_resume }]
    ]
  end

  def roots
    model.entities.grep(Sketchup::ComponentInstance).select { |i| i.get_attribute('archgen.building', 'revision') }
  end

  def metadata(instance)
    Archgen::Adapters::SketchUp::ComponentRepository::KEYS.map { |k| instance.get_attribute('archgen.building', k) }
  end

  def check_resume
    service = Archgen::Adapters::SketchUp::BuildingService.default(allow_internal: true)
    lines = []
    @kept.each do |pid, kept|
      loaded = service.load_building(model: model, persistent_id: pid)
      same = loaded.ok? && metadata(loaded.value.record.instance) == kept
      lines << "#{same ? 'OK  ' : 'ECHEC'} PID #{pid} : métadonnées identiques après réouverture"
      next unless loaded.ok?

      again = Archgen::Core::GeometryEngine.generate(loaded.value.config, materials: Archgen::Composition.materials['materials'])
      digest = Archgen::Core::GeometryEngine.plan_digest(again.value)
      lines << "#{digest == loaded.value.record.metadata['plan_digest'] ? 'OK  ' : 'ECHEC'} PID #{pid} : même plan recalculé (P07)"
      entity = loaded.value.record.instance
      model.selection.clear
      model.selection.add(entity)
      lines << "#{service.load_selection(model: model).ok? ? 'OK  ' : 'ECHEC'} PID #{pid} : sélection rechargée, régénérable"
    end
    File.binwrite(RESUME_REPORT, "#{lines.join("\n")}\n")
  end

  def rest
    [
      ['H08', lambda {
        fresh
        ArchgenStylesProbe.run(images: false)
      }],
      ['H09', lambda {
        fresh
        ArchgenH09Probe.run
      }, -> { finished?('h09.txt') }, LONG_TIMEOUT_S],
      ['H10', lambda {
        fresh
        ArchgenH10Probe.run
      }, -> { finished?('h10.txt') }, LONG_TIMEOUT_S],
      ['Fermer le panneau', -> { ArchgenH10Probe.dialog.close }],
      ['H11, H06 et H07 en LOD 1', lambda {
        fresh
        ArchgenH11Probe.run
      }, -> { finished?('h11.txt') }, LONG_TIMEOUT_S],
      ['H12', lambda {
        fresh
        ArchgenH12Probe.run
      }, -> { finished?('h12/sketchup.txt') }, LONG_TIMEOUT_S],
      ['H13 relevé', lambda {
        fresh
        ArchgenSurveyProbe.run
      }, -> { finished?('h13-releve.txt') }, LONG_TIMEOUT_S],
      ['H13 écriture', lambda {
        fresh
        ArchgenSiteWriteProbe.run
      }, -> { finished?('h13-ecriture.txt') }, LONG_TIMEOUT_S],
      ['H15', lambda {
        fresh
        ArchgenH15Probe.run
      }, -> { finished?('h15.txt') }, LONG_TIMEOUT_S],
      ['H16', lambda {
        fresh
        ArchgenH16Probe.run
      }, -> { finished?('h16.txt') }, LONG_TIMEOUT_S],
      ['H17', lambda {
        fresh
        ArchgenH17Probe.run
      }, -> { finished?('h17.txt') }, LONG_TIMEOUT_S],
      ['H17 préparation de la copie', lambda {
        fresh
        ArchgenH17Probe.prepare_copy
        log('ATTENTE copier-coller H17')
      }, -> { ArchgenH17Probe.copy_done? }, COPY_TIMEOUT_S],
      ['H17 copie', -> { ArchgenH17Probe.after_copy }],
      ['H18', lambda {
        fresh
        ArchgenH18Probe.run
      }, -> { finished?('h18.txt') }, LONG_TIMEOUT_S * 3],
      ['H14', lambda {
        fresh
        ArchgenH14Probe.run
      }, -> { finished?('h14.txt') }, 1800]
    ]
  end

  def advance
    stage = @queue.shift
    return summarize unless stage

    label, action, done, timeout = stage
    begin
      action.call
      log("FAIT  #{label}")
    rescue Exception => e # rubocop:disable Lint/RescueException
      @failures += 1
      log("ECHEC #{label} : #{e.class} #{e.message} #{e.backtrace.first(2).join(' | ')}")
    end
    wait(label, done, timeout)
  end

  def wait(label, done, timeout)
    return UI.start_timer(STEP_DELAY_S, false) { advance } unless done

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    poll = lambda do
      if done.call
        UI.start_timer(STEP_DELAY_S, false) { advance }
      elsif Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        @failures += 1
        log("ECHEC #{label} : délai dépassé")
        advance
      else
        UI.start_timer(POLL_S, false) { poll.call }
      end
    end
    UI.start_timer(POLL_S, false) { poll.call }
  end

  # Un rapport plus ancien que ce passage ne prouve rien.
  def summarize
    log('--- rapports')
    @reports.each do |name|
      path = File.join(TMP, "#{name}.txt")
      unless File.exist?(path) && File.mtime(path) >= @started
        @failures += 1
        log("ECHEC #{name} : rapport absent ou ancien")
        next
      end
      lines = File.read(path, encoding: 'UTF-8').lines
      failures = lines.grep(/\AECHEC/)
      @failures += failures.size
      log("#{failures.empty? ? 'OK   ' : 'ECHEC'} #{name} : #{lines.grep(/\AOK/).size} contrôles, #{failures.size} échec(s)")
      failures.first(12).each { |line| log("      #{line.strip}") }
    end
    log("FIN #{@failures} echec(s), ARCHGEN #{Archgen::VERSION}, moteur #{Archgen::ENGINE_VERSION}, SketchUp #{Sketchup.version}, Ruby #{RUBY_VERSION}, code #{installed_from}")
  end

  # Le code exécuté vient du dossier Plugins, pas du dépôt.
  def installed_from
    Sketchup.extensions['ARCHGEN'].extension_path
  end

  def run
    start(REPORTS) { stages }
  end

  # Rejeu de H05, de la reprise et de H09 après une panne de la sonde, sans changer le RBZ.
  def run_again
    start(%w[h05 v01-reprise h09]) do
      h09_stage = rest.find { |stage| stage.first == 'H09' }
      h05 + resume + [h09_stage]
    end
  end

  # Rejeu de H15 à H17 seules, sans la charge de H14, sur le même RBZ.
  def run_ensembles
    start(%w[h15 h16 h17 h17-copie]) { rest.select { |stage| stage.first.start_with?('H15', 'H16', 'H17') } }
  end

  # Rejeu de H18 seule, sur le même RBZ.
  def run_h18
    start(%w[h18]) { [rest.find { |stage| stage.first == 'H18' }] }
  end

  # Rejeu de H14 seule, sur le même RBZ. La charge bloque SketchUp plusieurs minutes :
  # Windows peut l'annoncer « ne répond pas », ne pas fermer la fenêtre.
  def run_h14
    start(%w[h14]) { [rest.find { |stage| stage.first == 'H14' }] }
  end

  def start(reports)
    @lines = []
    @failures = 0
    @started = Time.now - 2
    @reports = reports
    %w[run creation regeneration styles panel h09 h10 faults h11 h12 survey site_write h15 h16 h17 h18 h14].each { |file| load File.join(HOST, "#{file}.rb") }
    log("V0.1 départ #{Time.now}, ARCHGEN #{Archgen::VERSION}, code #{installed_from}")
    @queue = yield
    advance
    'recette lancee'
  end
end
