# frozen_string_literal: true

module Archgen
  module Geometry
    # Lucarnes (docs/VOLETS_LUCARNES_CONTRACT.md, AG-072, ADR-47) : une par travée de la façade
    # avant, volume posé qui traverse la peau du toit sans la percer, comme une souche. Repère du
    # bâtiment : façade avant en y = 0, x le long de la façade, z vers le haut.
    module DormerSolver
      Dormer = Struct.new(:id, :x0, :x1, :y_front, :y_back, :sill_z, :window_height, :eave_z, :ridge_z, keyword_init: true)

      SETBACK_M = 0.15
      CHEEK_M = 0.10
      SILL_ABOVE_WALLS_M = 0.30
      HEAD_M = 0.15
      MAX_WINDOW_M = 1.40
      MIN_WINDOW_M = 0.60
      STEP_M = 0.05
      SPACING_M = 0.30
      INSIDE_M = 0.05
      SCAN_M = 0.01
      EPS = Core::Quant::EPSILON

      module_function

      # Résultat : Result<[Dormer]>, ou un avertissement sans lucarne sur un toit plat.
      def call(footprint:, levels:, config:, row:, blocked: [])
        roof = config['roof']
        unless %w[gable hip mansard].include?(roof['type'])
          return Core::Result.ok([], [Core::Diagnostic.warning('W_DETAIL', '/features/dormers', reason: 'dormer_flat_roof')])
        end

        top = levels.last.top_z_m
        width = config['facade']['window_width_m'] + (2 * CHEEK_M)
        planes = planes(footprint, top, roof, row)
        front_only = planes.reject { |plane| plane[:lateral] }
        problems = []
        skipped = []
        dormers = centres(footprint, config).each_with_index.filter_map do |centre, bay|
          id = "dormer/#{bay}"
          x0 = centre - (width / 2.0)
          x1 = centre + (width / 2.0)
          fitted = fit(id, x0, x1, top, roof, planes)
          unless fitted
            # Contre une croupe, la travée d'extrémité n'a pas de lucarne : omise, et dit.
            fit(id, x0, x1, top, roof, front_only) ? skipped << [id, 'hip'] : problems << problem('dormer_too_low', id)
            next
          end
          unless within(fitted, footprint, config, mitre: false)
            problems << problem('dormer_no_room', id)
            next
          end
          # Contre l'onglet d'une parcelle d'angle : omise, et dit.
          unless within(fitted, footprint, config, mitre: true)
            skipped << [id, 'corner']
            next
          end

          problems << problem('dormer_on_chimney', id) if blocked.any? { |box| overlaps?(fitted, box) }
          fitted
        end
        dormers.each_cons(2) { |a, b| problems << problem('dormer_no_room', b.id) if b.x0 - a.x1 < SPACING_M - EPS }
        return Core::Result.fail(problems.uniq { |d| [d.params['reason'], d.params['id']] }) unless problems.empty?

        warnings = skipped.group_by(&:last).map do |why, list|
          Core::Diagnostic.warning('W_DETAIL', '/features/dormers', reason: 'dormer_skipped', why: why, ids: list.map(&:first))
        end
        Core::Result.ok(dormers, warnings)
      end

      # Axes des travées de la façade avant (la trame, sans variation des baies).
      def centres(footprint, config)
        facade = config['facade']
        start, pitch = FacadeSolver.frame(footprint.facade('front'), facade['margin_m'], facade['front_bays'], config['structure']['wall_m'])
        (0...facade['front_bays']).map { |bay| start + ((bay + 0.5) * pitch) }
      end
      private_class_method :centres

      # La peau du toit est convexe : sa hauteur est le minimum de ses plans. Une rangée n'a pas de
      # pans latéraux (pignons) ; un bâtiment seul en a pour la croupe et la mansarde.
      def planes(footprint, top, roof, row)
        r = RoofSolver.slope(roof['pitch_deg'])
        w = footprint.width_m
        d = footprint.depth_m
        out = []
        add = lambda do |base, slope, axis, origin, lateral|
          out << { base: base, slope: slope, axis: axis, origin: origin, lateral: lateral }
        end
        case roof['type']
        when 'gable', 'hip'
          add.call(top, r, :y, 0.0, false)
          add.call(top, -r, :y, d, false)
          if roof['type'] == 'hip' && !row
            add.call(top, r, :x, 0.0, true)
            add.call(top, -r, :x, w, true)
          end
        when 'mansard'
          low = RoofSolver.slope(roof['lower_pitch_deg'])
          inset = roof['inset_m']
          ring = top + (low * inset)
          add.call(top, low, :y, 0.0, false)
          add.call(top, -low, :y, d, false)
          add.call(ring, r, :y, inset, false)
          add.call(ring, -r, :y, d - inset, false)
          unless row
            add.call(top, low, :x, 0.0, true)
            add.call(top, -low, :x, w, true)
            add.call(ring, r, :x, inset, true)
            add.call(ring, -r, :x, w - inset, true)
          end
        end
        out
      end
      private_class_method :planes

      def roof_z(planes, x, y)
        planes.map { |p| p[:base] + (p[:slope] * ((p[:axis] == :x ? x : y) - p[:origin])) }.min
      end
      private_class_method :roof_z

      # La plus haute fenêtre qui tient : appui au-dessus de la peau en façade, arrière du volume
      # enfoui sous la peau avant le faîtage.
      def fit(id, x0, x1, top, roof, planes)
        xc = (x0 + x1) / 2.0
        y_front = SETBACK_M
        sill = [top + SILL_ABOVE_WALLS_M, [x0, x1].map { |x| roof_z(planes, x, y_front) }.max + INSIDE_M].max
        sill = Core::Quant.q(sill)
        pitch = RoofSolver.slope(roof['pitch_deg'])
        height = MAX_WINDOW_M
        while height >= MIN_WINDOW_M - EPS
          eave = sill + height + HEAD_M
          ridge = eave + (((x1 - x0) / 2.0) * pitch)
          back = buried_at(planes, x0, xc, x1, y_front, eave, ridge)
          if back
            return Dormer.new(id: id, x0: Core::Quant.q(x0), x1: Core::Quant.q(x1), y_front: y_front, y_back: back, sill_z: sill,
                              window_height: Core::Quant.q(height), eave_z: Core::Quant.q(eave), ridge_z: Core::Quant.q(ridge))
          end

          height -= STEP_M
        end
        nil
      end
      private_class_method :fit

      def buried_at(planes, x0, xc, x1, y_front, eave, ridge)
        y = y_front + SCAN_M
        limit = planes.select { |p| p[:axis] == :y && p[:slope].negative? }.map { |p| p[:origin] }.max
        while y < limit
          inside = roof_z(planes, xc, y) >= ridge + INSIDE_M - EPS &&
                   [x0, x1].all? { |x| roof_z(planes, x, y) >= eave + INSIDE_M - EPS }
          return Core::Quant.q(y) if inside
          return nil if roof_z(planes, xc, y) < roof_z(planes, xc, y - SCAN_M) - EPS # passé le faîtage

          y += SCAN_M
        end
        nil
      end
      private_class_method :buried_at

      # Entre les marges de façade et à l'intérieur des murs latéraux, onglets compris.
      def within(dormer, footprint, config, mitre:)
        margin = config['facade']['margin_m']
        wall = config['structure']['wall_m']
        ys = mitre ? [0.0, dormer.y_back] : [0.0]
        left = [margin, ys.map { |y| footprint.left_x(y) }.max + wall].max
        right = [footprint.width_m - margin, ys.map { |y| footprint.right_x(y) }.min - wall].min
        dormer.x0 >= left - EPS && dormer.x1 <= right + EPS
      end
      private_class_method :within

      def overlaps?(dormer, box)
        (x0, x1), (y0, y1) = box
        dormer.x0 < x1 - EPS && dormer.x1 > x0 + EPS && dormer.y_front < y1 - EPS && dormer.y_back > y0 + EPS
      end
      private_class_method :overlaps?

      def problem(reason, id)
        Core::Diagnostic.error('E_OPENING_CLEARANCE', '/features/dormers', reason: reason, id: id)
      end
      private_class_method :problem

      # Volume ouvert dessous (il s'enfonce dans le toit), jour de la fenêtre laissé libre.
      def body(dormer, top, window_width, config)
        wall = config['materials']['wall']
        roof = config['materials']['roof']
        x0 = dormer.x0
        x1 = dormer.x1
        xc = Core::Quant.q((x0 + x1) / 2.0)
        xw0 = Core::Quant.q(xc - (window_width / 2.0))
        xw1 = Core::Quant.q(xc + (window_width / 2.0))
        yf = dormer.y_front
        yb = dormer.y_back
        zs = dormer.sill_z
        zt = Core::Quant.q(zs + dormer.window_height)
        ze = dormer.eave_z
        zr = dormer.ridge_z
        h = top
        mesh = MeshBuilder.new('surface')
        [
          [[[x0, yf, h], [xw0, yf, h], [xw0, yf, zt], [x0, yf, zt]], wall],
          [[[xw1, yf, h], [x1, yf, h], [x1, yf, zt], [xw1, yf, zt]], wall],
          [[[xw0, yf, h], [xw1, yf, h], [xw1, yf, zs], [xw0, yf, zs]], wall],
          [[[x0, yf, zt], [x1, yf, zt], [x1, yf, ze], [x0, yf, ze]], wall],
          [[[x0, yf, ze], [x1, yf, ze], [xc, yf, zr]], wall],
          [[[x1, yb, h], [x0, yb, h], [x0, yb, ze], [x1, yb, ze]], wall],
          [[[x1, yb, ze], [x0, yb, ze], [xc, yb, zr]], wall],
          [[[x0, yb, h], [x0, yf, h], [x0, yf, ze], [x0, yb, ze]], wall],
          [[[x1, yf, h], [x1, yb, h], [x1, yb, ze], [x1, yf, ze]], wall],
          [[[x0, yf, ze], [xc, yf, zr], [xc, yb, zr], [x0, yb, ze]], roof],
          [[[xc, yf, zr], [x1, yf, ze], [x1, yb, ze], [xc, yb, zr]], roof]
        ].each { |points, material| mesh.add_face(points, material) }
        Node.leaf(dormer.id, 'dormer', mesh.to_primitive)
      end
    end
  end
end
