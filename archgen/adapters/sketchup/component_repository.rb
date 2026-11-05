# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      BuildingRecord = Struct.new(:instance, :persistent_id, :metadata, keyword_init: true)

      # Identifie, lit et écrit les racines. Ne démarre jamais d'opération. Un marqueur
      # d'attribut ne garantit rien : chaque lecture contrôle appartenance et types.
      class ComponentRepository
        DICTIONARY = 'archgen.building'
        METADATA_VERSION = 1
        KEYS = %w[metadata_version building_uuid revision config_json plan_digest engine_version material_revision].freeze
        UUID_V4 = /\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/
        SHA256 = /\A\h{64}\z/

        def initialize(host: NativeHost)
          @host = host
        end

        # À l'identité : la position est ensuite celle que l'utilisateur donne au composant.
        def insert(model, definition:, transform: @host.identity)
          instance = model.entities.add_instance(definition, transform)
          raise WriteError, 'Insertion de la racine refusée' unless instance

          instance
        end

        def write_metadata(instance, metadata)
          KEYS.each { |key| instance.set_attribute(DICTIONARY, key, metadata.fetch(key)) }
        end

        def read_metadata(instance)
          KEYS.to_h { |key| [key, instance.get_attribute(DICTIONARY, key)] }
        end

        # Lecture seule : Result<BuildingRecord>, aucun attribut n'est réparé ni complété.
        def read(model, persistent_id:)
          entity = model.find_entity_by_persistent_id(persistent_id)
          return stale('target_not_found') unless entity

          read_instance(model, entity)
        end

        def read_instance(model, entity)
          return stale('not_a_component_instance') unless @host.component_instance?(entity)
          return stale('deleted_target') unless entity.valid?
          return stale('not_at_model_root') unless entity.parent == model

          metadata = read_metadata(entity)
          return stale('not_an_archgen_root') if metadata['metadata_version'].nil?

          problem = metadata_problem(metadata)
          return Core::Result.fail([problem]) if problem

          Core::Result.ok(BuildingRecord.new(instance: entity, persistent_id: entity.persistent_id, metadata: metadata))
        end

        private

        def stale(reason)
          Core::Result.fail([Core::Diagnostic.error('E_TARGET_STALE', '/target', reason: reason)])
        end

        def metadata_problem(metadata)
          unless metadata['metadata_version'] == METADATA_VERSION
            return Core::Diagnostic.error('E_VERSION', '/metadata/metadata_version', reason: 'unsupported',
                                          value: metadata['metadata_version'], supported: METADATA_VERSION)
          end

          field = invalid_field(metadata)
          field && Core::Diagnostic.error('E_SCHEMA', "/metadata/#{field}", reason: 'invalid_metadata')
        end

        def invalid_field(metadata)
          return 'building_uuid' unless metadata['building_uuid'].is_a?(String) && UUID_V4.match?(metadata['building_uuid'])
          return 'revision' unless metadata['revision'].is_a?(Integer) && metadata['revision'] >= 1
          return 'config_json' unless metadata['config_json'].is_a?(String)
          return 'plan_digest' unless metadata['plan_digest'].is_a?(String) && SHA256.match?(metadata['plan_digest'])
          return 'engine_version' unless metadata['engine_version'].is_a?(String)
          return 'material_revision' unless metadata['material_revision'].is_a?(Integer)

          nil
        end
      end
    end
  end
end
