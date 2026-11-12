# frozen_string_literal: true

# Sonde native de la recette H05, à charger dans la console d'un modèle de test :
#   load 'C:/chemin/du/depot/test/host/regeneration.rb'
#   ArchgenRegenerationProbe.prepare              crée A, le déplace, le pivote, le sélectionne
#   (Édition > Copier, Édition > Coller sur place : la copie réelle de SketchUp)
#   ArchgenRegenerationProbe.after_copy           déplace B, vérifie le partage
#   ArchgenRegenerationProbe.regenerate_a         sélectionne A, change ses dimensions
#   (Édition > Annuler)  ArchgenRegenerationProbe.after_undo
#   (Édition > Rétablir) ArchgenRegenerationProbe.after_redo
#   ArchgenRegenerationProbe.regenerate_b         change le style de la copie seule
#   ArchgenRegenerationProbe.refusals             transformation et cible invalides
module ArchgenRegenerationProbe
  REPO = File.expand_path('../..', __dir__)
  TMP = File.join(REPO, 'tmp')
  DICTIONARY = 'archgen.building'
  DRAFT = { 'schema_version' => 1, 'profile' => { 'id' => 'generic' }, 'name' => 'Bâtiment A', 'mode' => 'structural' }.freeze
  EDIT = { 'schema_version' => 1, 'footprint' => { 'width_m' => 16.0 } }.freeze
  USER_TAG = 'Tag utilisateur H05'
  REPORT = File.join(TMP, 'h05.txt')

  @lines = []

  module_function

  def service
    @service ||= Archgen::Adapters::SketchUp::BuildingService.default(allow_internal: true)
  end

  def model
    Sketchup.active_model
  end

  def check(label, ok, detail = nil)
    @lines << "#{ok ? 'OK  ' : 'ECHEC'} #{label}#{detail.nil? ? '' : " : #{detail}"}"
    ok
  end

  def flush(step)
    File.binwrite(REPORT, "#{@lines.join("\n")}\n")
    puts "#{step} : #{@lines.count { |l| l.start_with?('ECHEC') }} echec(s) sur #{@lines.count { |l| l.start_with?('OK', 'ECHEC') }}"
  end

  def faces_in(entities)
    entities.grep(Sketchup::Face).size + entities.grep(Sketchup::Group).sum { |g| faces_in(g.entities) }
  end

  def state(instance)
    {
      pid: instance.persistent_id,
      transform: instance.transformation.to_a,
      tag: instance.layer.name,
      name: instance.name,
      definition: instance.definition.name,
      faces: faces_in(instance.definition.entities),
      width: instance.definition.bounds.width,
      attrs: Archgen::Adapters::SketchUp::ComponentRepository::KEYS.to_h { |k| [k, instance.get_attribute(DICTIONARY, k)] },
      third_party: instance.get_attribute('autre.extension', 'cle')
    }
  end

  def select_only(instance)
    model.selection.clear
    model.selection.add(instance)
  end

  def diff(a, b)
    (a.keys.select { |k| a[k] != b[k] }).join(', ')
  end

  def prepare
    @lines << "H05 #{Sketchup.version} Ruby #{RUBY_VERSION} #{Sketchup.platform}"
    created = service.create(model: model, draft: DRAFT)
    check('Création de A', created.ok?, created.errors.map(&:to_h).inspect)
    @a = model.find_entity_by_persistent_id(created.value.persistent_id)
    model.start_operation('Placement utilisateur H05', true)
    tag = model.layers.add(USER_TAG)
    @a.layer = tag
    @a.name = 'A, nom utilisateur'
    @a.set_attribute('autre.extension', 'cle', 'valeur')
    move = Geom::Transformation.translation([30.m, 12.m, 0])
    turn = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 37.degrees)
    @a.transformation = move * turn
    model.commit_operation
    check('Modèle identique dans deux appels', Sketchup.active_model == Sketchup.active_model)
    select_only(@a)
    @a0 = state(@a)
    flush('prepare')
  end

  # B vient du vrai copier-coller de SketchUp : il faut observer ce qu'il recopie.
  def after_copy
    copies = model.selection.to_a
    check('Une copie sélectionnée', copies.size == 1 && copies.first != @a, copies.size)
    @b = copies.first
    model.start_operation('Déplacement copie H05', true)
    @b.transform!(Geom::Transformation.translation([0, 40.m, 0]))
    model.commit_operation
    check('A et B partagent la définition', @a.definition == @b.definition, @a.definition.name)
    check('B a son propre PID', @a.persistent_id != @b.persistent_id)
    same = @a.get_attribute(DICTIONARY, 'building_uuid') == @b.get_attribute(DICTIONARY, 'building_uuid')
    check('La copie reproduit l’UUID', same)
    check('La lecture de B ne réécrit rien', begin
      before = state(@b)
      select_only(@b)
      service.load_selection(model: model).ok? && state(@b) == before
    end)
    @b0 = state(@b)
    @old_definition = @a.definition
    @old_definition_faces = faces_in(@old_definition.entities)
    flush('after_copy')
  end

  def regenerate_a
    select_only(@a)
    loaded = service.load_selection(model: model)
    check('Sélection de A lue', loaded.ok?, loaded.errors.map(&:to_h).inspect)
    tokens = Archgen::UI::TargetTokens.new
    token = tokens.issue(loaded.value.target, model: model)
    resolved = tokens.resolve(token, model: Sketchup.active_model)
    check('Jeton résolu pour ce modèle', resolved.ok?, resolved.errors.map(&:to_h).inspect)
    @target_before = loaded.value.target
    result = service.regenerate(model: model, target: resolved.value, draft: EDIT)
    check('Régénération de A', result.ok?, result.errors.map(&:to_h).inspect)
    return flush('regenerate_a') unless result.ok?

    @a1 = state(@a)
    @summary = result.value
    check('A : PID conservé', @a1[:pid] == @a0[:pid])
    check('A : placement conservé', @a1[:transform] == @a0[:transform])
    check('A : tag conservé', @a1[:tag] == USER_TAG, @a1[:tag])
    check('A : nom conservé', @a1[:name] == 'A, nom utilisateur')
    check('A : attribut tiers conservé', @a1[:third_party] == 'valeur')
    check('A : toujours sélectionné seul', model.selection.size == 1 && model.selection.first == @a)
    check('A : nouvelle définition', @a.definition != @old_definition, @a.definition.name)
    check('A : largeur 16 m', (@a.definition.bounds.width * 0.0254 - 16.0).abs < 0.001)
    check('A : révision 2', @a1[:attrs]['revision'] == 2)
    check('A : nouvel UUID car partagé', @a1[:attrs]['building_uuid'] != @a0[:attrs]['building_uuid'])
    check('A : config mise à jour', JSON.parse(@a1[:attrs]['config_json'])['footprint']['width_m'] == 16.0)
    check('B : strictement inchangé', state(@b) == @b0, diff(state(@b), @b0))
    check('B : garde l’ancienne définition', @b.definition == @old_definition)
    check('Ancienne définition intacte', faces_in(@old_definition.entities) == @old_definition_faces)
    flush('regenerate_a')
  end

  def after_undo
    now = state(@a)
    check('Annuler : A revenu à l’identique', now == @a0, diff(now, @a0))
    check('Annuler : ancienne définition sur A', @a.definition == @old_definition)
    check('Annuler : B inchangé', state(@b) == @b0, diff(state(@b), @b0))
    select_only(@a)
    stale = service.regenerate(model: model, target: @summary.target, draft: EDIT)
    check('Annuler : cible de révision 2 refusée', !stale.ok? && stale.errors.first.code == 'E_TARGET_STALE', stale.errors.map { |d| d.params['reason'] }.join(','))
    check('Annuler : refus sans écriture', state(@a) == @a0)
    flush('after_undo')
  end

  def after_redo
    now = state(@a)
    check('Rétablir : A identique à la régénération', now == @a1, diff(now, @a1))
    check('Rétablir : B inchangé', state(@b) == @b0, diff(state(@b), @b0))
    flush('after_redo')
  end

  # Changement de style sur la seule copie, puis lecture croisée.
  def regenerate_b
    select_only(@b)
    loaded = service.load_selection(model: model)
    check('Sélection de B lue', loaded.ok?, loaded.errors.map(&:to_h).inspect)
    a_before = state(@a)
    result = service.regenerate(model: model, target: loaded.value.target,
                                draft: { 'schema_version' => 1, 'profile' => { 'id' => 'brutalist', 'revision' => 1 } })
    check('Régénération de B en brutaliste', result.ok?, result.errors.map(&:to_h).inspect)
    data = JSON.parse(@b.get_attribute(DICTIONARY, 'config_json'))
    check('B : profil brutaliste, révision 2', data['profile']['id'] == 'brutalist' && @b.get_attribute(DICTIONARY, 'revision') == 2)
    check('B : dimensions conservées', data['footprint']['width_m'] == 12.0)
    check('B : UUID conservé, désormais unique', @b.get_attribute(DICTIONARY, 'building_uuid') == @b0[:attrs]['building_uuid'])
    check('A : inchangé par B', state(@a) == a_before, diff(state(@a), a_before))
    uuids = model.entities.grep(Sketchup::ComponentInstance).filter_map { |i| i.get_attribute(DICTIONARY, 'building_uuid') }
    check('UUID distincts', uuids.uniq.size == uuids.size, uuids.size)
    flush('regenerate_b')
  end

  # Altérations annulées ensuite ; chaque refus doit laisser le modèle intact.
  def refusals
    select_only(@a)
    target = service.load_selection(model: model).value.target
    {
      'mise à l’échelle' => Geom::Transformation.scaling(2),
      'miroir' => Geom::Transformation.scaling(-1, 1, 1)
    }.each do |label, change|
      model.start_operation('Altération H05', true)
      @a.transform!(change)
      model.commit_operation
      before = state(@a)
      count = model.definitions.count
      result = service.load_selection(model: model)
      fresh = result.ok? ? result.value.target : target
      refused = service.regenerate(model: model, target: fresh, draft: EDIT)
      check("Refus : #{label}", !refused.ok? && refused.errors.first.params['reason'] == 'non_rigid_transform', refused.errors.map { |d| d.params['reason'] }.join(','))
      check("Sans écriture : #{label}", state(@a) == before && model.definitions.count == count)
      model.start_operation('Restauration H05', true)
      @a.transform!(change.inverse)
      model.commit_operation
    end
    @a.locked = true
    locked = service.regenerate(model: model, target: service.load_selection(model: model).value.target, draft: EDIT)
    check('Refus : cible verrouillée', !locked.ok? && locked.errors.first.params['reason'] == 'target_locked')
    @a.locked = false
    model.selection.clear
    empty = service.regenerate(model: model, target: target, draft: EDIT)
    check('Refus : sélection vide', !empty.ok? && empty.errors.first.params['reason'] == 'selection_changed')
    flush('refusals')
  end
end
