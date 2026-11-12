# frozen_string_literal: true

module Archgen
  module Core
    # Plan tangent local (docs/CARTOGRAPHIE_CONTRACT.md D-39) : équirectangulaire autour d'une origine,
    # en mètres, X vers l'est, Y vers le nord, arrondi au millimètre. Sur 2 km, l'écart avec une
    # projection conforme reste sous 0,1 %.
    class MapProjection
      EARTH_RADIUS_M = 6_371_008.8
      MM = 1000.0

      attr_reader :lat0, :lon0

      def initialize(lat0, lon0)
        @lat0 = lat0.to_f
        @lon0 = lon0.to_f
        @cos0 = Math.cos(radians(@lat0))
      end

      # [latitude, longitude] en degrés → [x, y] en mètres.
      def call(lat, lon)
        x = EARTH_RADIUS_M * radians(lon - @lon0) * @cos0
        y = EARTH_RADIUS_M * radians(lat - @lat0)
        [(x * MM).round / MM, (y * MM).round / MM]
      end

      def inverse(x, y)
        [@lat0 + degrees(y / EARTH_RADIUS_M), @lon0 + degrees(x / (EARTH_RADIUS_M * @cos0))]
      end

      private

      def radians(deg) = deg * Math::PI / 180.0
      def degrees(rad) = rad * 180.0 / Math::PI
    end
  end
end
