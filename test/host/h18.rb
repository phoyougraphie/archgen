# frozen_string_literal: true

require 'json'
require 'fileutils'

# Recette H18, à lancer sur un document neuf, panneaux fermés :
#   load '.../test/host/h18.rb'; ArchgenH18Probe.run
# Étagement d'un ensemble sur un vrai terrain : rue, angles, îlots, refus, pannes, panneau par son
# DOM, enregistrer et rouvrir, puis charge. Rapport : tmp/h18.txt ; vues : tmp/h18/.
module ArchgenH18Probe
  REPO = File.expand_path('../..', __dir__)
  REPORT = File.join(REPO, 'tmp', 'h18.txt')
  IMAGES = File.join(REPO, 'tmp', 'h18')
  SKP = File.join(REPO, 'tmp', 'h18.skp')
  PANEL = Archgen::UI::StreetPanel
  SP = Archgen::Adapters::SketchUp
  CORE = Archgen::Core
  INCH = 0.0254
  ENSEMBLE = 'archgen.ensemble'
  SITE = 'archgen.site'
  ASSISE = %r{/assise\z}
  METERS = 4
  DELAY_S = 0.4
  PANEL_DELAY_S = 2.5
  Injected = Class.new(StandardError)

  # Pente régulière : l'altitude réelle se compare à la formule, sans rayon.
  SLOPE = ->(x, y) { 100.0 + (0.05 * x) + (0.02 * y) }
  CASES = {
    'rue-haussmann-structural' => { profile: 'haussmann', mode: 'structural', lod: 1, points: [[0, 0], [60, 0]], at: [10.0, 10.0] },
    'coude-brutaliste' => { profile: 'brutalist', mode: 'shell', lod: 0, points: [[0, 0], [48, 0], [48, 48]], at: [10.0, 70.0] },
    'angle-rentrant-toulousain' => { profile: 'toulousain', mode: 'structural', lod: 1, points: [[0, 0], [48, 0], [48, -40]], at: [100.0, 60.0] },
    'deux-cotes-haussmann' => { profile: 'haussmann', mode: 'shell', lod: 1, points: [[0, 0], [60, 0]], at: [10.0, 160.0], layout: { 'side' => 'both', 'street_width_m' => 14.0 } },
    'ilot-interruption' => { profile: 'brutalist', mode: 'structural', lod: 1, points: [[0, 0], [40, 0], [40, 40], [0, 40]], at: [90.0, 110.0], closed: true },
    'ilot-porche' => { profile: 'haussmann', mode: 'structural', lod: 1, points: [[0, 0], [52, 0], [52, 52], [0, 52]], at: [150.0, 110.0], closed: true }
  }.freeze

  module_function

  def model
    Sketchup.active_model
  end

  def view
    model.active_view
  end

  def service
    @service ||= SP::EnsembleService.default
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

  def clock
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def diagnostics(result)
    result.errors.map(&:to_h).inspect[0, 400]
  end

  # --- Terrain : un groupe de triangles, jamais retouché.

  def build_terrain(x_max, y_max, step, name, x_min: 0.0, y_min: 0.0, &altitude)
    group = model.entities.add_group
    group.name = name
    mesh = Geom::PolygonMesh.new
    xs = (0..((x_max - x_min) / step).ceil).map { |i| x_min + (i * step) }
    ys = (0..((y_max - y_min) / step).ceil).map { |j| y_min + (j * step) }
    index = {}
    ys.each do |y|
      xs.each { |x| index[[x, y]] = mesh.add_point(Geom::Point3d.new(x / INCH, y / INCH, altitude.call(x, y) / INCH)) }
    end
    ys.each_cons(2) do |y0, y1|
      xs.each_cons(2) do |x0, x1|
        mesh.add_polygon(index[[x0, y0]], index[[x1, y0]], index[[x1, y1]])
        mesh.add_polygon(index[[x0, y0]], index[[x1, y1]], index[[x0, y1]])
      end
    end
    group.entities.add_faces_from_mesh(mesh)
    group
  end

  def terrain_print(group)
    faces = group.entities.grep(Sketchup::Face)
    [faces.size, CORE::Canonical.digest(faces.flat_map { |f| f.vertices.map { |v| v.position.to_a.map { |c| c.round(6) } } })]
  end

  # --- Lectures dans le modèle.

  def roots
    model.entities.grep(Sketchup::ComponentInstance).select { |i| i.get_attribute(ENSEMBLE, 'ensemble_version') }
  end

  def nested(root)
    root.definition.entities.grep(Sketchup::ComponentInstance)
  end

  def buildings(root)
    nested(root).reject { |i| ASSISE.match?(i.name) }
  end

  def assises(root)
    nested(root).select { |i| ASSISE.match?(i.name) }
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

  # Sommets dans le repère du modèle, pour une assise écrite.
  def world_vertices(entities, transform, out = [])
    entities.each do |entity|
      case entity
      when Sketchup::Face then entity.vertices.each { |v| out << (transform * v.position) }
      when Sketchup::Group then world_vertices(entity.entities, transform * entity.transformation, out)
      when Sketchup::ComponentInstance then world_vertices(entity.definition.entities, transform * entity.transformation, out)
      end
    end
    out
  end

  def tree_for(spec)
    tree = { 'trace' => { 'points_m' => spec[:points], 'closed' => spec[:closed] == true },
             'building' => { 'profile' => { 'id' => spec[:profile] }, 'mode' => spec[:mode], 'lod' => spec[:lod] } }
    tree['layout'] = spec[:layout] if spec[:layout]
    tree
  end

  def create_at(spec, altitude)
    x, y = spec[:at]
    result = service.create(model: model, tree: tree_for(spec), origin_m: [x, y, altitude.call(x, y)])
    raise diagnostics(result) unless result.ok?

    root = model.find_entity_by_persistent_id(result.value.persistent_id)
    model.selection.clear
    model.selection.add(root)
    [root, result.value.target]
  end

  def retain(terrain, root)
    model.selection.clear
    model.selection.add(terrain)
    reference = service.retain_terrain(model: model)
    model.selection.clear
    model.selection.add(root)
    reference.value
  end

  # Le bas de l'assise rejoint le terrain à chaque angle de parcelle, et la plateforme le domine :
  # relu dans le modèle, pas dans le plan.
  def verify_written(label, root, site_plan, altitude, tolerance: 0.02)
    root_z = root.transformation.to_a[14] * INCH
    levels = buildings(root).map { |i| i.transformation.to_a[14] * INCH }
    planned = site_plan['parcels'].map { |p| p['level_m'] }
    check("#{label} : chaque bâtiment est à son niveau", levels.size == planned.size && levels.zip(planned).all? { |a, b| (a - b).abs < 1e-5 })
    check("#{label} : chaque parcelle a une assise", assises(root).size == planned.size)
    gaps = 0
    below = 0
    parcel_transform = root.transformation
    rings = perimeter_rings(root)
    assises(root).zip(site_plan['parcels']).each do |instance, entry|
      ring = rings.fetch(entry['id'])
      to_world = parcel_transform * instance.transformation
      vertices = world_vertices(instance.definition.entities, Geom::Transformation.new).select { |p| on_ring?(ring, p.x * INCH, p.y * INCH) }.map { |p| to_world * p }
      platform = entry['platform_z_m']
      segments = nil
      below += 1 if (instance.transformation.to_a[14] * INCH) + root_z - platform > 1e-4 || (instance.transformation.to_a[14] * INCH) + root_z - platform < -1e-4
      vertices.group_by { |p| [(p.x * INCH).round(3), (p.y * INCH).round(3)] }.each do |(x, y), column|
        ground = altitude.call(x, y)
        lowest = column.map { |p| p.z * INCH }.min
        # Un bord vertical du soubassement descend sous le terrain, ou la plateforme y est déjà.
        next unless lowest > ground + tolerance && lowest > platform - tolerance

        # Un angle de plancher de passage n'a pas de sommet de soubassement dessous : on lit le bord réel.
        segments ||= world_segments(instance.definition.entities, to_world)
        gaps += 1 if edge_lowest(segments, x, y, lowest) > ground + tolerance
      end
    end
    check("#{label} : altitude des plateformes", below.zero?, "écarts #{below}")
    check("#{label} : aucun vide entre assise et terrain", gaps.zero?, "colonnes #{gaps}")
  end

  def world_segments(entities, transform, out = [])
    entities.each do |entity|
      case entity
      when Sketchup::Edge then out << [transform * entity.start.position, transform * entity.end.position]
      when Sketchup::Group then world_segments(entity.entities, transform * entity.transformation, out)
      when Sketchup::ComponentInstance then world_segments(entity.definition.entities, transform * entity.transformation, out)
      end
    end
    out
  end

  # Altitude la plus basse d'une arête passant au droit de (x, y), en mètres.
  def edge_lowest(segments, x, y, fallback)
    segments.reduce(fallback) do |lowest, (a, b)|
      ax = a.x * INCH
      ay = a.y * INCH
      dx = (b.x * INCH) - ax
      dy = (b.y * INCH) - ay
      length2 = (dx * dx) + (dy * dy)
      next lowest if length2 < 1e-9

      t = (((x - ax) * dx) + ((y - ay) * dy)) / length2
      next lowest if t < -0.001 || t > 1.001
      next lowest if Math.hypot(ax + (t * dx) - x, ay + (t * dy) - y) > 0.003

      [lowest, ((a.z + (t * (b.z - a.z))) * INCH)].min
    end
  end

  def perimeter_rings(root)
    settings = Archgen::Composition.ensemble_intake.settings(root.get_attribute(ENSEMBLE, 'ensemble_json')).value
    layout = CORE::EnsembleEngine.layout_for(settings, registry: Archgen::Composition.registry.value).value
    layout['parcels'].to_h { |parcel| [parcel['id'], parcel['local_ring_m']] }
  end

  def on_ring?(ring, x, y)
    ring.each_with_index.any? do |a, index|
      b = ring[(index + 1) % ring.size]
      length = Math.hypot(b[0] - a[0], b[1] - a[1])
      distance = (((b[0] - a[0]) * (y - a[1])) - ((b[1] - a[1]) * (x - a[0]))).abs / length
      along = (((x - a[0]) * (b[0] - a[0])) + ((y - a[1]) * (b[1] - a[1]))) / length
      distance < 0.002 && along > -0.002 && along < length + 0.002
    end
  end

  def faces_ok?(root, computed, site_plan)
    expected = computed.plan['metrics']['expanded_face_count'] + site_plan['metrics']['expanded_site_face_count']
    [deep_faces(root.definition.entities), expected]
  end

  # --- Étapes : un document par enchaînement, un temps de pause entre chaque, comme H15.

  def stage_cases
    model.options['UnitsOptions']['LengthUnit'] = METERS
    @terrain = build_terrain(320.0, 240.0, 8.0, 'Terrain H18', x_min: -80.0, y_min: -80.0, &SLOPE)
    @terrain_print = terrain_print(@terrain)
    CASES.map { |name, spec| -> { stage_case(name, spec) } } + [-> { stage_terrain_untouched }, -> { stage_rotated }]
  end

  def stage_case(name, spec)
    root, target = create_at(spec, SLOPE)
    z = root.transformation.to_a[14]
    definitions_before = buildings(root).map(&:definition).uniq.size
    digest = root.get_attribute(ENSEMBLE, 'ensemble_digest')
    before_ops = model.definitions.length
    reference = retain(@terrain, root)
    started = clock
    preview = service.preview_site(model: model, target: target, terrain: reference, site: {})
    unless preview.ok?
      trace_missing(preview, root)
      return check("#{name} : aperçu", false, diagnostics(preview))
    end

    surveyed = clock - started
    check("#{name} : aperçu sans écriture", model.definitions.length == before_ops)
    written = service.adapt_to_site(model: model, target: target, terrain: reference, site: {}, site_digest: preview.value.site_digest)
    return check("#{name} : adapter", false, diagnostics(written)) unless written.ok?

    metrics = preview.value.site_plan['metrics']
    log("     #{name} : #{metrics['parcel_count']} parcelles, #{metrics['survey_point_count']} points, relevé #{surveyed.round(2)} s, plateformes #{metrics['platform_min_z_m']} à #{metrics['platform_max_z_m']}, ressaut #{metrics['max_step_m']}, assises #{metrics['expanded_site_face_count']} faces, #{metrics['site_definition_count']} définitions, avertissements #{written.diagnostics.size}")
    check("#{name} : racine immobile", root.transformation.to_a[14] == z)
    check("#{name} : ensemble_digest inchangé", root.get_attribute(ENSEMBLE, 'ensemble_digest') == digest)
    check("#{name} : bâtiments toujours partagés", buildings(root).map(&:definition).uniq.size == definitions_before, "#{definitions_before} avant")
    verify_written(name, root, preview.value.site_plan, SLOPE)
    computed = service.preview(tree: JSON.parse(root.get_attribute(ENSEMBLE, 'ensemble_json'))).value
    counted, expected = faces_ok?(root, computed, preview.value.site_plan)
    check("#{name} : faces réelles = plan", counted == expected, "#{counted} / #{expected}")
    picture(name, root)
    @last = { name: name, root: root, target: written.value.target, definition: root.definition.persistent_id, reference: reference }
    :pause_undo
  end

  # Quand un rayon ne trouve pas le terrain : la chaîne des impacts, et le même point une seconde fois.
  def trace_missing(result, root)
    found = result.errors.find { |d| d.code == 'E_SITE_SURVEY' }
    return unless found

    settings = Archgen::Composition.ensemble_intake.settings(root.get_attribute(ENSEMBLE, 'ensemble_json')).value
    layout = CORE::EnsembleEngine.layout_for(settings, registry: Archgen::Composition.registry.value).value
    id = found.path[%r{/parcels/(.+)/site}, 1]
    parcel = layout['parcels'].find { |p| p['id'] == id }
    tangent = parcel['tangent']
    origin = parcel['origin_m']
    at = root.transformation
    found.params['points'].first(3).each do |x, y|
      local = Geom::Point3d.new((origin[0] + ((x + 0.0002) * tangent[0]) - ((y + 0.0002) * tangent[1])) / INCH, (origin[1] + ((x + 0.0002) * tangent[1]) + ((y + 0.0002) * tangent[0])) / INCH, 0)
      world = at * local
      2.times do |pass|
        ray = [Geom::Point3d.new(world.x, world.y, 130.0 / INCH), Geom::Vector3d.new(0, 0, -1)]
        chain = []
        20.times do
          hit = model.raytest(ray, true)
          unless hit
            chain << 'nil'
            break
          end
          chain << "#{(hit[0].z * INCH).round(3)}:#{hit[1].first == @terrain ? 'terrain' : hit[1].first.class.name[10, 6]}"
          break if hit[1].first == @terrain

          ray = [hit[0], ray[1]]
        end
        log("     rayon #{id} (#{x}, #{y}) passe #{pass} : #{chain.join(' ')}")
      end
    end
    faces = @terrain.entities.grep(Sketchup::Face).size
    log("     terrain : #{faces} faces, valide #{@terrain.valid?}, masqué #{@terrain.hidden?}")
  end
  def picture(name, root)
    FileUtils.mkdir_p(IMAGES)
    bounds = root.bounds
    centre = bounds.center
    reach = [bounds.width, bounds.height].max
    eye = Geom::Point3d.new(centre.x + (reach * 0.9), centre.y - (reach * 1.1), centre.z + (reach * 0.25))
    view.camera = Sketchup::Camera.new(eye, centre, Geom::Vector3d.new(0, 0, 1))
    path = File.join(IMAGES, "#{name}.png")
    view.write_image(path, 1400, 900, true)
    check("#{name} : image", File.size?(path).to_i.positive?)
  end

  def stage_terrain_untouched
    check('Terrain intact après toutes les adaptations', terrain_print(@terrain) == @terrain_print)
  end

  def stage_undo
    Sketchup.undo
  end

  def stage_after_undo
    root = @last[:root]
    check("#{@last[:name]} : Annuler enlève l'étagement en une fois", root.get_attribute(SITE, 'site_version').nil? && assises(root).empty? && buildings(root).all? { |i| i.transformation.to_a[14].zero? })
    Sketchup.redo
  end

  def stage_after_redo
    root = @last[:root]
    check("#{@last[:name]} : Rétablir le remet", root.get_attribute(SITE, 'site_version') == 1 && assises(root).size == buildings(root).size && root.definition.persistent_id == @last[:definition],
          "site #{root.get_attribute(SITE, 'site_version').inspect}, assises #{assises(root).size}/#{buildings(root).size}, définition #{root.definition.persistent_id}/#{@last[:definition]}")
  end

  def stage_rotated
    spec = { profile: 'brutalist', mode: 'shell', lod: 0, points: [[0, 0], [48, 0]], at: [10.0, 190.0] }
    root, target = create_at(spec, SLOPE)
    tr = Geom::Transformation.new(root.transformation.origin) * Geom::Transformation.rotation(ORIGIN, Z_AXIS, 30.degrees)
    root.transformation = tr
    reference = retain(@terrain, root)
    written = service.adapt_to_site(model: model, target: target, terrain: reference, site: {})
    return check('Racine pivotée : adapter', false, diagnostics(written)) unless written.ok?

    plan = service.preview_site(model: model, target: written.value.target, terrain: reference, site: {}).value.site_plan
    verify_written('Racine pivotée', root, plan, SLOPE)
    @rotated = root
  end

  # --- Refus : le document reste tel quel.

  def snapshot
    [model.definitions.length, model.entities.length, model.materials.count, model.layers.count, roots.map { |r| [r.definition, r.get_attribute(SITE, 'site_digest'), r.transformation.to_a] }]
  end

  def refused(label, result, code, reason = nil)
    found = result.ok? ? nil : result.errors.find { |d| d.code == code && (reason.nil? || d.params['reason'] == reason) }
    check("Refus #{label}", !found.nil?, found ? found.path : diagnostics(result))
  end

  def stage_refusals
    spec = { profile: 'brutalist', mode: 'shell', lod: 0, points: [[0, 0], [48, 0]], at: [10.0, 10.0] }
    @refusal_terrain = build_terrain(30.0, 30.0, 6.0, 'Trop petit', &SLOPE)
    root, target = create_at(spec, SLOPE)
    before = snapshot
    small = retain(@refusal_terrain, root)
    refused('terrain trop petit : localisé sur la parcelle', service.preview_site(model: model, target: target, terrain: small, site: {}), 'E_SITE_SURVEY')
    # AG-109 : le talus est permis sur une rangée droite ; son relevé élargi sort de ce terrain trop petit.
    refused('talus : relevé élargi hors du terrain', service.preview_site(model: model, target: target, terrain: small, site: { 'earthwork' => 'embankment' }), 'E_SITE_SURVEY')
    model.selection.clear
    model.selection.add(root)
    bad = service.retain_terrain(model: model)
    check('Refus : un ensemble ne sert pas de terrain', !bad.ok? && bad.errors.first.params['reason'] == 'terrain_is_building')
    model.selection.clear
    model.selection.add(root)
    refused('pas fin sur un terrain trop petit', service.preview_site(model: model, target: target, terrain: small, site: { 'survey' => { 'step_m' => 0.5 } }), 'E_SITE_SURVEY')
    check('Refus : document intact', snapshot == before)
    @refused_root = root
    @refused_target = target
  end

  def stage_relief
    cliff = build_terrain(90.0, 160.0, 3.0, 'Falaise', y_min: 100.0) { |x, _y| x > 30.0 ? 110.0 : 100.0 }
    spec = { profile: 'brutalist', mode: 'shell', lod: 0, points: [[0, 0], [48, 0]], at: [10.0, 110.0] }
    root, target = create_at(spec, ->(_x, _y) { 100.0 })
    reference = retain(cliff, root)
    before = snapshot
    refused('relief trop fort sur une parcelle', service.preview_site(model: model, target: target, terrain: reference, site: {}), 'E_SITE_RELIEF')
    check('Refus relief : document intact', snapshot == before)
    @cliff_root = root
  end

  def stage_terrain_changed
    land = build_terrain(90.0, 360.0, 6.0, 'Mouvant', y_min: 300.0) { |x, y| 50.0 + (0.03 * x) + (0.0 * y) }
    spec = { profile: 'brutalist', mode: 'shell', lod: 0, points: [[0, 0], [48, 0]], at: [10.0, 310.0] }
    root, target = create_at(spec, ->(x, _y) { 50.0 + (0.03 * x) })
    reference = retain(land, root)
    digest = service.preview_site(model: model, target: target, terrain: reference, site: {}).value.site_digest
    land.transform!(Geom::Transformation.translation([0, 0, 1.0 / INCH]))
    before = snapshot
    refused('terrain changé après l’aperçu', service.adapt_to_site(model: model, target: target, terrain: reference, site: {}, site_digest: digest), 'E_TARGET_STALE', 'terrain_changed')
    check('Refus terrain changé : document intact', snapshot == before)
  end

  class FailingWriter
    def initialize(inner)
      @inner = inner
    end

    def write(*args, **options)
      @inner.write(*args, **options)
    end

    def mark_definition(*args, **options)
      @inner.mark_definition(*args, **options)
    end

    def write_site(*)
      raise Injected, 'panne'
    end
  end

  def stage_fault
    root = @rotated
    pid = root.persistent_id
    model.selection.clear
    model.selection.add(root)
    faulty = SP::EnsembleService.default(writer: FailingWriter.new(SP::GeometryWriter.new))
    loaded = faulty.load_selection(model: model).value
    reference = retain(@terrain, root)
    before = snapshot
    result = faulty.adapt_to_site(model: model, target: loaded.target, terrain: reference, site: {})
    check('Panne en écrivant une assise : refus', !result.ok? && result.errors.first.params['reason'] == 'write_failed', diagnostics(result))
    check('Panne : aucun résidu', snapshot == before && model.find_entity_by_persistent_id(pid) == root)
    @fault_ok = true
  end

  # --- Panneau, par son DOM.

  SNAPSHOT = <<~JS
    (function () {
      function byId(id) { return document.getElementById(id); }
      sketchup.archgen_probe(JSON.stringify({
        status: byId('status').textContent, terrain_shown: !byId('s-terrain').hidden, summary: byId('summary-list').textContent, summary_shown: !byId('summary').hidden,
        warnings: byId('warnings').textContent, lines: byId('site-lines').textContent, lines_shown: !byId('site-lines').hidden,
        adapt: !byId('site-adapt').disabled, remove: !byId('site-remove').disabled, survey: !byId('site-survey').disabled,
        create: !byId('create').disabled, policy: byId('s-site-policy').value, step: byId('s-site-step').value, depth: byId('s-depth').value
      }));
    }());
  JS

  def js(script)
    PANEL.send_script(script)
  end

  def click_dom(id)
    js("document.getElementById(#{id.to_json}).click();")
  end

  def set_input(id, value)
    js("(function(){var e=document.getElementById(#{id.to_json});e.value=#{value.to_json};e.dispatchEvent(new Event('input',{bubbles:true}));}());")
  end

  def select_only(entity)
    model.selection.clear
    model.selection.add(entity)
  end

  def panel_steps
    root = @panel_root
    [
      ['Ouvrir en modification : section Terrain visible', lambda {
        select_only(root)
        PANEL.show('edit')
        dialog = PANEL.instance_variable_get(:@dialog)
        dialog.add_action_callback('archgen_probe') { |_c, text| receive(JSON.parse(text)) }
      }, ->(p) { p['terrain_shown'] && p['survey'] && !p['adapt'] && !p['remove'] }],
      ['Relever sans terrain retenu : expliqué', -> { click_dom('site-survey') }, ->(p) { p['summary'].include?('Retenir ce terrain') && !p['adapt'] }],
      ['Retenir le terrain', lambda {
        select_only(@terrain)
        click_dom('site-retain')
      }, ->(p) { p['status'].include?('Terrain retenu') }],
      ['Recharger l’ensemble : terrain gardé', lambda {
        select_only(root)
        click_dom('reload')
      }, ->(p) { p['status'].start_with?('Révision') }],
      ['Relever : valeurs montrées, rien d’écrit', lambda {
        @before_panel = snapshot
        click_dom('site-survey')
      }, ->(p) { p['lines'].include?('Plateformes') && p['lines'].include?('Relevé') && p['adapt'] && snapshot == @before_panel }],
      ['Changer un réglage périme l’aperçu', -> { set_input('s-site-offset', '0,5') }, ->(p) { !p['adapt'] && !p['lines_shown'] }],
      ['Relever de nouveau', -> { click_dom('site-survey') }, ->(p) { p['adapt'] && p['lines'].include?('Plateformes') }],
      ['Adapter : une seule écriture, racine immobile', lambda {
        @panel_z = root.transformation.to_a[14]
        click_dom('site-adapt')
      }, lambda { |p|
        p['status'].include?('adapté') && root.get_attribute(SITE, 'site_version') == 1 && root.transformation.to_a[14] == @panel_z &&
          assises(root).size == buildings(root).size && p['remove'] && !p['adapt']
      }],
      ['Recharger : réglages d’assise relus', -> { click_dom('reload') }, ->(p) { p['remove'] && p['status'].start_with?('Révision') }],
      ['Annuler par l’API puis recharger : assise retirée', lambda {
        Sketchup.undo
        select_only(root)
        click_dom('reload')
      }, ->(p) { root.get_attribute(SITE, 'site_version').nil? && assises(root).empty? && !p['remove'] }],
      ['Rétablir', lambda {
        Sketchup.redo
        select_only(root)
        click_dom('reload')
      }, ->(p) { root.get_attribute(SITE, 'site_version') == 1 && p['remove'] }],
      ['Remplacer garde l’assise : relevé refait', lambda {
        @panel_definition = root.definition
        set_input('s-depth', '10')
      }, ->(p) { p['create'] }],
      ['Remplacer', -> { click_dom('create') }, lambda { |p|
        p['status'].include?('remplacé') && root.definition != @panel_definition && root.get_attribute(SITE, 'site_version') == 1 && assises(root).size == buildings(root).size
      }],
      ['Retirer l’assise', -> { click_dom('site-remove') }, lambda { |p|
        p['status'].include?('retirée') && root.get_attribute(SITE, 'site_version').nil? && assises(root).empty? && buildings(root).all? { |i| i.transformation.to_a[14].zero? } && !p['remove']
      }]
    ]
  end

  def receive(panel)
    label, verifier = @current
    return unless verifier

    @current = nil
    begin
      check(label, verifier.call(panel), panel.reject { |k, _| %w[terrain_shown].include?(k) }.to_s[0, 400])
    rescue StandardError => e
      check(label, false, "#{e.class} #{e.message}")
    end
    panel_advance
  end

  def panel_advance
    step = @panel_queue.shift
    return after_panel unless step

    label, action, verifier = step
    begin
      action.call
    rescue Exception => e # rubocop:disable Lint/RescueException
      check("action #{label}", false, "#{e.class} #{e.message} #{e.backtrace.first(2).join(' | ')}")
    end
    @current = [label, verifier]
    UI.start_timer(PANEL_DELAY_S, false) { js(SNAPSHOT) }
  end

  def after_panel
    UI.start_timer(DELAY_S, false) { run_queue(reopen_stages) }
  end

  # --- Enregistrer, rouvrir, copier.

  def reopen_stages
    [
      lambda {
        PANEL.instance_variable_get(:@dialog)&.close
        root = @copy_source
        @copy_faces = deep_faces(root.definition.entities)
        @copy_pid = root.persistent_id
        @copy_digest = root.get_attribute(SITE, 'site_digest')
        @terrain_pid = @terrain.persistent_id
        @terrain_saved = terrain_print(@terrain)
        model.save(SKP)
      },
      -> { Sketchup.open_file(SKP) },
      -> { stage_reopened },
      -> { stage_copy },
      -> { stage_load_start }
    ]
  end

  def stage_reopened
    root = model.find_entity_by_persistent_id(@copy_pid)
    return check('Rouvrir : racine retrouvée', false) unless root

    check('Rouvrir : mêmes faces', deep_faces(root.definition.entities) == @copy_faces)
    check('Rouvrir : assise relue', root.get_attribute(SITE, 'site_digest') == @copy_digest && assises(root).size == buildings(root).size)
    terrain = model.find_entity_by_persistent_id(@terrain_pid)
    check('Rouvrir : terrain intact', terrain && terrain_print(terrain) == @terrain_saved)
    select_only(root)
    @service = nil
    loaded = service.load_selection(model: model).value
    status = service.site_status(model: model, target: loaded.target).value
    check('Rouvrir : assise à jour', status && status['moved'] == false)
    written = service.regenerate(model: model, target: loaded.target, changes: { 'parcel' => { 'depth_m' => 11 } })
    check('Rouvrir : remplacer reste possible et garde l’assise', written.ok? && root.get_attribute(SITE, 'site_version') == 1 && assises(root).size == buildings(root).size, written.ok? ? nil : diagnostics(written))
    @reopened_root = root
    @reopened_terrain = terrain
  end

  # Copie simulée, attributs recopiés : le vrai geste de copie d'un ensemble est prouvé en H17.
  def stage_copy
    original = @reopened_root
    definition = original.definition
    moved = Geom::Transformation.translation([40.0 / INCH, 0, 0]) * original.transformation
    copy = model.entities.add_instance(definition, moved)
    [ENSEMBLE, SITE].each { |dictionary| original.attribute_dictionary(dictionary).each_pair { |key, value| copy.set_attribute(dictionary, key, value) } }
    select_only(copy)
    loaded = service.load_selection(model: model).value
    status = service.site_status(model: model, target: loaded.target).value
    check('Copie : déclarée déplacée', status['moved'] == true)
    written = service.regenerate(model: model, target: loaded.target, changes: { 'parcel' => { 'depth_m' => 9 } })
    check('Copie : relevée à son emplacement, isolée', written.ok? && copy.definition != definition && original.definition == definition, written.ok? ? nil : diagnostics(written))
    levels = buildings(copy).map { |i| i.transformation.to_a[14] }
    check('Copie : l’original garde son étagement', buildings(original).map { |i| i.transformation.to_a[14] }.uniq.size > 1 && levels.uniq.size > 1)
  end

  # --- Charge : mesures simples, un passage, portable non isolé.

  LOADS = {
    'rue droite, 12 parcelles' => [[0, 0], [144, 0]],
    'rue droite, 50 parcelles' => [[0, 0], [600, 0]],
    'rue coudée, 200 parcelles' => [[0, 0], [1200, 0], [1200, 1200]]
  }.freeze

  def zigzag(segments)
    points = [[0.0, 0.0]]
    segments.times do |index|
      length = 30.0 + (index * 1.7)
      angle = index.even? ? 0.5 : -0.5
      last = points.last
      points << [(last[0] + (length * Math.cos(angle))).round(3), (last[1] + (length * Math.sin(angle))).round(3)]
    end
    points
  end

  def stage_load_start
    model.save(SKP)
    Sketchup.file_new
    UI.start_timer(1.0, false) do
      model.options['UnitsOptions']['LengthUnit'] = METERS
      @load_terrain = build_terrain(1400.0, 1400.0, 25.0, 'Pente de charge', x_min: -100.0, y_min: -100.0) { |x, y| 100.0 + (0.03 * x) + (0.01 * y) }
      steps = LOADS.flat_map { |label, points| %w[haussmann brutalist].map { |profile| -> { load_case(label, profile, points) } } }
      steps += %w[haussmann brutalist].map { |profile| -> { load_case('zigzag, 66 définitions', profile, zigzag(20)) } }
      run_queue(steps + [-> { finish }])
    end
  end

  def load_case(label, profile, points)
    @service = nil
    tree = { 'trace' => { 'points_m' => points, 'closed' => false }, 'building' => { 'profile' => { 'id' => profile }, 'mode' => 'structural', 'lod' => 1 } }
    created = service.create(model: model, tree: tree, origin_m: [0.0, 0.0, 100.0])
    return check("Charge #{label} #{profile} : créer", false, diagnostics(created)) unless created.ok?

    root = model.find_entity_by_persistent_id(created.value.persistent_id)
    reference = retain(@load_terrain, root)
    started = clock
    preview = service.preview_site(model: model, target: created.value.target, terrain: reference, site: {})
    return check("Charge #{label} #{profile} : relevé", false, diagnostics(preview)) unless preview.ok?

    surveyed = clock - started
    started = clock
    written = service.adapt_to_site(model: model, target: created.value.target, terrain: reference, site: {})
    return check("Charge #{label} #{profile} : adapter", false, diagnostics(written)) unless written.ok?

    adapted = clock - started
    metrics = preview.value.site_plan['metrics']
    path = File.join(REPO, 'tmp', 'h18-charge.skp')
    started = clock
    model.save(path)
    saved = clock - started
    log("     Charge #{label}, #{profile} : #{metrics['parcel_count']} parcelles, #{metrics['survey_point_count']} points, relevé #{surveyed.round(1)} s, relevé puis écriture #{adapted.round(1)} s, assises #{metrics['expanded_site_face_count']} faces en #{metrics['site_definition_count']} définitions, enregistrement #{saved.round(1)} s, #{File.size(path)} octets")
    check("Charge #{label} #{profile} : faces réelles", deep_faces(root.definition.entities) == created.value.metrics['expanded_face_count'] + metrics['expanded_site_face_count'])
    root.erase!
  end

  def finish
    log("FIN #{@failures} echec(s), ARCHGEN #{Archgen::VERSION}, SketchUp #{Sketchup.version}, Ruby #{RUBY_VERSION}")
  end

  # --- Enchaînement.

  def run_queue(steps)
    @queue = steps
    pump
  end

  def pump
    step = @queue.shift
    return unless step

    begin
      answer = step.call
      @queue.unshift(-> { stage_undo }, -> { stage_after_undo }, -> { stage_after_redo }) if answer == :pause_undo
    rescue Exception => e # rubocop:disable Lint/RescueException
      check('étape', false, "#{e.class} #{e.message} #{e.backtrace.first(3).join(' | ')}")
    end
    UI.start_timer(DELAY_S, false) { pump }
  end

  def run
    @lines = []
    @failures = 0
    @service = nil
    FileUtils.mkdir_p(IMAGES)
    log("H18 départ #{Time.now}, ARCHGEN #{Archgen::VERSION}")
    stages = stage_cases + [-> { stage_refusals }, -> { stage_relief }, -> { stage_terrain_changed }, -> { stage_fault }, -> { start_panel }]
    run_queue(stages)
    'recette lancee'
  end

  def start_panel
    spec = { profile: 'brutalist', mode: 'shell', lod: 0, points: [[0, 0], [48, 0]], at: [10.0, 40.0] }
    @panel_root, = create_at(spec, SLOPE)
    @copy_source = @rotated
    @queue = []
    @panel_queue = panel_steps
    panel_advance
  end
end
