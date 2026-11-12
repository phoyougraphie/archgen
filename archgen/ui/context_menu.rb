# frozen_string_literal: true

module Archgen
  module UI
    # Clic droit (docs/VILLE_MIXTE_CONTRACT.md, AG-095) : un seul sous-menu ARCHGEN, selon ce qui est
    # sélectionné. `entries` ne dépend que de la sélection : testable avec un modèle factice.
    module ContextMenu
      BUILDING = 'archgen.building'
      ENSEMBLE = 'archgen.ensemble'

      module_function

      # [[libellé, action]] ; action : :edit_building, :edit_street, :customize_parcel, :export_game (AG-118).
      def entries(model)
        out = []
        out << ['Personnaliser ce bâtiment', :customize_parcel] if parcel_picked?(model)
        selection = model.selection
        return out unless selection.length == 1 && !model.active_path

        item = selection.first
        out << ['Modifier ce bâtiment', :edit_building] if root_with?(item, BUILDING, 'config_json')
        out << ['Modifier cette rue', :edit_street] if root_with?(item, ENSEMBLE, 'ensemble_json')
        export = out.any?
        # AG-145 : voies et réseaux se rouvrent aussi au clic droit ; ils ne s'exportent pas.
        out << ['Modifier cette voie', :edit_road] if root_with?(item, 'archgen.road', 'road_json')
        out << ['Modifier ce réseau', :edit_network] if root_with?(item, 'archgen.network', 'network_json')
        out << ['Exporter pour un moteur de jeu…', :export_game] if export
        out
      end

      def root_with?(item, dictionary, key)
        item.respond_to?(:get_attribute) && !item.get_attribute(dictionary, key).nil?
      end
      private_class_method :root_with?

      def parcel_picked?(model)
        defined?(ParcelPanel) && model.respond_to?(:active_path) && model.active_path && ParcelPanel.picked(model)
      end
      private_class_method :parcel_picked?

      def install
        ::UI.add_context_menu_handler do |menu|
          model = ::Sketchup.active_model
          list = model ? entries(model) : []
          next if list.empty?

          submenu = menu.add_submenu('ARCHGEN')
          list.each { |label, action| submenu.add_item(label) { run(action) } }
        end
      end

      def run(action)
        case action
        when :edit_building then Panel.show('edit')
        when :edit_street then StreetPanel.show('edit')
        when :customize_parcel then ParcelPanel.show
        when :edit_road then RoadPanel.show('edit')
        when :edit_network then NetworkPanel.show('edit')
        when :export_game then ExportCommand.run
        end
      end
    end
  end
end
