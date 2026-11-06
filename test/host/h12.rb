# frozen_string_literal: true

require 'json'

# Recette H12, côté SketchUp, à lancer dans la console d'un modèle de test sans intérêt :
#   load '.../test/host/h12.rb'; ArchgenH12Probe.run
# Écrit dans tmp/h12/ un OBJ par style en Shell LOD 0 et expected.json, puis le contrôle se
# fait hors de SketchUp : blender --background --factory-startup --python test/host/h12_blender.py
# Le modèle courant est vidé. L'export ne passe que par l'API native, le produit n'exporte rien.
module ArchgenH12Probe
  REPO = File.expand_path('../..', __dir__)
  OUT = File.join(REPO, 'tmp', 'h12')
  REPORT = File.join(OUT, 'sketchup.txt')
  FIXTURES = %w[rect-neutre-shell haussmann-12x9 toulousain brutalist].freeze
  # U06 : aires des murs du plan neutre.
  WALL_AREAS = { 'rect-neutre-shell' => { 'front' => 119.0, 'rear' => 119.04 } }.freeze
  OPTIONS = { show_summary: false, triangulated_faces: true, doublesided_faces: false, edges: false,
              texture_maps: false, swap_yz: false, units: 'm', selectionset_only: false }.freeze
  LENGTH_UNIT_INCHES = 0
  LENGTH_UNIT_MILLIMETERS = 2
  LENGTH_UNIT_METERS = 4
  FACADES = {
    'front' => { origin: ->(_w, _d) { [0.0, 0.0] }, tangent: [1.0, 0.0], normal: [0.0, -1.0] },
    'right' => { origin: ->(w, _d) { [w, 0.0] }, tangent: [0.0, 1.0], normal: [1.0, 0.0] },
    'rear' => { origin: ->(w, d) { [w, d] }, tangent: [-1.0, 0.0], normal: [0.0, 1.0] },
    'left' => { origin: ->(_w, d) { [0.0, d] }, tangent: [0.0, -1.0], normal: [-1.0, 0.0] }
  }.freeze

  module_function

  def model
    Sketchup.active_model
  end

  def log(line)
    @lines << line
    File.binwrite(REPORT, "#{@lines.join("\n")}\n")
  end

  def clear_model
    model.selection.clear
    model.start_operation('H12 remise à zéro', true)
    model.entities.clear!
    model.commit_operation
    model.definitions.purge_unused
    model.materials.purge_unused
  end

  def draft(name)
    data = JSON.parse(File.read(File.join(REPO, 'examples', 'buildings', "#{name}.json"), mode: 'rb', encoding: 'UTF-8'))
    data.merge('mode' => 'shell', 'lod' => 0)
  end

  def plan_for(data)
    config = Archgen::Core::ConfigResolver.resolve(data, registry: Archgen::Composition.registry.value, intake: Archgen::Composition.intake, allow_internal: true).value
    [config, Archgen::Core::GeometryEngine.generate(config, materials: Archgen::Composition.materials.fetch('materials')).value]
  end

  def primitives(nodes)
    nodes.flat_map { |node| (node['primitive'] ? [node['primitive']] : []) + primitives(node['children']) }
  end

  def bounds(prims)
    points = prims.flat_map { |p| p['vertices'] }
    { 'min' => (0..2).map { |i| points.map { |v| v[i] }.min }, 'max' => (0..2).map { |i| points.map { |v| v[i] }.max } }
  end

  def world_point(facade, width, depth, along, height)
    spec = FACADES.fetch(facade)
    origin = spec[:origin].call(width, depth)
    [origin[0] + (spec[:tangent][0] * along), origin[1] + (spec[:tangent][1] * along), height]
  end

  def segment(facade, width, depth, along, height, id)
    { 'id' => id, 'facade' => facade, 'point' => world_point(facade, width, depth, along, height), 'normal' => [*FACADES.fetch(facade)[:normal], 0.0] }
  end

  # Le centre de chaque ouverture doit laisser passer le segment ; un coin plein doit l'arrêter.
  def expected(name, config, plan, file)
    data = config.to_h
    width = plan['metrics']['width_m']
    depth = plan['metrics']['depth_m']
    catalog = Archgen::Composition.materials.fetch('materials')
    {
      'name' => name, 'file' => file, 'width_m' => width, 'depth_m' => depth, 'roof_top_z_m' => plan['metrics']['roof_top_z_m'],
      'wall_m' => data['structure']['wall_m'], 'overhang_m' => data['roof']['overhang_m'], 'bounds' => bounds(primitives(plan['nodes'])),
      'materials' => data['materials'].values_at('wall', 'roof').uniq.map { |id| { 'id' => id, 'label' => catalog.dig(id, 'label'), 'srgb' => catalog.dig(id, 'srgb') } },
      'openings' => plan['openings'].map do |o|
        segment(o['facade_id'], width, depth, (o['u_min_m'] + o['u_max_m']) / 2.0, (o['z_min_m'] + o['z_max_m']) / 2.0, o['id'])
      end,
      'witnesses' => FACADES.keys.map { |id| segment(id, width, depth, 0.1, 0.1, "plein/#{id}") },
      'wall_areas' => WALL_AREAS.fetch(name, {})
    }
  end

  def vertex_bounds(path)
    mins = [Float::INFINITY] * 3
    maxs = [-Float::INFINITY] * 3
    File.foreach(path, encoding: 'UTF-8') do |line|
      next unless line.start_with?('v ')

      line.split[1, 3].map(&:to_f).each_with_index do |value, i|
        mins[i] = value if value < mins[i]
        maxs[i] = value if value > maxs[i]
      end
    end
    (0..2).map { |i| (maxs[i] - mins[i]).round(4) }
  end

  def export_fixture(name)
    data = draft(name)
    config, plan = plan_for(data)
    clear_model
    result = Archgen::Adapters::SketchUp::BuildingService.default(allow_internal: true).create(model: model, draft: data)
    raise result.errors.map(&:to_h).inspect unless result.ok?
    raise 'plan différent de celui écrit' unless result.value.plan_digest == Archgen::Core::GeometryEngine.plan_digest(plan)

    file = "#{name}.obj"
    path = File.join(OUT, file)
    ok = model.export(path, OPTIONS)
    log("#{ok && File.exist?(path) ? 'OK   ' : 'ECHEC'} #{name} : export #{ok}, #{File.exist?(path) ? File.size(path) : 0} octets, étendue #{vertex_bounds(path).inspect}")
    expected(name, config, plan, file)
  end

  # Ce que devient l'unité : même modèle, document affiché en pouces.
  def units_variants
    options = model.options['UnitsOptions']
    before = options['LengthUnit']
    { 'pouces' => LENGTH_UNIT_INCHES, 'millimetres' => LENGTH_UNIT_MILLIMETERS, 'metres' => LENGTH_UNIT_METERS }.each do |label, unit|
      options['LengthUnit'] = unit
      { 'model' => 'model', 'm' => 'm' }.each do |key, value|
        path = File.join(OUT, "unites-#{label}-#{key}.obj")
        ok = model.export(path, OPTIONS.merge(units: value))
        log("MESURE document en #{label}, units=#{value} : export #{ok}, étendue #{File.exist?(path) ? vertex_bounds(path).inspect : 'absent'}")
      end
    end
  ensure
    options['LengthUnit'] = before
  end

  def run
    @lines = []
    Dir.mkdir(File.dirname(OUT)) unless File.directory?(File.dirname(OUT))
    Dir.mkdir(OUT) unless File.directory?(OUT)
    log("H12 SketchUp #{Sketchup.version} #{Sketchup.is_pro? ? 'Pro' : 'non Pro'} Ruby #{RUBY_VERSION} #{Sketchup.platform} moteur #{Archgen::ENGINE_VERSION}")
    log("Unité du document : #{model.options['UnitsOptions']['LengthUnit']}")
    # La ligne d'expected.json n'est écrite qu'à la fin : Blender attend un jeu complet.
    entries = FIXTURES.map { |name| export_fixture(name) }
    File.binwrite(File.join(OUT, 'expected.json'), JSON.pretty_generate('fixtures' => entries))
    units_variants
    log('FIN')
  rescue StandardError => e
    log("ECHEC #{e.class} #{e.message} #{e.backtrace.first(3).join(' | ')}")
    log('FIN')
  end
end
