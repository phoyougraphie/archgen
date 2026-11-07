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
      core/survey_grid
      core/site_intake
      core/ensemble_intake
      core/road_profile_intake
      core/road_intake
      core/road_network_intake
      core/trace_session
      core/site_assise
      geometry/types
      geometry/road_section
      geometry/road_axis
      geometry/road_ribbons
      geometry/road_item_shapes
      geometry/road_items
      geometry/road_junction
      geometry/road_signals
      geometry/road_network
      geometry/road_roundabout
      geometry/planar
      geometry/trace_rows
      geometry/parcel_layout
      geometry/access_planner
      geometry/footprint_solver
      geometry/floor_planner
      geometry/facade_solver
      geometry/opening_solver
      geometry/wall_builder
      geometry/porch_solver
      geometry/roof_solver
      geometry/row_roof_solver
      geometry/detail_solver
      core/budget
      core/plan_validator
      core/site_plan_validator
      core/plan_projection
      core/geometry_engine
      core/parcel_building
      core/ensemble_engine
      core/ensemble_site
      core/road_engine
      core/road_network_engine
      geometry/embankment_builder
      geometry/site_planner
      composition
    ].freeze

    # Chargé seulement par main.rb ou par les tests de contrat du writer.
    ADAPTER = %w[
      adapters/sketchup/native_host
      adapters/sketchup/resources
      adapters/sketchup/geometry_writer
      adapters/sketchup/component_repository
      adapters/sketchup/transaction_guard
      adapters/sketchup/terrain_surveyor
      adapters/sketchup/ensemble_repository
      adapters/sketchup/building_service
      adapters/sketchup/ensemble_service
      adapters/sketchup/road_repository
      adapters/sketchup/road_service
      adapters/sketchup/street_tool
      ui/target_tokens
      ui/confirmation_tokens
      ui/messages
      ui/dialog_controller
      ui/street_controller
      ui/road_controller
    ].freeze

    def self.load_core
      CORE.each { |path| load_internal(path) }
    end

    def self.load_adapter
      ADAPTER.each { |path| load_internal(path) }
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
