# frozen_string_literal: true

require 'json'

module Archgen
  module UI
    # Éditeur de coupe de voirie (AG-038). Toute la logique est dans RoadController, testable
    # sans SketchUp ; ce panneau n'écrit rien dans le modèle.
    module RoadPanel
      HTML = File.join(__dir__, 'road_panel.html')

      def self.show
        @dialog ||= ::UI::HtmlDialog.new(
          dialog_title: 'ARCHGEN : coupe de voirie', preferences_key: 'archgen_road_panel', scrollable: true, resizable: true,
          left: 60, top: 130, width: 1100, height: 760, min_width: 560, min_height: 480, style: ::UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.visible? ? @dialog.bring_to_front : attach_and_show
      end

      def self.controller
        @controller ||= RoadController.new(
          intake: Composition.road_profile_intake, bands: Composition.road_bands,
          items: Composition.road_items, presets: Composition.road_presets
        )
      end

      def self.literal(text)
        text.to_json.gsub("\u2028", '\\u2028').gsub("\u2029", '\\u2029')
      end

      # Le rappel de fermeture n'est pas utile ici : aucune session à oublier.
      def self.attach_and_show
        @dialog.set_file(HTML)
        @dialog.add_action_callback('archgen_road') do |_context, raw|
          @dialog.execute_script("archgenRoadReceive(#{literal(JSON.generate(controller.dispatch(raw)))})")
        end
        @dialog.show
      end
      private_class_method :attach_and_show
    end
  end
end
