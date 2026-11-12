# frozen_string_literal: true

require 'json'

module Archgen
  module UI
    # Panneau de réseau de voies (AG-048) : tracer des voies une à une, régler les carrefours, créer
    # le réseau ; ou modifier le réseau sélectionné. Toute la logique est dans NetworkController,
    # testable sans SketchUp. Fermer le panneau quitte le tracé.
    module NetworkPanel
      HTML = File.join(__dir__, 'network_panel.html')

      def self.show(mode = 'trace')
        controller.mode = mode
        @dialog ||= ::UI::HtmlDialog.new(
          dialog_title: 'ARCHGEN : réseau de voies', preferences_key: 'archgen_network_panel', scrollable: true, resizable: true,
          left: 60, top: 130, width: 1200, height: 800, min_width: 640, min_height: 480, style: ::UI::HtmlDialog::STYLE_DIALOG
        )
        visible = @dialog.visible?
        visible ? @dialog.bring_to_front : attach_and_show
        mode == 'trace' ? activate_tool : leave_tool
        send_script('archgenNetworkRestart()') if visible
      end

      def self.controller
        @controller ||= NetworkController.new(
          presets: Composition.road_presets, catalog: Composition.road_catalog,
          service: Adapters::SketchUp::NetworkService.default, session: Core::TraceSession.new,
          model_provider: -> { ::Sketchup.active_model },
          recipes: Recipes.new('road')
        )
      end

      def self.activate_tool
        tool = Adapters::SketchUp::StreetTool.new(
          session: controller.session, kind: :road,
          on_change: -> { send_script("archgenNetworkTrace(#{literal(JSON.generate(controller.trace_state))})") },
          overlay: -> { controller.overlay },
          on_deactivate: lambda {
            controller.tool_active = false
            send_script('archgenNetworkTool(false)')
          }
        )
        @tool = tool
        ::Sketchup.active_model.select_tool(tool)
        controller.tool_active = true
        send_script('archgenNetworkTool(true)')
      end

      def self.leave_tool
        ::Sketchup.active_model.select_tool(nil) if @tool
        @tool = nil
        controller.tool_active = false
      end

      def self.literal(text)
        text.to_json.gsub("\u2028", '\\u2028').gsub("\u2029", '\\u2029')
      end

      def self.send_script(script)
        @dialog&.execute_script(script)
      end

      # Le rappel de fermeture est rattaché à chaque affichage : SketchUp l'oublie à la fermeture.
      def self.attach_and_show
        @dialog.set_file(HTML)
        @dialog.set_on_closed { close_session }
        @dialog.add_action_callback('archgen_network') do |_context, raw|
          if raw == 'activate_tool'
            activate_tool
          else
            send_script("archgenNetworkReceive(#{literal(JSON.generate(controller.dispatch(raw)))})")
          end
          ::Sketchup.active_model.active_view.invalidate
        end
        watch_documents
        @dialog.show
      end
      private_class_method :attach_and_show

      def self.watch_documents
        return if @app_watcher

        @app_watcher = PanelObservers::AppWatcher.new do |_model|
          controller.document_changed
          controller.mode == 'trace' ? activate_tool : nil
          send_script('archgenNetworkRestart()')
        end
        ::Sketchup.add_observer(@app_watcher)
      end
      private_class_method :watch_documents

      def self.close_session
        controller.close_session
        ::Sketchup.remove_observer(@app_watcher) if @app_watcher
        @app_watcher = nil
        leave_tool
      end
      private_class_method :close_session
    end
  end
end
