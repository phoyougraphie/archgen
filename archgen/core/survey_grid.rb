# frozen_string_literal: true

module Archgen
  module Core
    # Altitudes relevées aux nœuds d'une grille, dans le repère du bâtiment. Immuable,
    # sans lien avec SketchUp : `null` signifie qu'aucun terrain n'a été trouvé.
    class SurveyGrid
      HINT = 'increase_survey_step'
      NOISE = 1e-9

      attr_reader :xs, :ys

      # Axes attendus : le pas tombe juste sur 0 et sur la longueur, sans sliver au bout.
      def self.plan(width_m:, depth_m:, settings:)
        step = settings.dig('survey', 'step_m')
        margin = margin_m(settings)
        xs = axis(width_m, step, margin)
        ys = axis(depth_m, step, margin)
        points = xs.size * ys.size
        return Result.ok('xs_m' => xs, 'ys_m' => ys) if points <= Limits::SITE_MAX_SURVEY_POINTS

        Result.fail([Diagnostic.error('E_SITE_BUDGET', '/site/survey/step_m', reason: 'survey_points',
                                                                              limit: Limits::SITE_MAX_SURVEY_POINTS, value: points, hint: HINT)])
      end

      # Le talus doit pouvoir descendre du remblai le plus haut que les réglages permettent.
      def self.margin_m(settings)
        return 0.0 unless settings['earthwork'] == 'embankment'

        height = Limits::SITE_RELIEF_MAX_M + settings.dig('platform', 'offset_m').abs
        (height * settings['embankment_ratio']) + settings.dig('survey', 'step_m')
      end

      def self.axis(length, step, margin)
        count = [((length / step) - NOISE).ceil, 1].max
        inner = (0..count).map { |i| Quant.q(length * i / count) }
        outer = [((margin / step) - NOISE).ceil, 0].max
        (1..outer).map { |i| Quant.q(-i * step) }.reverse + inner + (1..outer).map { |i| Quant.q(length + (i * step)) }
      end
      private_class_method :axis

      def initialize(data)
        @data = Canonical.deep_freeze(data)
        @xs = @data['xs_m']
        @ys = @data['ys_m']
        freeze
      end

      def to_h
        @data
      end

      def digest
        Canonical.digest(@data)
      end

      def z(column, row)
        @data['z_m'][row][column]
      end

      # Nœuds dans le rectangle [0,W]×[0,D], bords compris : [x, y, z ou nil].
      def points_within(width_m, depth_m)
        columns = indices(@xs, width_m)
        indices(@ys, depth_m).flat_map { |j| columns.map { |i| [@xs[i], @ys[j], z(i, j)] } }
      end

      # Cellules dans ce rectangle : [largeur, profondeur, [z des quatre angles]].
      def cells_within(width_m, depth_m)
        columns = indices(@xs, width_m)
        rows = indices(@ys, depth_m)
        rows.each_cons(2).flat_map do |j, up|
          columns.each_cons(2).map do |i, right|
            [@xs[right] - @xs[i], @ys[up] - @ys[j], [z(i, j), z(right, j), z(right, up), z(i, up)]]
          end
        end
      end

      # Interpolation bilinéaire. nil hors grille ou si un angle de la cellule manque.
      def altitude_at(x_m, y_m)
        i = cell_index(@xs, x_m)
        j = cell_index(@ys, y_m)
        return nil unless i && j

        corners = [z(i, j), z(i + 1, j), z(i, j + 1), z(i + 1, j + 1)]
        return nil if corners.any?(&:nil?)

        u = (x_m - @xs[i]) / (@xs[i + 1] - @xs[i])
        v = (y_m - @ys[j]) / (@ys[j + 1] - @ys[j])
        low = corners[0] + (u * (corners[1] - corners[0]))
        high = corners[2] + (u * (corners[3] - corners[2]))
        low + (v * (high - low))
      end

      private

      def indices(axis, length)
        axis.each_index.select { |i| axis[i] >= -Quant::EPSILON && axis[i] <= length + Quant::EPSILON }
      end

      def cell_index(axis, value)
        return nil if value < axis.first - Quant::EPSILON || value > axis.last + Quant::EPSILON

        [axis.bsearch_index { |v| v > value } || axis.size, axis.size - 1].min.then { |upper| [upper - 1, 0].max }
      end
    end
  end
end
