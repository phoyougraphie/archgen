# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      RoadRecord = Struct.new(:instance, :persistent_id, :metadata, keyword_init: true)

      # Référence Ruby d'une voie : tout ce qui doit encore concorder avant d'écrire.
      RoadTarget = Struct.new(:document_key, :persistent_id, :definition_id, :revision, :road_digest, keyword_init: true)

      # Lit et écrit les attributs d'une racine de voie (docs/VOIRIE_CONTRACT.md, Écriture et
      # persistance). Ne démarre jamais d'opération et ne répare rien.
      class RoadRepository
        DICTIONARY = 'archgen.road'
        VERSION = 1
        KEYS = %w[road_version revision road_json road_digest road_engine_version material_revision].freeze
        SHA256 = /\A\h{64}\z/

        def initialize(host: NativeHost)
          @host = host
        end

        def write(instance, metadata)
          KEYS.each { |key| instance.set_attribute(DICTIONARY, key, metadata.fetch(key)) }
        end

        def read_metadata(instance)
          KEYS.to_h { |key| [key, instance.get_attribute(DICTIONARY, key)] }
        end

        def read(model, persistent_id:)
          entity = model.find_entity_by_persistent_id(persistent_id)
          return stale('target_not_found') unless entity

          read_instance(model, entity)
        end

        def read_instance(model, entity)
          return stale('not_a_road_root') unless @host.component_instance?(entity)
          return stale('deleted_target') unless entity.valid?
          return stale('not_at_model_root') unless entity.parent == model

          metadata = read_metadata(entity)
          return stale('not_a_road_root') if metadata['road_version'].nil?

          problem = metadata_problem(metadata)
          return Core::Result.fail([problem]) if problem

          Core::Result.ok(RoadRecord.new(instance: entity, persistent_id: entity.persistent_id, metadata: metadata))
        end

        private

        def stale(reason)
          Core::Result.fail([Core::Diagnostic.error('E_TARGET_STALE', '/target', reason: reason)])
        end

        def metadata_problem(metadata)
          unless metadata['road_version'] == VERSION
            return Core::Diagnostic.error('E_VERSION', '/metadata/road_version', reason: 'unsupported_road', value: metadata['road_version'], supported: VERSION)
          end

          field = invalid_field(metadata)
          field && Core::Diagnostic.error('E_SCHEMA', "/metadata/#{field}", reason: 'invalid_metadata')
        end

        def invalid_field(metadata)
          return 'revision' unless metadata['revision'].is_a?(Integer) && metadata['revision'] >= 1
          return 'road_json' unless metadata['road_json'].is_a?(String)
          return 'road_digest' unless metadata['road_digest'].is_a?(String) && SHA256.match?(metadata['road_digest'])
          return 'road_engine_version' unless metadata['road_engine_version'].is_a?(String)
          return 'material_revision' unless metadata['material_revision'].is_a?(Integer)

          nil
        end
      end
    end
  end
end
