# frozen_string_literal: true

require 'json'

module Archgen
  module UI
    # Panneau de rue et outil de tracé. Toute la logique est dans StreetController et
    # TraceSession, testables sans SketchUp. Fermer le panneau quitte le tracé.
    module StreetPanel
      HTML = File.join(__dir__, 'street_panel.html')

      # mode : 'new' active l'outil de tracé ; 'edit' relit l'ensemble sélectionné, sans outil.
      def self.show(mode = 'new')
        controller.mode = mode
        @dialog ||= ::UI::HtmlDialog.new(
          dialog_title: 'ARCHGEN : rue', preferences_key: 'archgen_street_panel', scrollable: true, resizable: true,
          # Ouverture sous les menus : au coin de l'écran, le panneau cacherait Édition.
          left: 60, top: 130, width: 420, height: 640, min_width: 340, min_height: 420, style: ::UI::HtmlDialog::STYLE_DIALOG
        )
        visible = @dialog.visible?
        visible ? @dialog.bring_to_front : attach_and_show
        mode == 'new' ? activate_tool : leave_tool
        send_script('archgenStreetRestart()') if visible
      end

      def self.leave_tool
        ::Sketchup.active_model.select_tool(nil) if @tool
        @tool = nil
        controller.tool_active = false
      end

      def self.controller
        @controller ||= StreetController.new(
          service: Adapters::SketchUp::EnsembleService.default,
          session: Core::TraceSession.new,
          registry: Composition.registry.value,
          model_provider: -> { ::Sketchup.active_model }
        )
      end

      def self.activate_tool
        tool = Adapters::SketchUp::StreetTool.new(
          session: controller.session,
          on_change: -> { push_state },
          overlay: -> { controller.overlay },
          on_deactivate: lambda {
            controller.tool_active = false
            notify_tool(false)
          }
        )
        @tool = tool
        ::Sketchup.active_model.select_tool(tool)
        controller.tool_active = true
        notify_tool(true)
      end

      def self.literal(text)
        text.to_json.gsub("\u2028", '\\u2028').gsub("\u2029", '\\u2029')
      end

      def self.send_script(script)
        @dialog&.execute_script(script)
      end

      def self.push_state
        send_script("archgenStreetState(#{literal(JSON.generate(controller.state))})")
      end

      def self.notify_tool(active)
        send_script("archgenStreetTool(#{active ? 'true' : 'false'})")
      end

      # Le rappel de fermeture est rattaché à chaque affichage : SketchUp l'oublie à la fermeture.
      def self.attach_and_show
        @dialog.set_file(HTML)
        @dialog.set_on_closed { close_session }
        @dialog.add_action_callback('archgen_street') do |_context, raw|
          if raw == 'activate_tool'
            activate_tool
          else
            send_script("archgenStreetReceive(#{literal(JSON.generate(controller.dispatch(raw)))})")
          end
          ::Sketchup.active_model.active_view.invalidate
        end
        watch_documents
        @dialog.show
      end
      private_class_method :attach_and_show

      # Le tracé vit en coordonnées d'un document : il n'en suit pas un autre.
      def self.watch_documents
        return if @app_watcher

        @app_watcher = PanelObservers::AppWatcher.new do |_model|
          controller.document_changed
          if controller.mode == 'new'
            push_state
            activate_tool
          else
            send_script('archgenStreetRestart()')
          end
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
