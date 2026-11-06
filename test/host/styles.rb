# frozen_string_literal: true

# Sonde native de la recette H08, à charger dans la console d'un modèle de test :
#   load 'C:/chemin/du/depot/test/host/styles.rb'
#   ArchgenStylesProbe.run
# Crée les trois profils en LOD 0 et 1, Shell et Structural, par le service réel (sans
# profil interne). Écrit tmp/h08.txt et docs/recette/img/h08-*.png. Ne pas enregistrer.
module ArchgenStylesProbe
  REPO = File.expand_path('../..', __dir__)
  TMP = File.join(REPO, 'tmp')
  IMG = File.join(REPO, 'docs', 'recette', 'img')
  INCH = 0.0254
  PROFILES = %w[haussmann toulousain brutalist].freeze
  STEP_X_M = 30.0
  STEP_Y_M = 45.0
  KEY = 'archgen.resource'
  SHADOW = 'ShadowTime'

  @lines = []

  module_function

  def check(label, ok, detail = nil)
    @lines << "#{ok ? 'OK  ' : 'ECHEC'} #{label}#{detail.nil? ? '' : " : #{detail}"}"
    ok
  end

  def group_named(entities, name)
    entities.grep(Sketchup::Group).find { |g| g.name == name }
  end

  def faces_in(entities)
    entities.grep(Sketchup::Face).size +
      entities.grep(Sketchup::Group).sum { |g| faces_in(g.entities) } +
      entities.grep(Sketchup::ComponentInstance).sum { |i| faces_in(i.definition.entities) }
  end

  def material_id(entities)
    face = entities.grep(Sketchup::Face).first
    return face.material&.get_attribute(KEY, 'id') if face

    group = entities.grep(Sketchup::Group).first
    group && material_id(group.entities)
  end

  # images: false ne réécrit pas les vues de docs/recette/img (rejeu sur le RBZ final).
  def run(images: true)
    model = Sketchup.active_model
    service = Archgen::Adapters::SketchUp::BuildingService.default
    plans = {}
    @lines << "H08 #{Sketchup.version} Ruby #{RUBY_VERSION} #{Sketchup.platform}"
    @lines << "Profils publiés : #{Archgen::Composition.registry.value.active_profiles.map(&:id).join(', ')}"
    PROFILES.each_with_index do |id, row|
      %w[shell structural].product([0, 1]).each_with_index do |(mode, lod), column|
        draft = { 'schema_version' => 1, 'name' => "#{id} #{mode} LOD #{lod}", 'profile' => { 'id' => id }, 'mode' => mode, 'lod' => lod }
        preview = service.preview(draft: draft)
        result = service.create(model: model, draft: draft)
        label = "#{id} #{mode} LOD#{lod}"
        next check("#{label} : création", false, result.errors.map(&:to_h).inspect) unless result.ok?

        instance = model.find_entity_by_persistent_id(result.value.persistent_id)
        check("#{label} : aucun avertissement", result.warnings.empty?, result.warnings.map(&:code).join(','))
        check("#{label} : même plan que l’aperçu", preview.value.plan_digest == result.value.plan_digest)
        check("#{label} : faces natives", faces_in(instance.definition.entities) == result.value.metrics['expanded_face_count'],
              "#{faces_in(instance.definition.entities)} / #{result.value.metrics['expanded_face_count']}")
        plans[[id, mode, lod]] = { instance: instance, plan: preview.value.plan, data: preview.value.config.to_h }
        place(model, instance, column, row)
        check_openings(model, label, instance, preview.value.plan, preview.value.config.to_h)
        check_signature(label, instance, preview.value.config.to_h, lod)
      end
      check_common_dimensions(id, plans)
    end
    check_sharing(model, plans)
    check_regeneration(model, service, plans)
    export_images(model, plans) if images
    finish
  rescue StandardError => e
    check('Exception dans la sonde', false, "#{e.class}: #{e.message} #{e.backtrace.first}")
    finish
  end

  def place(model, instance, column, row)
    model.start_operation('Placement H08', true)
    instance.transformation = Geom::Transformation.translation([column * STEP_X_M / INCH, row * STEP_Y_M / INCH, 0])
    model.commit_operation
  end

  # Un rayon au centre de chaque baie : cadres et encadrements ne bouchent rien.
  def check_openings(model, label, instance, plan, data)
    origin = instance.transformation.origin
    width = data['footprint']['width_m']
    depth = data['footprint']['depth_m']
    wall = data['structure']['wall_m']
    blocked = plan['openings'].reject do |o|
      u = (o['u_min_m'] + o['u_max_m']) / 2.0
      z = (o['z_min_m'] + o['z_max_m']) / 2.0
      start, direction = case o['facade_id']
                         when 'front' then [[u, -1.0], [0, 1, 0]]
                         when 'rear' then [[width - u, depth + 1.0], [0, -1, 0]]
                         when 'right' then [[width + 1.0, u], [-1, 0, 0]]
                         else [[-1.0, depth - u], [1, 0, 0]]
                         end
      point = Geom::Point3d.new(origin.x + (start[0] / INCH), origin.y + (start[1] / INCH), z / INCH)
      hit = model.raytest([point, Geom::Vector3d.new(*direction)], true)
      hit.nil? || (point.distance(hit[0]) * INCH) > 1.0 + wall + 0.01
    end
    check("#{label} : baies traversantes", blocked.empty?, "#{plan['openings'].size} rayons, bloquées : #{blocked.map { |o| o['id'] }.first(4).join(', ')}")
  end

  def check_signature(label, instance, data, lod)
    entities = instance.definition.entities
    check("#{label} : matériau de mur", material_id(group_named(entities, 'walls').entities) == data['materials']['wall'], data['materials']['wall'])
    check("#{label} : matériau de toit", material_id(group_named(entities, 'roof').entities) == data['materials']['roof'], data['materials']['roof'])
    details = group_named(entities, 'details')
    return check("#{label} : aucun détail au LOD 0", details.nil?) if lod.zero?

    frames = details.entities.grep(Sketchup::ComponentInstance)
    check("#{label} : un cadre par baie", frames.size == instance_openings(data), frames.size)
    check("#{label} : tag Détails", details.layer.get_attribute(KEY, 'id') == 'details', details.layer.name)
    names = details.entities.grep(Sketchup::Group).map(&:name)
    features = data['features']
    check("#{label} : corniche selon le profil", names.include?('cornice') == features['cornice'])
    check("#{label} : encadrements selon le profil", names.any? { |n| n.start_with?('surround/') } == features['surrounds'])
    expected = features['balcony'] ? [2, 5].select { |i| i < data['levels']['count'] }.map { |i| "balcony/#{i}" } : []
    check("#{label} : balcons attendus", names.grep(/^balcony/) == expected, names.grep(/^balcony/).join(','))
    frame = frames.first.definition.entities.grep(Sketchup::Group).first
    check("#{label} : barre de cadre manifold", frame.manifold?)
  end

  def instance_openings(data)
    (data['levels']['count'] * data['facade']['front_bays'] * 2) + (data['levels']['count'] * data['facade']['side_bays'] * 2)
  end

  # LOD et mode ne changent ni les cotes du volume ni les baies.
  def check_common_dimensions(id, plans)
    entries = plans.select { |k, _| k[0] == id }.values
    metrics = entries.map { |e| e[:plan]['metrics'].values_at('width_m', 'depth_m', 'wall_top_z_m', 'roof_top_z_m', 'opening_count') }
    check("#{id} : cotes communes aux quatre variantes", metrics.uniq.size == 1, metrics.first.inspect)
    check("#{id} : baies communes aux quatre variantes", entries.map { |e| e[:plan]['openings'] }.uniq.size == 1)
    roofs = entries.map { |e| bounds_top(e[:instance]) }
    check("#{id} : sommet natif commun", roofs.map { |r| r.round(3) }.uniq.size == 1, roofs.first.round(5))
    expected = entries.first[:plan]['metrics']['roof_top_z_m']
    check("#{id} : sommet natif = plan", (roofs.first - expected).abs < 0.001, format('%.5f / %.5f', roofs.first, expected))
  end

  def bounds_top(instance)
    instance.definition.bounds.max.z * INCH
  end

  # Un cadre répété n'existe qu'une fois dans le modèle.
  def check_sharing(model, plans)
    details = model.definitions.select { |d| d.get_attribute(KEY, 'kind') == 'detail' }
    keys = details.map { |d| d.get_attribute(KEY, 'key') }
    check('Cadres : une définition par clé', keys.uniq.size == keys.size, keys.size)
    expected = plans.values.flat_map { |e| e[:plan]['definitions'].keys }.uniq
    check('Cadres : exactement les clés des plans', keys.sort == expected.sort, "#{keys.size} / #{expected.size}")
    used = details.sum { |d| d.instances.size }
    @lines << "Mutualisation : #{used} instances de cadres pour #{details.size} définitions"
    check('Cadres : réellement partagés', used > details.size)
  end

  # Régénérer sans changement ne crée aucune définition de cadre de plus.
  def check_regeneration(model, service, plans)
    key = ['haussmann', 'structural', 1]
    entry = plans[key]
    before = model.definitions.count { |d| d.get_attribute(KEY, 'kind') == 'detail' }
    model.selection.clear
    model.selection.add(entry[:instance])
    target = service.load_selection(model: model).value.target
    result = service.regenerate(model: model, target: target, draft: { 'schema_version' => 1 })
    check('Régénération identique : réussie', result.ok?, result.errors.map(&:to_h).inspect)
    check('Régénération identique : même plan', result.value&.plan_digest == entry[:instance].get_attribute('archgen.building', 'plan_digest'))
    after = model.definitions.count { |d| d.get_attribute(KEY, 'kind') == 'detail' }
    check('Régénération identique : cadres stables', before == after, "#{before} / #{after}")
    changed = service.regenerate(model: model, target: result.value.target,
                                 draft: { 'schema_version' => 1, 'profile' => { 'id' => 'toulousain', 'revision' => 1 } })
    check('Changement de style en LOD 1 : réussi', changed.ok?, changed.errors.map(&:to_h).inspect)
    entry[:instance].definition.entities.grep(Sketchup::Group).find { |g| g.name == 'details' }.tap do |details|
      check('Changement de style : encadrements apparus', details.entities.grep(Sketchup::Group).any? { |g| g.name.start_with?('surround/') })
    end
    model.selection.clear
    service.create(model: model, draft: { 'schema_version' => 1, 'profile' => { 'id' => 'haussmann' }, 'name' => 'Remplaçant vue', 'mode' => 'structural', 'lod' => 1 })
         .tap { |r| plans[key] = entry.merge(instance: model.find_entity_by_persistent_id(r.value.persistent_id)) }
    place(model, plans[key][:instance], 3, 0)
    entry[:instance].erase! if entry[:instance].valid?
  end

  def export_images(model, plans)
    Dir.mkdir(IMG) unless File.directory?(IMG)
    view = model.active_view
    model.rendering_options['EdgeColorMode'] = 0
    PROFILES.each do |id|
      instance = plans[[id, 'structural', 1]][:instance]
      bounds = instance.bounds
      center = bounds.center
      size = bounds.width * 1.15
      eye = Geom::Point3d.new(center.x - (size * 0.75), center.y - (size * 1.45), center.z + (bounds.depth * 0.35))
      view.camera = Sketchup::Camera.new(eye, center, Z_AXIS)
      view.write_image(File.join(IMG, "h08-#{id}.png"), 1400, 900, true)
    end
    view.camera = Sketchup::Camera.new([40.m, -90.m, 50.m], [45.m, 45.m, 0], Z_AXIS)
    view.zoom_extents
    view.write_image(File.join(IMG, 'h08-ensemble.png'), 1600, 900, true)
    check('Rendus écrits', PROFILES.all? { |id| File.exist?(File.join(IMG, "h08-#{id}.png")) })
  end

  def finish
    failures = @lines.count { |l| l.start_with?('ECHEC') }
    Dir.mkdir(TMP) unless File.directory?(TMP)
    File.binwrite(File.join(TMP, 'h08.txt'), "#{@lines.join("\n")}\n")
    puts "h08 : #{failures} echec(s) sur #{@lines.count { |l| l.start_with?('OK', 'ECHEC') }}"
  end
end
