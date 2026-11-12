# frozen_string_literal: true

module Archgen
  module UI
    # Recettes (AG-148, ADR-71) : réglages d'un panneau enregistrés sous un nom, sur ce poste.
    # Une recette est une donnée, jamais du code : le panneau la recharge comme une saisie, et
    # l'aperçu la juge comme toute saisie (un style retiré depuis est refusé avec son diagnostic).
    # Le magasin est injecté : les préférences de SketchUp en vrai, une table en test.
    class Recipes
      KINDS = %w[building street road].freeze
      SCHEMA_VERSION = 1
      MAX_COUNT = 40
      MAX_NAME = 60
      MAX_BYTES = 65_536

      # Un fichier JSON par genre, dans %APPDATA%\ARCHGEN\recettes (le dossier personnel hors
      # Windows). Les préférences de SketchUp ne conviennent pas : read_default évalue la valeur comme
      # du Ruby, et SketchUp 2026 n'a gardé aucune valeur d'une session à l'autre (AG-148, vu dans l'hôte).
      class FileStore
        def initialize(directory = nil)
          @directory = directory
        end

        def directory
          @directory || File.join(ENV['APPDATA'] || Dir.home, 'ARCHGEN', 'recettes')
        end

        def read(key)
          path = File.join(directory, "#{key}.json")
          File.file?(path) ? File.binread(path).force_encoding(Encoding::UTF_8) : nil
        rescue SystemCallError, IOError
          nil
        end

        def write(key, value)
          Adapters::SketchUp::LocalFiles.write(File.join(directory, "#{key}.json"), value.to_s)
        end
      end

      # Magasin en mémoire, pour les tests et hors SketchUp.
      class MemoryStore
        attr_reader :values

        def initialize(values = {})
          @values = values
        end

        def read(key)
          @values[key]
        end

        def write(key, value)
          @values[key] = value
        end
      end

      def initialize(kind, store: FileStore.new)
        raise ArgumentError, "Genre de recette inconnu : #{kind}" unless KINDS.include?(kind)

        @kind = kind
        @store = store
      end

      def key
        "recipes_#{@kind}"
      end

      # [{ 'name' => …, 'data' => … }] triées par nom. Une valeur illisible donne une liste vide.
      def list
        read.fetch(:recipes)
      end

      def find(name)
        list.find { |recipe| recipe['name'] == name }
      end

      # Même nom : la recette est remplacée.
      def save(name, data)
        clean = clean_name(name)
        return refuse('/name', 'recipe_name', max: MAX_NAME) unless clean
        return refuse('/data', 'recipe_data') unless data.is_a?(Hash) && !data.empty?
        return refuse('/data', 'recipe_too_large', max: MAX_BYTES / 1024) if JSON.generate(data).bytesize > MAX_BYTES

        state = read
        recipes = state[:recipes].reject { |recipe| recipe['name'] == clean }
        return refuse('/name', 'recipe_full', max: MAX_COUNT) if recipes.size >= MAX_COUNT

        store(state, recipes << { 'name' => clean, 'data' => data })
      end

      def delete(name)
        state = read
        return refuse('/name', 'recipe_unknown') unless name.is_a?(String) && state[:recipes].any? { |recipe| recipe['name'] == name }

        store(state, state[:recipes].reject { |recipe| recipe['name'] == name })
      end

      private

      def clean_name(name)
        return nil unless name.is_a?(String)

        clean = name.strip.gsub(/\s+/, ' ')
        clean.empty? || clean.length > MAX_NAME || clean.match?(/[[:cntrl:]]/) ? nil : clean
      end

      def read
        raw = @store.read(key)
        return { recipes: [], unreadable: nil } if raw.nil? || raw.empty?

        parsed = Core::StrictJson.parse(raw)
        recipes = parsed.ok? ? valid_recipes(parsed.value) : nil
        return { recipes: [], unreadable: raw } unless recipes

        { recipes: recipes.sort_by { |recipe| [recipe['name'].downcase, recipe['name']] }, unreadable: nil }
      end

      def valid_recipes(value)
        return nil unless value.is_a?(Hash) && value['schema_version'] == SCHEMA_VERSION && value['recipes'].is_a?(Array)

        value['recipes'].select { |r| r.is_a?(Hash) && r['name'].is_a?(String) && r['data'].is_a?(Hash) }.map { |r| r.slice('name', 'data') }
      end

      def serialize(recipes)
        JSON.generate('schema_version' => SCHEMA_VERSION, 'recipes' => recipes)
      end

      def store(state, recipes)
        keep_unreadable(state)
        @store.write(key, serialize(recipes))
        Core::Result.ok(list)
      rescue SystemCallError, IOError
        refuse('/name', 'recipe_write')
      end

      # Une valeur illisible n'est jamais écrasée sans copie : elle passe sous une clé voisine.
      def keep_unreadable(state)
        @store.write("#{key}_illisible", state[:unreadable]) if state[:unreadable]
      end

      def refuse(path, reason, **params)
        Core::Result.fail([Core::Diagnostic.error('E_SCHEMA', path, reason: reason, **params)])
      end
    end

    # Actions de pont communes aux panneaux du bâtiment, de la rue et de la voirie. Le contrôleur
    # fournit @recipes (nil hors SketchUp : aucune recette, enregistrement refusé).
    module RecipeActions
      ACTIONS = %w[save_recipe delete_recipe].freeze
      PAYLOAD_KEYS = { 'save_recipe' => %w[name data], 'delete_recipe' => %w[name] }.freeze

      def recipe_list
        @recipes ? @recipes.list : []
      end

      def recipe_action(action, payload)
        return Core::Result.fail([Core::Diagnostic.error('E_SCHEMA', '/name', reason: 'recipe_unavailable')]) unless @recipes

        result = action == 'save_recipe' ? @recipes.save(payload['name'], payload['data']) : @recipes.delete(payload['name'])
        result.ok? ? Core::Result.ok({ 'recipes' => result.value }) : result
      end
    end
  end
end
