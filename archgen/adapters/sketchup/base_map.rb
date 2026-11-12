# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      # Fond de plan à l'échelle (ADR-59) : tuiles d'images posées à plat sous le point géolocalisé, sur
      # deux calques que l'on allume l'un ou l'autre. « carte » : OpenStreetMap, emprises des bâtiments ;
      # « photo » : orthophotographie de l'IGN (France). Hôtes fermés, HTTPS, confirmation à chaque fois.
      module BaseMap
        module_function

        LAYERS = {
          'map' => { 'label' => 'ARCHGEN Fond carte', 'zoom' => 18, 'ext' => 'png',
                     'url' => 'https://tile.openstreetmap.org/%<z>d/%<x>d/%<y>d.png',
                     'attribution' => '© les contributeurs d’OpenStreetMap, ODbL' },
          'photo' => { 'label' => 'ARCHGEN Fond photo', 'zoom' => 19, 'ext' => 'jpg',
                       'url' => 'https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=ORTHOIMAGERY.ORTHOPHOTOS' \
                                '&STYLE=normal&TILEMATRIXSET=PM&TILEMATRIX=%<z>d&TILEROW=%<y>d&TILECOL=%<x>d&FORMAT=image/jpeg',
                       'attribution' => 'Orthophotographie IGN, Licence Ouverte 2.0' }
        }.freeze
        HOSTS = %w[tile.openstreetmap.org data.geopf.fr].freeze
        MAX_TILES = 100
        MIN_SIDE_M = 50.0
        MAX_SIDE_M = 1500.0
        DICTIONARY = 'archgen.basemap'
        # La photo sous la carte : allumées ensemble, la carte reste lisible et rien ne scintille.
        LIFT_M = { 'map' => 0.002, 'photo' => 0.0 }.freeze

        # Tuiles à télécharger et à poser pour chaque calque : url, nom de fichier, placement en mètres.
        def plan(lat, lon, size_m, layers: LAYERS.keys)
          projection = Core::MapProjection.new(lat, lon)
          layers.to_h do |kind|
            spec = LAYERS.fetch(kind)
            z = Core::MapTiles.zoom_for(lat, lon, size_m, wanted: spec['zoom'], max_tiles: MAX_TILES)
            tiles = Core::MapTiles.tiles(lat, lon, size_m, z).map do |t|
              t.merge('url' => format(spec['url'], z: t['z'], x: t['x'], y: t['y']),
                      'file' => "#{kind}_#{t['z']}_#{t['x']}_#{t['y']}.#{spec['ext']}")
               .merge(Core::MapTiles.placement(t, projection))
            end
            [kind, { 'zoom' => z, 'tiles' => tiles, 'label' => spec['label'], 'attribution' => spec['attribution'] }]
          end
        end

        def size_problem(size_m)
          return nil if size_m.is_a?(Numeric) && size_m.between?(MIN_SIDE_M, MAX_SIDE_M)

          Core::Diagnostic.error('E_MAP', '/basemap/size_m', reason: 'map_download', reason_detail: 'size', min: MIN_SIDE_M, limit: MAX_SIDE_M)
        end

        def headers
          { 'User-Agent' => "ARCHGEN/#{Archgen::VERSION} (extension SketchUp)" }
        end

        # Écrit les calques en une opération. files : { nom => chemin local } des tuiles reçues ;
        # une tuile manquante est simplement absente. frame : rotation du nord du modèle, ou nil.
        # host doit savoir poser une image (add_image) et créer un calque (layers.add).
        def write(model, plan, files, frame: nil, host: NativeHost)
          model.start_operation('ARCHGEN : fond de plan', true)
          begin
            written = plan.to_h do |kind, layer|
              group = model.entities.add_group
              group.name = layer['label']
              tag = model.layers[layer['label']] || model.layers.add(layer['label'])
              group.layer = tag
              count = 0
              layer['tiles'].each do |t|
                path = files[t['file']]
                next unless path

                x, y = t['origin_m']
                point = host.point(x / GeometryWriter::METERS_PER_INCH, y / GeometryWriter::METERS_PER_INCH, LIFT_M.fetch(kind) / GeometryWriter::METERS_PER_INCH)
                image = group.entities.add_image(path, point, t['width_m'] / GeometryWriter::METERS_PER_INCH, t['height_m'] / GeometryWriter::METERS_PER_INCH)
                count += 1 if image
              end
              group.transformation = host.transformation(frame) if frame
              group.set_attribute(DICTIONARY, 'kind', kind)
              group.set_attribute(DICTIONARY, 'attribution', layer['attribution'])
              group.set_attribute(DICTIONARY, 'zoom', layer['zoom'])
              [kind, count]
            end
            model.commit_operation
            Core::Result.ok(written)
          rescue StandardError => e
            model.abort_operation
            Core::Result.fail([Core::Diagnostic.error('E_WRITE', '/model', reason: 'write_failed', error: e.class.name)])
          end
        end
      end
    end
  end
end
