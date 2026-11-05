# frozen_string_literal: true

module Archgen
  module Core
    # Configuration effective complète : copie profonde gelée, sans UUID ni placement.
    class BuildingConfig
      DEFAULT_NAME = 'Bâtiment ARCHGEN'

      def initialize(hash)
        @data = Canonical.deep_freeze(Canonical.deep_copy(hash))
        freeze
      end

      def to_h
        @data
      end

      def dig(*keys)
        @data.dig(*keys)
      end

      # Projection sans libellé, seule entrée du moteur de géométrie.
      def geometry_input
        Canonical.deep_freeze(@data.reject { |k, _| k == 'name' })
      end

      # Empreinte de configuration complète, `name` compris : contrôle de cible.
      def config_digest
        Canonical.digest(@data)
      end

      # Empreinte de géométrie : hors `name`, avec les révisions qui changent le plan.
      def geometry_digest(engine_version:, material_revision:)
        Canonical.digest(
          'config' => @data.reject { |k, _| k == 'name' },
          'engine_version' => engine_version,
          'material_revision' => material_revision
        )
      end

      def ==(other)
        other.is_a?(BuildingConfig) && to_h == other.to_h
      end
    end
  end
end
