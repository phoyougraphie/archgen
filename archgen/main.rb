# frozen_string_literal: true

# Point de composition, chargé par SketchUp seulement si l'extension est activée.
Sketchup.require(File.join(__dir__, 'loader'))
Archgen::Loader.load_core
Archgen::Loader.load_export
Archgen::Loader.load_adapter
Archgen::Loader.load_internal('ui/panel_observers')
Archgen::Loader.load_internal('ui/panel')
Archgen::Loader.load_internal('ui/street_panel')
Archgen::Loader.load_internal('ui/parcel_panel')
Archgen::Loader.load_internal('ui/context_menu')
Archgen::Loader.load_internal('ui/export_command')
Archgen::Loader.load_internal('ui/road_panel')
Archgen::Loader.load_internal('ui/network_panel')
Archgen::Loader.load_internal('ui/map_panel')
Archgen::Loader.load_internal('ui/map_quick')
Archgen::Loader.load_internal('ui/base_map_command')

module Archgen
  # La garde empêche de dédoubler le menu en cas de double chargement.
  unless defined?(@menu_installed) && @menu_installed
    # ::UI est l'API SketchUp ; Archgen::UI est le module du plugin.
    submenu = ::UI.menu('Extensions').add_submenu('ARCHGEN')
    submenu.add_item('Nouveau bâtiment') { UI::Panel.show('new') }
    submenu.add_item('Modifier le bâtiment sélectionné') { UI::Panel.show('edit') }
    submenu.add_item('Tracer une rue') { UI::StreetPanel.show('new') }
    submenu.add_item('Modifier l’ensemble sélectionné') { UI::StreetPanel.show('edit') }
    submenu.add_item('Tracer une voie') { UI::RoadPanel.show('trace') }
    submenu.add_item('Modifier la voie sélectionnée') { UI::RoadPanel.show('edit') }
    submenu.add_item('Tracer un réseau de voies') { UI::NetworkPanel.show('trace') }
    submenu.add_item('Modifier le réseau sélectionné') { UI::NetworkPanel.show('edit') }
    submenu.add_item('Fond de plan (carte et photo) autour du point géolocalisé…') { UI::BaseMapCommand.run }
    submenu.add_item('Importer rues et bâtiments autour du point géolocalisé…') { UI::MapQuick.run }
    submenu.add_item('Importer une carte depuis un fichier…') { UI::MapPanel.show }
    # AG-069, AG-095 : clic droit — personnaliser un bâtiment d'une rue ouverte, modifier un bâtiment seul ou une rue.
    UI::ContextMenu.install
    @menu_installed = true
  end
end
