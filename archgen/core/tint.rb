# frozen_string_literal: true

module Archgen
  module Core
    # Teintes (docs/TEINTES_ABORDS_CONTRACT.md, AG-104, ADR-51) : chaque bâtiment tire, avec sa
    # seed, une variante `id~niveau.n` de ses matériaux de mur, menuiserie et volets, et une de
    # sa porte. La couleur se déduit du catalogue : aucun matériau n'est ajouté au fichier de styles.
    module Tint
      LEVELS = (1..3)
      VARIANTS = 8
      ROLES = %w[wall cladding frames shutters timber].freeze
      PATTERN = /\A([a-z][a-z0-9_]{0,63})~([1-3])\.([1-8])\z/
      # Écart de clarté et de chaleur par niveau, puis rang de chaque variante (de -1 à 1).
      LIGHT_STEP = 0.04
      WARM_STEP = 0.02
      LIGHT = [-1.0, -0.71, -0.43, -0.14, 0.14, 0.43, 0.71, 1.0].freeze
      WARM = [0.5, -1.0, 1.0, -0.5, 0.75, -0.25, 0.25, -0.75].freeze

      module_function

      # Entrée du moteur, teintée si `facade.tint` est posé ; sinon la même.
      def apply(input)
        level = input.dig('facade', 'tint')
        return input unless level

        materials = input['materials'].dup
        picks = ROLES.to_h { |role| [role, pick(input['seed'], role)] }
        ROLES.each { |role| materials[role] = variant(materials[role], level, picks[role]) if materials[role] }
        door = pick(input['seed'], 'door')
        door = (door % VARIANTS) + 1 if door == picks['frames']
        materials['door'] = variant(input['materials']['frames'], level, door)
        Canonical.deep_freeze(input.merge('materials' => materials))
      end

      def variant(id, level, n)
        "#{id}~#{level}.#{n}"
      end

      # Entrée de catalogue d'un matériau ou d'une de ses variantes ; nil s'il est inconnu.
      def entry(catalog, id)
        return catalog[id] if catalog.key?(id)

        match = PATTERN.match(id.to_s)
        base = match && catalog[match[1]]
        return nil unless base

        level = match[2].to_i
        n = match[3].to_i
        base.merge('label' => "#{base['label']} (teinte #{level}.#{n})", 'srgb' => srgb(base['srgb'], level, n))
      end

      def srgb(hex, level, n)
        red, green, blue = hex.delete_prefix('#').scan(/../).map { |pair| pair.to_i(16) }
        light = 1.0 + (LIGHT_STEP * level * LIGHT[n - 1])
        warm = WARM_STEP * level * WARM[n - 1]
        format('#%02x%02x%02x', *[red * light * (1 + warm), green * light, blue * light * (1 - warm)].map { |c| c.round.clamp(0, 255) })
      end

      def pick(seed, role)
        (DeterministicRandom.unit(seed, "tint/#{role}") * VARIANTS).floor + 1
      end
      private_class_method :pick
    end
  end
end
