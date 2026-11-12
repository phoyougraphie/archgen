# frozen_string_literal: true

require 'digest'
require 'json'

# Recette H13, partie écriture (AG-025), à lancer une fois sur un modèle neuf :
#   load '.../test/host/survey.rb'; load '.../test/host/site_write.rb'; ArchgenSiteWriteProbe.run
# Service réel, vrai Annuler et vrai Rétablir par l'API, pannes par sous-classes des ports : le
# produit n'a aucun crochet. Rapport : tmp/h13-ecriture.txt ; vues : tmp/h13-*.png ; modèle dans tmp/.
module ArchgenSiteWriteProbe
  REPO = File.expand_path('../..', __dir__)
  TMP = File.join(REPO, 'tmp')
  REPORT = File.join(TMP, 'h13-ecriture.txt')
  SKP = File.join(TMP, 'h13-ecriture.skp')
  SP = Archgen::Adapters::SketchUp
  TERRAIN = ArchgenSurveyProbe
  INCH = 0.0254
  TOLERANCE_M = 0.001
  STEP_DELAY_S = 1.2
  SITE = 'archgen.site'
  BUILDING = 'archgen.building'
  Injected = Class.new(StandardError)
  DRAFT = { 'schema_version' => 1, 'profile' => { 'id' => 'haussmann' }, 'name' => 'Assise H13', 'mode' => 'structural', 'lod' => 1,
            'footprint' => { 'width_m' => 12.0, 'depth_m' => 9.0 } }.freeze
  EMBANKMENT = { 'earthwork' => 'embankment' }.freeze

  class FaultInSite < SP::GeometryWriter
    def write_site(*, **)
      raise Injected, 'panne avant l’assise'
    end
  end

  # Laisse de vraies faces d'assise écrites avant la panne.
  class FaultAfterSite < SP::GeometryWriter
    def write_site(*, **)
      super
      raise Injected, 'panne après l’assise'
    end
  end

  class FaultOnPlacing < SP::ComponentRepository
    def place_at_altitude(instance, altitude_m)
      super
      raise Injected, 'panne après la pose'
    end
  end

  class FaultMidSite < SP::ComponentRepository
    def write_site(instance, site)
      instance.set_attribute(SITE_DICTIONARY, 'site_version', site['site_version'])
      instance.set_attribute(SITE_DICTIONARY, 'site_json', site['site_json'])
      raise Injected, 'panne au milieu de l’assise'
    end
  end

  class FaultOnSiteReadBack < SP::ComponentRepository
    def read_site(_instance)
      nil
    end
  end

  module_function

  def model
    Sketchup.active_model
  end

  def service(**ports)
    SP::BuildingService.default(allow_internal: true, **ports)
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

  def near(label, expected, actual)
    check(label, (expected - actual).abs <= TOLERANCE_M, "attendu #{expected.round(6)}, lu #{actual.round(6)}")
  end

  def root
    model.find_entity_by_persistent_id(@pid)
  end

  def terrain
    model.find_entity_by_persistent_id(@terrain_pid)
  end

  def ref
    SP::TerrainRef.new(document_key: model.guid, persistent_id: @terrain_pid)
  end

  def target
    model.selection.clear
    model.selection.add(root)
    service.load_selection(model: model).value.target
  end

  def z_m
    root.transformation.to_a[14] * INCH
  end

  def plan_faces
    root.get_attribute(BUILDING, 'plan_digest')
  end

  # Tous les sommets du terrain, en coordonnées du modèle : il ne doit jamais bouger.
  def terrain_digest
    inner = terrain.entities.grep(Sketchup::Group).first
    tr = terrain.transformation * inner.transformation
    points = inner.entities.grep(Sketchup::Face).flat_map { |face| face.vertices.map { |v| v.position.transform(tr).to_a.map { |c| c.to_f.round(6) } } }
    Digest::SHA256.hexdigest(points.flatten.join(','))
  end

  def record
    instance = root
    {
      definitions: model.definitions.map(&:name).sort, materials: model.materials.map(&:name).sort, layers: model.layers.map(&:name).sort,
      selection: model.selection.map(&:persistent_id), definition: instance.definition.persistent_id, transform: instance.transformation.to_a,
      building: SP::ComponentRepository::KEYS.map { |k| instance.get_attribute(BUILDING, k) },
      site: SP::ComponentRepository::SITE_KEYS.map { |k| instance.get_attribute(SITE, k) }
    }
  end

  def diff(a, b)
    a.keys.select { |k| a[k] != b[k] }.join(', ')
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

  def named_group(entities, name)
    entities.grep(Sketchup::Group).find { |g| g.name == name }
  end

  def view_image(name)
    view = model.active_view
    camera = view.camera
    bounds = root.bounds
    center = Geom::Point3d.new(bounds.center.x, bounds.center.y, bounds.min.z + (7.0 / INCH))
    eye = center.offset(Geom::Vector3d.new(-0.9, -1.0, 0.28), 42.0 / INCH)
    view.camera = Sketchup::Camera.new(eye, center, Z_AXIS)
    view.write_image(filename: File.join(TMP, "h13-#{name}.png"), width: 1200, height: 800, antialias: true, transparent: false)
    view.camera = camera
  end

  def prepare
    @terrain_pid = TERRAIN.build_terrain.persistent_id
    created = service.create(model: model, draft: DRAFT)
    raise created.errors.map(&:to_h).inspect unless created.ok?

    @pid = created.value.persistent_id
    place = Geom::Point3d.new(TERRAIN.m(24.0), TERRAIN.m(22.0), 0).transform(terrain.transformation)
    model.start_operation('Placement H13', true)
    root.transformation = Geom::Transformation.translation([place.x, place.y, 0]) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, 30.degrees)
    root.layer = model.layers.add('Tag utilisateur H13')
    root.name = 'Nom utilisateur H13'
    root.set_attribute('autre.extension', 'cle', 'valeur')
    model.commit_operation
    @terrain_before = terrain_digest
    log("Départ : #{Archgen::VERSION}, moteur #{Archgen::ENGINE_VERSION}, #{deep_faces(root.definition.entities)} faces dans le bâtiment")
  end

  def adapt_plinth
    t = target
    @flat = record
    @matrix = root.transformation.to_a
    @definition_before = root.definition
    @plan_before = plan_faces
    @faces_before = deep_faces(root.definition.entities)
    result = service.adapt_to_site(model: model, target: t, terrain: ref, site: {})
    return check('Adapter au terrain', false, result.errors.map(&:to_h).inspect) unless result.ok?

    check('Adapter au terrain', true)
    @metrics = result.value.site_metrics
    @adapted = record
    log("MESURE plateforme #{@metrics['platform_z_m']} m, remblai max #{@metrics['fill_max_m']} m, déblai max #{@metrics['cut_max_m']} m, #{@metrics['site_face_count']} faces d'assise, seuil #{@metrics['door_gap_m']} m")
    log("Avertissements : #{result.diagnostics.map(&:code).join(', ')}")
    instance = root
    now = instance.transformation.to_a
    check('Même PID', instance.persistent_id == @pid)
    check('X, Y et rotation conservés', (0..15).reject { |i| i == 14 }.all? { |i| (now[i] - @matrix[i]).abs < 1e-9 })
    near('Z de la racine à la plateforme', @metrics['platform_z_m'], z_m)
    check('Nom, tag et attribut tiers conservés', instance.name == 'Nom utilisateur H13' && instance.layer.name == 'Tag utilisateur H13' && instance.get_attribute('autre.extension', 'cle') == 'valeur')
    check('Révision 2, plan du bâtiment inchangé', instance.get_attribute(BUILDING, 'revision') == 2 && plan_faces == @plan_before)
    check('Ancienne définition intacte', deep_faces(@definition_before.entities) == @faces_before)
    check('Faces natives = bâtiment + assise', deep_faces(instance.definition.entities) == @faces_before + @metrics['site_face_count'],
          "#{deep_faces(instance.definition.entities)} pour #{@faces_before} + #{@metrics['site_face_count']}")
    site = named_group(instance.definition.entities, 'site')
    check('Groupe d’assise avec son tag', site && site.layer.name == 'ARCHGEN Terrassement', site&.layer&.name)
    check('Terrain intact', terrain_digest == @terrain_before)
    plinth_bottom(site)
    view_image('soubassement')
    Sketchup.undo
  end

  # Le bas de la bande avant, à l'angle (0, 0) : 5 cm sous le terrain réel.
  def plinth_bottom(site)
    strip = named_group(named_group(site.entities, 'site/plinth').entities, 'site/plinth/front')
    low = strip.entities.grep(Sketchup::Face).flat_map(&:vertices).map(&:position).select { |p| p.x.abs < 1e-6 && p.y.abs < 1e-6 }.map { |p| p.z.to_f * INCH }.min
    world = Geom::Point3d.new(0, 0, 0).transform(root.transformation)
    local = world.transform(terrain.transformation.inverse)
    expected = TERRAIN.exact_altitude(local.x.to_f * INCH, local.y.to_f * INCH) - @metrics['platform_z_m'] - 0.05
    near('Bas de bande à terrain − 5 cm', expected, low)
  end

  def after_undo
    now = record
    check('Annuler : tout revient, une seule ligne', now == @flat, diff(now, @flat))
    check('Annuler : altitude d’origine', z_m.abs < 1e-9)
    check('Annuler : plus de dictionnaire d’assise', root.attribute_dictionary(SITE).nil?)
    check('Annuler : terrain intact', terrain_digest == @terrain_before)
    Sketchup.redo
  end

  def after_redo
    now = record
    check('Rétablir : tout revient', now == @adapted, diff(now, @adapted))
    near('Rétablir : altitude', @metrics['platform_z_m'], z_m)
    check('Rétablir : faces', deep_faces(root.definition.entities) == @faces_before + @metrics['site_face_count'])
  end

  def faults
    cases = {
      'avant les faces d’assise' => { writer: FaultInSite.new },
      'après de vraies faces d’assise' => { writer: FaultAfterSite.new },
      'après la pose en altitude' => { repository: FaultOnPlacing.new },
      'au milieu des attributs d’assise' => { repository: FaultMidSite.new },
      'à la relecture de l’assise' => { repository: FaultOnSiteReadBack.new }
    }
    t = target
    cases.each do |label, ports|
      before = record
      result = service(**ports).adapt_to_site(model: model, target: t, terrain: ref, site: EMBANKMENT)
      check("Panne #{label} : refus", !result.ok? && result.errors.first.code == 'E_WRITE', result.errors.map { |d| d.params['reason'] }.join(','))
      after = record
      check("Panne #{label} : rien ne reste", before == after, diff(before, after))
      check("Panne #{label} : ni terre ni restauration incomplète", model.materials.none? { |m| m.name == 'ARCHGEN Terre' } && result.errors.first.params['reason'] == 'write_failed')
    end
    check('Pannes : terrain intact', terrain_digest == @terrain_before)
    Sketchup.undo
  end

  # Si une panne avait laissé une ligne, cet Annuler ne défairait pas l'adaptation.
  def undo_reaches_adaptation
    check('Après les pannes, un Annuler défait l’adaptation : aucune ligne ajoutée', root.attribute_dictionary(SITE).nil?)
    Sketchup.redo
  end

  def terrain_changed
    t = target
    digest = service.preview_site(model: model, target: t, terrain: ref, site: {}).value.survey.survey_digest
    lift = Geom::Transformation.translation([0, 0, TERRAIN.m(0.02)])
    model.start_operation('Terrain modifié H13', true)
    terrain.transform!(lift)
    model.commit_operation
    before = record
    result = service.adapt_to_site(model: model, target: t, terrain: ref, site: {}, survey_digest: digest)
    check('Terrain changé depuis l’aperçu : refus', result.errors.first&.params&.fetch('reason', nil) == 'terrain_changed', result.errors.map(&:to_h).inspect)
    check('Terrain changé : aucune écriture', before == record, diff(before, record))
    model.start_operation('Terrain rétabli H13', true)
    terrain.transform!(lift.inverse)
    model.commit_operation
  end

  def embankment
    before = @metrics
    result = service.adapt_to_site(model: model, target: target, terrain: ref, site: EMBANKMENT)
    return check('Adapter avec un talus', false, result.errors.map(&:to_h).inspect) unless result.ok?

    check('Adapter avec un talus', true)
    metrics = result.value.site_metrics
    log("MESURE talus : #{metrics['site_face_count']} faces, emprise #{metrics['embankment_reach_m']} m, plateforme #{metrics['platform_z_m']} m")
    near('Même plateforme que le soubassement', before['platform_z_m'], metrics['platform_z_m'])
    site = named_group(root.definition.entities, 'site')
    check('Talus présent, plus de bande', named_group(site.entities, 'site/embankment') && named_group(site.entities, 'site/plinth').nil?)
    check('Matériau Terre créé', model.materials['ARCHGEN Terre'] && model.materials['ARCHGEN Terre'].get_attribute('archgen.resource', 'id') == 'earth')
    check('Faces natives = bâtiment + talus', deep_faces(root.definition.entities) == @faces_before + metrics['site_face_count'])
    check('Terrain intact', terrain_digest == @terrain_before)
    @embankment_metrics = metrics
    view_image('talus')
  end

  def save_and_reopen
    @saved = [root.get_attribute(SITE, 'site_digest'), root.get_attribute(SITE, 'site_json'), root.transformation.to_a]
    model.save(SKP)
    Sketchup.open_file(SKP)
  end

  def after_reopen
    instance = root
    check('Rouvert : racine retrouvée par PID', !instance.nil?)
    check('Rouvert : empreinte d’assise identique', instance.get_attribute(SITE, 'site_digest') == @saved[0])
    check('Rouvert : réglages d’assise identiques', instance.get_attribute(SITE, 'site_json') == @saved[1])
    drift = instance.transformation.to_a.zip(@saved[2]).map { |a, b| (a - b).abs }.max
    log("MESURE réouverture : plus grand écart de la matrice #{drift}")
    check('Rouvert : placement identique à 10⁻⁶ pouce près', drift < 1e-6, drift)
    status = service.site_status(model: model, target: target)
    check('Rouvert : état lu', status.ok? && status.value['settings']['earthwork'] == 'embankment' && status.value['moved'] == false, status.ok? ? status.value.reject { |k, _| k == 'settings' } : status.errors.map(&:to_h))
    check('Rouvert : terrain intact', terrain_digest == @terrain_before)
    result = service.regenerate(model: model, target: target, draft: { 'schema_version' => 1, 'footprint' => { 'width_m' => 14.0 } })
    check('Rouvert : régénérer garde l’assise', result.ok? && !result.value.site_metrics.nil?, result.errors.map(&:to_h).inspect)
    site = named_group(root.definition.entities, 'site')
    check('Régénérer : talus présent pour 14 m', site && named_group(site.entities, 'site/embankment') && JSON.parse(root.get_attribute(BUILDING, 'config_json'))['footprint']['width_m'] == 14.0)
    near('Régénérer : altitude à la nouvelle plateforme', result.value.site_metrics['platform_z_m'], z_m) if result.ok?
  end

  def move_then_regenerate
    t = target
    model.start_operation('Déplacement H13', true)
    root.transform!(Geom::Transformation.translation([TERRAIN.m(4.0), TERRAIN.m(3.0), 0]))
    model.commit_operation
    moved = service.site_status(model: model, target: target)
    check('Déplacé : assise signalée périmée', moved.ok? && moved.value['moved'] == true)
    check('Déplacé : ancienne cible encore lisible', t.is_a?(SP::TargetRef))
    result = service.regenerate(model: model, target: target, draft: { 'schema_version' => 1 })
    check('Déplacé : régénérer relit le nouvel emplacement', result.ok?, result.errors.map(&:to_h).inspect)
    near('Déplacé : altitude à la nouvelle plateforme', result.value.site_metrics['platform_z_m'], z_m) if result.ok?
    check('Déplacé : assise à jour', service.site_status(model: model, target: target).value['moved'] == false)
  end

  def terrain_hidden_blocks
    t = target
    before = record
    terrain.hidden = true
    result = service.regenerate(model: model, target: t, draft: { 'schema_version' => 1 })
    check('Terrain masqué : régénérer refusé', result.errors.first&.params&.fetch('reason', nil) == 'terrain_hidden', result.errors.map(&:to_h).inspect)
    terrain.hidden = false
    check('Terrain masqué : assise conservée, aucune écriture', before == record, diff(before, record))
  end

  def copy_stays_apart
    original = root
    model.start_operation('Copie H13', true)
    copy = model.entities.add_instance(original.definition, Geom::Transformation.translation([TERRAIN.m(3.0), TERRAIN.m(-4.0), 0]) * original.transformation)
    [BUILDING, SITE].each { |dict| original.attribute_dictionary(dict).each { |k, v| copy.set_attribute(dict, k, v) } }
    model.commit_operation
    @copy_pid = copy.persistent_id
    before = record
    model.selection.clear
    model.selection.add(copy)
    result = service.regenerate(model: model, target: service.load_selection(model: model).value.target, draft: { 'schema_version' => 1 })
    check('Copie : régénérée à son emplacement', result.ok?, result.errors.map(&:to_h).inspect)
    model.selection.clear
    model.selection.add(root)
    after = record
    check('Copie : original inchangé', before.reject { |k, _| %i[selection definitions].include?(k) } == after.reject { |k, _| %i[selection definitions].include?(k) }, diff(before, after))
    check('Copie : sa définition est la sienne', model.find_entity_by_persistent_id(@copy_pid).definition != root.definition)
  end

  def remove
    @with_site = record
    altitude = z_m
    result = service.remove_site(model: model, target: target)
    check('Retirer l’assise', result.ok?, result.errors.map(&:to_h).inspect)
    check('Retirer : plus de dictionnaire ni de groupe', root.attribute_dictionary(SITE).nil? && named_group(root.definition.entities, 'site').nil?)
    near('Retirer : altitude inchangée', altitude, z_m)
    check('Retirer : terrain intact', terrain_digest == @terrain_before)
    @removed = record
    Sketchup.undo
  end

  def remove_undone
    now = record
    check('Annuler le retrait : assise revenue', now == @with_site, diff(now, @with_site))
    Sketchup.redo
  end

  def remove_redone
    now = record
    check('Rétablir le retrait', now == @removed, diff(now, @removed))
  end

  def steps
    [
      -> { prepare }, -> { adapt_plinth }, -> { after_undo }, -> { after_redo }, -> { faults }, -> { undo_reaches_adaptation },
      -> { terrain_changed }, -> { embankment }, -> { save_and_reopen }, -> { after_reopen }, -> { move_then_regenerate },
      -> { terrain_hidden_blocks }, -> { copy_stays_apart }, -> { remove }, -> { remove_undone }, -> { remove_redone }
    ]
  end

  def advance
    step = @queue.shift
    return finish unless step

    begin
      step.call
    rescue StandardError => e
      @failures += 1
      log("ECHEC exception #{e.class} #{e.message} #{e.backtrace.first(3).join(' | ')}")
    end
    UI.start_timer(STEP_DELAY_S, false) { advance }
  end

  def finish
    model.save(SKP)
    log("FIN #{@failures} echec(s), SketchUp #{Sketchup.version}, Ruby #{RUBY_VERSION}")
  end

  def run
    @lines = []
    @failures = 0
    @queue = steps
    advance
    'recette lancee'
  end
end
