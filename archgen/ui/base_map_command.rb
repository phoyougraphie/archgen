# frozen_string_literal: true

require 'fileutils'

module Archgen
  module UI
    # Extensions → ARCHGEN → Fond de plan (carte et photo) autour du point géolocalisé… (ADR-59).
    # Mode ultra simple : rien n'est modélisé, deux images à l'échelle au sol pour dessiner par-dessus.
    module BaseMapCommand
      SIZES = %w[200 300 400 500 750 1000].freeze
      CHOICES = { 'Carte et photo' => %w[map photo], 'Carte seule' => %w[map], 'Photo seule' => %w[photo] }.freeze

      module_function

      def run(model = ::Sketchup.active_model)
        origin = MapPanel.georef(model)
        return ::UI.messagebox(MapQuick.not_georeferenced.sub('importe les rues et les bâtiments', 'pose le fond de plan')) unless origin

        answer = ::UI.inputbox(['Côté de la zone (m)', 'Calques'], ['400', CHOICES.keys.first],
                               [SIZES.join('|'), CHOICES.keys.join('|')], 'ARCHGEN : fond de plan')
        return unless answer

        size = answer[0].to_f
        problem = Adapters::SketchUp::BaseMap.size_problem(size)
        return ::UI.messagebox(Messages.text(problem)) if problem

        plan = Adapters::SketchUp::BaseMap.plan(origin[0], origin[1], size, layers: CHOICES.fetch(answer[1]))
        return unless ::UI.messagebox(confirmation(plan, size), MB_OKCANCEL) == IDOK

        directory = File.join(cache_root(model), format('fond_%<lat>.5f_%<lon>.5f', lat: origin[0], lon: origin[1]))
        FileUtils.mkdir_p(directory)
        queue = plan.values.flat_map { |layer| layer['tiles'] }
        download(queue, directory, {}, queue.size) { |files| finish(model, plan, files, queue.size) }
      end

      def confirmation(plan, size)
        lines = plan.map do |kind, layer|
          host = Adapters::SketchUp::BaseMap::LAYERS.fetch(kind)['url'][%r{https://([^/]+)}, 1]
          "• #{layer['label']} : #{layer['tiles'].size} images depuis #{host}"
        end
        "ARCHGEN va télécharger le fond de plan d’un carré de #{size.round} m autour du point géolocalisé :\n" \
          "#{lines.join("\n")}\n\nSeules les coordonnées des images demandées sont envoyées. Continuer ?"
      end

      def cache_root(model)
        path = model.path.to_s
        path.empty? ? File.join(Dir.home, 'Documents', 'ARCHGEN') : File.dirname(path)
      end

      # Une image à la fois, comme le demandent les serveurs de tuiles ; une image déjà reçue n'est pas redemandée.
      def download(queue, directory, files, total, &done)
        if queue.empty?
          ::Sketchup.status_text = ''
          return done.call(files)
        end

        tile = queue.first
        rest = queue.drop(1)
        target = File.join(directory, tile['file'])
        if File.exist?(target) && File.size(target).positive?
          files[tile['file']] = target
          return download(rest, directory, files, total, &done)
        end

        ::Sketchup.status_text = "ARCHGEN : fond de plan, image #{total - queue.size + 1} sur #{total}"
        @request = ::Sketchup::Http::Request.new(tile['url'], ::Sketchup::Http::GET)
        @request.headers = Adapters::SketchUp::BaseMap.headers
        @request.start do |_req, response|
          body = response.body.to_s.b
          if response.status_code == 200 && !body.empty?
            File.binwrite(target, body)
            files[tile['file']] = target
          end
          ::UI.start_timer(0, false) { download(rest, directory, files, total, &done) }
        rescue StandardError
          ::UI.start_timer(0, false) { download(rest, directory, files, total, &done) }
        end
      end

      def finish(model, plan, files, total)
        frame = MapPanel.frame(model)
        result = Adapters::SketchUp::BaseMap.write(model, plan, files, frame: frame)
        return ::UI.messagebox('Le fond de plan n’a pas pu être posé : rien n’a été écrit.') unless result.ok?

        model.active_view.camera = ::Sketchup::Camera.new([0, 0, 1000], [0, 0, 0], [0, 1, 0]) rescue nil
        model.active_view.zoom_extents
        missing = total - files.size
        lines = plan.map { |kind, layer| "• #{layer['label']} : #{result.value[kind]} images (#{layer['attribution']})" }
        ::UI.messagebox("Fond de plan posé à l’échelle, au sol :\n#{lines.join("\n")}\n" \
                        "#{missing.positive? ? "#{missing} images n’ont pas pu être reçues.\n" : ''}" \
                        "\nAllumez ou éteignez chaque calque dans Fenêtre → Balises. Une seule entrée d’Annuler retire tout.")
      end
    end
  end
end
