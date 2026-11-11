# frozen_string_literal: true

module Archgen
  module UI
    # Extensions → ARCHGEN → Importer les rues et bâtiments autour du point géolocalisé (ADR-58).
    # Le modèle est géolocalisé par SketchUp (Fichier → Ajouter un emplacement) ; ARCHGEN demande la taille
    # de la zone et le style, confirme le téléchargement, montre ce qu'il a trouvé et importe d'un coup.
    module MapQuick
      SIZES = %w[200 300 400 500 750 1000].freeze

      module_function

      def run(model = ::Sketchup.active_model)
        origin = MapPanel.georef(model)
        return ::UI.messagebox(not_georeferenced) unless origin

        choice = ask_settings
        return unless choice

        size, style = choice
        controller = MapPanel.controller
        controller.on_downloaded = ->(response) { downloaded(model, response, origin, style) }
        started = controller.dispatch(envelope('download', 'lat' => origin[0], 'lon' => origin[1], 'size_m' => size))
        ::UI.messagebox(messages(started)) unless started['ok']
      end

      def not_georeferenced
        "Le modèle n’est pas géolocalisé.\n\n" \
          "1. Fichier → Ajouter un emplacement…\n" \
          "2. Cherchez l’adresse, puis cliquez sur « Définir la géolocalisation ».\n" \
          "3. Relancez cette commande : ARCHGEN importe les rues et les bâtiments autour de ce point."
      end

      # [côté en mètres, identifiant du style] ou nil.
      def ask_settings
        styles = Messages::SIGNATURES.keys.filter_map { |id| Composition.registry.value.fetch(id).value }
        labels = styles.map(&:label)
        answer = ::UI.inputbox(['Côté de la zone (m)', 'Style des bâtiments'], ['400', labels.first],
                               [SIZES.join('|'), labels.join('|')], 'ARCHGEN : rues et bâtiments OpenStreetMap')
        return nil unless answer

        [answer[0].to_f, styles[labels.index(answer[1]) || 0].id]
      end

      # Téléchargement reçu : aperçu, confirmation chiffrée, import en une opération.
      def downloaded(model, response, origin, style)
        return ::UI.messagebox(messages(response)) unless response['ok']

        controller = MapPanel.controller
        preview = controller.dispatch(envelope('preview', 'map_path' => response['result']['path'], 'lat' => origin[0], 'lon' => origin[1],
                                                          'style' => style, 'layers' => %w[roads buildings],
                                                          'source' => response['result']['source']))
        return ::UI.messagebox(messages(preview)) unless preview['ok']
        return unless ::UI.messagebox(summary(preview['result']), MB_OKCANCEL) == IDOK

        imported = controller.dispatch(envelope('import', {}))
        ::UI.messagebox(imported['ok'] ? done_text(preview['result']) : messages(imported))
        model.active_view.zoom_extents if imported['ok'] && model.respond_to?(:active_view)
      rescue StandardError => e
        ::UI.messagebox("L’import n’a pas abouti (#{e.class}) : rien n’a été écrit.")
      end

      def summary(result)
        c = result['counts']
        skipped = result['skipped'].values.sum
        "ARCHGEN a trouvé :\n• #{c['streets']} rues (à plat, chacune à sa largeur)\n• #{c['buildings']} bâtiments\n" \
          "• #{skipped} éléments écartés (types inconnus, tunnels, bâtiments non rectangulaires ou en trop)\n\n" \
          "Importer ? Une seule entrée d’Annuler retirera tout.\n\n#{result['attribution'].join(' ; ')}"
      end

      def done_text(result)
        "Import terminé : #{result['counts']['streets']} rues, #{result['counts']['buildings']} bâtiments.\n" \
          'Chaque bâtiment se modifie au clic droit. Attribution à citer : ' + result['attribution'].join(' ; ')
      end

      def messages(response)
        list = Array(response['diagnostics']).map { |d| d['message'] }
        list.empty? ? 'Opération refusée.' : list.join("\n")
      end

      def envelope(action, payload)
        JSON.generate('v' => 1, 'request_id' => "q#{action}", 'action' => action, 'payload' => payload)
      end
    end
  end
end
