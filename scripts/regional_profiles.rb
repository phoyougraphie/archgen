# frozen_string_literal: true

# Écrit les profils régionaux de J13 (docs/STYLES_REGIONAUX_CONTRACT.md) dans examples/profiles et
# archgen/styles/profiles, à l'identique. Les profils sont des données versionnées : ce script ne
# fait que les mettre en forme ; il refuse d'écraser une révision publiée qui aurait changé.
#   ruby scripts/regional_profiles.rb provencal_mas provencal_village
require 'json'

ROOT = File.expand_path('..', __dir__)
DIRS = %w[examples/profiles archgen/styles/profiles].freeze

def rules(levels:, roofs:, ratio:, walls:)
  [
    { 'id' => 'window_proportion', 'rule' => 'window_ratio', 'params' => { 'min' => ratio[0], 'max' => ratio[1] }, 'kind' => 'historical' },
    { 'id' => 'regional_levels', 'rule' => 'level_count', 'params' => { 'min' => levels[0], 'max' => levels[1] }, 'kind' => 'historical' },
    { 'id' => 'regional_roof', 'rule' => 'roof_type', 'params' => { 'values' => roofs }, 'kind' => 'historical' },
    { 'id' => 'local_wall', 'rule' => 'material_allowed', 'params' => { 'role' => 'wall', 'values' => walls }, 'kind' => 'soft' }
  ]
end

def gable(pitch, overhang)
  { 'type' => 'gable', 'overhang_m' => overhang, 'pitch_deg' => pitch }
end

PROFILES = {
  'provencal_mas' => {
    'label' => 'Provençal — mas', 'period' => 'Mas provençal, XVIIIe-XIXe siècle', 'regions' => %w[provence], 'typologies' => %w[residential],
    'requires' => %w[gable glazing muntins shutters genoise chimneys],
    'defaults' => {
      'footprint' => { 'width_m' => 14, 'depth_m' => 9 },
      'levels' => { 'count' => 2, 'height_m' => 2.8, 'heights_m' => [] },
      'facade' => { 'front_bays' => 4, 'window_width_m' => 0.9, 'window_height_m' => 1.3, 'sill_m' => 0.9, 'entry_bay' => 1, 'door_width_m' => 1.0, 'door_height_m' => 2.2, 'muntin_rows' => 3 },
      'roof' => gable(22, 0.1),
      'materials' => { 'wall' => 'ochre_render', 'roof' => 'terracotta_canal', 'frames' => 'painted_wood', 'glass' => 'glass', 'shutters' => 'painted_wood_green' },
      'features' => { 'glazing' => true, 'muntins' => true, 'shutters' => true, 'genoise' => true, 'chimneys' => true }
    },
    'rules' => rules(levels: [1, 3], roofs: %w[gable hip], ratio: [1.2, 1.8], walls: %w[ochre_render light_render limestone])
  },
  'provencal_village' => {
    'label' => 'Provençal — maison de village', 'period' => 'Maison de village provençale, XVIIIe-XIXe siècle', 'regions' => %w[provence], 'typologies' => %w[residential mixed_use],
    'requires' => %w[gable glazing muntins shutters genoise],
    'defaults' => {
      'footprint' => { 'width_m' => 8, 'depth_m' => 9 },
      'levels' => { 'count' => 3, 'height_m' => 2.9, 'heights_m' => [] },
      'facade' => { 'front_bays' => 2, 'window_width_m' => 1.0, 'window_height_m' => 1.6, 'sill_m' => 0.9, 'entry_bay' => 0, 'door_width_m' => 1.0, 'door_height_m' => 2.3, 'muntin_rows' => 3 },
      'roof' => gable(22, 0.1),
      'materials' => { 'wall' => 'light_render', 'roof' => 'terracotta_canal', 'frames' => 'painted_wood', 'glass' => 'glass', 'shutters' => 'painted_wood_blue' },
      'features' => { 'glazing' => true, 'muntins' => true, 'shutters' => true, 'genoise' => true }
    },
    'rules' => rules(levels: [2, 4], roofs: %w[gable], ratio: [1.4, 2.0], walls: %w[ochre_render light_render limestone])
  },
  'breton_longere' => {
    'label' => 'Breton — longère', 'period' => 'Longère bretonne, XVIIIe-XIXe siècle', 'regions' => %w[bretagne], 'typologies' => %w[residential],
    'requires' => %w[gable glazing muntins dormers chimneys],
    'defaults' => {
      'footprint' => { 'width_m' => 16, 'depth_m' => 7 },
      'levels' => { 'count' => 1, 'height_m' => 2.6, 'heights_m' => [] },
      'facade' => { 'front_bays' => 4, 'window_width_m' => 0.9, 'window_height_m' => 1.2, 'sill_m' => 0.9, 'entry_bay' => 1, 'door_width_m' => 0.9, 'door_height_m' => 2.0, 'muntin_rows' => 3 },
      'structure' => { 'wall_m' => 0.5 },
      'roof' => gable(45, 0.15),
      'materials' => { 'wall' => 'granite', 'roof' => 'slate', 'frames' => 'painted_wood', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'muntins' => true, 'dormers' => true, 'chimneys' => true }
    },
    'rules' => rules(levels: [1, 2], roofs: %w[gable], ratio: [1.1, 1.8], walls: %w[granite schist light_render])
  },
  'breton_bourg' => {
    'label' => 'Breton — maison de bourg', 'period' => 'Maison de bourg bretonne, XIXe siècle', 'regions' => %w[bretagne], 'typologies' => %w[residential mixed_use],
    'requires' => %w[gable glazing muntins dormers chimneys surrounds],
    'defaults' => {
      'footprint' => { 'width_m' => 9, 'depth_m' => 8 },
      'levels' => { 'count' => 2, 'height_m' => 2.8, 'heights_m' => [] },
      'facade' => { 'front_bays' => 3, 'window_width_m' => 1.0, 'window_height_m' => 1.5, 'sill_m' => 0.9, 'entry_bay' => 1, 'door_width_m' => 1.0, 'door_height_m' => 2.2, 'muntin_rows' => 3 },
      'structure' => { 'wall_m' => 0.45 },
      'roof' => gable(45, 0.15),
      'materials' => { 'wall' => 'schist', 'roof' => 'slate', 'frames' => 'painted_wood', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'muntins' => true, 'dormers' => true, 'chimneys' => true, 'surrounds' => true }
    },
    'rules' => rules(levels: [2, 3], roofs: %w[gable], ratio: [1.3, 1.9], walls: %w[granite schist light_render])
  }
}.freeze

def document(id, spec)
  {
    'schema_version' => 1, 'id' => id, 'revision' => 1, 'kind' => 'profile', 'status' => 'active',
    'parent' => { 'id' => 'masonry_vernacular', 'revision' => 1 }, 'family_id' => 'masonry_vernacular', 'label' => spec['label'],
    'context' => { 'period' => spec['period'], 'regions' => spec['regions'], 'typologies' => spec['typologies'] },
    'requires' => spec['requires'], 'defaults' => spec['defaults'], 'rules' => spec['rules']
  }
end

ARGV.each do |id|
  spec = PROFILES.fetch(id)
  text = "#{JSON.pretty_generate(document(id, spec))}\n"
  DIRS.each do |dir|
    path = File.join(ROOT, dir, "#{id}.json")
    abort "#{path} existe déjà avec un autre contenu : nouvelle révision nécessaire" if File.exist?(path) && File.read(path, encoding: 'utf-8') != text
    File.binwrite(path, text)
  end
  puts "écrit #{id}"
end
