# frozen_string_literal: true

module Archgen
  # Manifeste de chargement du noyau pur. Aucun fichier du noyau ne fait de
  # `require` interne et le chemin de chargement reste intact (docs/RUBY_SKETCHUP.md).
  module Loader
    ROOT = __dir__

    CORE = %w[
      version
      core/limits
      core/result
      core/quant
      core/canonical
      core/strict_json
      core/schema_validator
      core/building_config
      core/constraint_validator
      core/intake
      core/deterministic_random
      core/style_registry
      core/fidelity_rules
      core/config_resolver
      geometry/types
      geometry/footprint_solver
      geometry/floor_planner
      geometry/facade_solver
      geometry/opening_solver
      geometry/wall_builder
      geometry/roof_solver
      composition
    ].freeze

    def self.load_core
      CORE.each { |path| load_internal(path) }
    end

    def self.load_internal(relative)
      path = File.join(ROOT, relative)
      if defined?(::Sketchup)
        ::Sketchup.require(path)
      else
        require(path)
      end
    end
  end
end
