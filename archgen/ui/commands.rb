# frozen_string_literal: true

module Archgen
  module UI
    # Accès direct (AG-145, ADR-70) : une seule liste de commandes pour le menu Extensions → ARCHGEN et
    # la barre d'outils ARCHGEN. `ENTRIES`, `selection_kind` et `enabled?` ne dépendent que de la
    # sélection : testables avec un modèle factice. `install` est le seul point qui touche l'API SketchUp.
    module Commands
      ICONS = File.join(__dir__, 'icons')

      # Racines ARCHGEN reconnues : [genre, dictionnaire, clé qui prouve la racine].
      ROOTS = [
        [:building, 'archgen.building', 'config_json'],
        [:ensemble, 'archgen.ensemble', 'ensemble_json'],
        [:road, 'archgen.road', 'road_json'],
        [:network, 'archgen.network', 'network_json']
      ].freeze

      # id, libellé du menu, info-bulle, texte de la barre d'état, icône, groupe (séparateur entre groupes).
      Entry = Struct.new(:id, :menu, :tooltip, :status, :icon, :group, keyword_init: true)

      ENTRIES = [
        Entry.new(id: :new_building, menu: 'Nouveau bâtiment', icon: 'building', group: :create,
                  tooltip: 'Nouveau bâtiment', status: 'Ouvre le panneau du bâtiment : style, dimensions, façade, aperçu, puis Générer.'),
        Entry.new(id: :street, menu: 'Tracer une rue', icon: 'street', group: :create,
                  tooltip: 'Tracer une rue', status: 'Tracez une rue dans la vue : ARCHGEN la découpe en parcelles et y construit des bâtiments.'),
        Entry.new(id: :road, menu: 'Tracer une voie', icon: 'road', group: :create,
                  tooltip: 'Tracer une voie', status: 'Choisissez une coupe de voirie, puis tracez la voie dans la vue.'),
        Entry.new(id: :network, menu: 'Tracer un réseau de voies', icon: 'network', group: :create,
                  tooltip: 'Tracer un réseau de voies', status: 'Tracez plusieurs voies : les carrefours et les ponts naissent aux croisements.'),
        Entry.new(id: :edit, menu: 'Modifier la sélection', icon: 'edit', group: :edit,
                  tooltip: 'Modifier la sélection',
                  status: 'Rouvre le bon panneau pour le bâtiment, la rue, la voie ou le réseau sélectionné.'),
        Entry.new(id: :base_map, menu: 'Fond de plan (carte et photo) autour du point géolocalisé…', icon: 'base_map', group: :map,
                  tooltip: 'Fond de plan autour du point géolocalisé', status: 'Pose une carte et une photo aérienne sous le modèle, autour de sa géolocalisation.'),
        Entry.new(id: :map_quick, menu: 'Importer rues et bâtiments autour du point géolocalisé…', icon: 'map_quick', group: :map,
                  tooltip: 'Importer rues et bâtiments autour du point géolocalisé',
                  status: 'Télécharge les rues et les bâtiments d’OpenStreetMap autour de la géolocalisation, puis les construit.'),
        Entry.new(id: :map_file, menu: 'Importer une carte depuis un fichier…', icon: 'map_file', group: :map,
                  tooltip: 'Importer une carte depuis un fichier', status: 'Importe un fichier .osm ou .geojson, et un terrain IGN si vous en avez un.'),
        Entry.new(id: :export, menu: 'Exporter pour un moteur de jeu…', icon: 'export', group: :export,
                  tooltip: 'Exporter pour un moteur de jeu', status: 'Exporte le bâtiment ou la rue sélectionné en glTF, avec ses niveaux de détail.')
      ].freeze

      # Panneau ouvert par « Modifier la sélection », selon ce qui est sélectionné.
      EDIT_ACTIONS = { building: :edit_building, ensemble: :edit_street, road: :edit_road, network: :edit_network, parcel: :customize_parcel }.freeze

      module_function

      # :building, :ensemble, :road, :network, :parcel (bâtiment pris dans une rue ouverte) ou nil.
      def selection_kind(model)
        return nil unless model
        return :parcel if parcel_picked?(model)

        selection = model.selection
        return nil unless selection.length == 1 && !model.active_path

        item = selection.first
        found = ROOTS.find { |_kind, dictionary, key| item.respond_to?(:get_attribute) && !item.get_attribute(dictionary, key).nil? }
        found&.first
      end

      def enabled?(id, model)
        case id
        when :edit then !selection_kind(model).nil?
        when :export then %i[building ensemble].include?(selection_kind(model))
        else true
        end
      end

      def parcel_picked?(model)
        defined?(ParcelPanel) && model.respond_to?(:active_path) && model.active_path && ParcelPanel.picked(model) ? true : false
      end
      private_class_method :parcel_picked?

      def run(id, model = ::Sketchup.active_model)
        case id
        when :new_building then Panel.show('new')
        when :street then StreetPanel.show('new')
        when :road then RoadPanel.show('trace')
        when :network then NetworkPanel.show('trace')
        when :edit then edit(model)
        when :base_map then BaseMapCommand.run
        when :map_quick then MapQuick.run
        when :map_file then MapPanel.show
        when :export then ExportCommand.run
        end
      end

      def edit(model)
        case EDIT_ACTIONS[selection_kind(model)]
        when :edit_building then Panel.show('edit')
        when :edit_street then StreetPanel.show('edit')
        when :edit_road then RoadPanel.show('edit')
        when :edit_network then NetworkPanel.show('edit')
        when :customize_parcel then ParcelPanel.show
        else ::UI.messagebox('Sélectionnez un bâtiment, une rue, une voie ou un réseau ARCHGEN, puis recommencez.')
        end
      end

      def icon(name)
        File.join(ICONS, "#{name}.svg")
      end

      # Une commande SketchUp par entrée, partagée par le menu et la barre d'outils.
      def command(entry)
        cmd = ::UI::Command.new(entry.menu) { run(entry.id) }
        cmd.tooltip = entry.tooltip
        cmd.status_bar_text = entry.status
        cmd.small_icon = icon(entry.icon)
        cmd.large_icon = icon(entry.icon)
        cmd.set_validation_proc { enabled?(entry.id, ::Sketchup.active_model) ? MF_ENABLED : MF_GRAYED }
        cmd
      end

      def install
        commands = ENTRIES.to_h { |entry| [entry.id, command(entry)] }
        install_menu(commands)
        install_toolbar(commands)
      end

      def install_menu(commands)
        menu = ::UI.menu('Extensions').add_submenu('ARCHGEN')
        groups(menu) { |entry| menu.add_item(commands.fetch(entry.id)) }
        # Les modifications par genre restent au menu : on les connaît depuis la V0.1.
        menu.add_separator
        edits = menu.add_submenu('Modifier…')
        edits.add_item('Le bâtiment sélectionné') { Panel.show('edit') }
        edits.add_item('L’ensemble sélectionné') { StreetPanel.show('edit') }
        edits.add_item('La voie sélectionnée') { RoadPanel.show('edit') }
        edits.add_item('Le réseau sélectionné') { NetworkPanel.show('edit') }
        menu.add_separator
        menu.add_item('Afficher la barre d’outils ARCHGEN') { @toolbar&.show }
      end
      private_class_method :install_menu

      def install_toolbar(commands)
        @toolbar = ::UI::Toolbar.new('ARCHGEN')
        groups(@toolbar) { |entry| @toolbar.add_item(commands.fetch(entry.id)) }
        # Visible au premier lancement, puis comme l'utilisateur l'a laissée.
        @toolbar.get_last_state == TB_NEVER_SHOWN ? @toolbar.show : @toolbar.restore
      end
      private_class_method :install_toolbar

      def groups(container)
        ENTRIES.chunk_while { |a, b| a.group == b.group }.each_with_index do |chunk, index|
          container.add_separator if index.positive?
          chunk.each { |entry| yield entry }
        end
      end
      private_class_method :groups
    end
  end
end
