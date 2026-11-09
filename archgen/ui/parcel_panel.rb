# frozen_string_literal: true

require 'json'

module Archgen
  module UI
    # Clic droit sur un bâtiment, dans une rue ou un îlot ouvert : « ARCHGEN → Personnaliser ce
    # bâtiment » (AG-069, D-22). Seule action qui accepte une parcelle sélectionnée dans un ensemble.
    module ParcelPanel
      HTML = File.join(__dir__, 'parcel_panel.html')
      ENSEMBLE_DICTIONARY = 'archgen.ensemble'

      # Le bâtiment choisi : [racine d'ensemble, id de parcelle], ou nil.
      def self.picked(model)
        path = model.active_path
        return nil unless path && !path.empty?

        root = path.last
        return nil unless root.is_a?(::Sketchup::ComponentInstance) && root.attribute_dictionary(ENSEMBLE_DICTIONARY)
        return nil unless model.selection.length == 1

        parcel = model.selection.first
        return nil unless parcel.is_a?(::Sketchup::ComponentInstance) && parcel.parent == root.definition
        return nil unless parcel.name.match?(Core::EnsembleParcels::ID_PATTERN)

        [root, parcel.name]
      end

      # L'édition de l'ensemble est refermée et la racine sélectionnée : l'écriture remplacera sa
      # définition, jamais pendant qu'on est dedans.
      def self.show
        model = ::Sketchup.active_model
        root, parcel_id = picked(model)
        return unless root

        model.active_path.size.times { model.close_active if model.active_path }
        return ::UI.messagebox('Refermez l’édition de la rue (Échap), puis recommencez.') if model.active_path

        model.selection.clear
        model.selection.add(root)
        loaded = controller.load(parcel_id)
        unless loaded.ok?
          ::UI.messagebox(loaded.errors.map { |d| Messages.text(d) }.join("\n"))
          return
        end

        @dialog ||= ::UI::HtmlDialog.new(
          dialog_title: 'ARCHGEN : bâtiment de la rue', preferences_key: 'archgen_parcel_panel', scrollable: true, resizable: true,
          left: 80, top: 150, width: 380, height: 560, min_width: 320, min_height: 380, style: ::UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.visible? ? restart : attach_and_show
      end

      def self.controller
        @controller ||= ParcelController.new(
          service: Adapters::SketchUp::EnsembleService.default,
          registry: Composition.registry.value,
          intake: Composition.intake,
          model_provider: -> { ::Sketchup.active_model }
        )
      end

      def self.literal(text)
        text.to_json.gsub("\u2028", '\\u2028').gsub("\u2029", '\\u2029')
      end

      def self.restart
        @dialog.bring_to_front
        @dialog.execute_script('archgenParcelRestart()')
      end
      private_class_method :restart

      def self.attach_and_show
        @dialog.set_file(HTML)
        @dialog.set_on_closed { controller.forget }
        @dialog.add_action_callback('archgen_parcel') do |_context, raw|
          @dialog.execute_script("archgenParcelReceive(#{literal(JSON.generate(controller.dispatch(raw)))})")
        end
        @dialog.show
      end
      private_class_method :attach_and_show
    end
  end
end
