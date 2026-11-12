# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      # Export pour un moteur de jeu (docs/DECOR_JEU_CONTRACT.md §4, AG-118). Relit la racine
      # sélectionnée, recalcule ses plans et écrit trois `.glb` ; le modèle n'est jamais modifié,
      # aucune opération n'est ouverte. `files` écrit les octets : un double en test.
      class ExportService
        BUILDING = 'archgen.building'
        ENSEMBLE = 'archgen.ensemble'
        UNSUPPORTED = { 'archgen.road' => 'road_version', 'archgen.network' => 'network_version' }.freeze

        Written = Struct.new(:kind, :name, :files, :notes, keyword_init: true)

        # Écrit sur le disque.
        module DiskFiles
          module_function

          def exist?(path) = File.exist?(path)

          def write(path, bytes)
            LocalFiles.write(path, bytes)
          end
        end

        def self.default
          new(buildings: BuildingService.default, ensembles: EnsembleService.default, materials: Composition.site_materials)
        end

        def initialize(buildings:, ensembles:, materials:, files: DiskFiles)
          @buildings = buildings
          @ensembles = ensembles
          @materials = materials
          @files = files
        end

        # Ce que la sélection permet d'exporter : 'building', 'street' ou nil.
        def self.kind(model)
          selection = model.selection
          return nil unless selection.length == 1

          item = selection.first
          return nil unless item.respond_to?(:get_attribute)
          return 'building' if item.get_attribute(BUILDING, 'config_json')
          return 'street' if item.get_attribute(ENSEMBLE, 'ensemble_json')

          nil
        end

        # Nom proposé pour le fichier LOD0.
        def self.suggested_name(model)
          item = model.selection.first
          base = item.respond_to?(:name) ? item.name.to_s.strip : ''
          base = kind(model) == 'street' ? 'archgen_rue' : 'archgen_batiment' if base.empty?
          base.gsub(/[^\p{L}\p{N}_-]+/, '_')
        end

        # Chemins des trois fichiers à partir du chemin choisi (suffixe _LODn et extension retirés).
        def self.paths(chosen)
          base = chosen.sub(/\.glb\z/i, '').sub(/_LOD[0-2]\z/i, '')
          %w[LOD0 LOD1 LOD2].to_h { |suffix| [suffix, "#{base}_#{suffix}.glb"] }
        end

        # Fichiers qui seraient remplacés, hors celui que la boîte « Enregistrer sous » a confirmé.
        def existing(chosen)
          self.class.paths(chosen).values.reject { |path| path == chosen }.select { |path| @files.exist?(path) }
        end

        # Rend Result.ok(Written) ou les diagnostics ; avertissements LOD et notes compris.
        def export(model:, path:)
          refusal = unsupported(model)
          return refusal if refusal

          kind = self.class.kind(model)
          built = kind == 'street' ? street(model) : building(model)
          return built unless built.ok?

          name, result, notes = built.value
          return result unless result.ok?

          paths = self.class.paths(path)
          files = result.value.map do |file|
            target = paths.fetch(file['suffix'])
            @files.write(target, file['bytes'])
            { 'suffix' => file['suffix'], 'path' => target, 'triangles' => file['stats'].drawn_triangle_count }
          end
          Core::Result.ok(Written.new(kind: kind, name: name, files: files, notes: notes), built.diagnostics + result.diagnostics)
        end

        private

        def unsupported(model)
          selection = model.selection
          return refuse('export_selection') unless selection.length == 1

          item = selection.first
          return refuse('export_selection') unless item.respond_to?(:get_attribute)

          UNSUPPORTED.each do |dictionary, key|
            return refuse('export_unsupported') unless item.get_attribute(dictionary, key).nil?
          end
          return refuse('export_selection') unless self.class.kind(model)

          nil
        end

        def refuse(reason)
          Core::Result.fail([Core::Diagnostic.error('E_EXPORT', '/export', reason: reason)])
        end

        def building(model)
          source = @buildings.export_source(model: model)
          return source unless source.ok?

          value = source.value
          name = self.class.suggested_name(model)
          lod1 = Gltf::LodSet.lod1_plan(value['config'], @materials)
          lod1_plan = lod1.ok? ? lod1.value : nil
          result = Gltf::LodSet.building(name: name, plan: value['plan'], lod1: lod1_plan, materials: @materials, site: value['site_plan'])
          Core::Result.ok([name, result, []], source.diagnostics)
        end

        def street(model)
          source = @ensembles.export_source(model: model)
          return source unless source.ok?

          value = source.value
          name = self.class.suggested_name(model)
          items = street_items(value['plan'], value['site_plan'])
          lod1 = value['lod1_plan'] && street_items(value['lod1_plan'], value['site_plan'])
          result = Gltf::LodSet.call(name: name, items: items, lod1_items: lod1, materials: @materials)
          Core::Result.ok([name, result, ['street_ground_excluded']], source.diagnostics)
        end

        def street_items(plan, site_plan)
          levels = site_plan ? site_plan['parcels'].to_h { |entry| [entry['id'], entry] } : {}
          plan['parcels'].map do |parcel|
            entry = levels[parcel['id']]
            matrix = parcel['matrix'].dup
            matrix[14] = entry['level_m'] if entry
            item = { 'name' => parcel['id'], 'plan' => plan['definitions'].fetch(parcel['definition_id']), 'matrix' => matrix,
                     'share' => parcel['definition_id'] }
            if entry
              item['site'] = site_plan['definitions'].fetch(entry['site_definition_id'])
              item['site_share'] = entry['site_definition_id']
            end
            item
          end
        end
      end
    end
  end
end
