# frozen_string_literal: true

require 'json'

module Archgen
  module UI
    # Panneau modeless. Toute la logique est dans DialogController, testable sans SketchUp.
    module Panel
      HTML = File.join(__dir__, 'panel.html')

      def self.show(mode)
        controller.mode = mode
        @dialog ||= build
        if @dialog.visible?
          @dialog.bring_to_front
          send_script("archgenSetMode(#{literal(mode)})")
        else
          attach_and_show
        end
      end

      # Une chaîne JSON re-encodée en littéral JS : aucune interpolation directe.
      def self.literal(text)
        text.to_json.gsub("\u2028", '\\u2028').gsub("\u2029", '\\u2029')
      end

      def self.send_script(script)
        @dialog&.execute_script(script)
      end

      def self.controller
        @controller ||= begin
          registry = Composition.registry
          raise ArgumentError, 'Profils invalides' unless registry.ok?

          DialogController.new(
            service: Adapters::SketchUp::BuildingService.default,
            registry: registry.value,
            materials: Composition.materials.fetch('materials'),
            model_provider: -> { ::Sketchup.active_model }
          )
        end
      end

      def self.build
        ::UI::HtmlDialog.new(
          dialog_title: 'ARCHGEN',
          preferences_key: 'archgen_panel',
          scrollable: true, resizable: true,
          width: 1000, height: 760, min_width: 380, min_height: 480,
          style: ::UI::HtmlDialog::STYLE_DIALOG
        )
      end
      private_class_method :build

      # Les rappels sont rattachés avant chaque affichage ; le panneau refait `init`.
      def self.attach_and_show
        @dialog.set_file(HTML)
        @dialog.add_action_callback('archgen_dispatch') do |_context, raw|
          response = controller.dispatch(raw)
          send_script("archgenReceive(#{literal(JSON.generate(response))})")
        end
        @dialog.show
      end
      private_class_method :attach_and_show
    end
  end
end
