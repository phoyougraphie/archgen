# frozen_string_literal: true

# Mesure du calcul de plan pur : 3 échauffements puis 20 passages, p95 = rang 19.
# Les cibles de sortie se mesurent en AG-018 sur le poste de référence documenté.
require 'json'
require File.expand_path('../archgen/loader', __dir__)
Archgen::Loader.load_core

include Archgen::Core

sources = Archgen::Composition.schemas
intake = Intake.new(sources)
materials = Archgen::Composition.materials.fetch('materials')
root = File.expand_path('..', __dir__)
base = intake.effective(File.read(File.join(root, 'examples/buildings/haussmann-12x9.json'), mode: 'rb', encoding: 'UTF-8')).value

scenarios = {
  'Haussmann 12x9 Shell LOD0' => { 'mode' => 'shell', 'lod' => 0 },
  'Haussmann 12x9 Structural LOD0' => { 'mode' => 'structural', 'lod' => 0 },
  '24x18 10 niv. Structural LOD0' => {
    'mode' => 'structural', 'lod' => 0, 'footprint' => { 'width_m' => 24.0, 'depth_m' => 18.0 },
    'levels' => { 'count' => 10 }, 'facade' => { 'front_bays' => 8, 'side_bays' => 4 },
    'roof' => { 'type' => 'flat', 'overhang_m' => 0.0, 'pitch_deg' => 0.0, 'lower_pitch_deg' => 0.0, 'inset_m' => 0.0 }
  }
}

puts "Ruby #{RUBY_VERSION} #{RUBY_PLATFORM}, moteur #{Archgen::ENGINE_VERSION}"
scenarios.each do |label, overrides|
  config = BuildingConfig.new(Merge.leaves(base, overrides))
  times = Array.new(23) do
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = GeometryEngine.generate(config, materials: materials)
    raise result.errors.map(&:to_h).inspect unless result.ok?

    Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  end.drop(3).sort
  plan = GeometryEngine.generate(config, materials: materials).value
  puts format('%-34s p95 %7.1f ms   %6d faces   %4d ouvertures', label, times[18] * 1000, plan['metrics']['unique_face_count'], plan['metrics']['opening_count'])
end
