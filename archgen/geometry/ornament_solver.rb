# frozen_string_literal: true

module Archgen
  module Geometry
    # Arcs et ornements classiques (docs/ARCS_ORNEMENTS_CONTRACT.md, AG-086, AG-087, ADR-48).
    # Rien ne déplace un percement : écoinçons, pilastres, soubassement et fronton sont posés devant le mur.
    module OrnamentSolver
      SEGMENTS = 8
      ARCH_MARGIN_M = 0.30
      SPANDREL_D_M = [-0.02, 0.0].freeze
      PILASTER_M = 0.30
      RELIEF_D_M = [-0.06, 0.0].freeze
      PLINTH_M = 0.80
      PEDIMENT_WIDEN_M = 0.60
      PEDIMENT_RISE_M = 0.50
      PEDIMENT_GAP_M = 0.15
      PEDIMENT_D_M = [-0.10, 0.0].freeze
      EPS = Core::Quant::EPSILON

      module_function

      def arched(openings)
        openings.select { |o| %w[window door].include?(o.kind) }
      end
      private_class_method :arched

      def rise(kind, width)
        kind == 'pointed' ? width * Math.sqrt(3) / 2.0 : width / 2.0
      end

      # --- Arcs

      def arch_problems(openings, config)
        kind = config['facade']['arch']
        arched(openings).filter_map do |o|
          next if o.z_max_m - o.z_min_m >= rise(kind, o.u_max_m - o.u_min_m) + ARCH_MARGIN_M - EPS

          path = o.kind == 'door' ? '/facade/door_height_m' : '/facade/window_height_m'
          Core::Diagnostic.error('E_OPENING_CLEARANCE', path, reason: 'arch_too_low', id: o.id)
        end
      end

      def arches(footprint, openings, config)
        kind = config['facade']['arch']
        material = config['materials']['wall']
        arched(openings).flat_map do |o|
          facade = footprint.facade(o.facade_id)
          curve(kind, o).each_with_index.map do |ring, n|
            Node.leaf("arch/#{o.facade_id}/#{o.level_index}/#{o.bay_index}/#{n}", 'arch', slab(facade, ring, SPANDREL_D_M, material))
          end
        end
      end

      # Bandes verticales entre l'arc et le haut de la baie, de gauche à droite.
      def curve(kind, o)
        u0 = o.u_min_m
        u1 = o.u_max_m
        width = u1 - u0
        top = o.z_max_m
        spring = top - rise(kind, width)
        left, right = if kind == 'pointed'
                        [arc([u1, spring], width, Math::PI, 2 * Math::PI / 3), arc([u0, spring], width, Math::PI / 3, 0.0)]
                      else
                        centre = [(u0 + u1) / 2.0, spring]
                        [arc(centre, width / 2.0, Math::PI, Math::PI / 2), arc(centre, width / 2.0, Math::PI / 2, 0.0)]
                      end
        (strips(left, top) + strips(right, top))
      end
      private_class_method :curve

      def arc(centre, radius, from, to)
        (0..SEGMENTS).map do |k|
          a = from + ((to - from) * k / SEGMENTS)
          [Core::Quant.q(centre[0] + (radius * Math.cos(a))), Core::Quant.q(centre[1] + (radius * Math.sin(a)))]
        end
      end
      private_class_method :arc

      def strips(points, top)
        points.each_cons(2).filter_map do |(ua, za), (ub, zb)|
          ring = [[ua, za], [ub, zb], [ub, top], [ua, top]].uniq
          ring.size >= 3 ? ring : nil
        end
      end
      private_class_method :strips

      # --- Ornements classiques, façade avant

      def classical_problems(footprint, openings, config, levels)
        facade = footprint.facade('front')
        front = openings.select { |o| o.facade_id == 'front' && o.kind != 'porch' }
        problems = pilasters(facade, config).filter_map do |span|
          hit = front.zip(front.map { |o| [occupied(o, config)] + shutter_spans(o, config) }).find { |_, spans| spans.any? { |s| overlap?(span, s) } }
          hit && Core::Diagnostic.error('E_OPENING_CLEARANCE', '/features/classical', reason: 'pilaster_no_room', id: hit[0].id)
        end
        pediment = pediment_span(front)
        if pediment
          top = pediment[2] + PEDIMENT_RISE_M
          clash = top > levels.first.top_z_m - config['structure']['slab_m'] + EPS ||
                  pilasters(facade, config).any? { |span| overlap?(span, pediment[0, 2]) }
          problems << Core::Diagnostic.error('E_OPENING_CLEARANCE', '/features/classical', reason: 'pediment_no_room') if clash
        end
        problems
      end

      # `top` : haut des murs.
      def classical(footprint, openings, config, top)
        facade = footprint.facade('front')
        material = config['materials']['wall']
        front = openings.select { |o| o.facade_id == 'front' }
        nodes = standing_pilasters(facade, config, front).each_with_index.map do |(u0, u1), n|
          Node.leaf("classical/pilaster/#{n}", 'classical', Boxes.on_facade(facade, u0, u1, PLINTH_M, top, *RELIEF_D_M, material))
        end
        plinth_spans(facade, front).each_with_index do |(u0, u1), n|
          nodes << Node.leaf("classical/plinth/#{n}", 'classical', Boxes.on_facade(facade, u0, u1, 0.0, PLINTH_M, *RELIEF_D_M, material))
        end
        pediment = pediment_span(front)
        if pediment
          u0, u1, z0 = pediment
          ring = [[u0, z0], [u1, z0], [Core::Quant.q((u0 + u1) / 2.0), Core::Quant.q(z0 + PEDIMENT_RISE_M)]]
          nodes << Node.leaf('classical/pediment', 'classical', slab(facade, ring, PEDIMENT_D_M, material))
        end
        nodes
      end

      # Un pilastre devant le passage d'un porche est omis (et dit par porch_warning).
      def standing_pilasters(facade, config, front)
        passages = front.select { |o| o.kind == 'porch' }.map { |o| [o.u_min_m, o.u_max_m] }
        pilasters(facade, config).reject { |span| passages.any? { |p| overlap?(span, p) } }
      end
      private_class_method :standing_pilasters

      def porch_warning(footprint, openings, config)
        front = openings.select { |o| o.facade_id == 'front' }
        facade = footprint.facade('front')
        return nil if standing_pilasters(facade, config, front).size == pilasters(facade, config).size

        Core::Diagnostic.warning('W_DETAIL', '/features/classical', reason: 'pilaster_porch')
      end

      # Aux deux bouts et entre deux travées de la trame avant.
      def pilasters(facade, config)
        f = config['facade']
        start, pitch = FacadeSolver.frame(facade, f['margin_m'], f['front_bays'], config['structure']['wall_m'])
        centres = (1...f['front_bays']).map { |i| start + (i * pitch) }
        spans = [[0.0, PILASTER_M], [facade.length_m - PILASTER_M, facade.length_m]]
        spans + centres.map { |c| [Core::Quant.q(c - (PILASTER_M / 2.0)), Core::Quant.q(c + (PILASTER_M / 2.0))] }
      end
      private_class_method :pilasters

      def occupied(o, config)
        off = config['features']['surrounds'] && o.kind == 'window' ? 0.04 : 0.0
        [o.u_min_m - off, o.u_max_m + off]
      end
      private_class_method :occupied

      def shutter_spans(o, config)
        return [] unless config['features']['shutters'] && o.kind == 'window'

        off = config['features']['surrounds'] ? 0.04 : 0.0
        half = (o.u_max_m - o.u_min_m) / 2.0
        [[o.u_min_m - off - half, o.u_min_m - off], [o.u_max_m + off, o.u_max_m + off + half]]
      end
      private_class_method :shutter_spans

      # Le soubassement s'interrompt au droit des baies qui descendent sous son haut.
      def plinth_spans(facade, front)
        cuts = front.select { |o| o.z_min_m < PLINTH_M - EPS }.map { |o| [o.u_min_m, o.u_max_m] }.sort
        spans = []
        cursor = 0.0
        cuts.each do |u0, u1|
          spans << [cursor, u0] if u0 - cursor > Core::Quant::MIN_EDGE_M
          cursor = [cursor, u1].max
        end
        spans << [cursor, facade.length_m] if facade.length_m - cursor > Core::Quant::MIN_EDGE_M
        spans.map { |a, b| [Core::Quant.q(a), Core::Quant.q(b)] }
      end
      private_class_method :plinth_spans

      def pediment_span(front)
        door = front.find { |o| o.kind == 'door' }
        return nil unless door

        half = ((door.u_max_m - door.u_min_m) + PEDIMENT_WIDEN_M) / 2.0
        centre = (door.u_min_m + door.u_max_m) / 2.0
        [Core::Quant.q(centre - half), Core::Quant.q(centre + half), Core::Quant.q(door.z_max_m + PEDIMENT_GAP_M)]
      end
      private_class_method :pediment_span

      def overlap?(a, b)
        a[0] < b[1] - EPS && a[1] > b[0] + EPS
      end
      private_class_method :overlap?

      # Solide fermé dans le plan de façade : face extérieure antihoraire vue du dehors.
      def slab(facade, ring, depth, material)
        front = ring.map { |u, z| facade.point(u, z, depth[0]) }
        back = ring.map { |u, z| facade.point(u, z, depth[1]) }
        mesh = MeshBuilder.new('solid')
        mesh.add_face(front, material)
        mesh.add_face(back.reverse, material)
        ring.each_index do |i|
          j = (i + 1) % ring.size
          mesh.add_face([back[i], back[j], front[j], front[i]], material)
        end
        mesh.to_primitive
      end
      private_class_method :slab
    end
  end
end
