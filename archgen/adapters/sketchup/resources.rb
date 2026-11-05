# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      # Matériaux et tags possédés par ARCHGEN. Une ressource n'est réutilisée que si
      # elle porte le marqueur et reste conforme ; une ressource homonyme de
      # l'utilisateur n'est jamais modifiée. Ne démarre aucune opération.
      class Resources
        DICTIONARY = 'archgen.resource'
        TAG_LABELS = {
          'walls' => 'ARCHGEN Murs', 'slabs' => 'ARCHGEN Dalles',
          'roof' => 'ARCHGEN Toiture', 'details' => 'ARCHGEN Détails'
        }.freeze

        # Journal des ressources créées, pour le contrôle d'intégrité du service.
        attr_reader :created

        def initialize(model, catalog:, revision:, host: NativeHost)
          @model = model
          @catalog = catalog
          @revision = revision
          @host = host
          @materials = {}
          @tags = {}
          @created = []
        end

        def material(id)
          @materials[id] ||= find_material(id) || create_material(id)
        end

        # nil pour une catégorie sans tag : ses entités restent Untagged.
        def tag(category)
          label = TAG_LABELS[category]
          return nil unless label

          @tags[category] ||= find_tag(category) || create_tag(category, label)
        end

        private

        def entry(id)
          @catalog.fetch(id) { raise WriteError, "Matériau absent du catalogue : #{id}" }
        end

        def rgb(id)
          entry(id).fetch('srgb').delete_prefix('#').scan(/../).map { |pair| pair.to_i(16) }
        end

        def find_material(id)
          @model.materials.find { |m| conforming_material?(m, id) }
        end

        def conforming_material?(material, id)
          return false unless material.get_attribute(DICTIONARY, 'kind') == 'material'
          return false unless material.get_attribute(DICTIONARY, 'id') == id
          return false unless material.get_attribute(DICTIONARY, 'revision') == @revision

          color = material.color
          [color.red, color.green, color.blue] == rgb(id)
        end

        def create_material(id)
          base = "ARCHGEN #{entry(id).fetch('label')}"
          material = @model.materials.add(free_name(base, @model.materials))
          raise WriteError, "Création du matériau refusée : #{id}" unless material

          material.color = @host.color(*rgb(id))
          material.set_attribute(DICTIONARY, 'kind', 'material')
          material.set_attribute(DICTIONARY, 'id', id)
          material.set_attribute(DICTIONARY, 'revision', @revision)
          @created << material
          material
        end

        def find_tag(category)
          @model.layers.find do |layer|
            layer.get_attribute(DICTIONARY, 'kind') == 'tag' && layer.get_attribute(DICTIONARY, 'id') == category
          end
        end

        def create_tag(category, label)
          tag = @model.layers.add(free_name(label, @model.layers))
          raise WriteError, "Création du tag refusée : #{category}" unless tag

          tag.set_attribute(DICTIONARY, 'kind', 'tag')
          tag.set_attribute(DICTIONARY, 'id', category)
          @created << tag
          tag
        end

        # Layers#add rendrait la ressource existante : on choisit d'abord un nom libre.
        def free_name(base, collection)
          return base unless collection[base]

          suffix = 2
          suffix += 1 while collection["#{base} (#{suffix})"]
          "#{base} (#{suffix})"
        end
      end
    end
  end
end
