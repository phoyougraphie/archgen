# frozen_string_literal: true

module Archgen
  # Manifeste de chargement du noyau pur. Aucun fichier du noyau ne fait de
  # `require` interne et $LOAD_PATH n'est jamais modifié (docs/RUBY_SKETCHUP.md).
  module Loader
    ROOT = __dir__

    CORE = %w[
      version
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
