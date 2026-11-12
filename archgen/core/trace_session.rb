# frozen_string_literal: true

module Archgen
  module Core
    # Le tracé en cours, en mètres, dans le repère du modèle (docs/ENSEMBLE_CONTRACT.md, Outil de
    # tracé). Pur : l'outil natif ne fait que lui passer des points et des touches.
    class TraceSession
      SIDES = %w[left right both].freeze
      LOCKS = %w[red green prev].freeze
      MIN_STEP_M = 0.001
      QUARTER = Math::PI / 2.0

      attr_reader :points, :z_m, :axis_lock, :lock_90
      attr_accessor :side

      def initialize
        @side = 'left'
        @lock_90 = false
        clear
      end

      def clear
        @points = []
        @z_m = 0.0
        @closed = false
        @finished = false
        @axis_lock = nil
      end

      def empty?
        @points.empty?
      end

      def closed?
        @closed
      end

      def finished?
        @finished
      end

      def state
        return 'empty' if empty?

        finished? ? 'ready' : 'drawing'
      end

      def start(x_m, y_m, z_m)
        clear
        @points = [[x_m, y_m]]
        @z_m = z_m
      end

      # Faux si le point se confond avec le précédent : un double-clic n'ajoute rien.
      def add(point)
        return false if distance(point, @points.last) < MIN_STEP_M

        @points << point
        @axis_lock = nil
        true
      end

      # Échap ou double-clic : garde le tracé s'il a au moins deux points, sinon l'oublie.
      def finish
        return clear if @points.size < 2

        @finished = true
        @axis_lock = nil
      end

      # Faux tant qu'il n'y a pas assez de points pour une forme fermée.
      def close
        return false if @points.size < 3

        @closed = true
        @finished = true
        @axis_lock = nil
        true
      end

      def cycle_side
        @side = SIDES[(SIDES.index(@side) + 1) % SIDES.size]
      end

      def toggle_90
        @lock_90 = !@lock_90
      end

      # Faux si le blocage demandé n'a pas de sens : pas de segment précédent.
      def toggle_lock(kind)
        return false if kind == 'prev' && previous_direction.nil?

        @axis_lock = @axis_lock == kind ? nil : kind
        true
      end

      def previous_direction
        return nil if @points.size < 2

        unit(sub(@points[-1], @points[-2]))
      end

      # Point de la souris après les blocages : la direction imposée, le sens suit la souris.
      def constrain(target)
        from = @points.last
        return target unless from

        vector = sub(target, from)
        return target if length(vector).zero?

        direction = locked_direction(vector)
        return target unless direction

        along = dot(vector, direction)
        [from[0] + (along * direction[0]), from[1] + (along * direction[1])]
      end

      # Saisie : `longueur`, ou `longueur;angle` en degrés depuis l'axe rouge. Sans angle, la
      # direction est celle de la souris. nil si elle est inconnue.
      def typed(length_m, angle_deg, mouse)
        from = @points.last
        direction = if angle_deg
                      radians = angle_deg * Math::PI / 180.0
                      [Math.cos(radians), Math.sin(radians)]
                    elsif mouse && length(sub(mouse, from)).positive?
                      unit(sub(mouse, from))
                    end
        direction && [from[0] + (length_m * direction[0]), from[1] + (length_m * direction[1])]
      end

      # Point saisi dans la boîte de mesure, déjà découpé : parse_length rend des mètres ou nil.
      def self.parse_typed(text, parse_length)
        parts = text.to_s.split(';', -1).map(&:strip)
        return nil if parts.empty? || parts.size > 2

        length = parse_length.call(parts[0])
        return nil unless length&.positive?
        return [length, nil] if parts.size == 1

        angle = Float(parts[1].tr(',', '.'), exception: false)
        angle && [length, angle]
      end

      # Point dans le repère de la racine : le premier point est l'origine.
      def relative_points
        first = @points.first
        @points.map { |x, y| [Quant.q(x - first[0]), Quant.q(y - first[1])] }
      end

      def origin_m
        [@points.first[0], @points.first[1], @z_m]
      end

      def trace
        { 'points_m' => relative_points, 'closed' => @closed }
      end

      def length_m
        segments = @points.each_cons(2).sum { |a, b| distance(a, b) }
        @closed ? segments + distance(@points.last, @points.first) : segments
      end

      private

      def locked_direction(vector)
        case @axis_lock
        when 'red' then [vector[0].negative? ? -1.0 : 1.0, 0.0]
        when 'green' then [0.0, vector[1].negative? ? -1.0 : 1.0]
        when 'prev' then quarter(vector, previous_direction)
        else @lock_90 ? quarter(vector, previous_direction || [1.0, 0.0]) : nil
        end
      end

      # Direction arrondie au quart de tour par rapport à une référence.
      def quarter(vector, reference)
        base = Math.atan2(reference[1], reference[0])
        angle = (((Math.atan2(vector[1], vector[0]) - base) / QUARTER).round * QUARTER) + base
        [Math.cos(angle), Math.sin(angle)]
      end

      def sub(a, b)
        [a[0] - b[0], a[1] - b[1]]
      end

      def dot(a, b)
        (a[0] * b[0]) + (a[1] * b[1])
      end

      def length(a)
        Math.hypot(a[0], a[1])
      end

      def unit(a)
        size = length(a)
        [a[0] / size, a[1] / size]
      end

      def distance(a, b)
        length(sub(a, b))
      end
    end
  end
end
