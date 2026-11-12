# frozen_string_literal: true

# Sonde native des recettes H03 et H04, à charger dans la console d'un modèle de test :
#   load 'C:/chemin/du/depot/test/host/creation.rb'
#   ArchgenCreationProbe.h03_setup ; ArchgenCreationProbe.h03_create
#   (Édition > Annuler)   ArchgenCreationProbe.h03_after_undo
#   (Édition > Rétablir)  ArchgenCreationProbe.h03_after_redo
#   ArchgenCreationProbe.h04_save
#   (rouvrir SketchUp)    ArchgenCreationProbe.h04_open ; ArchgenCreationProbe.h04_check
# Annuler et Rétablir passent par le menu : c'est le geste réel de l'utilisateur.
module ArchgenCreationProbe
  REPO = File.expand_path('../..', __dir__)
  TMP = File.join(REPO, 'tmp')
  SKP = File.join(TMP, 'h04.skp')
  EXPECT = File.join(TMP, 'h04-attendu.json')
  HOMONYM_MATERIAL = 'ARCHGEN Béton brut'
  HOMONYM_TAG = 'ARCHGEN Murs'
  HOMONYM_DEFINITION = 'ARCHGEN bâtiment'
  USER_MATERIAL = 'Utilisateur H03'
  DRAFT = { 'schema_version' => 1, 'profile' => { 'id' => 'generic' }, 'name' => 'Bâtiment H03 é', 'mode' => 'structural' }.freeze

  @lines = []

  module_function

  def service
    Archgen::Adapters::SketchUp::BuildingService.default(allow_internal: true)
  end

  def check(label, ok, detail = nil)
    @lines << "#{ok ? 'OK  ' : 'ECHEC'} #{label}#{detail.nil? ? '' : " : #{detail}"}"
    ok
  end

  def flush(name)
    Dir.mkdir(TMP) unless File.directory?(TMP)
    File.binwrite(File.join(TMP, "#{name}.txt"), "#{@lines.join("\n")}\n")
    failures = @lines.count { |l| l.start_with?('ECHEC') }
    @lines = []
    puts "#{name} : #{failures.zero? ? 'REUSSI' : "#{failures} ECHEC(S)"}"
    failures
  end

  def snapshot(model)
    {
      entities: model.entities.length,
      definitions: model.definitions.map(&:name).sort,
      materials: model.materials.map { |m| [m.name, m.color.red, m.color.green, m.color.blue] }.sort,
      layers: model.layers.map(&:name).sort
    }
  end

  def faces_in(entities)
    entities.grep(Sketchup::Face).size +
      entities.grep(Sketchup::Group).sum { |g| faces_in(g.entities) }
  end

  def user_resources_intact(model)
    material = model.materials[HOMONYM_MATERIAL]
    check('Matériau homonyme intact', material && material.color.red == 255 && material.get_attribute('archgen.resource', 'kind').nil?)
    own = model.materials[USER_MATERIAL]
    check('Matériau utilisateur intact', own && own.color.green == 200 && own.get_attribute('archgen.resource', 'kind').nil?)
    tag = model.layers[HOMONYM_TAG]
    check('Tag homonyme intact', tag && tag.get_attribute('archgen.resource', 'kind').nil?)
    definition = model.definitions[HOMONYM_DEFINITION]
    check('Définition homonyme intacte', definition && definition.get_attribute('archgen.definition', 'kind').nil? && definition.entities.grep(Sketchup::Face).size == 1)
    check('Géométrie utilisateur présente', model.entities.grep(Sketchup::Face).size == 1)
    check('Instance utilisateur présente', model.entities.grep(Sketchup::ComponentInstance).any? { |i| i.definition.name == HOMONYM_DEFINITION })
  end

  # Ressources préexistantes de l'utilisateur, dans leur propre opération.
  def h03_setup
    model = Sketchup.active_model
    model.start_operation('Préparation utilisateur H03', true)
    material = model.materials.add(HOMONYM_MATERIAL)
    material.color = Sketchup::Color.new(255, 0, 0)
    own = model.materials.add(USER_MATERIAL)
    own.color = Sketchup::Color.new(10, 200, 30)
    model.layers.add(HOMONYM_TAG)
    face = model.entities.add_face([-10.m, -10.m, 0], [-8.m, -10.m, 0], [-8.m, -8.m, 0], [-10.m, -8.m, 0])
    face.material = own
    definition = model.definitions.add(HOMONYM_DEFINITION)
    definition.entities.add_face([0, 0, 0], [1.m, 0, 0], [1.m, 1.m, 0])
    model.entities.add_instance(definition, Geom::Transformation.new([-20.m, -20.m, 0]))
    model.commit_operation
    @baseline = snapshot(model)
    puts 'setup ok'
  end

  def h03_create
    model = Sketchup.active_model
    result = service.create(model: model, draft: DRAFT)
    check('Création réussie', result.ok?, result.errors.map(&:to_h).inspect)
    @summary = result.value
    @created_snapshot = snapshot(model)
    instance = model.find_entity_by_persistent_id(@summary.persistent_id)
    @metadata = Archgen::Adapters::SketchUp::ComponentRepository.new.read_metadata(instance)
    check('Une entité racine ajoutée', model.entities.length == @baseline[:entities] + 1)
    check('Racine au niveau modèle', instance.parent == model)
    check('Nom de l’instance', instance.name == DRAFT['name'], instance.name)
    check('Identité par défaut', instance.transformation.identity?)
    check('Faces natives', faces_in(instance.definition.entities) == 709, faces_in(instance.definition.entities))
    check('Définition distincte de l’homonyme', instance.definition.name != HOMONYM_DEFINITION, instance.definition.name)
    check('Marqueur de définition', instance.definition.get_attribute('archgen.definition', 'kind') == 'building')
    @lines << "Métadonnées : uuid #{@metadata['building_uuid']}, révision #{@metadata['revision']}, digest #{@metadata['plan_digest'][0, 16]}, moteur #{@metadata['engine_version']}, matériaux #{@metadata['material_revision']}"
    @lines << "Ressources créées : #{(@created_snapshot[:materials].map(&:first) - @baseline[:materials].map(&:first)).join(', ')} ; #{(@created_snapshot[:layers] - @baseline[:layers]).join(', ')}"
    user_resources_intact(model)
    flush('h03-creation')
  end

  # Après un seul Édition > Annuler.
  def h03_after_undo
    model = Sketchup.active_model
    now = snapshot(model)
    check('Entités revenues à l’identique', now[:entities] == @baseline[:entities], now[:entities])
    check('Définitions revenues à l’identique', now[:definitions] == @baseline[:definitions], (now[:definitions] - @baseline[:definitions]).inspect)
    check('Matériaux revenus à l’identique', now[:materials] == @baseline[:materials], (now[:materials] - @baseline[:materials]).inspect)
    check('Tags revenus à l’identique', now[:layers] == @baseline[:layers], (now[:layers] - @baseline[:layers]).inspect)
    check('Racine introuvable', model.find_entity_by_persistent_id(@summary.persistent_id).nil?)
    user_resources_intact(model)
    flush('h03-annuler')
  end

  # Après un seul Édition > Rétablir.
  def h03_after_redo
    model = Sketchup.active_model
    now = snapshot(model)
    check('État de création rétabli', now == @created_snapshot, now == @created_snapshot ? nil : (now.to_a - @created_snapshot.to_a).inspect)
    loaded = service.load_building(model: model, persistent_id: @summary.persistent_id)
    check('Racine relue', loaded.ok?, loaded.errors.map(&:to_h).inspect)
    if loaded.ok?
      check('Mêmes métadonnées', loaded.value.record.metadata == @metadata)
      check('Faces natives', faces_in(loaded.value.record.instance.definition.entities) == 709)
    end
    user_resources_intact(model)
    flush('h03-retablir')
  end

  def h04_save
    model = Sketchup.active_model
    saved = model.save(SKP)
    check('Enregistrement', saved, SKP)
    File.binwrite(EXPECT, JSON.generate('persistent_id' => @summary.persistent_id, 'metadata' => @metadata))
    flush('h04-sauvegarde')
  end

  def h04_open
    Sketchup.open_file(SKP)
  end

  def h04_check
    model = Sketchup.active_model
    expected = JSON.parse(File.binread(EXPECT).force_encoding('UTF-8'))
    @lines << "H04 #{Sketchup.version} Ruby #{RUBY_VERSION}, fichier #{File.basename(model.path)}"
    probe = service
    loaded = probe.load_building(model: model, persistent_id: expected['persistent_id'])
    check('Racine retrouvée par PID', loaded.ok?, loaded.errors.map(&:to_h).inspect)
    return flush('h04-reouverture') unless loaded.ok?

    record = loaded.value.record
    check('Métadonnées identiques', record.metadata == expected['metadata'])
    check('JSON canonique identique', Archgen::Core::Canonical.dump(loaded.value.config.to_h) == expected['metadata']['config_json'])
    check('Nom accentué conservé', loaded.value.config.to_h['name'] == DRAFT['name'], loaded.value.config.to_h['name'])
    regenerated = Archgen::Core::GeometryEngine.generate(loaded.value.config, materials: Archgen::Composition.materials['materials'])
    check('Même plan recalculé', Archgen::Core::GeometryEngine.plan_digest(regenerated.value) == record.metadata['plan_digest'])
    check('Faces natives', faces_in(record.instance.definition.entities) == 709)
    check('Marqueur de définition', record.instance.definition.get_attribute('archgen.definition', 'kind') == 'building')
    user_resources_intact(model)
    h04_refusals(model, probe, record.instance, expected)
    flush('h04-reouverture')
  end

  # Altérations de test, chacune annulée ensuite : la lecture doit refuser sans rien écrire.
  def h04_refusals(model, probe, instance, expected)
    dictionary = 'archgen.building'
    config = JSON.parse(expected['metadata']['config_json'])
    {
      'config_json en version future' => ['config_json', JSON.generate(config.merge('schema_version' => 99)), 'E_VERSION'],
      'metadata_version future' => ['metadata_version', 2, 'E_VERSION'],
      'révision de profil absente' => ['config_json', JSON.generate(config.merge('profile' => { 'id' => 'generic', 'revision' => 9 })), 'E_PROFILE_UNAVAILABLE']
    }.each do |label, (key, value, code)|
      original = instance.get_attribute(dictionary, key)
      model.start_operation('Altération de test', true)
      instance.set_attribute(dictionary, key, value)
      model.commit_operation
      before = [snapshot(model), instance.get_attribute(dictionary, key)]
      result = probe.load_building(model: model, persistent_id: expected['persistent_id'])
      check("Refus : #{label}", !result.ok? && result.errors.first.code == code, result.errors.map(&:code).join(','))
      check("Aucune mutation : #{label}", before == [snapshot(model), instance.get_attribute(dictionary, key)])
      model.start_operation('Restauration de test', true)
      instance.set_attribute(dictionary, key, original)
      model.commit_operation
    end
  end
end
