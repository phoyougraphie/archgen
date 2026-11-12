# frozen_string_literal: true

module Archgen
  module Core
    # Tuiles d'images en Web Mercator (pavage « XYZ » d'OpenStreetMap et du WMTS « PM » de l'IGN) pour le
    # fond de plan (ADR-59). Pur : calcule quelles tuiles couvrent une zone et où les poser, en mètres,
    # dans le plan tangent de la carte (MapProjection).
    module MapTiles
      module_function

      EARTH_CIRCUMFERENCE_M = 40_075_016.686
      MAX_LAT = 85.05112878

      # Tuile (x, y) contenant (lat, lon) au niveau z.
      def tile_of(lat, lon, z)
        n = 2**z
        x = ((lon + 180.0) / 360.0 * n).floor
        lat_r = lat.clamp(-MAX_LAT, MAX_LAT) * Math::PI / 180
        y = ((1.0 - (Math.log(Math.tan(lat_r) + (1.0 / Math.cos(lat_r))) / Math::PI)) / 2.0 * n).floor
        [x.clamp(0, n - 1), y.clamp(0, n - 1)]
      end

      # Coin nord-ouest de la tuile (x, y, z) : [lat, lon].
      def corner(x, y, z)
        n = 2.0**z
        lon = (x / n * 360.0) - 180.0
        lat = Math.atan(Math.sinh(Math::PI * (1 - (2 * y / n)))) * 180 / Math::PI
        [lat, lon]
      end

      # Taille d'une tuile au sol, en mètres, à la latitude donnée.
      def tile_size_m(lat, z)
        EARTH_CIRCUMFERENCE_M * Math.cos(lat * Math::PI / 180) / (2**z)
      end

      # Niveau le plus fin, au plus `wanted`, qui couvre la zone en `max_tiles` tuiles au plus.
      def zoom_for(lat, lon, size_m, wanted:, max_tiles:)
        wanted.downto(1).find { |z| tiles(lat, lon, size_m, z).size <= max_tiles } || 1
      end

      # Tuiles couvrant le carré de `size_m` centré sur (lat, lon), triées de l'ouest à l'est, du nord au sud.
      def tiles(lat, lon, size_m, z)
        projection = MapProjection.new(lat, lon)
        half = size_m / 2.0
        south, west = projection.inverse(-half, -half)
        north, east = projection.inverse(half, half)
        x0, y0 = tile_of(north, west, z)
        x1, y1 = tile_of(south, east, z)
        (y0..y1).flat_map { |y| (x0..x1).map { |x| { 'x' => x, 'y' => y, 'z' => z } } }
      end

      # Pose d'une tuile dans le plan de la carte : coin sud-ouest, largeur et hauteur en mètres.
      def placement(tile, projection)
        x, y, z = tile.values_at('x', 'y', 'z')
        north, west = corner(x, y, z)
        south, east = corner(x + 1, y + 1, z)
        sw = projection.call(south, west)
        ne = projection.call(north, east)
        { 'origin_m' => sw, 'width_m' => Quant.q(ne[0] - sw[0]), 'height_m' => Quant.q(ne[1] - sw[1]) }
      end
    end
  end
end
