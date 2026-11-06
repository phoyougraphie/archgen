# frozen_string_literal: true

module Archgen
  module Adapters
    module SketchUp
      # Outil de tracé au geste du Mur connecté de YSKE. Ne décide de rien : les points vont à
      # Core::TraceSession, le jugement au contrôleur. Aucune écriture dans le modèle : ce qui
      # est visible pendant le tracé n'existe que dans la vue.
      class StreetTool
        INCH = 0.0254
        CLOSE_PIXELS = 10.0
        KEY_LEFT = defined?(::VK_LEFT) ? ::VK_LEFT : 37
        KEY_RIGHT = defined?(::VK_RIGHT) ? ::VK_RIGHT : 39
        KEY_DOWN = defined?(::VK_DOWN) ? ::VK_DOWN : 40
        KEY_CTRL = defined?(::COPY_MODIFIER_KEY) ? ::COPY_MODIFIER_KEY : 17
        KEY_ALT = defined?(::ALT_MODIFIER_KEY) ? ::ALT_MODIFIER_KEY : 18
        LOCK_KEYS = { KEY_RIGHT => 'red', KEY_LEFT => 'green', KEY_DOWN => 'prev' }.freeze
        LOCK_LABELS = { 'red' => 'axe rouge', 'green' => 'axe vert', 'prev' => 'perpendiculaire ou prolongement' }.freeze
        SIDE_LABELS = { 'left' => 'à gauche du tracé', 'right' => 'à droite du tracé', 'both' => 'des deux côtés' }.freeze
        TRACE_RGB = [0, 120, 215].freeze
        LOCK_RGB = { 'red' => [220, 0, 0], 'green' => [0, 160, 0], 'prev' => [200, 0, 200] }.freeze
        PARCEL_RGB = [90, 90, 90].freeze
        REFUSED_RGB = [200, 40, 40].freeze

        # on_change : le tracé a changé. overlay : contours des parcelles et état, en mètres.
        def initialize(session:, on_change:, overlay:, host: NativeHost, on_deactivate: nil)
          @session = session
          @on_change = on_change
          @overlay = overlay
          @host = host
          @on_deactivate = on_deactivate
          @mouse = nil
        end

        def activate
          @ip = @host.input_point
          update_ui
          @host.active_view&.invalidate
        end

        def deactivate(view)
          @on_deactivate&.call
          view.invalidate
        end

        def resume(view)
          update_ui
          view.invalidate
        end

        def enableVCB?
          true
        end

        def onMouseMove(_flags, x, y, view)
          @ip.pick(view, x, y)
          @mouse = mouse_point(view, x, y)
          update_ui
          view.tooltip = @ip.tooltip if @ip.valid?
          view.invalidate
        end

        def onLButtonDown(_flags, x, y, view)
          @ip.pick(view, x, y)
          return start_trace(view, x, y) if @session.empty? || @session.finished?
          return closed(view) if near_first?(view, x, y) && @session.close

          add_point(mouse_point(view, x, y), view)
        end

        # Le premier clic a déjà posé le point : le double-clic ne fait que terminer.
        def onLButtonDoubleClick(_flags, _x, _y, view)
          finish(view)
        end

        # Échap : termine le tracé en cours ; sur un tracé terminé, l'oublie.
        def onCancel(_reason, view)
          if @session.finished?
            @session.clear
            changed(view)
          else
            finish(view)
          end
        end

        def onUserText(text, view)
          return refuse('Cliquez d’abord le point de départ.') if @session.empty? || @session.finished?

          parsed = Core::TraceSession.parse_typed(text, ->(value) { @host.parse_length_m(value) })
          return refuse('Tapez « longueur » ou « longueur;angle ».') unless parsed

          point = @session.typed(parsed[0], parsed[1], @mouse)
          return refuse('Bougez la souris pour donner la direction.') unless point

          add_point(point, view)
        end

        def onKeyDown(key, repeat, _flags, view)
          return false unless repeat == 1

          case key
          when KEY_CTRL then side_changed(view)
          when KEY_ALT then @session.toggle_90
          else
            kind = LOCK_KEYS[key]
            return false unless kind
            unless @session.toggle_lock(kind)
              refuse('Flèche bas : il faut un segment précédent.')
              return true
            end
          end
          update_ui
          view.invalidate
          true
        end

        # Sans étendue, SketchUp coupe ce qui sort du modèle.
        def getExtents
          points = @session.points.map { |p| model_point(p) }
          points << model_point(@mouse) if @mouse && !@session.finished? && !@session.empty?
          overlay.fetch(:rings, []).each { |ring| ring.each { |p| points << model_point(p) } }
          @host.bounding_box(points)
        end

        def draw(view)
          draw_parcels(view)
          draw_trace(view)
          @ip.draw(view) if @ip&.display?
        end

        private

        def overlay
          @overlay.call || {}
        end

        def start_trace(view, x, y)
          return unless @ip.valid?

          position = @ip.position
          @session.start(position.x * INCH, position.y * INCH, position.z * INCH)
          @mouse = mouse_point(view, x, y)
          changed(view)
        end

        def add_point(point, view)
          return unless point

          @session.add(point) ? changed(view) : view.invalidate
        end

        def closed(view)
          @mouse = nil
          changed(view)
        end

        def finish(view)
          @session.finish
          @mouse = nil
          changed(view)
        end

        def side_changed(view)
          @session.cycle_side
          changed(view)
        end

        def changed(view)
          @on_change.call
          update_ui
          view.invalidate
        end

        # Sur un sommet existant, sa position ; sinon le plan du premier point. Un point visé à une
        # autre altitude est ainsi ramené dans ce plan, le long du rayon de vue.
        def mouse_point(view, x, y)
          drawing = !@session.empty? && !@session.finished?
          z = drawing ? @session.z_m : 0.0
          raw = if @ip.valid? && @ip.degrees_of_freedom.zero?
                  [@ip.position.x * INCH, @ip.position.y * INCH]
                else
                  hit = @host.plane_hit(view, x, y, z / INCH)
                  hit && [hit.x * INCH, hit.y * INCH]
                end
          raw && drawing ? @session.constrain(raw) : raw
        end

        def near_first?(view, x, y)
          first = @session.points.first
          return false unless first

          screen = view.screen_coords(model_point(first))
          Math.hypot(screen.x - x, screen.y - y) <= CLOSE_PIXELS
        end

        def model_point(point)
          @host.point(point[0] / INCH, point[1] / INCH, @session.z_m / INCH)
        end

        def draw_parcels(view)
          data = overlay
          rings = data.fetch(:rings, [])
          return if rings.empty?

          view.line_width = 1
          view.drawing_color = @host.color(*(data[:refused] ? REFUSED_RGB : PARCEL_RGB))
          rings.each { |ring| view.draw(@host.gl_line_loop, ring.map { |p| model_point(p) }) }
        end

        def draw_trace(view)
          points = @session.points.map { |p| model_point(p) }
          return if points.empty?

          view.line_width = 2
          view.drawing_color = @host.color(*TRACE_RGB)
          points += [points.first] if @session.closed?
          view.draw(@host.gl_line_strip, points) if points.size > 1
          view.draw_points([points.first], 10, 1, @host.color(*TRACE_RGB))
          draw_rubber(view, points.last)
        end

        def draw_rubber(view, from)
          return if @session.finished? || @mouse.nil?

          to = model_point(@mouse)
          view.line_width = @session.axis_lock ? 4 : 1
          view.drawing_color = @host.color(*(LOCK_RGB[@session.axis_lock] || TRACE_RGB))
          view.draw(@host.gl_lines, [from, to])
        end

        def update_ui
          @host.status(status_text)
          @host.vcb(vcb_label, vcb_value)
        end

        def status_text
          options = "Flèches : axes. #{SIDE_LABELS.fetch(@session.side)} (Ctrl), 90° #{@session.lock_90 ? 'verrouillé' : 'libre'} (Alt)."
          return "Cliquez le départ de la rue. #{options}" if @session.empty?
          return 'Tracé terminé : vérifiez le panneau, puis créez. Échap efface, un clic recommence.' if @session.finished?

          lock = @session.axis_lock ? "Bloqué : #{LOCK_LABELS.fetch(@session.axis_lock)}. " : ''
          "#{lock}Cliquez le point suivant, ou tapez « longueur » ou « longueur;angle ». Double-clic ou Échap pour finir. #{options}"
        end

        def vcb_label
          'Longueur;angle'
        end

        def vcb_value
          return '' unless @mouse && !@session.empty? && !@session.finished?

          last = @session.points.last
          @host.format_length(Math.hypot(@mouse[0] - last[0], @mouse[1] - last[1]) / INCH)
        end

        def refuse(message)
          @host.beep
          @host.status(message)
          nil
        end
      end
    end
  end
end
