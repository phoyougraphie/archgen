# frozen_string_literal: true

module Archgen
  module Core
    # Réglages propres d'une parcelle (docs/DETAILS_CONTRACT.md, AG-068, D-21) : clé facultative
    # `parcels` du format ensemble V1, `id de parcelle → réglages`. Ils passent après les réglages
    # de l'ensemble et le tirage de variété, sans changer le tirage des autres parcelles.
    module EnsembleParcels
      ID_PATTERN = %r{\A[a-z][a-z0-9_]{0,31}/\d{1,4}/\d{1,4}\z}
      MAX_ENTRIES = 512
      MIN_NEIGHBOUR_WIDTH_M = 6.0
      CONTIGUOUS_M = 1e-4
      ENTRY_SCHEMA = {
        'type' => 'object',
        'properties' => {
          'levels' => { 'type' => 'integer', 'minimum' => 1, 'maximum' => 15 },
          'roof' => { 'enum' => %w[flat gable mansard] },
          'ground_floor' => { 'enum' => %w[dwelling shop] },
          'shop' => { 'type' => 'object', 'properties' => { 'height_m' => { 'type' => 'number', 'minimum' => 3.2, 'maximum' => 6 } },
                      'additionalProperties' => false },
          'chimneys' => { 'type' => 'boolean' },
          'glazing' => { 'type' => 'boolean' },
          'muntins' => { 'type' => 'boolean' },
          'shutters' => { 'type' => 'boolean' },
          'dormers' => { 'type' => 'boolean' },
          'genoise' => { 'type' => 'boolean' },
          'stepped_gable' => { 'type' => 'boolean' },
          'cladding' => { 'type' => 'boolean' },
          'timber_frame' => { 'type' => 'boolean' },
          'classical' => { 'type' => 'boolean' },
          'pilotis' => { 'type' => 'boolean' },
          'structural_grid' => { 'type' => 'boolean' },
          'sun_shades' => { 'type' => 'boolean' },
          'shop_front' => { 'enum' => %w[none awning pergola] },
          'width_m' => { 'type' => 'number', 'minimum' => 6, 'maximum' => 60 },
          'style' => { 'type' => 'string', 'pattern' => '^[a-z][a-z0-9_]{0,63}$' },
          'style_revision' => { 'type' => 'integer', 'minimum' => 1, 'maximum' => 999999 }
        },
        'additionalProperties' => false
      }.freeze

      module_function

      def validator
        @validator ||= SchemaValidator.new(ENTRY_SCHEMA)
      end

      # Format seul, à la lecture des réglages : clés et champs connus.
      def problems(tree)
        entries = tree['parcels']
        return [] if entries.nil?
        return [error('E_SCHEMA', '/parcels', 'max_items', limit: MAX_ENTRIES)] if entries.size > MAX_ENTRIES

        entries.flat_map do |id, entry|
          path = "/parcels/#{id}"
          next [error('E_SCHEMA', path, 'pattern')] unless id.match?(ID_PATTERN)
          next [error('E_SCHEMA', path, 'empty_parcel')] if entry.is_a?(Hash) && entry.empty?

          validator.validate(entry).map { |d| Diagnostic.error(d.code, "#{path}#{d.path}", **d.params.transform_keys(&:to_sym)) }
        end
      end

      def normalize(entries)
        entries.transform_values { |entry| validator.normalize(entry) }
      end

      # Sur les parcelles définitives (accès compris) : ids connus, puis largeurs propres.
      def layout(settings, layout)
        entries = settings['parcels']
        return Result.ok(layout) if entries.nil? || entries.empty?

        parcels = layout['parcels']
        known = parcels.map { |p| p['id'] }
        unknown = (entries.keys - known).sort.map { |id| error('E_STREET_PARCEL', "/parcels/#{id}", 'unknown_parcel', id: id) }
        return Result.fail(unknown) unless unknown.empty?

        widened = widths(entries, parcels)
        widened.ok? ? Result.ok(layout.merge('parcels' => widened.value)) : widened
      end

      # D-21, A : la limite mitoyenne se déplace aux dépens de la voisine suivante du même segment,
      # la précédente pour la dernière. Ni le nombre de parcelles ni leurs ids ne changent.
      def widths(entries, parcels)
        out = parcels.map(&:dup)
        problems = []
        entries.keys.sort.each do |id|
          width = entries[id]['width_m']
          next unless width

          index = out.index { |p| p['id'] == id }
          problem = widen(out, index, Quant.q(width), entries)
          problems << problem if problem
        end
        problems.empty? ? Result.ok(out) : Result.fail(problems)
      end

      def widen(parcels, index, width, entries)
        parcel = parcels[index]
        path = "/parcels/#{parcel['id']}/width_m"
        return error('E_STREET_PARCEL', path, 'width_locked', why: 'corner') if parcel['corner']

        side, other = neighbour(parcels, index)
        return error('E_STREET_PARCEL', path, 'width_locked', why: 'no_neighbour') unless other

        neighbour = parcels[other]
        return error('E_STREET_PARCEL', path, 'width_locked', why: 'neighbour_width', other: neighbour['id']) if entries.dig(neighbour['id'], 'width_m')
        return error('E_STREET_PARCEL', path, 'width_locked', why: 'corner', other: neighbour['id']) if neighbour['corner']

        delta = width - parcel['width_m']
        rest = Quant.q(neighbour['width_m'] - delta)
        if rest < MIN_NEIGHBOUR_WIDTH_M - Quant::EPSILON
          return error('E_STREET_PARCEL', path, 'neighbour_too_narrow', other: neighbour['id'], limit: MIN_NEIGHBOUR_WIDTH_M, value: rest)
        end

        if side == :next
          parcels[index] = Geometry::ParcelLayout.reshaped(parcel, shift_m: 0.0, width_m: width)
          parcels[other] = Geometry::ParcelLayout.reshaped(neighbour, shift_m: delta, width_m: rest)
        else
          parcels[other] = Geometry::ParcelLayout.reshaped(neighbour, shift_m: 0.0, width_m: rest)
          parcels[index] = Geometry::ParcelLayout.reshaped(parcel, shift_m: -delta, width_m: width)
        end
        nil
      end
      private_class_method :widen

      # Voisine contiguë du même segment (un accès de cour entre les deux les sépare).
      def neighbour(parcels, index)
        parcel = parcels[index]
        after = parcels[index + 1]
        return [:next, index + 1] if after && contiguous?(parcel, after)

        before = index.positive? ? parcels[index - 1] : nil
        return [:previous, index - 1] if before && contiguous?(before, parcel)

        [nil, nil]
      end
      private_class_method :neighbour

      def contiguous?(first, second)
        return false unless first['row'] == second['row'] && first['segment'] == second['segment']

        end_point = Geometry::Planar.add(first['origin_m'], Geometry::Planar.scale(first['tangent'], first['width_m']))
        Geometry::Planar.length(Geometry::Planar.sub(end_point, second['origin_m'])) <= CONTIGUOUS_M
      end
      private_class_method :contiguous?

      # Après la variété : réglages propres de la parcelle, rangés pour ParcelBuilding.
      def attach(settings, parcels)
        entries = settings['parcels'] || {}
        return parcels if entries.empty?

        parcels.map { |parcel| entries[parcel['id']] ? parcel.merge('own' => entries[parcel['id']]) : parcel }
      end

      # AG-096 : le style propre d'une parcelle, révision comprise, remplace celui de la rue.
      def profile_for(own)
        return nil unless own&.dig('style')

        ref = { 'id' => own['style'] }
        own['style_revision'] ? ref.merge('revision' => own['style_revision']) : ref
      end

      # Fige la révision courante de chaque style propre qui n'en a pas (ADR-46, ADR-49).
      def pin_styles(settings, registry:)
        entries = settings['parcels']
        return settings unless entries&.any? { |_, own| own['style'] && !own['style_revision'] }

        pinned = entries.to_h do |id, own|
          next [id, own] unless own['style'] && !own['style_revision']

          revision = registry.fetch(own['style']).value&.revision
          [id, revision ? own.merge('style_revision' => revision) : own]
        end
        Canonical.deep_freeze(settings.merge('parcels' => pinned))
      end

      # Champs du brouillon de bâtiment correspondant aux réglages propres.
      def building_overrides(own)
        out = {}
        out['levels'] = { 'count' => own['levels'] } if own['levels']
        out['roof'] = { 'type' => own['roof'] } if own['roof']
        out['ground_floor'] = own['ground_floor'] if own['ground_floor']
        out['shop'] = own['shop'] if own['shop']
        features = own.slice('chimneys', 'glazing', 'muntins', 'shutters', 'dormers', 'genoise', 'stepped_gable', 'cladding', 'timber_frame', 'classical', 'pilotis', 'structural_grid', 'sun_shades', 'shop_front')
        out['features'] = features unless features.empty?
        out
      end

      # AG-069 : ce que la rue donne à cette parcelle sans ses réglages propres (valeurs grisées du
      # panneau de parcelle). Mêmes étapes que EnsembleEngine.call, sans plan.
      def street_values(settings, id, registry:, intake:)
        others = (settings['parcels'] || {}).reject { |key, _| key == id }
        street = settings.merge('parcels' => others)
        layout = EnsembleEngine.layout_for(street, registry: registry)
        return layout unless layout.ok?

        parcels = layout.value['parcels']
        parcel = parcels.find { |p| p['id'] == id }
        return Result.fail([error('E_STREET_PARCEL', "/parcels/#{id}", 'unknown_parcel', id: id)]) unless parcel

        parcel = EnsembleVariety.assign(street, parcels).find { |p| p['id'] == id } if street['variety']
        ready = ParcelBuilding.prepare(street, parcel, registry: registry, intake: intake)
        return ready unless ready.ok?

        config = ready.value.config.to_h
        Result.ok(
          'levels' => config['levels']['count'], 'roof' => config['roof']['type'],
          'ground_floor' => config.fetch('ground_floor', 'dwelling'),
          'shop_height_m' => config.dig('shop', 'height_m') || shop_default(config, registry),
          'chimneys' => config['features']['chimneys'] == true, 'glazing' => config['features']['glazing'] == true,
          'muntins' => config['features']['muntins'] == true, 'shutters' => config['features']['shutters'] == true,
          'dormers' => config['features']['dormers'] == true, 'genoise' => config['features']['genoise'] == true,
          'stepped_gable' => config['features']['stepped_gable'] == true, 'cladding' => config['features']['cladding'] == true,
          'timber_frame' => config['features']['timber_frame'] == true, 'classical' => config['features']['classical'] == true,
          'pilotis' => config['features']['pilotis'] == true, 'structural_grid' => config['features']['structural_grid'] == true,
          'sun_shades' => config['features']['sun_shades'] == true, 'shop_front' => config['features']['shop_front'] || 'none',
          'width_m' => parcel['width_m'], 'corner' => parcel['corner'] == true,
          'style' => registry.fetch(config['profile']['id'], revision: config['profile']['revision']).value&.label.to_s
        )
      end

      def shop_default(config, registry)
        profile = registry.fetch(config['profile']['id'], revision: config['profile']['revision'])
        (profile.ok? && profile.value.defaults.dig('shop', 'height_m')) || ConfigResolver::DEFAULT_SHOP_HEIGHT_M
      end
      private_class_method :shop_default

      def error(code, path, reason, **params)
        Diagnostic.error(code, path, reason: reason, **params)
      end
      private_class_method :error
    end
  end
end
