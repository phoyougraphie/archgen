# frozen_string_literal: true

# Enregistre l'extension uniquement : aucune logique ici (docs/RUBY_SKETCHUP.md).
require 'sketchup.rb'
require 'extensions.rb'

module Archgen
  unless defined?(Archgen::EXTENSION)
    version_file = File.join(__dir__, 'archgen', 'version')
    Sketchup.require(version_file)

    EXTENSION = SketchupExtension.new('ARCHGEN', File.join(__dir__, 'archgen', 'main'))
    EXTENSION.version = VERSION
    EXTENSION.creator = 'ARCHGEN'
    EXTENSION.description = 'Génération paramétrique de bâtiments.'
    Sketchup.register_extension(EXTENSION, true)
  end
end
