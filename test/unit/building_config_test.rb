# frozen_string_literal: true

require_relative '../test_helper'

class BuildingConfigTest < Minitest::Test
  include Archgen::Core

  def config(overrides = {})
    base = TestData.intake.effective(TestData.building('rect-neutre-shell')).value
    BuildingConfig.new(base.merge(overrides))
  end

  def test_deeply_frozen_and_independent_of_source
    source = TestData.intake.effective(TestData.building('rect-neutre-shell')).value
    built = BuildingConfig.new(source)
    source['footprint']['width_m'] = 99.0
    assert_equal 12.0, built.dig('footprint', 'width_m')
    assert built.to_h.frozen?
    assert built.to_h['footprint'].frozen?
    assert built.to_h['levels']['heights_m'].frozen?
    assert_raises(FrozenError) { built.to_h['footprint']['width_m'] = 1.0 }
  end

  def test_geometry_digest_ignores_name_config_digest_does_not
    a = config('name' => 'A')
    b = config('name' => 'B')
    args = { engine_version: '1', material_revision: 1 }
    assert_equal a.geometry_digest(**args), b.geometry_digest(**args)
    refute_equal a.config_digest, b.config_digest
    refute_includes a.geometry_input.keys, 'name'
  end

  def test_geometry_digest_tracks_geometry_and_versions
    a = config
    b = config('seed' => 7)
    refute_equal a.geometry_digest(engine_version: '1', material_revision: 1),
                 b.geometry_digest(engine_version: '1', material_revision: 1)
    refute_equal a.geometry_digest(engine_version: '1', material_revision: 1),
                 a.geometry_digest(engine_version: '2', material_revision: 1)
    refute_equal a.geometry_digest(engine_version: '1', material_revision: 1),
                 a.geometry_digest(engine_version: '1', material_revision: 2)
  end

  # --- Contraintes transversales, bloquantes dans tous les modes

  def validate(mutator)
    data = JSON.parse(JSON.generate(config.to_h))
    mutator.call(data)
    ConstraintValidator.call(data, materials: TestData.materials)
  end

  def assert_problem(code, path, mutator)
    problems = validate(mutator)
    assert(problems.any? { |d| d.code == code && d.path == path }, "attendu #{code} #{path}, reçu #{problems.map(&:to_h)}")
  end

  def test_neutral_fixture_has_no_problem
    assert_empty validate(->(_) {})
  end

  def test_blank_name_rejected
    assert_problem 'E_SCHEMA', '/name', ->(d) { d['name'] = "  \t " }
  end

  def test_heights_must_match_count
    assert_problem 'E_SCHEMA', '/levels/heights_m', ->(d) { d['levels']['heights_m'] = [3.0, 3.0] }
  end

  def test_wall_top_budget
    assert_problem 'E_BUDGET', '/levels', ->(d) { d['levels'].merge!('count' => 11, 'height_m' => 6.0) }
    assert_empty validate(->(d) { d['levels'].merge!('count' => 10, 'height_m' => 6.0) })
  end

  def test_entry_bay_inside_front_bays
    assert_problem 'E_SCHEMA', '/facade/entry_bay', ->(d) { d['facade']['entry_bay'] = 4 }
  end

  def test_unknown_material_rejected
    assert_problem 'E_SCHEMA', '/materials/wall', ->(d) { d['materials']['wall'] = 'unobtainium' }
  end

  def test_flat_roof_keeps_angles_at_zero
    assert_problem 'E_ROOF_GEOMETRY', '/roof/pitch_deg', ->(d) { d['roof']['pitch_deg'] = 10.0 }
  end

  def test_sloped_roof_ranges
    assert_problem 'E_ROOF_GEOMETRY', '/roof/pitch_deg', ->(d) { d['roof'].merge!('type' => 'gable', 'pitch_deg' => 4.0) }
    assert_problem 'E_ROOF_GEOMETRY', '/roof/pitch_deg', ->(d) { d['roof'].merge!('type' => 'hip', 'pitch_deg' => 66.0) }
    assert_problem 'E_ROOF_GEOMETRY', '/roof/inset_m', ->(d) { d['roof'].merge!('type' => 'gable', 'pitch_deg' => 25.0, 'inset_m' => 0.5) }
  end

  def test_mansard_rules
    mansard = { 'type' => 'mansard', 'pitch_deg' => 25.0, 'lower_pitch_deg' => 65.0, 'inset_m' => 0.9 }
    assert_empty validate(->(d) { d['roof'].merge!(mansard) })
    assert_problem 'E_ROOF_GEOMETRY', '/roof/pitch_deg', ->(d) { d['roof'].merge!(mansard, 'pitch_deg' => 46.0) }
    assert_problem 'E_ROOF_GEOMETRY', '/roof/lower_pitch_deg', ->(d) { d['roof'].merge!(mansard, 'lower_pitch_deg' => 44.0) }
    assert_problem 'E_ROOF_GEOMETRY', '/roof/lower_pitch_deg', ->(d) { d['roof'].merge!(mansard, 'pitch_deg' => 45.0, 'lower_pitch_deg' => 45.0) }
    assert_problem 'E_ROOF_GEOMETRY', '/roof/inset_m', ->(d) { d['roof'].merge!(mansard, 'inset_m' => 0.0) }
    narrow = ->(d, inset) { d['footprint']['depth_m'] = 8.0; d['roof'].merge!(mansard, 'inset_m' => inset) }
    assert_problem 'E_ROOF_GEOMETRY', '/roof/inset_m', ->(d) { narrow.call(d, 3.9) }
    assert_empty validate(->(d) { narrow.call(d, 3.8) })
  end

  def test_eave_below_ground_rejected
    low = lambda do |d, overhang|
      d['levels'].merge!('count' => 1, 'height_m' => 2.2)
      d['roof'].merge!('type' => 'mansard', 'pitch_deg' => 25.0, 'lower_pitch_deg' => 65.0, 'inset_m' => 0.9, 'overhang_m' => overhang)
    end
    # tan(65°) ≈ 2,1445 : 1 m de débord reste à +0,0555 m. À 80°, la rive passe sous le sol.
    assert_empty validate(->(d) { low.call(d, 1.0) })
    assert_problem 'E_ROOF_GEOMETRY', '/roof/overhang_m', lambda { |d|
      low.call(d, 1.0)
      d['roof']['lower_pitch_deg'] = 80.0
    }
  end
end
