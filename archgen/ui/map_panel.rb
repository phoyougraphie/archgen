# frozen_string_literal: true

require 'json'

module Archgen
  module UI
    # Extensions → ARCHGEN → Importer une carte… (docs/CARTOGRAPHIE_CONTRACT.md §5, AG-129).
    # Le téléchargement OpenStreetMap passe par Sketchup::Http, après confirmation (ADR-57).
    module MapPanel
      HTML = File.join(__dir__, 'map_panel.html')

      def self.show
        @dialog ||= ::UI::HtmlDialog.new(
          dialog_title: 'ARCHGEN : importer une carte', preferences_key: 'archgen_map_panel', scrollable: true, resizable: true,
          left: 90, top: 120, width: 420, height: 640, min_width: 340, min_height: 420, style: ::UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.visible? ? @dialog.bring_to_front : attach_and_show
      end

      def self.controller
        @controller ||= MapController.new(service: Adapters::SketchUp::MapImportService.default, registry: Composition.registry.value, ports: ports)
      end

      def self.ports
        {
          georef: -> { georef(::Sketchup.active_model) },
          pick: lambda do |kind|
            filter = kind == 'terrain' ? 'Terrain ASCII Grid|*.asc||' : 'Carte OSM ou GeoJSON|*.osm;*.geojson;*.json||'
            ::UI.openpanel(kind == 'terrain' ? 'Fichier de terrain' : 'Fichier de carte', nil, filter)
          end,
          read: ->(path) { File.binread(path) },
          confirm: ->(text) { ::UI.messagebox(text, MB_OKCANCEL) == IDOK },
          fetch: ->(request, &done) { fetch(request, &done) },
          save: ->(name, bytes) { save(name, bytes) },
          model: -> { ::Sketchup.active_model }
        }
      end

      # Origine de la carte : la géolocalisation du modèle, si elle existe.
      def self.georef(model)
        return nil unless model.respond_to?(:georeferenced?) && model.georeferenced?

        point = model.point_to_latlong(ORIGIN)
        [point.y.to_f, point.x.to_f]
      end

      # Requête Overpass ; @request garde la requête en vie jusqu'à la réponse.
      def self.fetch(request, &done)
        @request = ::Sketchup::Http::Request.new(request['url'], ::Sketchup::Http::POST)
        @request.headers = request['headers']
        @request.body = request['body']
        @request.start do |_req, response|
          done.call(response.status_code, response.body.to_s.b)
        end
      end

      # À côté du SKP, ou dans un dossier choisi si le modèle n'est pas encore enregistré.
      def self.save(name, bytes)
        path = ::Sketchup.active_model.path.to_s
        directory = path.empty? ? ::UI.select_directory(title: 'Dossier où garder l’extrait OpenStreetMap') : File.dirname(path)
        raise ArgumentError, 'Aucun dossier choisi' unless directory

        target = File.join(directory, name)
        File.binwrite(target, bytes)
        target
      end

      def self.literal(text)
        text.to_json.gsub("\u2028", '\\u2028').gsub("\u2029", '\\u2029')
      end

      def self.attach_and_show
        @dialog.set_file(HTML)
        @dialog.set_on_closed { @controller = nil }
        controller.on_downloaded = lambda do |response|
          @dialog.execute_script("archgenMapDownloaded(#{literal(JSON.generate(response))})") if @dialog&.visible?
        end
        @dialog.add_action_callback('archgen_map') do |_context, raw|
          @dialog.execute_script("archgenMapReceive(#{literal(JSON.generate(controller.dispatch(raw)))})")
        end
        @dialog.show
      end
      private_class_method :attach_and_show
    end
  end
end
