# frozen_string_literal: true

module Archgen
  module Core
    # Première barrière : taille, syntaxe, version, clés, types, finitude.
    # Accepte une chaîne JSON (entrée non fiable) ou un arbre déjà parsé.
    class Intake
      SUPPORTED_VERSION = 1

      # schemas : { 'draft' => Hash, 'config' => Hash } chargés par le point de composition.
      def initialize(schemas)
        @draft = SchemaValidator.new(schemas.fetch('draft'))
        @config = SchemaValidator.new(schemas.fetch('config'))
      end

      def draft(input)
        read(input, @draft)
      end

      def effective(input)
        read(input, @config)
      end

      private

      def read(input, validator)
        parsed = input.is_a?(String) ? StrictJson.parse(input) : Result.ok(input)
        return parsed unless parsed.ok?

        tree = parsed.value
        version = version_diagnostics(tree)
        return Result.fail(version) unless version.empty?

        problems = validator.validate(tree)
        return Result.fail(problems) unless problems.empty?

        Result.ok(validator.normalize(tree))
      end

      # Une version future garde son diagnostic propre : lecture sans écrasement.
      def version_diagnostics(tree)
        return [] unless tree.is_a?(Hash) && tree['schema_version'].is_a?(Numeric)

        version = tree['schema_version']
        return [] if version == SUPPORTED_VERSION

        [Diagnostic.error('E_VERSION', '/schema_version', reason: 'unsupported', value: version, supported: SUPPORTED_VERSION)]
      end
    end
  end
end
