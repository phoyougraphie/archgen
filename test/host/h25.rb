# frozen_string_literal: true

require 'json'
require 'fileutils'

# Recette H25, rues variées (AG-061 à AG-063), à lancer sur un document neuf, panneaux fermés :
#   load '.../test/host/h25.rb'; ArchgenH25Probe.run
# Écrit une rue variée par le service réel et par le contrôleur du panneau de rue, la relit,
# la régénère, l'annule et l'enregistre. Rapport : tmp/h25.txt, vues dans tmp/h25/.
# Le dernier mot du rapport est « FIN ».
module ArchgenH25Probe
  REPO = File.expand_path('../..', __dir__)
  TMP = File.join(REPO, 'tmp')
  IMAGES = File.join(TMP, 'h25')
  REPORT = File.join(TMP, 'h25.txt')
  SKP = File.join(TMP, 'h25.skp')
  SP = Archgen::Adapters::SketchUp
  INCH = 0.0254
  DICTIONARY = 'archgen.ensemble'
  DELAY_S = 1.5
  ELBOW = [[0, 0], [72, 0], [72, 48]].freeze
  VARIED = { 'levels' => { 'min' => 3, 'max' => 7 }, 'roofs' => %w[flat gable mansard] }.freeze

  module_function

  def model
    Sketchup.active_model
  end

  def service
    @service ||= SP::EnsembleService.default
  end

  def tree(variety: VARIED, seed: 4, profile: 'brutalist', points: ELBOW, closed: false, layout: { 'side' => 'both' })
    out = { 'seed' => seed, 'trace' => { 'points_m' => points, 'closed' => closed }, 'building' => { 'profile' => { 'id' => profile } } }
    out['layout'] = layout unless closed
    variety ? out.merge('variety' => variety) : out
  end

  def log(line)
    @lines << line
    File.binwrite(REPORT, "#{@lines.join("\n")}\n")
  end

  def check(label, ok, detail = nil)
    @failures += 1 unless ok
    log("#{ok ? 'OK   ' : 'ECHEC'} #{label}#{detail ? " : #{detail}" : ''}")
    ok
  end

  def roots
    model.entities.grep(Sketchup::ComponentInstance).select { |i| i.get_attribute(DICTIONARY, 'ensemble_version') }
  end

  def counts
    { definitions: model.definitions.length, materials: model.materials.length, layers: model.layers.length, entities: model.entities.length }
  end

  def parcels_of(instance)
    instance.definition.entities.grep(Sketchup::ComponentInstance)
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

  # Hauteur de chaque bâtiment dans le modèle, au millimètre.
  def tops(root)
    parcels_of(root).to_h { |p| [p.name, (p.bounds.max.z * INCH * 1000).round] }
  end

  def stored(root)
    JSON.parse(root.get_attribute(DICTIONARY, 'ensemble_json'))
  end

  def reason_of(result)
    result.errors.first&.params&.fetch('reason', nil)
  end

  # Écart de niveaux entre voisines d'une même rangée, d'après le plan.
  def max_neighbour_step(plan)
    plan['parcels'].group_by { |e| e['id'].split('/').first }.values.flat_map do |row|
      row.each_cons(2).map { |a, b| (a['variety']['levels'] - b['variety']['levels']).abs }
    end.max
  end

  # --- Étapes

  def stage_refused
    before = counts
    result = service.create(model: model, tree: tree(variety: { 'levels' => { 'min' => 3, 'max' => 7 }, 'roofs' => %w[hip] }), origin_m: [0.0, 0.0, 0.0])
    check('Croupe refusée en rangée', !result.ok? && reason_of(result) == 'variety_hip_roof', reason_of(result).to_s)
    check('Refus : document intact', counts == before && roots.empty?)
    order = service.create(model: model, tree: tree(variety: { 'levels' => { 'min' => 6, 'max' => 3 } }), origin_m: [0.0, 0.0, 0.0])
    check('Fourchette inversée refusée', reason_of(order) == 'variety_levels_order', reason_of(order).to_s)
  end

  def stage_create
    @before_create = counts
    @tree = tree
    preview = service.preview(tree: @tree)
    return check('Aperçu de la rue variée', false, preview.errors.map(&:to_h).inspect) unless preview.ok?

    @plan = preview.value.plan
    result = service.create(model: model, tree: @tree, origin_m: [0.0, 0.0, 0.0])
    return check('Création de la rue variée', false, result.errors.map(&:to_h).inspect) unless result.ok?

    root = roots.first
    metrics = result.value.metrics
    summary = @plan['variety']
    check('Création de la rue variée', true, "#{metrics['parcel_count']} parcelles, #{metrics['definition_count']} définitions, répartition #{summary.to_json}")
    check('Répartition = parcelles', summary['levels'].values.sum == metrics['parcel_count'] && summary['roofs'].values.sum == metrics['parcel_count'])
    check('Niveaux dans la fourchette', summary['levels'].keys.map(&:to_i).all? { |n| n.between?(3, 7) }, summary['levels'].keys.join(', '))
    check('Écart entre voisines ≤ 2', max_neighbour_step(@plan) <= 2, "max #{max_neighbour_step(@plan)}")
    check('Trois toits tirés', summary['roofs'].keys.sort == %w[flat gable mansard], summary['roofs'].keys.join(', '))
    heights = tops(root).values.uniq.sort
    check('Hauteurs variées dans le modèle', heights.size >= 3, heights.map { |h| format('%.2f m', h / 1000.0) }.join(', '))
    check('Faces réelles = plan', deep_faces(root.definition.entities) == metrics['expanded_face_count'], "#{metrics['expanded_face_count']} faces")
    check('Définitions partagées', parcels_of(root).map(&:definition).uniq.size == metrics['definition_count'])
    kept = stored(root)['variety'] || {}
    check('Variété enregistrée', kept['roofs'] == VARIED['roofs'] && kept['levels']&.slice('min', 'max') == VARIED['levels'], kept.to_json)
    @after_create = counts
    @digest = root.get_attribute(DICTIONARY, 'ensemble_digest')
    @tops = tops(root)
    Sketchup.undo
  end

  def stage_after_undo
    check('Annuler retire la rue en une fois', roots.empty? && counts == @before_create, "#{@before_create} / #{counts}")
    Sketchup.redo
  end

  def stage_after_redo
    root = roots.first
    check('Rétablir ramène la rue', roots.size == 1 && counts == @after_create)
    check('Mêmes hauteurs après Rétablir', root && tops(root) == @tops)
  end

  def select(root)
    model.selection.clear
    model.selection.add(root)
  end

  def stage_regenerate_seed
    root = roots.first
    select(root)
    loaded = service.load_selection(model: model)
    check('Rue variée relue', loaded.ok?, loaded.errors.map(&:to_h).first.to_s)
    again = service.preview(tree: loaded.value.settings)
    check('Même empreinte recalculée', again.ok? && again.value.ensemble_digest == @digest, @digest[0, 12])
    result = service.regenerate(model: model, target: loaded.value.target, changes: { 'seed' => 5 })
    check('Autre graine : régénérée', result.ok?, result.errors.map(&:to_h).first.to_s)
    root = roots.first
    check('Autre graine : autre rue', root.get_attribute(DICTIONARY, 'ensemble_digest') != @digest && tops(root) != @tops)
    Sketchup.undo
  end

  def stage_seed_undone
    root = roots.first
    check('Annuler la régénération rend la rue', root.get_attribute(DICTIONARY, 'ensemble_digest') == @digest && tops(root) == @tops)
  end

  # Le contrôleur du panneau, avec le service réel : case décochée en modification, la variété part.
  def stage_panel_remove
    root = roots.first
    select(root)
    controller = Archgen::UI::StreetController.new(service: service, session: Archgen::Core::TraceSession.new, registry: Archgen::Composition.registry.value,
                                                   model_provider: -> { model })
    controller.mode = 'edit'
    call = lambda do |action, payload|
      @request = (@request || 0) + 1
      controller.dispatch(JSON.generate('v' => 1, 'request_id' => "h25-#{@request}", 'action' => action, 'payload' => payload))
    end
    loaded = call.call('load_selection', {})
    check('Panneau : variété relue', loaded['ok'] && loaded.dig('result', 'settings', 'variety', 'roofs') == VARIED['roofs'] && loaded.dig('result', 'variety'), loaded['diagnostics'].to_s)
    plain = { 'building' => { 'profile' => { 'id' => 'brutalist' } }, 'variety' => nil }
    shown = call.call('edit_preview', 'settings' => plain)['result']
    check('Panneau : case décochée annoncée', shown['changed'] && !shown.key?('variety'))
    written = call.call('regenerate', 'settings' => plain, 'ensemble_digest' => shown['ensemble_digest'])
    check('Panneau : un seul gabarit écrit', written['ok'] && !stored(roots.first).key?('variety'), written['diagnostics'].to_s)
    check('Panneau : hauteurs égales', tops(roots.first).values.uniq.size == 1, tops(roots.first).values.uniq.join(', '))
    Sketchup.undo
    check('Annuler rend la rue variée', tops(roots.first) == @tops)
  end

  def stage_block
    result = service.create(model: model, tree: tree(profile: 'toulousain', points: [[0, 0], [40, 0], [40, 40], [0, 40]], closed: true, layout: nil,
                                                     variety: { 'levels' => { 'min' => 2, 'max' => 4 }, 'roofs' => %w[gable flat] }, seed: 2), origin_m: [120.0, 0.0, 0.0])
    check('Îlot varié créé', result.ok?, result.ok? ? "#{result.value.metrics['parcel_count']} parcelles" : result.errors.map(&:to_h).first.to_s)
  end

  def stage_save
    root = roots.find { |r| r.get_attribute(DICTIONARY, 'ensemble_digest') == @digest }
    @saved_pid = root.persistent_id
    check('Enregistrer', model.save(SKP))
  end

  def stage_views
    FileUtils.mkdir_p(IMAGES)
    view = model.active_view
    { 'rue' => [[-25, -45, 35], [40, 5, 8]], 'coude' => [[110, -30, 30], [60, 20, 8]], 'ilot' => [[100, -40, 45], [140, 20, 5]] }.each do |name, (eye, target)|
      view.camera = Sketchup::Camera.new(Geom::Point3d.new(*eye.map { |v| v / INCH }), Geom::Point3d.new(*target.map { |v| v / INCH }), Z_AXIS)
      path = File.join(IMAGES, "#{name}.png")
      view.write_image(path, 1400, 900, true)
      check("Image #{name}", File.size?(path).to_i.positive?)
    end
  end

  # --- Déroulé

  def stages
    [-> { stage_refused }, -> { stage_create }, -> { stage_after_undo }, -> { stage_after_redo }, -> { stage_regenerate_seed }, -> { stage_seed_undone },
     -> { stage_panel_remove }, -> { stage_block }, -> { stage_save }, -> { stage_views }]
  end

  def advance
    stage = @queue.shift
    return finish unless stage

    begin
      stage.call
    rescue Exception => e # rubocop:disable Lint/RescueException
      @failures += 1
      log("ECHEC étape : #{e.class} #{e.message} #{e.backtrace.first(3).join(' | ')}")
    end
    UI.start_timer(DELAY_S, false) { advance }
  end

  def finish
    log("FIN #{@failures} echec(s), ARCHGEN #{Archgen::VERSION}, SketchUp #{Sketchup.version}, Ruby #{RUBY_VERSION}")
  end

  def run
    @lines = []
    @failures = 0
    @service = nil
    @queue = stages
    log("H25 départ #{Time.now}, ARCHGEN #{Archgen::VERSION}, code #{Sketchup.extensions['ARCHGEN'].extension_path}")
    advance
    'recette lancee'
  end
end
