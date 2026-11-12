# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      BuildingRecord = Struct.new(:instance, :persistent_id, :metadata, keyword_init: true)

      # Référence Ruby d'une cible : tout ce qui doit encore concorder avant d'écrire.
      TargetRef = Struct.new(:document_key, :persistent_id, :definition_id, :revision, :config_digest, keyword_init: true)

      # Identifie, lit et écrit les racines. Ne démarre jamais d'opération. Un marqueur
      # d'attribut ne garantit rien : chaque lecture contrôle appartenance et types.
      class ComponentRepository
        DICTIONARY = 'archgen.building'
        METADATA_VERSION = 1
        KEYS = %w[metadata_version building_uuid revision config_json plan_digest engine_version material_revision].freeze
        SITE_DICTIONARY = 'archgen.site'
        SITE_VERSION = 1
        SITE_KEYS = %w[site_version site_json survey_digest site_digest terrain_pid placement_json].freeze
        METERS_PER_INCH = 0.0254
        UUID_V4 = /\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/
        SHA256 = /\A\h{64}\z/
        RIGID_TOLERANCE = 1e-6

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

        # nil si la racine n'a pas d'assise.
        def read_site(instance)
          return nil if instance.get_attribute(SITE_DICTIONARY, 'site_version').nil?

          SITE_KEYS.to_h { |key| [key, instance.get_attribute(SITE_DICTIONARY, key)] }
        end

        def write_site(instance, site)
          SITE_KEYS.each { |key| instance.set_attribute(SITE_DICTIONARY, key, site.fetch(key)) }
        end

        def clear_site(instance)
          instance.delete_attribute(SITE_DICTIONARY)
        end

        # Un diagnostic si l'assise enregistrée n'est pas exploitable, sinon nil.
        def site_problem(site)
          return nil unless site
          unless site['site_version'] == SITE_VERSION
            return Core::Diagnostic.error('E_VERSION', '/metadata/site/site_version', reason: 'unsupported', value: site['site_version'], supported: SITE_VERSION)
          end

          field = invalid_site_field(site)
          field && Core::Diagnostic.error('E_SCHEMA', "/metadata/site/#{field}", reason: 'invalid_metadata')
        end

        # X, Y et orientation de la racine, en mètres : ce qui rend une assise périmée s'il change.
        def placement(instance)
          m = instance.transformation.to_a
          [m[12] * METERS_PER_INCH, m[13] * METERS_PER_INCH, m[0], m[1]].map { |value| Core::Quant.q(value) }
        end

        # Seule exception à « la transformation est conservée » : le Z vaut la plateforme.
        def place_at_altitude(instance, altitude_m)
          before = instance.transformation.to_a
          after = before.dup
          after[14] = altitude_m / METERS_PER_INCH
          instance.transformation = @host.transformation(after)
          now = instance.transformation.to_a
          same = now.each_index.reject { |i| i == 14 }.all? { |i| (now[i] - before[i]).abs <= RIGID_TOLERANCE }
          raise WriteError, 'Placement modifié pendant la pose sur la plateforme' unless same && (now[14] - after[14]).abs <= RIGID_TOLERANCE
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

        # L'adresse d'édition est l'instance physique : une copie peut porter le même UUID.
        def uuid_shared?(model, uuid, except:)
          model.entities.any? do |entity|
            @host.component_instance?(entity) && entity != except && entity.valid? &&
              entity.get_attribute(DICTIONARY, 'building_uuid') == uuid
          end
        end

        # Remplace la définition d'une seule instance ; l'ancienne n'est jamais modifiée.
        def swap(instance, definition:)
          before = instance_state(instance)
          instance.definition = definition
          raise WriteError, 'Définition non remplacée' unless instance.definition == definition
          raise WriteError, 'Identité ou placement modifié' unless instance_state(instance) == before
        end

        # Miroir, échelle et matrice singulière refusés : seule la position est conservable.
        def rigid_direct?(transformation)
          m = transformation.to_a
          x = m[0, 3]
          y = m[4, 3]
          z = m[8, 3]
          return false unless [m[3], m[7], m[11]].all? { |c| c.abs < RIGID_TOLERANCE } && (m[15] - 1.0).abs < RIGID_TOLERANCE
          return false unless [x, y, z].all? { |c| (dot(c, c) - 1.0).abs < RIGID_TOLERANCE }
          return false unless [dot(x, y), dot(y, z), dot(x, z)].all? { |c| c.abs < RIGID_TOLERANCE }

          (dot(cross(x, y), z) - 1.0).abs < RIGID_TOLERANCE
        end

        private

        def instance_state(instance)
          [instance.persistent_id, instance.transformation.to_a, instance.layer, instance.name]
        end

        def dot(a, b)
          (a[0] * b[0]) + (a[1] * b[1]) + (a[2] * b[2])
        end

        def cross(a, b)
          [(a[1] * b[2]) - (a[2] * b[1]), (a[2] * b[0]) - (a[0] * b[2]), (a[0] * b[1]) - (a[1] * b[0])]
        end

        def stale(reason)
          Core::Result.fail([Core::Diagnostic.error('E_TARGET_STALE', '/target', reason: reason)])
        end

        def invalid_site_field(site)
          %w[site_json placement_json].each { |key| return key unless site[key].is_a?(String) }
          %w[survey_digest site_digest].each { |key| return key unless site[key].is_a?(String) && SHA256.match?(site[key]) }
          return 'terrain_pid' unless site['terrain_pid'].is_a?(Integer)

          nil
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
