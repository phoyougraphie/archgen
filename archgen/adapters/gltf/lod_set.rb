# frozen_string_literal: true

module Archgen
  module Adapters
    module Gltf
      # Trois fichiers par objet (D-31) et une collision convexe par bâtiment (D-32), docs/DECOR_JEU_CONTRACT.md §3.
      # Un objet est une liste d'éléments : un bâtiment seul, ou les maisons d'une rue avec leurs assises.
      module LodSet
        module_function

        # Erreur d'un fichier, remontée telle quelle.
        class Failed < StandardError
          attr_reader :diagnostics

          def initialize(diagnostics)
            @diagnostics = diagnostics
            super('export')
          end
        end

        # Result du plan au réglage ARCHGEN `lod: 0`, sans rien changer d'autre ; valeur nil s'il y est déjà.
        def lod1_plan(config, materials)
          data = config.to_h
          return Core::Result.ok(nil) if data['lod'].to_i.zero?

          Core::GeometryEngine.generate(Core::BuildingConfig.new(Core::Merge.leaves(data, 'lod' => 0)), materials: materials)
        end

        def building(name:, plan:, lod1:, materials:, site: nil)
          item = { 'name' => name, 'plan' => plan, 'site' => site }
          call(name: name, items: [item], lod1_items: lod1 && [item.merge('plan' => lod1)], materials: materials)
        end

        # `items` : [{ 'name', 'plan', 'matrix' (nil = origine), 'share' (clé de plan répété), 'site' (plan d'assise ou nil),
        # 'site_share' (clé d'assise répétée) }].
        # Rend Result.ok([{ 'suffix', 'bytes', 'stats' }, ...], avertissements).
        def call(name:, items:, lod1_items:, materials:)
          volumes = {}
          items.each do |item|
            key = item['share'] || item['name']
            volumes[key] ||= Volumes.call(item['plan']) || raise(GlbWriter::ExportError.new('export_volume', item['name']))
          end
          files = [file('LOD0', scene(items, materials, volumes: volumes, collision: name))]
          files << file('LOD1', scene(lod1_items, materials)) if lod1_items
          files << file('LOD2', simple(items, volumes, materials))
          Core::Result.ok(files, warnings(files, lod1_items.nil?))
        rescue GlbWriter::ExportError => e
          GlbWriter.failure(e)
        rescue Failed => e
          Core::Result.fail(e.diagnostics)
        end

        def scene(items, materials, volumes: nil, collision: nil)
          glb = GlbWriter.new(materials: materials)
          items.each do |item|
            plan = item['plan']
            glb.add(name: item['name'], nodes: plan['nodes'], definitions: plan['definitions'] || {}, matrix: item['matrix'], share: item['share'])
            site = item['site']
            if site
              glb.add(name: "#{item['name']}/assise", nodes: site['nodes'], definitions: site['definitions'] || {}, matrix: item['matrix'],
                      share: item['site_share'] && "assise/#{item['site_share']}")
            end
          end
          items.each_with_index do |item, index|
            next unless volumes

            glb.add_triangles(name: format('UCX_%<name>s_%<index>02d', name: collision, index: index),
                              triangles: volumes.fetch(item['share'] || item['name'])['triangles'], matrix: item['matrix'],
                              share: "ucx/#{item['share'] || item['name']}")
          end
          glb.to_glb
        end

        def simple(items, volumes, materials)
          glb = GlbWriter.new(materials: materials)
          items.each do |item|
            key = item['share'] || item['name']
            volume = volumes.fetch(key)
            top = volume['wall_top'].to_f + 1e-3
            glb.add_triangles(name: item['name'], triangles: volume['triangles'], matrix: item['matrix'], share: "lod2/#{key}",
                              material: ->(tri) { tri.sum { |p| p[2] } / 3.0 > top ? volume['roof'] : volume['wall'] })
          end
          glb.to_glb
        end

        def file(suffix, result)
          raise Failed, result.diagnostics unless result.ok?

          { 'suffix' => suffix, 'bytes' => result.value['bytes'], 'stats' => result.value['stats'] }
        end

        def warnings(files, lod1_skipped)
          counts = files.map { |f| f['stats'].drawn_triangle_count }
          list = []
          list << Core::Diagnostic.warning('W_EXPORT_LOD', '/export', reason: 'lod1_skipped') if lod1_skipped
          unless counts.each_cons(2).all? { |a, b| b < a }
            list << Core::Diagnostic.warning('W_EXPORT_LOD', '/export', reason: 'lod_not_decreasing', value: counts.join(' > '))
          end
          list
        end
      end
    end
  end
end
