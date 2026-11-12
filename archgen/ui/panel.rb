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
            model_provider: -> { ::Sketchup.active_model },
            recipes: Recipes.new('building')
          )
        end
      end

      # Prévient le panneau ; le texte vient de Ruby comme tous les messages.
      def self.notify(reason)
        payload = { 'reason' => reason, 'message' => Messages::NOTICES[reason] }
        send_script("archgenNotify(#{literal(JSON.generate(payload))})")
      end

      def self.on_selection
        notify('selection') if controller.selection_changed(::Sketchup.active_model)
      end

      def self.on_transaction(reason)
        controller.invalidate
        notify(reason)
      end

      def self.on_document(model)
        controller.invalidate(document_changed: true)
        watch_model(model)
        notify('document')
      end

      def self.build
        dialog = ::UI::HtmlDialog.new(
          dialog_title: 'ARCHGEN',
          preferences_key: 'archgen_panel',
          scrollable: true, resizable: true,
          width: 1000, height: 760, min_width: 380, min_height: 480,
          style: ::UI::HtmlDialog::STYLE_DIALOG
        )
        dialog
      end
      private_class_method :build

      # Les rappels sont rattachés avant chaque affichage, celui de fermeture compris :
      # SketchUp l'oublie à la fermeture (H14). Le panneau refait `init`.
      def self.attach_and_show
        @dialog.set_file(HTML)
        @dialog.set_on_closed { close_session }
        @dialog.add_action_callback('archgen_dispatch') do |_context, raw|
          response = controller.dispatch(raw)
          send_script("archgenReceive(#{literal(JSON.generate(response))})")
        end
        start_watching
        @dialog.show
      end
      private_class_method :attach_and_show

      def self.start_watching
        return if @app_watcher

        @app_watcher = PanelObservers::AppWatcher.new { |model| on_document(model) }
        ::Sketchup.add_observer(@app_watcher)
        watch_model(::Sketchup.active_model)
      end
      private_class_method :start_watching

      def self.watch_model(model)
        stop_watching_model
        return unless model

        @model_watcher = PanelObservers::ModelWatcher.new { |reason| on_transaction(reason) }
        @selection_watcher = PanelObservers::SelectionWatcher.new { on_selection }
        model.add_observer(@model_watcher)
        model.selection.add_observer(@selection_watcher)
        @watched_model = model
      end
      private_class_method :watch_model

      def self.stop_watching_model
        return unless @watched_model

        @watched_model.remove_observer(@model_watcher)
        @watched_model.selection.remove_observer(@selection_watcher)
      rescue StandardError
        nil
      ensure
        @watched_model = nil
      end
      private_class_method :stop_watching_model

      def self.close_session
        controller.close_session
        stop_watching_model
        ::Sketchup.remove_observer(@app_watcher) if @app_watcher
        @app_watcher = nil
      end
      private_class_method :close_session
    end
  end
end
