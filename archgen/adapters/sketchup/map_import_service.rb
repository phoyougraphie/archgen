# frozen_string_literal: true

require 'digest'

module Archgen
  module Adapters
    module SketchUp
      MapPreview = Struct.new(:origin, :networks, :buildings, :terrain, :skipped, :attribution, :source, :counts, keyword_init: true)

      # Import d'une carte (docs/CARTOGRAPHIE_CONTRACT.md §5, AG-129). L'aperçu calcule tout sans écrire ;
      # l'import écrit en une seule opération : réseaux et bâtiments comme racines ARCHGEN ordinaires,
      # modifiables au clic droit, un composant de terrain et un marqueur « ARCHGEN Carte ».
      class MapImportService
        DICTIONARY = 'archgen.map'
        MARKER_NAME = 'ARCHGEN Carte'
        TERRAIN_NAME = 'ARCHGEN Terrain'
        OSM_ATTRIBUTION = '© les contributeurs d’OpenStreetMap, ODbL'
        IGN_ATTRIBUTION = 'IGN, Licence Ouverte 2.0'
        LAYERS = %w[roads buildings terrain].freeze

        def self.default
          new(buildings: BuildingService.default, networks: NetworkService.default)
        end

        def initialize(buildings:, networks:, host: NativeHost)
          @buildings = buildings
          @networks = networks
          @host = host
          @guard = TransactionGuard.new
        end

        # source : { 'kind' => 'download'|'file', 'host', 'bbox', 'date', 'file' } ; aucune écriture.
        def preview(map_bytes:, format:, origin:, style:, layers: LAYERS, terrain_bytes: nil, ign: false, source: {})
          map = Core::MapReader.call(map_bytes, format: format, origin: origin)
          return map unless map.ok?

          skipped = Hash.new(0)
          map.value['skipped'].each { |k, v| skipped["map/#{k}"] += v }
          networks = layers.include?('roads') ? network_previews(map.value, skipped) : []
          return networks if networks.is_a?(Core::Result)

          buildings = layers.include?('buildings') ? building_previews(map.value, style, skipped) : []
          return buildings if buildings.is_a?(Core::Result)

          terrain = nil
          if terrain_bytes && layers.include?('terrain')
            terrain = Core::MapTerrain.call(terrain_bytes, origin: map.value['origin'], extent: extent(map.value))
            return terrain unless terrain.ok?

            terrain = terrain.value
          end
          return empty if networks.empty? && buildings.empty? && terrain.nil?

          attribution = [OSM_ATTRIBUTION]
          attribution << IGN_ATTRIBUTION if terrain && ign
          counts = { 'networks' => networks.size, 'roads' => networks.sum { |n| n[:computed].settings['roads'].size },
                     'buildings' => buildings.size, 'terrain_faces' => terrain ? terrain['metrics']['face_count'] : 0 }
          Core::Result.ok(MapPreview.new(origin: map.value['origin'], networks: networks, buildings: buildings, terrain: terrain,
                                         skipped: skipped.sort.to_h, attribution: attribution, counts: counts,
                                         source: source.merge('sha256' => Digest::SHA256.hexdigest(map_bytes))))
        end

        # Une seule opération : un refus ou une panne laisse le document intact.
        def import(model:, preview:)
          return Core::Result.fail([Core::Diagnostic.error('E_TARGET_STALE', '/model', reason: 'nested_edit_context')]) if model.active_path

          @guard.run(model, 'ARCHGEN : importer une carte') do
            preview.networks.each { |n| @networks.write_imported(model, n[:computed], n[:origin]) }
            preview.buildings.each { |b| @buildings.write_imported(model, b[:config], b[:plan], @host.transformation(inches(b[:matrix]))) }
            write_terrain(model, preview.terrain) if preview.terrain
            write_marker(model, preview)
            preview.counts
          end
        end

        private

        def empty
          Core::Result.fail([Core::Diagnostic.error('E_MAP', '/map', reason: 'map_empty')])
        end

        def network_previews(map, skipped)
          roads = Core::MapRoads.call(map, presets: Composition.road_presets, road_intake: Composition.road_intake,
                                           bands: Composition.road_bands, items: Composition.road_items)
          return roads unless roads.ok?

          roads.value['skipped'].each { |k, v| skipped["roads/#{k}"] += v }
          roads.value['networks'].filter_map do |network|
            computed = @networks.preview(tree: network['tree'])
            next { computed: computed.value, origin: network['origin_m'] } if computed.ok?

            skipped['roads/network_refused'] += network['tree']['roads'].size
            nil
          end
        end

        def building_previews(map, style, skipped)
          lines = map['ways'].map { |w| w['points_m'] }
          converted = Core::MapBuildings.call(map, style: style, roads: lines)
          return converted unless converted.ok?

          converted.value['skipped'].each { |k, v| skipped["buildings/#{k}"] += v }
          converted.value['buildings'].filter_map do |b|
            prepared = @buildings.prepare_import(b['draft'])
            unless prepared.ok?
              skipped['buildings/refused'] += 1
              next
            end
            config, plan = prepared.value
            { id: b['id'], config: config, plan: plan, matrix: matrix(b['origin_m'], b['x_axis']) }
          end
        end

        # Repère du bâtiment : X le long de la façade avant, Y vers l'intérieur, en mètres.
        def matrix(origin, x_axis)
          cx, cy = x_axis
          [cx, cy, 0.0, 0.0, -cy, cx, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, origin[0].to_f, origin[1].to_f, 0.0, 1.0]
        end

        def inches(m)
          m.each_with_index.map { |v, i| [12, 13, 14].include?(i) ? v / GeometryWriter::METERS_PER_INCH : v }
        end

        def extent(map)
          points = map['ways'].flat_map { |w| w['points_m'] } + map['buildings'].flat_map { |b| b['ring_m'] }
          return nil if points.empty?

          [[points.map(&:first).min, points.map(&:last).min], [points.map(&:first).max, points.map(&:last).max]]
        end

        def write_terrain(model, terrain)
          resources = Resources.new(model, catalog: Composition.site_materials, revision: 1, host: @host)
          definition = model.definitions.add(TERRAIN_NAME)
          raise WriteError, 'Création de la définition refusée' unless definition

          site_plan = { 'units' => 'm', 'nodes' => terrain['nodes'], 'metrics' => { 'site_face_count' => terrain['metrics']['face_count'] } }
          GeometryWriter.new(host: @host).write_site(site_plan, entities: definition.entities, resources: resources)
          soften(definition.entities)
          instance = model.entities.add_instance(definition, @host.identity)
          raise WriteError, 'Insertion du terrain refusée' unless instance

          instance.name = TERRAIN_NAME
          tag = resources.tag('site')
          instance.layer = tag if tag
          instance.set_attribute(DICTIONARY, 'kind', 'terrain')
        end

        # Le relief se lit doux : arêtes intérieures adoucies, comme un terrain de SketchUp.
        def soften(entities)
          entities.each do |entity|
            next unless @host.edge?(entity) && entity.respond_to?(:soft=)

            entity.soft = true
            entity.smooth = true if entity.respond_to?(:smooth=)
          end
        end

        def write_marker(model, preview)
          definition = model.definitions.add(MARKER_NAME)
          raise WriteError, 'Création de la définition refusée' unless definition

          definition.entities.add_cpoint(@host.point(0, 0, 0)) if definition.entities.respond_to?(:add_cpoint)
          instance = model.entities.add_instance(definition, @host.identity)
          raise WriteError, 'Insertion du marqueur refusée' unless instance

          instance.name = MARKER_NAME
          values = { 'map_version' => 1, 'origin_lat' => preview.origin[0], 'origin_lon' => preview.origin[1],
                     'attribution' => preview.attribution.join(' ; '), 'counts_json' => Core::Canonical.dump(preview.counts),
                     'source_json' => Core::Canonical.dump(preview.source) }
          values['z_origin_m'] = preview.terrain['metrics']['z_origin_m'] if preview.terrain
          values.each { |key, value| instance.set_attribute(DICTIONARY, key, value) }
        end
      end
    end
  end
end
