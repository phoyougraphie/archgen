# frozen_string_literal: true

# Point de composition, chargé par SketchUp seulement si l'extension est activée.
Sketchup.require(File.join(__dir__, 'loader'))
Archgen::Loader.load_core
Archgen::Loader.load_adapter
Archgen::Loader.load_internal('ui/diagnostic_dialog')
Archgen::Loader.load_internal('ui/panel')

module Archgen
  # La garde empêche de dédoubler le menu en cas de double chargement.
  unless defined?(@menu_installed) && @menu_installed
    # ::UI est l'API SketchUp ; Archgen::UI est le module du plugin.
    submenu = ::UI.menu('Extensions').add_submenu('ARCHGEN')
    submenu.add_item('Nouveau bâtiment') { UI::Panel.show('new') }
    submenu.add_item('Modifier le bâtiment sélectionné') { UI::Panel.show('edit') }
    submenu.add_separator
    submenu.add_item('Diagnostic') { UI::DiagnosticDialog.show }
    @menu_installed = true
  end
end
