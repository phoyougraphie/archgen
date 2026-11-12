# frozen_string_literal: true

require_relative '../test_helper'

# U43 : rues variées, jointures à hauteurs différentes (docs/RUE_VARIEE_CONTRACT.md ; AG-062, ADR-44).
class EnsembleJointsTest < Minitest::Test
  include Archgen::Core

  TOL = 1e-5
  ROOF = %w[roof roof_face gable_end].freeze

  def registry
    @registry ||= Archgen::Composition.registry.value
  end

  def intake
    Archgen::Composition.intake
  end

  def settings(points, variety, profile: 'brutalist', closed: false, seed: 1)
    tree = { 'seed' => seed, 'trace' => { 'points_m' => points, 'closed' => closed },
             'building' => { 'profile' => { 'id' => profile } } }
    tree['variety'] = variety if variety
    r = Archgen::Composition.ensemble_intake.settings(tree)
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def plan(value)
    r = EnsembleEngine.call(value, registry: registry, intake: intake, materials: Archgen::Composition.materials.fetch('materials'))
    assert r.ok?, r.errors.map(&:to_h).inspect
    r.value
  end

  def vertices(definition, categories)
    out = []
    walk = lambda do |n, inside|
      inside ||= categories.include?(n['category'])
      out.concat(n['primitive']['vertices']) if inside && n['primitive'] && n['primitive']['vertices']
      n['children'].each { |c| walk.call(c, inside) }
    end
    definition['nodes'].each { |n| walk.call(n, false) }
    out
  end

  VARIED = { 'levels' => { 'min' => 3, 'max' => 7 }, 'roofs' => %w[flat gable mansard] }.freeze

  # Chaque toit reste entre les deux plans latéraux de sa parcelle (onglets compris) : aucune face de toit
  # n'entre chez le voisin, quelle que soit sa hauteur. Rue en coude et îlot, trois graines.
  def test_roofs_stay_between_the_side_planes_of_their_parcel
    cases = [[[[0, 0], [48, 0], [48, 48]], false, 'brutalist'], [[[0, 0], [40, 0], [40, 40], [0, 40]], true, 'toulousain']]
    cases.each do |points, closed, profile|
      variety = profile == 'toulousain' ? { 'levels' => { 'min' => 2, 'max' => 4 }, 'roofs' => %w[gable flat] } : VARIED
      (1..3).each do |seed|
        value = settings(points, variety, profile: profile, closed: closed, seed: seed)
        p = plan(value)
        layout = EnsembleEngine.layout_for(value, registry: registry).value['parcels'].to_h { |x| [x['id'], x] }
        p['parcels'].each do |entry|
          parcel = layout.fetch(entry['id'])
          w = parcel['width_m']
          d = parcel['depth_m']
          gl = parcel['delta_left_m']
          dr = parcel['delta_right_m']
          roof = vertices(p['definitions'][entry['definition_id']], ROOF)
          refute_empty roof, entry['id']
          roof.each do |x, y, _z|
            assert_operator x, :>=, (gl * y / d) - TOL, "#{entry['id']} graine #{seed} : #{[x, y].inspect}"
            assert_operator x, :<=, w - (dr * y / d) + TOL, "#{entry['id']} graine #{seed} : #{[x, y].inspect}"
          end
        end
      end
    end
  end

  # Le mur latéral d'un bâtiment monte à toute sa hauteur, quel que soit le voisin : la partie au-dessus d'un
  # voisin plus bas est le mur mitoyen découvert, aveugle (D-16).
  def test_side_walls_rise_to_their_own_height_whatever_the_neighbour
    p = plan(settings([[0, 0], [72, 0]], { 'levels' => { 'min' => 2, 'max' => 7, 'max_step' => 5 } }))
    tops = p['parcels'].map { |e| p['definitions'][e['definition_id']]['metrics']['wall_top_z_m'] }
    assert_operator tops.uniq.size, :>, 1
    p['parcels'].each do |e|
      definition = p['definitions'][e['definition_id']]
      walls = vertices(definition, %w[walls wall])
      assert_in_delta definition['metrics']['wall_top_z_m'], walls.map { |v| v[2] }.max, TOL, e['id']
    end
  end

  # Étagement : une plateforme par parcelle, qui ne dépend que du terrain ; varier les hauteurs n'y change rien.
  def test_terrain_steps_are_unchanged_by_the_variety
    slope = ->(x, _y) { 100.0 + (0.05 * x) }
    platforms = [nil, VARIED].map do |variety|
      value = settings([[0, 0], [48, 0]], variety)
      p = plan(value)
      layout = EnsembleEngine.layout_for(value, registry: registry).value
      site = Archgen::Composition.site_intake.settings({}).value
      requests = EnsembleSite.requests(p, layout, site).value
      grids = requests.to_h do |request|
        axes = request['axes']
        m = request['matrix']
        rows = axes['ys_m'].map { |y| axes['xs_m'].map { |x| slope.call((m[0] * x) + (m[4] * y) + m[12], 0) } }
        [request['id'], Archgen::Composition.site_intake.parcel_grid({ 'schema_version' => 1, 'xs_m' => axes['xs_m'], 'ys_m' => axes['ys_m'], 'z_m' => rows }, axes).value]
      end
      r = EnsembleSite.call(settings: value, site: site, plan: p, layout: layout, grids: grids, root_z_m: 100.0, registry: registry, intake: intake,
                            materials: Archgen::Composition.site_materials)
      assert r.ok?, r.errors.map(&:to_h).inspect
      r.value['parcels'].map { |x| x['platform_z_m'] }
    end
    assert_equal platforms.first, platforms.last
  end
end
