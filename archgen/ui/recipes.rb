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

      # Préférences de SketchUp : aucun fichier écrit par ARCHGEN, une clé par genre. read_default
      # évalue la valeur stockée comme du Ruby (vu dans SketchUp 2026) : un JSON n'y relit pas et un nom
      # hostile y deviendrait du code. Le texte y est donc rangé en Base64, dont l'alphabet ne forme
      # aucun code, et toute erreur de relecture rend une valeur absente.
      class PreferenceStore
        SECTION = 'ARCHGEN'
        BASE64 = %r{\A[A-Za-z0-9+/]*={0,2}\z}

        # host : ::Sketchup par défaut ; un double en test.
        def initialize(host = nil)
          @host = host
        end

        def host
          @host || ::Sketchup
        end

        def read(key)
          value = host.read_default(SECTION, key)
          return nil unless value.is_a?(String) && value.match?(BASE64)

          text = value.unpack1('m0').force_encoding(Encoding::UTF_8)
          text.valid_encoding? ? text : nil
        rescue ScriptError, StandardError
          nil
        end

        def write(key, value)
          host.write_default(SECTION, key, [value.to_s.b].pack('m0'))
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

      def initialize(kind, store: PreferenceStore.new)
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

        keep_unreadable(state)
        @store.write(key, serialize(recipes << { 'name' => clean, 'data' => data }))
        Core::Result.ok(list)
      end

      def delete(name)
        state = read
        return refuse('/name', 'recipe_unknown') unless name.is_a?(String) && state[:recipes].any? { |recipe| recipe['name'] == name }

        keep_unreadable(state)
        @store.write(key, serialize(state[:recipes].reject { |recipe| recipe['name'] == name }))
        Core::Result.ok(list)
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
