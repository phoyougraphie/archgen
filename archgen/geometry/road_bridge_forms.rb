# frozen_string_literal: true

module Archgen
  module Geometry
    # Arc et voûte d'un pont (AG-058 ; docs/PONT_CONTRACT.md). Coordonnées dans le plan vertical de la voie
    # portée : a le long de la voie depuis le nœud, z la cote. Le gabarit se contrôle au-dessus de chaque
    # bande de circulation, de rails ou d'eau de la voie franchie. Plan pur, en mètres.
    module RoadBridgeForms
      ARCH_RISE = 0.2 # flèche = portée / 5
      RING_M = 1.0
      POST_PITCH_M = 5.0
      POST_M = 0.4
      POST_MIN_GAP_M = 0.3
      ARCH_SEGMENTS = 16
      VAULT_MAX_OPENING_M = 20.0
      PIER_M = 2.0
      KEY_M = 0.3
      VAULT_SEGMENTS = 12
      GABARIT_M = 4.5
      NAVIGATION_M = 2.5
      MAX_CLEARANCE_M = 30.0
      TRAFFIC = %w[carriageway tram rail].freeze

      Shape = Struct.new(:kind, :dh, :bottom, :spring, :rise, :openings, :piers, keyword_init: true)

      module_function

      # Forme sous le tablier pour une sous-face à la cote `bottom`.
      def shape(kind, dh, bottom)
        case kind
        when 'arch'
          spring = [bottom - (ARCH_RISE * 2 * dh), 0.0].max
          Shape.new(kind: kind, dh: dh, bottom: bottom, spring: spring, rise: bottom - spring)
        when 'vault'
          n = ((2 * dh) / VAULT_MAX_OPENING_M).ceil
          n += 1 while ((2 * dh) - ((n - 1) * PIER_M)) / n > VAULT_MAX_OPENING_M
          width = ((2 * dh) - ((n - 1) * PIER_M)) / n
          openings = (0...n).map { |k| a0 = -dh + (k * (width + PIER_M)); [a0, a0 + width] }
          piers = openings.each_cons(2).map { |(_, a1), (b0, _)| [a1, b0] }
          Shape.new(kind: kind, dh: dh, bottom: bottom, openings: openings, piers: piers)
        else
          Shape.new(kind: kind, dh: dh, bottom: bottom)
        end
      end

      def extrados(shape, a)
        shape.spring + (shape.rise * (1 - ((a / shape.dh)**2)))
      end

      # Hauteur libre sous la forme à l'abscisse a (le sol est à 0 ; la sous-face du tablier pour la poutre).
      def free_height(shape, a)
        case shape.kind
        when 'arch' then [extrados(shape, a) - RING_M, 0.0].max
        when 'vault'
          opening = shape.openings.find { |a0, a1| a >= a0 - 1e-9 && a <= a1 + 1e-9 }
          return 0.0 unless opening

          r = (opening[1] - opening[0]) / 2
          mid = (opening[0] + opening[1]) / 2
          zc = shape.bottom - KEY_M - r
          [zc + Math.sqrt([(r * r) - ((a - mid)**2), 0.0].max), 0.0].max
        else shape.bottom
        end
      end

      # Bandes à contrôler : [indice, a bas, a haut, cote exigée, circulation ?].
      def bands(under, sin, cot, over_half)
        section = under.section
        section['bands'].filter_map do |b|
          traffic = TRAFFIC.include?(b['role'])
          water = %w[water sea].include?(b['type'])
          next unless traffic || water

          u0 = under.ax - b['x1_m']
          u1 = under.ax - b['x0_m']
          spread = over_half * cot
          top = if water
                  section['water'].find { |w| w['band'] == b['index'] }['z_m']
                else
                  (b['surface'].map(&:last) + section['rails'].select { |r| r['band'] == b['index'] }.map { |r| r['z_m'] }).max
                end
          gabarit = water ? NAVIGATION_M : (b['clearance_m'] || GABARIT_M)
          [b['index'], (u0 / sin) - spread, (u1 / sin) + spread, top + gabarit, traffic]
        end
      end

      # Premier défaut de la forme au-dessus des bandes : [raison, indice de bande] ou nil.
      def problem(shape, list)
        list.each do |index, lo, hi, need, traffic|
          if shape.kind == 'vault' && traffic && shape.piers.any? { |p0, p1| p0 < hi - 1e-9 && p1 > lo + 1e-9 }
            return ['pier_on_traffic', index]
          end

          samples = [lo, hi, 0.0].select { |a| a.between?(lo, hi) }
          samples += (shape.openings || []).flat_map { |a0, a1| [a0, a1, (a0 + a1) / 2] }.select { |a| a.between?(lo, hi) }
          samples += (shape.piers || []).flatten.select { |a| a.between?(lo, hi) }
          # Une pile dans l'eau est permise : sous elle, pas de hauteur libre à tenir.
          samples.reject! { |a| (shape.piers || []).any? { |p0, p1| a > p0 + 1e-9 && a < p1 - 1e-9 } }
          return ['bridge_clearance', index] if samples.any? { |a| free_height(shape, a) < need - 1e-6 }
        end
        nil
      end

      # Contrôle d'un arc ou d'une voûte ; en cas de défaut de gabarit, la hauteur libre qui suffirait.
      def check(kind, dh, top, clearance, under, sin, cot, over_half)
        return nil if kind == 'beam'

        list = bands(under, sin, cot, over_half)
        found = problem(shape(kind, dh, top + clearance), list)
        return nil unless found

        reason, index = found
        return { reason: reason, band: index } if reason == 'pier_on_traffic'

        enough = ->(c) { problem(shape(kind, dh, top + c), list).nil? }
        return { reason: reason, band: index } unless enough.call(MAX_CLEARANCE_M)

        lo = clearance
        hi = MAX_CLEARANCE_M
        40.times do
          mid = (lo + hi) / 2
          enough.call(mid) ? hi = mid : lo = mid
        end
        { reason: reason, band: index, needed: (hi * 100).ceil / 100.0 }
      end

      # Solides sous le tablier : [nom, chaîne haute, chaîne basse], deux listes de points (a, z) aux mêmes
      # abscisses. Le plan n'admet que triangles et quadrilatères : chaque face d'about se découpe en bandes
      # entre les deux chaînes.
      def profiles(shape)
        case shape.kind
        when 'arch' then arch_profiles(shape)
        when 'vault' then vault_profiles(shape)
        else []
        end
      end

      def q2(a, z)
        [Core::Quant.q(a), Core::Quant.q(z)]
      end

      def rect(a0, a1, z0, z1)
        [[q2(a0, z1), q2(a1, z1)], [q2(a0, z0), q2(a1, z0)]]
      end

      def arch_profiles(shape)
        dh = shape.dh
        as = (0..ARCH_SEGMENTS).map { |k| -dh + (2 * dh * k / ARCH_SEGMENTS) }
        upper = as.map { |a| q2(a, extrados(shape, a)) }
        lower = as.map { |a| q2(a, [extrados(shape, a) - RING_M, 0.0].max) }
        out = [['arch', upper, lower]]
        k = 0
        ((-dh / POST_PITCH_M).ceil..(dh / POST_PITCH_M).floor).each do |i|
          a = i * POST_PITCH_M
          z = extrados(shape, a)
          next if shape.bottom - z < POST_MIN_GAP_M || (a.abs + (POST_M / 2)) > dh

          k += 1
          out << ["post/#{k}", *rect(a - (POST_M / 2), a + (POST_M / 2), z, shape.bottom)]
        end
        out
      end

      def vault_profiles(shape)
        out = shape.piers.each_with_index.map { |(p0, p1), k| ["pier/#{k + 1}", *rect(p0, p1, 0.0, shape.bottom)] }
        shape.openings.each_with_index do |(a0, a1), k|
          r = (a1 - a0) / 2
          mid = (a0 + a1) / 2
          zc = shape.bottom - KEY_M - r
          lower = (0..VAULT_SEGMENTS).map do |i|
            t = Math::PI * (VAULT_SEGMENTS - i) / VAULT_SEGMENTS
            q2(mid + (r * Math.cos(t)), [zc + (r * Math.sin(t)), 0.0].max)
          end
          upper = lower.map { |a, _| q2(a, shape.bottom) }
          out << ["spandrel/#{k + 1}", upper, lower]
        end
        out
      end
    end
  end
end
