# frozen_string_literal: true

module Archgen
  module Core
    # Limites bloquantes V0.1 (docs/SECURITY_PERFORMANCE.md).
    module Limits
      JSON_BYTES = 64 * 1024
      JSON_DEPTH = 12
      MAX_FOOTPRINT_M = 60.0
      MAX_LEVELS = 15
      MAX_WALL_TOP_M = 60.0
      MAX_ROOF_TOP_M = 90.0
      MAX_OPENINGS = 720
      MAX_UNIQUE_FACES = 30_000
      MAX_EXPANDED_FACES = 60_000
      MAX_WALL_CELLS = 100_000
      MAX_DETAIL_DEFINITIONS = 128
      # Assise : valeurs de départ du contrat terrain, à calibrer à la recette.
      SITE_RELIEF_MAX_M = 6.0
      SITE_MAX_SURVEY_POINTS = 3000
      SITE_MAX_FACES = 20_000
      # Ensemble : valeurs de départ du contrat d'ensemble, à calibrer à la recette.
      ENSEMBLE_MIN_SEGMENT_M = 6.0
      ENSEMBLE_MAX_COORDINATE_M = 2000.0
      ENSEMBLE_REAR_MIN_M = 2.0
      ENSEMBLE_CLEARANCE_M = 3.0
      ENSEMBLE_MAX_PARCELS = 200
    end
  end
end
