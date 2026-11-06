# frozen_string_literal: true

require 'json'

module Archgen
  # Point de composition : seul endroit du noyau qui lit des fichiers. Les solveurs
  # reçoivent des données déjà chargées (docs/ARCHITECTURE.md).
  module Composition
    ROOT = __dir__
    # Capacités géométriques réellement implémentées : un profil qui en requiert
    # d'autres reste indisponible. La liste complète publie les trois feuilles V0.1.
    IMPLEMENTED_CAPABILITIES = %w[rectangle rect_opening flat gable hip mansard cornice balcony surrounds].freeze

    module_function

    def read_json(*parts)
      JSON.parse(File.read(File.join(ROOT, *parts), mode: 'rb', encoding: 'UTF-8'))
    end

    def schemas
      {
        'draft' => read_json('schemas', 'building-draft.v1.schema.json'),
        'config' => read_json('schemas', 'building-config.v1.schema.json'),
        'profile' => read_json('schemas', 'style-profile.v1.schema.json'),
        'site' => read_json('schemas', 'site-settings.v1.schema.json'),
        'survey' => read_json('schemas', 'survey-grid.v1.schema.json')
      }
    end

    def materials
      read_json('styles', 'materials', 'materials.v1.json')
    end

    def profiles
      Dir.glob('styles/profiles/*.json', base: ROOT).sort.map { |path| read_json(path) }
    end

    # Catalogue complet d'une assise : celui du bâtiment, inchangé, plus la terre du talus.
    def site_materials
      materials.fetch('materials').merge(read_json('styles', 'materials', 'site_materials.v1.json').fetch('materials'))
    end

    # Retourne un Result<StyleRegistry>.
    def registry(capabilities: IMPLEMENTED_CAPABILITIES, sources: schemas)
      Core::StyleRegistry.load(
        profiles,
        schema: sources.fetch('profile'),
        config_validator: Core::SchemaValidator.new(sources.fetch('config')),
        capabilities: capabilities,
        materials: materials.fetch('materials')
      )
    end

    def intake(sources: schemas)
      Core::Intake.new(sources)
    end

    def site_intake(sources: schemas)
      Core::SiteIntake.new(sources, materials: materials.fetch('materials'))
    end
  end
end
