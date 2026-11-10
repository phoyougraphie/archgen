# frozen_string_literal: true

module Archgen
  module Adapters
    module Gltf
      # Trois fichiers par bâtiment (D-31) et sa collision convexe (D-32), docs/DECOR_JEU_CONTRACT.md §3.
      module LodSet
        module_function

        # Result du plan au réglage ARCHGEN `lod: 0`, sans rien changer d'autre ; valeur nil s'il y est déjà.
        def lod1_plan(config, materials)
          data = config.to_h
          return Core::Result.ok(nil) if data['lod'].to_i.zero?

          Core::GeometryEngine.generate(Core::BuildingConfig.new(Core::Merge.leaves(data, 'lod' => 0)), materials: materials)
        end

        # Rend Result.ok([{ 'suffix', 'bytes', 'stats' }, ...], avertissements) ; `lod1` peut manquer (nil).
        def building(name:, plan:, lod1:, materials:)
          volume = Volumes.call(plan) || raise(GlbWriter::ExportError.new('export_volume', name))
          files = [lod0(name, plan, volume, materials)]
          files << file('LOD1', GlbWriter.building(lod1, name: name, materials: materials)) if lod1
          files << file('LOD2', simple(name, volume, materials))
          Core::Result.ok(files, warnings(files, lod1.nil?))
        rescue GlbWriter::ExportError => e
          GlbWriter.failure(e)
        rescue Failed => e
          Core::Result.fail(e.diagnostics)
        end

        # Erreur d'un fichier, remontée telle quelle.
        class Failed < StandardError
          attr_reader :diagnostics

          def initialize(diagnostics)
            @diagnostics = diagnostics
            super('export')
          end
        end

        def lod0(name, plan, volume, materials)
          scene = GlbWriter.new(materials: materials)
          scene.add(name: name, nodes: plan['nodes'], definitions: plan['definitions'] || {})
          scene.add_triangles(name: "UCX_#{name}_00", triangles: volume['triangles'])
          file('LOD0', scene.to_glb)
        end

        def simple(name, volume, materials)
          top = volume['wall_top'].to_f + 1e-3
          scene = GlbWriter.new(materials: materials)
          scene.add_triangles(name: name, triangles: volume['triangles'],
                              material: ->(tri) { tri.sum { |p| p[2] } / 3.0 > top ? volume['roof'] : volume['wall'] })
          scene.to_glb
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
