# frozen_string_literal: true

module Archgen
  module Core
    # Codes fermés (docs/CONFIG_SCHEMA.md). Un avertissement permet de continuer,
    # une erreur interdit la mutation.
    module Codes
      ALL = %w[
        E_SCHEMA E_VERSION E_PROFILE_UNAVAILABLE E_HISTORICAL W_HISTORICAL W_DETAIL
        E_OPENING_CLEARANCE E_ROOF_GEOMETRY E_BUDGET E_PLAN
        E_TARGET_STALE E_CONFIRMATION_STALE E_WRITE
        E_SITE_SURVEY E_SITE_RELIEF E_SITE_BUDGET E_SITE_DOOR_BURIED E_SITE_TOE E_SITE_TERRAIN E_SITE_TRANSFORM W_SITE_DOOR_GAP W_SITE_BURIED
        E_STREET_TRACE E_STREET_CORNER E_STREET_OVERLAP E_STREET_BUDGET E_STREET_ROOF E_STREET_ACCESS E_STREET_SITE E_STREET_VARIETY E_STREET_PARCEL
        E_ROAD_BAND E_ROAD_ITEM W_ROAD_CLEARANCE W_ROAD_COMPOSITION E_ROAD_TRACE E_ROAD_BUDGET E_ROAD_JUNCTION E_ROAD_GROUND E_ROAD_GRADE E_ROAD_EARTHWORK E_ROAD_TOE E_ROAD_WATER
      ].freeze
    end

    Diagnostic = Struct.new(:code, :severity, :path, :params, keyword_init: true) do
      def self.error(code, path, **params)
        build(code, 'error', path, params)
      end

      def self.warning(code, path, **params)
        build(code, 'warning', path, params)
      end

      def self.build(code, severity, path, params)
        raise ArgumentError, "Code inconnu : #{code}" unless Codes::ALL.include?(code)

        new(code: code, severity: severity, path: path,
            params: params.transform_keys(&:to_s).freeze).freeze
      end
      private_class_method :build

      def error?
        severity == 'error'
      end

      def to_h
        { 'code' => code, 'severity' => severity, 'path' => path, 'params' => params }
      end

      # Ordre stable au sein d'une phase : chemin, code, identifiant de pièce.
      def sort_key
        [path, code, params['id'].to_s, params['reason'].to_s]
      end
    end

    # `value` en cas de succès, `diagnostics` toujours.
    class Result
      attr_reader :value, :diagnostics

      def self.ok(value, diagnostics = [])
        new(value, diagnostics)
      end

      def self.fail(diagnostics)
        new(nil, diagnostics)
      end

      def initialize(value, diagnostics)
        @diagnostics = diagnostics.dup.freeze
        @value = errors.empty? ? value : nil
        freeze
      end

      def errors
        @diagnostics.select(&:error?)
      end

      def warnings
        @diagnostics.reject(&:error?)
      end

      def ok?
        errors.empty?
      end
    end
  end
end
