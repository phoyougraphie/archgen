# frozen_string_literal: true

require 'json'

module Archgen
  module UI
    # Panneau de voirie (AG-038, AG-042) : composer une coupe, tracer une voie et la créer, ou
    # modifier la voie sélectionnée. Toute la logique est dans RoadController, testable sans
    # SketchUp. Fermer le panneau quitte le tracé.
    module RoadPanel
      HTML = File.join(__dir__, 'road_panel.html')

      # mode : 'trace' active l'outil de tracé ; 'edit' relit la voie sélectionnée, sans outil.
      def self.show(mode = 'trace')
        controller.mode = mode
        @dialog ||= ::UI::HtmlDialog.new(
          dialog_title: 'ARCHGEN : voirie', preferences_key: 'archgen_road_panel', scrollable: true, resizable: true,
          left: 60, top: 130, width: 1100, height: 780, min_width: 560, min_height: 480, style: ::UI::HtmlDialog::STYLE_DIALOG
        )
        visible = @dialog.visible?
        visible ? @dialog.bring_to_front : attach_and_show
        mode == 'trace' ? activate_tool : leave_tool
        send_script('archgenRoadRestart()') if visible
      end

      def self.controller
        @controller ||= RoadController.new(
          intake: Composition.road_profile_intake, bands: Composition.road_bands,
          items: Composition.road_items, presets: Composition.road_presets,
          service: Adapters::SketchUp::RoadService.default, session: Core::TraceSession.new,
          model_provider: -> { ::Sketchup.active_model }
        )
      end

      def self.activate_tool
        tool = Adapters::SketchUp::StreetTool.new(
          session: controller.session, kind: :road,
          on_change: -> { send_script("archgenRoadTrace(#{literal(JSON.generate(controller.trace_state))})") },
          overlay: -> { controller.overlay },
          on_deactivate: lambda {
            controller.tool_active = false
            send_script('archgenRoadTool(false)')
          }
        )
        @tool = tool
        ::Sketchup.active_model.select_tool(tool)
        controller.tool_active = true
        send_script('archgenRoadTool(true)')
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
        @dialog.add_action_callback('archgen_road') do |_context, raw|
          if raw == 'activate_tool'
            activate_tool
          else
            send_script("archgenRoadReceive(#{literal(JSON.generate(controller.dispatch(raw)))})")
          end
          ::Sketchup.active_model.active_view.invalidate
        end
        watch_documents
        @dialog.show
      end
      private_class_method :attach_and_show

      # Le tracé vit dans les coordonnées d'un document : il n'en suit pas un autre.
      def self.watch_documents
        return if @app_watcher

        @app_watcher = PanelObservers::AppWatcher.new do |_model|
          controller.document_changed
          controller.mode == 'trace' ? activate_tool : nil
          send_script('archgenRoadRestart()')
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
