# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      EnsembleRecord = Struct.new(:instance, :persistent_id, :metadata, keyword_init: true)

      # Référence Ruby d'une cible : tout ce qui doit encore concorder avant d'écrire.
      EnsembleTarget = Struct.new(:document_key, :persistent_id, :definition_id, :revision, :ensemble_digest, keyword_init: true)

      # Lit et écrit les attributs d'une racine d'ensemble. Ne démarre jamais d'opération, et
      # ne répare rien : chaque lecture contrôle appartenance et types (ADR-30).
      class EnsembleRepository
        DICTIONARY = 'archgen.ensemble'
        VERSION = 1
        KEYS = %w[ensemble_version revision ensemble_json ensemble_digest engine_version material_revision].freeze
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

        # Lecture seule : Result<EnsembleRecord>.
        def read(model, persistent_id:)
          entity = model.find_entity_by_persistent_id(persistent_id)
          return stale('target_not_found') unless entity

          read_instance(model, entity)
        end

        def read_instance(model, entity)
          return stale('not_an_ensemble_root') unless @host.component_instance?(entity)
          return stale('deleted_target') unless entity.valid?
          return stale('not_at_model_root') unless entity.parent == model

          metadata = read_metadata(entity)
          return stale('not_an_ensemble_root') if metadata['ensemble_version'].nil?

          problem = metadata_problem(metadata)
          return Core::Result.fail([problem]) if problem

          Core::Result.ok(EnsembleRecord.new(instance: entity, persistent_id: entity.persistent_id, metadata: metadata))
        end

        private

        def stale(reason)
          Core::Result.fail([Core::Diagnostic.error('E_TARGET_STALE', '/target', reason: reason)])
        end

        def metadata_problem(metadata)
          unless metadata['ensemble_version'] == VERSION
            return Core::Diagnostic.error('E_VERSION', '/metadata/ensemble_version', reason: 'unsupported', value: metadata['ensemble_version'], supported: VERSION)
          end

          field = invalid_field(metadata)
          field && Core::Diagnostic.error('E_SCHEMA', "/metadata/#{field}", reason: 'invalid_metadata')
        end

        def invalid_field(metadata)
          return 'revision' unless metadata['revision'].is_a?(Integer) && metadata['revision'] >= 1
          return 'ensemble_json' unless metadata['ensemble_json'].is_a?(String)
          return 'ensemble_digest' unless metadata['ensemble_digest'].is_a?(String) && SHA256.match?(metadata['ensemble_digest'])
          return 'engine_version' unless metadata['engine_version'].is_a?(String)
          return 'material_revision' unless metadata['material_revision'].is_a?(Integer)

          nil
        end
      end
    end
  end
end
