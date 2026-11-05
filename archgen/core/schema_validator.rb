# frozen_string_literal: true

module Archgen
  module Core
    # Sous-ensemble fermé de JSON Schema 2020-12 : assez pour les trois schémas V1.
    # Un mot-clé inconnu lève une erreur, ce qui garantit la parité avec les schémas
    # au lieu de l'ignorer en silence. Les données de schéma sont injectées.
    class SchemaValidator
      SUPPORTED = %w[
        $schema title const enum type properties additionalProperties required
        minimum maximum minLength maxLength pattern items minItems maxItems
        uniqueItems anyOf
      ].freeze

      def initialize(schema)
        @schema = schema
        assert_supported(schema)
        @patterns = {}
      end

      # Retourne une liste de diagnostics E_SCHEMA triés par chemin.
      def validate(value)
        out = []
        check(@schema, value, '', out)
        out.sort_by(&:sort_key)
      end

      # Normalise les nombres selon le schéma : Integer pour `integer` et les enums
      # entiers (1.0 → 1), Float pour `number`. Appeler après `validate`.
      def normalize(value)
        walk(@schema, value)
      end

      private

      def assert_supported(schema)
        return unless schema.is_a?(Hash)

        (schema.keys - SUPPORTED).each { |k| raise ArgumentError, "Mot-clé de schéma non pris en charge : #{k}" }
        schema.fetch('properties', {}).each_value { |s| assert_supported(s) }
        assert_supported(schema['items'])
        schema.fetch('anyOf', []).each { |s| assert_supported(s) }
      end

      def fail(out, path, reason, **params)
        out << Diagnostic.error('E_SCHEMA', path, reason: reason, **params)
      end

      def check(schema, value, path, out)
        return check_any_of(schema, value, path, out) if schema.key?('anyOf')
        return fail(out, path, 'const', expected: schema['const']) if schema.key?('const') && !equal?(schema['const'], value)
        return fail(out, path, 'enum', allowed: schema['enum']) if schema.key?('enum') && schema['enum'].none? { |e| equal?(e, value) }
        return fail(out, path, 'type', expected: schema['type']) if schema.key?('type') && !type?(schema['type'], value)

        case value
        when Hash then check_object(schema, value, path, out)
        when Array then check_array(schema, value, path, out)
        when String then check_string(schema, value, path, out)
        when Numeric then check_number(schema, value, path, out)
        end
      end

      def check_any_of(schema, value, path, out)
        branches = schema['anyOf'].map do |branch|
          inner = []
          check(branch, value, path, inner)
          inner
        end
        return if branches.any?(&:empty?)

        # La branche non nulle porte les erreurs utiles quand la valeur n'est pas nulle.
        out.concat(branches.min_by { |b| b.first.path.length * -1 })
      end

      def check_object(schema, value, path, out)
        properties = schema.fetch('properties', {})
        schema.fetch('required', []).each do |key|
          fail(out, "#{path}/#{key}", 'required') unless value.key?(key)
        end
        value.each do |key, child|
          child_path = "#{path}/#{key}"
          if properties.key?(key)
            check(properties[key], child, child_path, out)
          elsif schema['additionalProperties'] == false
            fail(out, child_path, 'unknown_key')
          end
        end
      end

      def check_array(schema, value, path, out)
        fail(out, path, 'min_items', limit: schema['minItems']) if schema['minItems'] && value.size < schema['minItems']
        fail(out, path, 'max_items', limit: schema['maxItems']) if schema['maxItems'] && value.size > schema['maxItems']
        fail(out, path, 'unique_items') if schema['uniqueItems'] && value.uniq.size != value.size
        return unless schema['items']

        value.each_with_index { |child, i| check(schema['items'], child, "#{path}/#{i}", out) }
      end

      def check_string(schema, value, path, out)
        fail(out, path, 'min_length', limit: schema['minLength']) if schema['minLength'] && value.length < schema['minLength']
        fail(out, path, 'max_length', limit: schema['maxLength']) if schema['maxLength'] && value.length > schema['maxLength']
        fail(out, path, 'pattern') if schema['pattern'] && !pattern(schema['pattern']).match?(value)
      end

      def check_number(schema, value, path, out)
        fail(out, path, 'minimum', limit: schema['minimum']) if schema['minimum'] && value < schema['minimum']
        fail(out, path, 'maximum', limit: schema['maximum']) if schema['maximum'] && value > schema['maximum']
      end

      # En Ruby, ^ et $ valent pour chaque ligne : on ancre sur toute la chaîne.
      def pattern(source)
        @patterns[source] ||= Regexp.new(source.sub(/\A\^/, '\\A').sub(/\$\z/, '\\z'))
      end

      def equal?(expected, value)
        return false if [true, false, nil].include?(value) != [true, false, nil].include?(expected)

        expected == value
      end

      def type?(type, value)
        case type
        when 'object' then value.is_a?(Hash)
        when 'array' then value.is_a?(Array)
        when 'string' then value.is_a?(String)
        when 'boolean' then [true, false].include?(value)
        when 'null' then value.nil?
        when 'number' then finite_number?(value)
        when 'integer' then integer?(value)
        else raise ArgumentError, "Type de schéma inconnu : #{type}"
        end
      end

      def finite_number?(value)
        value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
      end

      def integer?(value)
        value.is_a?(Integer) || (value.is_a?(Float) && value.finite? && value == value.floor)
      end

      def walk(schema, value)
        return schema['enum'].find { |e| e == value } if schema.key?('enum') && value.is_a?(Numeric)

        case value
        when Hash
          properties = schema.fetch('properties', {})
          value.to_h { |k, v| [k, properties[k] ? walk(properties[k], v) : v] }
        when Array then schema['items'] ? value.map { |v| walk(schema['items'], v) } : value
        when Numeric then walk_number(schema, value)
        else value
        end
      end

      def walk_number(schema, value)
        return value.to_i if schema['type'] == 'integer' || schema.key?('const')

        schema['type'] == 'number' ? zero_positive(value.to_f) : value
      end

      def zero_positive(float)
        float.zero? ? 0.0 : float
      end
    end
  end
end
