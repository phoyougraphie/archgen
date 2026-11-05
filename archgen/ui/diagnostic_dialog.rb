# frozen_string_literal: true

require 'json'

module Archgen
  module UI
    # Panneau local de diagnostic (AG-002). Le vrai panneau arrive avec AG-016.
    module DiagnosticDialog
      HTML = File.join(__dir__, 'diagnostic.html')

      def self.show
        @dialog ||= build
        @dialog.visible? ? @dialog.bring_to_front : attach_and_show
      end

      # Une chaîne JSON re-encodée en littéral JS : aucune interpolation directe.
      def self.js_literal(json)
        json.to_json.gsub("\u2028", '\\u2028').gsub("\u2029", '\\u2029')
      end

      def self.report
        {
          'archgen' => VERSION,
          'engine' => ENGINE_VERSION,
          'sketchup' => ::Sketchup.version,
          'ruby' => RUBY_VERSION,
          'platform' => ::Sketchup.platform.to_s
        }
      end

      def self.build
        ::UI::HtmlDialog.new(
          dialog_title: 'ARCHGEN — Diagnostic',
          preferences_key: 'archgen_diagnostic',
          scrollable: true, resizable: true,
          width: 420, height: 320,
          style: ::UI::HtmlDialog::STYLE_DIALOG
        )
      end
      private_class_method :build

      # Les rappels sont rattachés avant chaque affichage (docs/UI_SPEC.md).
      def self.attach_and_show
        @dialog.set_file(HTML)
        @dialog.add_action_callback('archgen_ready') do |_context|
          @dialog.execute_script("archgenShow(#{js_literal(JSON.generate(report))})")
        end
        @dialog.show
      end
      private_class_method :attach_and_show
    end
  end
end
