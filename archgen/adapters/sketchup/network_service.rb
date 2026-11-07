# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      # Écrit et relit une racine de réseau de voies (AG-048) : toutes les voies et leurs carrefours
      # dans une seule définition, une validation = une opération. Mêmes gardes que RoadService : cible
      # relue avant chaque écriture, refus sans trace, copie qui garde sa définition.
      class NetworkService < RoadService
        DEFINITION_NAME = 'ARCHGEN réseau'
        ROOT_NAME = 'Réseau ARCHGEN'

        def self.default(writer: nil)
          new(intake: Composition.road_network_intake, bands: Composition.road_bands, items: Composition.road_items,
              materials: Composition.road_catalog, material_revision: Composition.road_materials.fetch('schema_version'), writer: writer)
        end

        def initialize(host: NativeHost, repository: nil, **rest)
          super(host: host, repository: repository || NetworkRepository.new(host: host), **rest)
        end

        # Aucune écriture, aucune trace dans l'Undo. settings : la forme d'entrée du réseau, relisible.
        def preview(tree:)
          settings = @intake.settings(tree)
          return settings unless settings.ok?

          plan = Core::RoadNetworkEngine.call(settings.value, bands: @bands, items: @items, limits: @limits)
          return plan unless plan.ok?

          input = Core::RoadNetworkIntake.input(settings.value)
          Core::Result.ok(RoadPreview.new(settings: input, plan: plan.value, road_digest: Core::RoadEngine.digest(plan.value)),
                          settings.diagnostics + plan.diagnostics)
        end

        private

        def labels
          { create: 'ARCHGEN : créer un réseau de voies', regenerate: 'ARCHGEN : régénérer le réseau de voies', kind: 'network',
            writing: 'du réseau', definition: DEFINITION_NAME, root: ROOT_NAME }
        end

        # Un changement remplace des clés entières : `roads`, `junctions`.
        def merged(settings, changes)
          settings.merge(changes)
        end

        def metadata_for(computed, revision)
          {
            'network_version' => NetworkRepository::VERSION, 'revision' => revision,
            'network_json' => Core::Canonical.dump(computed.settings), 'road_digest' => computed.road_digest,
            'road_engine_version' => ROAD_ENGINE_VERSION, 'material_revision' => @material_revision
          }
        end

        def load_record(model, record)
          parsed = Core::StrictJson.parse(record.metadata['network_json'])
          return parsed unless parsed.ok?

          settings = @intake.settings(parsed.value)
          return settings unless settings.ok?

          Core::Result.ok(LoadedRoad.new(record: record, settings: Core::RoadNetworkIntake.input(settings.value),
                                         target: target_for(model, record.instance, record.metadata)))
        end
      end
    end
  end
end
