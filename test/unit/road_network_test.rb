# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/road_net'
require File.expand_path('../../archgen/ui/messages', __dir__)

# U27 : réseau et carrefour simple (docs/VOIRIE_CONTRACT.md, Carrefours ; ADR-36). Les nœuds naissent
# tout seuls ; vu de dessus, chaque point des emprises est couvert une fois et une seule ; aucune arête
# libre ni partagée par plus de deux faces ; chaque contremarche et chaque muret regarde le côté bas.
class RoadNetworkTest < Minitest::Test
  include Archgen::Core
  include RoadNet

  SUITE_SEED = 20_261_107
  BOX = [10, -40, 90, 40].freeze
  STRAIGHT = %w[ville boulevard campagne rural nationale pieton verte].freeze
  # Seconde voie partant du nœud (T) ou le traversant (X) : 90°, 79°, 53° et 127°.
  SHAPES = {
    'X 90' => [[50, -50], [50, 50]], 'T 90' => [[50, 0], [50, 50]],
    'X 79' => [[50, -50], [30, 50]], 'T 53' => [[50, 0], [80, 40]], 'T 127' => [[50, 0], [20, 40]]
  }.freeze

  def plan(tree)
    result = build(tree)
    assert result.ok?, result.errors.map(&:to_h).inspect
    result.value
  end

  def refusal(tree)
    result = build(tree)
    refute result.ok?, 'refus attendu'
    result.errors
  end

  def reasons(tree)
    refusal(tree).map { |d| d.params['reason'] }.uniq
  end

  def strips_of(roads)
    roads.map do |r|
      pts = r['road']['trace']['points_m']
      strip(pts.first, pts.last, r['road']['profile'])
    end
  end

  def assert_sealed(roads, label, box: BOX, step: 0.37)
    plan = plan(network(*roads))
    strips = strips_of(roads)
    holes = coverage_defects(plan, strips, box, step: step)
    assert_empty holes, "#{label} : points couverts 0 ou 2 fois #{holes.first(5)}"
    over, free = edge_defects(plan, strips)
    assert_equal 0, over, "#{label} : arêtes portées par plus de deux faces"
    assert_equal 0, free, "#{label} : arêtes libres dans les emprises"
    walls = misfacing_walls(plan, box)
    assert_empty walls, "#{label} : faces verticales tournées vers le haut de la marche #{walls.first(3)}"
    plan
  end

  # --- Détection

  def test_a_crossing_makes_one_four_arm_junction
    p = plan(network(road('a', [[0, 0], [100, 0]]), road('b', [[50, -50], [50, 50]])))
    assert_equal [['a@50.0+b@50.0', 4, 6.0]], p['junctions'].map { |j| j.values_at('id', 'arms', 'corner_radius_m') }
    # Rue de 13 m, arrondi de 6 m : chaque branche est coupée à 10 m du nœud (4 m de chaussée + 6 m).
    assert_equal [10.0] * 4, p['junctions'].first['cuts_m']
    assert_equal 4, p['metrics']['piece_count']
    assert_equal 2, p['metrics']['road_count']
  end

  def test_a_road_ending_on_another_makes_a_t
    p = plan(network(road('a', [[0, 0], [100, 0]]), road('b', [[50, 0], [50, 50]])))
    assert_equal [['a@50.0+b@0.0', 3]], p['junctions'].map { |j| [j['id'], j['arms']] }
    assert_equal 3, p['metrics']['piece_count']
  end

  def test_an_end_within_a_metre_snaps_onto_the_other_road
    near = plan(network(road('a', [[0, 0], [100, 0]]), road('b', [[50, 0.6], [50, 50]])))
    assert_equal 3, near['junctions'].first['arms']
    # Un croisement à 1,5 m du bout est ce bout : la voie finit au carrefour, sans moignon.
    over = plan(network(road('a', [[0, 0], [100, 0]]), road('b', [[50, -1.5], [50, 50]])))
    assert_equal [['a@50.0+b@0.0', 3]], over['junctions'].map { |j| [j['id'], j['arms']] }
  end

  def test_two_ends_meeting_make_a_two_arm_junction
    p = plan(network(road('a', [[0, 0], [50, 0]]), road('b', [[50, 0], [93.3, 25]])))
    assert_equal [['a@50.0+b@0.0', 2]], p['junctions'].map { |j| [j['id'], j['arms']] }
  end

  def test_roads_apart_make_no_junction_and_match_the_single_road
    p = plan(network(road('a', [[0, 0], [100, 0]]), road('b', [[0, 30], [100, 30]])))
    assert_empty p['junctions']
    single = RoadEngine.call(Archgen::Composition.road_intake.settings(road('a', [[0, 0], [100, 0]])['road']).value,
                             bands: C.road_bands, items: C.road_items).value
    assert_equal 2 * surface(single)['faces'].size, surface(p)['faces'].size
    assert_equal 2 * single['metrics']['item_count'], p['metrics']['item_count']
  end

  # Un premier point qui n'est pas un nombre rond (H21, grille au sixième) : ramené à l'origine de
  # sa voie sans reste, la voie est acceptée.
  def test_an_odd_first_point_is_brought_to_the_road_origin
    step = 1000.0 / 6
    p = plan(network(road('a', [[0, 0], [1000, 0]]), road('b', [[step, -100], [step, 100]])))
    assert_equal 1, p['junctions'].size
  end

  def test_two_crossings_make_two_junctions
    p = plan(network(road('a', [[0, 0], [200, 0]]), road('b', [[50, -50], [50, 50]]), road('c', [[150, -50], [150, 50]])))
    assert_equal %w[a@150.0+c@50.0 a@50.0+b@50.0], p['junctions'].map { |j| j['id'] }
    assert_equal 7, p['metrics']['piece_count']
  end

  def test_the_plan_is_deterministic
    tree = network(road('a', [[0, 0], [100, 0]]), road('b', [[50, -50], [30, 50]], 'boulevard'))
    assert_equal RoadEngine.digest(plan(tree)), RoadEngine.digest(plan(tree))
  end

  # --- Étanchéité

  def test_every_straight_profile_seals_at_every_shape
    STRAIGHT.each do |profile|
      SHAPES.each do |shape, (b0, b1)|
        assert_sealed([road('a', [[0, 0], [100, 0]], profile), road('b', [b0, b1], profile)], "#{profile} #{shape}")
      end
    end
  end

  def test_mixed_profiles_seal
    {
      'rue × boulevard' => [road('a', [[0, 0], [100, 0]]), road('b', [[50, -50], [50, 50]], 'boulevard')],
      'boulevard T rue' => [road('a', [[0, 0], [100, 0]], 'boulevard'), road('b', [[50, 0], [50, 50]])],
      'rue T chemin' => [road('a', [[0, 0], [100, 0]]), road('b', [[50, 0], [50, 50]], 'pieton')],
      'rue T campagne' => [road('a', [[0, 0], [100, 0]]), road('b', [[50, 0], [50, 50]], 'campagne')],
      'chemin × voie verte' => [road('a', [[0, 0], [100, 0]], 'pieton'), road('b', [[50, -50], [50, 50]], 'verte')],
      'cinq branches' => [road('a', [[0, 0], [100, 0]]), road('b', [[50, -50], [50, 50]]), road('c', [[50, 0], [90, 40]], 'pieton')],
      'jonction à 150°' => [road('a', [[0, 0], [50, 0]]), road('b', [[50, 0], [93.3, 25]])]
    }.each { |label, roads| assert_sealed(roads, label) }
  end

  def test_random_angles_seal
    rng = Random.new(SUITE_SEED)
    sealed = 0
    profiles = %w[ville boulevard nationale rural pieton]
    12.times do |i|
      deg = 35 + rng.rand(110)
      rad = deg * Math::PI / 180
      tee = rng.rand < 0.5
      far = [50 + (45 * Math.cos(rad)), 45 * Math.sin(rad)].map { |c| c.round(2) }
      near = tee ? [50, 0] : [50 - (45 * Math.cos(rad)), -45 * Math.sin(rad)].map { |c| c.round(2) }
      roads = [road('a', [[0, 0], [100, 0]], profiles[rng.rand(profiles.size)]), road('b', [near, far], profiles[rng.rand(profiles.size)])]
      label = "cas #{i} : #{tee ? 'T' : 'X'} à #{deg}°"
      result = build(network(*roads))
      if result.ok?
        assert_sealed(roads, label, step: 0.61)
        sealed += 1
      else
        assert_equal ['junction_shape'], result.errors.map { |d| d.params['reason'] }.uniq, label
      end
    end
    assert_operator sealed, :>=, 10
  end

  # Accotement de 0,8 m contre trottoir planté de 6 m, à 125° : aucun coin ne tient avec 6 m de rayon ;
  # le refus le dit, et un rayon de 8 m donne un carrefour étanche.
  def test_very_unequal_edges_need_a_larger_radius
    rad = 125 * Math::PI / 180
    far = [50 + (45 * Math.cos(rad)), 45 * Math.sin(rad)].map { |c| c.round(2) }
    near = [50 - (45 * Math.cos(rad)), -45 * Math.sin(rad)].map { |c| c.round(2) }
    roads = [road('a', [[0, 0], [100, 0]], 'rural'), road('b', [near, far], 'boulevard')]
    assert_equal ['junction_shape'], reasons(network(*roads))
    tree = network(*roads, junctions: [{ 'id' => 'a@50.0+b@45.0', 'corner_radius_m' => 8 }])
    strips = strips_of(roads)
    p = plan(tree)
    assert_empty coverage_defects(p, strips, BOX, step: 0.43)
    assert_equal [0, 0], edge_defects(p, strips)
  end

  def test_items_stay_out_of_the_junction
    p = plan(network(road('a', [[0, 0], [100, 0]], 'boulevard'), road('b', [[50, -50], [50, 50]], 'boulevard')))
    cut = p['junctions'].first['cuts_m'].max
    items = []
    collect = lambda do |node|
      items << node['primitive']['matrix'].values_at(12, 13) if node['primitive'] && node['primitive']['type'] == 'instance'
      node['children'].each(&collect)
    end
    p['nodes'].each(&collect)
    refute_empty items
    inside = items.select { |x, y| (x - 50).abs < cut - 1e-6 && (y.abs < cut - 1e-6) }
    assert_empty inside, "objets dans le carrefour : #{inside.first(3)}"
    assert_equal items.size, items.uniq.size
  end

  def test_corner_radius_override_widens_the_cut
    roads = [road('a', [[0, 0], [100, 0]]), road('b', [[50, -50], [50, 50]])]
    small = plan(network(*roads, junctions: [{ 'id' => 'a@50.0+b@50.0', 'corner_radius_m' => 3 }]))
    large = plan(network(*roads, junctions: [{ 'id' => 'a@50.0+b@50.0', 'corner_radius_m' => 12 }]))
    assert_equal 3.0, small['junctions'].first['corner_radius_m']
    assert_operator large['metrics']['junction_face_count'], :>, small['metrics']['junction_face_count']
    assert_operator surface(large)['vertices'].map(&:first).select { |x| x < 50 }.size, :>, 0
  end

  # --- Refus

  def test_refusals_are_localised_on_the_junction
    a = road('a', [[0, 0], [100, 0]])
    {
      'motorway_at_grade' => [road('a', [[0, 0], [100, 0]], 'autoroute'), road('b', [[50, -50], [50, 50]])],
      'arms_too_close' => [a, road('b', [[50, 0], [95.3, 21.1]])],
      'junction_on_curve' => [road('a', [[0, 0], [50, 0], [100, 30]]), road('b', [[50, -50], [50, 50]])],
      'arm_too_short' => [a, road('b', [[50, -50], [50, 4]])],
      'too_many_arms' => [road('a', [[0, 0], [100, 0]]), road('b', [[50, -50], [50, 50]]), road('c', [[10, -40], [90, 40]]),
                          road('d', [[10, 40], [90, -40]])]
    }.each do |reason, roads|
      errors = refusal(network(*roads))
      assert_equal [reason], errors.map { |d| d.params['reason'] }.uniq, reason
      assert(errors.all? { |d| d.code == 'E_ROAD_JUNCTION' && d.path.start_with?('/junctions/') }, reason)
    end
  end

  # Voie ferrée sur ballast : refusée jusqu'au passage à niveau (AG-050). Le tram : U31.
  def test_a_railway_does_not_cross_at_grade
    assert_equal ['rails_at_junction'], reasons(network(road('a', [[0, 0], [100, 0]], 'fer'), road('b', [[50, -50], [50, 50]])))
  end

  def test_junctions_too_close_name_both
    errors = refusal(network(road('a', [[0, 0], [200, 0]]), road('b', [[50, -50], [50, 50]]), road('c', [[62, -50], [62, 50]])))
    found = errors.find { |d| d.params['reason'] == 'junctions_too_close' }
    assert found, errors.map(&:to_h).inspect
    assert_equal 'a', found.params['road']
  end

  def test_intake_refusals
    a = road('a', [[0, 0], [100, 0]])
    assert_equal ['duplicate_road_id'], reasons(network(a, road('a', [[50, -50], [50, 50]])))
    assert_equal ['first_point_not_network_origin'], reasons(network(road('a', [[5, 0], [100, 0]])))
    assert_equal ['unknown_junction'], reasons(network(a, junctions: [{ 'id' => 'nulle@part' }]))
    assert_equal ['duplicate_junction'], reasons(network(a, junctions: [{ 'id' => 'x' }, { 'id' => 'x' }]))
    version = refusal(network(a).merge('network_version' => 2))
    assert_equal 'unsupported_network', version.first.params['reason']
    # Un refus de la voie garde son chemin dans le réseau.
    bad = refusal(network(a, road('b', [[50, -50], [50, 50], [60, 50]], radii: [500])))
    assert(bad.all? { |d| d.path.start_with?('/roads/1/road/') }, bad.map(&:to_h).inspect)
  end

  def test_every_junction_reason_has_a_message
    %w[unsupported_network first_point_not_network_origin duplicate_road_id duplicate_junction unknown_junction
       motorway_at_grade rails_at_junction too_many_arms arms_too_close junction_on_curve arm_too_short
       junctions_too_close junction_shape junction_levels].each do |reason|
      assert Archgen::UI::Messages::REASONS.key?(reason), reason
    end
  end
end
