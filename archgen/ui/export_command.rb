# frozen_string_literal: true

module Archgen
  module UI
    # Clic droit ARCHGEN → Exporter pour un moteur de jeu… (docs/DECOR_JEU_CONTRACT.md §4, AG-118).
    # Boîte « Enregistrer sous », confirmation des fichiers voisins remplacés, rapport. Le modèle n'est pas modifié.
    module ExportCommand
      TITLE = 'Exporter pour un moteur de jeu'

      module_function

      def run(model = ::Sketchup.active_model)
        service = Adapters::SketchUp::ExportService.default
        name = Adapters::SketchUp::ExportService.suggested_name(model)
        directory = model.path.to_s.empty? ? nil : File.dirname(model.path)
        chosen = ::UI.savepanel(TITLE, directory, "#{name}_LOD0.glb")
        return unless chosen

        chosen = "#{chosen}.glb" unless chosen.downcase.end_with?('.glb')
        others = service.existing(chosen)
        return if others.any? && ::UI.messagebox("Ces fichiers seront remplacés :\n#{others.join("\n")}", MB_OKCANCEL) != IDOK

        ::UI.messagebox(report(service.export(model: model, path: chosen)))
      end

      def report(result)
        lines = []
        if result.ok?
          lines << 'Export terminé.'
          result.value.files.each { |file| lines << "#{file['suffix']} : #{file['triangles']} triangles — #{file['path']}" }
          result.value.notes.each { |note| lines << Messages::REASONS.fetch(note, note) }
        end
        lines.concat(result.diagnostics.map { |diagnostic| Messages.text(diagnostic) })
        lines.join("\n")
      end
    end
  end
end
