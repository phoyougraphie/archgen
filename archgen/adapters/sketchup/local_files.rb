# frozen_string_literal: true

require 'fileutils'

module Archgen
  module Adapters
    module SketchUp
      # Seul point d'écriture de fichiers d'ARCHGEN (ADR-71). Les appelants choisissent un dossier
      # fixe (export à côté du SKP, cache du fond de plan, recettes du poste) ; un profil ou une
      # page n'y choisit jamais un chemin. Écriture atomique : un fichier temporaire, puis renommé,
      # pour qu'une coupure ne laisse jamais un fichier à moitié écrit.
      module LocalFiles
        module_function

        def mkdir(directory)
          FileUtils.mkdir_p(directory)
        end

        def write(path, bytes)
          mkdir(File.dirname(path))
          temporary = "#{path}.tmp"
          File.binwrite(temporary, bytes)
          File.rename(temporary, path)
          path
        end
      end
    end
  end
end
