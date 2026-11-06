# frozen_string_literal: true

# Sonde native des recettes H06 et H07, à charger dans la console d'un modèle de test :
#   load 'C:/chemin/du/depot/test/host/faults.rb'
#   ArchgenFaultProbe.h06_prepare ; ArchgenFaultProbe.h06_faults
#   (lire le menu Édition : il doit afficher la sentinelle)
#   ArchgenFaultProbe.h06_clean_regeneration
#   (Édition > Annuler ; le menu doit revenir à la sentinelle)
#   ArchgenFaultProbe.h07_targets ; ArchgenFaultProbe.h07_document
# Les pannes passent par les ports du service : le produit ne contient aucun crochet.
# ArchgenFaultProbe.lod = 1 rejoue tout en LOD 1 ; test/host/h11.rb enchaîne ce rejeu.
module ArchgenFaultProbe
  REPO = File.expand_path('../..', __dir__)
  TMP = File.join(REPO, 'tmp')
  SP = Archgen::Adapters::SketchUp
  Injected = Class.new(StandardError)
  # zinc et calcaire n'existent pas encore : la tentative crée de vraies ressources à retirer.
  EDIT = { 'schema_version' => 1, 'footprint' => { 'width_m' => 15.0 }, 'materials' => { 'roof' => 'zinc', 'wall' => 'limestone' } }.freeze

  # Panne après les premières pièces écrites.
  class FaultAfterPieces < SP::GeometryWriter
    def initialize(pieces)
      super()
      @pieces = pieces
    end

    private

    def write_primitive(node, entities, resources)
      count = super
      @pieces -= 1
      raise Injected, 'panne après des faces réelles' if @pieces.zero?

      count
    end
  end

  class FaultOnMark < SP::GeometryWriter
    def mark_definition(*)
      raise Injected, 'panne au marquage'
    end
  end

  class FaultAfterSwap < SP::ComponentRepository
    def swap(instance, definition:)
      super
      raise Injected, 'panne après le remplacement'
    end
  end

  class FaultBeforeMetadata < SP::ComponentRepository
    def write_metadata(_instance, _metadata)
      raise Injected, 'panne avant les métadonnées'
    end
  end

  class FaultMidMetadata < SP::ComponentRepository
    def write_metadata(instance, metadata)
      instance.set_attribute(DICTIONARY, 'revision', metadata['revision'])
      instance.set_attribute(DICTIONARY, 'plan_digest', metadata['plan_digest'])
      raise Injected, 'panne au milieu des métadonnées'
    end
  end

  # La relecture finale échoue alors que tout a été écrit.
  class FaultOnReadBack < SP::ComponentRepository
    def read_metadata(_instance)
      {}
    end

    def read_instance(model, entity)
      SP::ComponentRepository.new.read_instance(model, entity)
    end

    def read(model, persistent_id:)
      SP::ComponentRepository.new.read(model, persistent_id: persistent_id)
    end
  end

  class FaultOnInsert < SP::ComponentRepository
    def insert(_model, definition:, transform: nil)
      raise Injected, "panne à l'insertion #{definition.name} #{transform.inspect}"
    end
  end

  # Panne sur la pose d'un cadre partagé : la définition vient d'être créée (LOD 1).
  class FaultOnFrame < SP::GeometryWriter
    private

    def write_instance(*)
      super
      raise Injected, 'panne à la pose d’un cadre'
    end
  end

  @lines = []
  @lod = 0

  module_function

  # ArchgenFaultProbe.lod = 1 rejoue les mêmes pannes et cibles en LOD 1 (AG-018).
  def lod=(value)
    @lod = value
  end

  def draft
    { 'schema_version' => 1, 'profile' => { 'id' => 'generic' }, 'name' => 'Cible', 'mode' => 'structural', 'lod' => @lod }
  end

  def new_building
    draft.merge('name' => 'Tentative', 'materials' => { 'roof' => 'zinc', 'wall' => 'limestone' })
  end

  def service(**ports)
    SP::BuildingService.default(allow_internal: true, **ports)
  end

  def model
    Sketchup.active_model
  end

  def check(label, ok, detail = nil)
    @lines << "#{ok ? 'OK  ' : 'ECHEC'} #{label}#{detail.nil? ? '' : " : #{detail}"}"
    ok
  end

  def flush(name)
    Dir.mkdir(TMP) unless File.directory?(TMP)
    File.binwrite(File.join(TMP, "#{name}.txt"), "#{@lines.join("\n")}\n")
    puts "#{name} : #{@lines.count { |l| l.start_with?('ECHEC') }} echec(s) sur #{@lines.count { |l| l.start_with?('OK', 'ECHEC') }}"
    @lines = []
  end

  # Enregistrement du contrat : définitions, matériaux, sélection, config, racine.
  def record(instance = nil)
    state = {
      definitions: model.definitions.map(&:name).sort,
      materials: model.materials.map(&:name).sort,
      layers: model.layers.map(&:name).sort,
      roots: model.entities.grep(Sketchup::ComponentInstance).map(&:persistent_id).sort,
      selection: model.selection.map(&:persistent_id),
      active_path: model.active_path.nil?
    }
    return state unless instance

    state.merge(
      target_definition: instance.definition.name,
      target_transform: instance.transformation.to_a,
      target_attrs: SP::ComponentRepository::KEYS.map { |k| instance.get_attribute(SP::ComponentRepository::DICTIONARY, k) }
    )
  end

  def diff(a, b)
    a.keys.select { |k| a[k] != b[k] }.join(', ')
  end

  def h06_prepare
    @lines << "H06 #{Sketchup.version} Ruby #{RUBY_VERSION} #{Sketchup.platform}"
    result = service.create(model: model, draft: draft)
    check('Cible créée', result.ok?, result.errors.map(&:to_h).inspect)
    @a = model.find_entity_by_persistent_id(result.value.persistent_id)
    model.selection.clear
    model.selection.add(@a)
    # Sentinelle : la dernière ligne d'historique avant les pannes.
    model.start_operation('Sentinelle H06', true)
    @a.set_attribute('autre.extension', 'cle', 'valeur')
    model.commit_operation
    @target = service.load_selection(model: model).value.target
    flush('h06-preparation')
  end

  def frame_faults
    @lod == 1 ? { 'Écriture : à la pose d’un cadre partagé' => { writer: FaultOnFrame.new } } : {}
  end

  def faults
    frame_faults.merge(
      'Écriture : après la première pièce' => { writer: FaultAfterPieces.new(1) },
      'Écriture : après trois pièces' => { writer: FaultAfterPieces.new(3) },
      'Écriture : au marquage de la définition' => { writer: FaultOnMark.new },
      'Remplacement : juste après le swap' => { repository: FaultAfterSwap.new },
      'Métadonnées : avant la première écriture' => { repository: FaultBeforeMetadata.new },
      'Métadonnées : au milieu de l’écriture' => { repository: FaultMidMetadata.new },
      'Métadonnées : relecture finale' => { repository: FaultOnReadBack.new }
    )
  end

  def creation_faults
    frame_faults.transform_keys { |label| label.sub('Écriture', 'Création') }.merge(
      'Création : après la première pièce' => { writer: FaultAfterPieces.new(1) },
      'Création : à l’insertion' => { repository: FaultOnInsert.new },
      'Création : au milieu des métadonnées' => { repository: FaultMidMetadata.new }
    )
  end

  def h06_faults
    faults.each do |label, ports|
      before = record(@a)
      result = service(**ports).regenerate(model: model, target: @target, draft: EDIT)
      refused = !result.ok? && result.errors.first.code == 'E_WRITE'
      check("#{label} : refusé", refused, result.errors.map { |d| d.params['reason'] }.join(','))
      after = record(@a)
      check("#{label} : enregistrements identiques", before == after, diff(before, after))
      check("#{label} : matériaux tentés retirés", model.materials.none? { |m| m.name == 'ARCHGEN Zinc' })
    end
    creation_faults.each do |label, ports|
      before = record(@a)
      result = service(**ports).create(model: model, draft: new_building)
      check("#{label} : refusé", !result.ok? && result.errors.first.code == 'E_WRITE', result.errors.map { |d| d.params['reason'] }.join(','))
      after = record(@a)
      check("#{label} : enregistrements identiques", before == after, diff(before, after))
    end
    flush('h06-pannes')
  end

  # À appeler après un Annuler natif : si les pannes avaient laissé une ligne, la sentinelle resterait.
  def h06_sentinel_was_last
    check('Un Annuler après les pannes retire la sentinelle', @a.get_attribute('autre.extension', 'cle').nil?)
    flush('h06-sentinelle')
  end

  # Après toutes les pannes, l'écriture réelle doit encore fonctionner normalement.
  def h06_clean_regeneration
    before = record(@a)
    result = service.regenerate(model: model, target: @target, draft: EDIT)
    check('Régénération saine après les pannes', result.ok?, result.errors.map(&:to_h).inspect)
    check('Révision 2', @a.get_attribute('archgen.building', 'revision') == 2)
    check('Nouveau matériau présent', model.materials.any? { |m| m.name == 'ARCHGEN Zinc' })
    @before_clean = before
    flush('h06-saine')
  end

  def h06_after_undo
    now = record(@a)
    check('Annuler ramène l’état d’avant', now == @before_clean, diff(now, @before_clean))
    flush('h06-annuler')
  end

  def fresh_target(name)
    created = service.create(model: model, draft: draft.merge('name' => name))
    instance = model.find_entity_by_persistent_id(created.value.persistent_id)
    model.selection.clear
    model.selection.add(instance)
    [instance, service.load_selection(model: model).value.target]
  end

  def expect_refusal(label, reasons, before: nil, instance: nil)
    result = yield
    reason = result.errors.first&.params&.fetch('reason', nil)
    check("#{label} : refusé", !result.ok? && reasons.include?(reason), "#{result.errors.first&.code} #{reason}")
    return unless before

    after = record(instance)
    check("#{label} : aucune écriture", before == after, diff(before, after))
  end

  def h07_targets
    @lines << "H07 #{Sketchup.version} Ruby #{RUBY_VERSION} #{Sketchup.platform}"
    probe = service

    instance, target = fresh_target('Verrouillée')
    instance.locked = true
    before = record(instance)
    expect_refusal('Verrouillée', %w[target_locked], before: before, instance: instance) { probe.regenerate(model: model, target: target, draft: EDIT) }
    instance.locked = false

    instance, target = fresh_target('Échelle')
    model.start_operation('Échelle de test', true)
    instance.transform!(Geom::Transformation.scaling(1.5))
    model.commit_operation
    before = record(instance)
    expect_refusal('Mise à l’échelle', %w[non_rigid_transform], before: before, instance: instance) { probe.regenerate(model: model, target: target, draft: EDIT) }

    _, target = fresh_target('Supprimée')
    instance = model.find_entity_by_persistent_id(target.persistent_id)
    model.start_operation('Suppression de test', true)
    instance.erase!
    model.commit_operation
    before = record
    expect_refusal('Supprimée', %w[target_not_found deleted_target], before: before) { probe.regenerate(model: model, target: target, draft: EDIT) }

    instance, target = fresh_target('Imbriquée')
    model.start_operation('Imbrication de test', true)
    group = model.entities.add_group(instance)
    group.name = 'Groupe de test'
    model.commit_operation
    before = record
    expect_refusal('Imbriquée', %w[not_at_model_root target_not_found selection_changed], before: before) { probe.regenerate(model: model, target: target, draft: EDIT) }

    nested = group.entities.grep(Sketchup::ComponentInstance).first
    check('La cible imbriquée garde ses métadonnées', nested && nested.get_attribute('archgen.building', 'revision') == 1)
    model.selection.clear
    model.selection.add(group)
    expect_refusal('Sélection d’un groupe', %w[not_a_component_instance]) { probe.load_selection(model: model) }

    instance, target = fresh_target('Sélection changée')
    other = fresh_target('Autre').first
    model.selection.clear
    model.selection.add(other)
    before = record(instance)
    expect_refusal('Sélection changée après aperçu', %w[selection_changed], before: before, instance: instance) { probe.regenerate(model: model, target: target, draft: EDIT) }

    instance, target = fresh_target('Contexte')
    edit_context(group) do
      before = record(instance)
      expect_refusal('Édition d’un groupe en cours : régénérer', %w[nested_edit_context], before: before, instance: instance) { probe.regenerate(model: model, target: target, draft: EDIT) }
      expect_refusal('Édition d’un groupe en cours : créer', %w[nested_edit_context], before: before, instance: instance) { probe.create(model: model, draft: draft) }
    end

    h07_versions(probe)
    flush('h07-cibles')
  end

  def edit_context(group)
    model.active_path = [group]
    check('Contexte d’édition ouvert', !model.active_path.nil?)
    yield
  ensure
    model.active_path = nil
  end

  def h07_versions(probe)
    {
      'engine_version' => ['999', '/metadata/engine_version'],
      'material_revision' => [99, '/metadata/material_revision']
    }.each do |key, (value, path)|
      instance, target = fresh_target("Version #{key}")
      model.start_operation('Version de test', true)
      instance.set_attribute('archgen.building', key, value)
      model.commit_operation
      check("#{key} récent : consultable", probe.load_selection(model: model).ok?)
      before = record(instance)
      result = probe.regenerate(model: model, target: target, draft: EDIT)
      check("#{key} récent : refusé", !result.ok? && result.errors.first.code == 'E_VERSION' && result.errors.first.path == path, result.errors.first&.path)
      after = record(instance)
      check("#{key} récent : aucune écriture", before == after, diff(before, after))
    end
  end

  # Un jeton et une cible émis pour un document ne servent pas dans un autre.
  def h07_document
    @lines << "H07 document #{Sketchup.version}"
    probe = service
    instance, target = fresh_target('Autre document')
    tokens = Archgen::UI::TargetTokens.new
    old_model = model
    token = tokens.issue(target, model: old_model)
    check('Jeton valide dans son document', tokens.resolve(token, model: Sketchup.active_model).ok?)
    path = File.join(TMP, 'h07.skp')
    pid = instance.persistent_id
    old_model.save(path)
    saved_token = tokens.resolve(token, model: Sketchup.active_model)
    check('Enregistrer périme le jeton', !saved_token.ok? && saved_token.errors.first.params['reason'] == 'other_model')
    before = record(instance)
    after_save = probe.regenerate(model: old_model, target: target, draft: EDIT)
    check('Enregistrer périme la cible', !after_save.ok? && after_save.errors.first.params['reason'] == 'document_changed', after_save.errors.first&.params)
    check('Cible périmée : aucune écriture', before == record(instance), diff(before, record(instance)))
    reloaded = probe.load_selection(model: old_model).value.target
    check('Recharger la sélection redonne une cible', reloaded.document_key == old_model.guid)
    Sketchup.file_new
    fresh = Sketchup.active_model
    @lines << "Mesure : ancien modèle valid? #{old_model.valid?}, nouveau == ancien #{fresh == old_model}, guid distinct #{fresh.guid != target.document_key}"
    resolved = tokens.resolve(token, model: fresh)
    check('Jeton refusé dans un autre document', !resolved.ok? && resolved.errors.first.params['reason'] == 'other_model', resolved.errors.first&.params)
    inventory = [fresh.entities.length, fresh.definitions.length, fresh.materials.count]
    in_new = probe.regenerate(model: fresh, target: reloaded, draft: EDIT)
    check('Cible refusée dans un autre document', !in_new.ok? && in_new.errors.first.params['reason'] == 'document_changed', in_new.errors.map { |d| d.params['reason'] }.join(','))
    check('Nouveau document intact', inventory == [fresh.entities.length, fresh.definitions.length, fresh.materials.count])
    Sketchup.open_file(path)
    reopened = Sketchup.active_model
    entity = reopened.find_entity_by_persistent_id(pid)
    check('Même PID présent dans le fichier rouvert', !entity.nil?)
    reopened.selection.clear
    reopened.selection.add(entity)
    before = record(entity)
    collision = probe.regenerate(model: reopened, target: target, draft: EDIT)
    check('PID identique, cible d’avant enregistrement refusée', !collision.ok? && collision.errors.first.params['reason'] == 'document_changed', collision.errors.map { |d| d.params['reason'] }.join(','))
    check('Collision : aucune écriture', before == record(entity), diff(before, record(entity)))
    legit = probe.regenerate(model: reopened, target: probe.load_selection(model: reopened).value.target, draft: EDIT)
    check('Sélection rechargée : régénération acceptée', legit.ok?, legit.errors.map(&:to_h).inspect)
    flush('h07-document')
  rescue StandardError => e
    check('Exception inattendue', false, "#{e.class}: #{e.message}")
    flush('h07-document')
  end
end
