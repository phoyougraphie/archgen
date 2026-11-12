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
  },
  'lyonnais' => {
    'label' => 'Lyonnais', 'period' => 'Immeuble lyonnais, XIXe siècle (Croix-Rousse, Presqu\'île)', 'regions' => %w[lyon], 'typologies' => %w[residential mixed_use],
    'requires' => %w[gable glazing muntins shutters surrounds],
    'defaults' => {
      'footprint' => { 'width_m' => 12, 'depth_m' => 11 },
      'levels' => { 'count' => 5, 'height_m' => 3.0, 'heights_m' => [] },
      'facade' => { 'front_bays' => 4, 'window_width_m' => 1.1, 'window_height_m' => 1.9, 'sill_m' => 0.7, 'entry_bay' => 1, 'door_width_m' => 1.2, 'door_height_m' => 2.6, 'muntin_rows' => 4 },
      'roof' => gable(20, 0.3),
      'materials' => { 'wall' => 'golden_stone', 'roof' => 'terracotta_canal', 'frames' => 'painted_wood', 'glass' => 'glass', 'shutters' => 'painted_wood_grey' },
      'features' => { 'glazing' => true, 'muntins' => true, 'shutters' => true, 'surrounds' => true }
    },
    'rules' => rules(levels: [4, 7], roofs: %w[gable hip], ratio: [1.5, 2.2], walls: %w[golden_stone light_render ochre_render])
  },
  'bordelais_echoppe' => {
    'label' => 'Bordelais — échoppe', 'period' => 'Échoppe bordelaise, XIXe-début XXe siècle', 'regions' => %w[bordeaux], 'typologies' => %w[residential],
    'requires' => %w[flat glazing muntins surrounds cornice],
    'defaults' => {
      'footprint' => { 'width_m' => 7, 'depth_m' => 12 },
      'levels' => { 'count' => 1, 'height_m' => 3.6, 'heights_m' => [] },
      'facade' => { 'front_bays' => 2, 'window_width_m' => 1.1, 'window_height_m' => 2.2, 'sill_m' => 0.6, 'entry_bay' => 0, 'door_width_m' => 1.1, 'door_height_m' => 2.8, 'muntin_rows' => 3 },
      'roof' => { 'type' => 'flat', 'overhang_m' => 0.0, 'pitch_deg' => 0 },
      'materials' => { 'wall' => 'blond_stone', 'roof' => 'zinc', 'frames' => 'painted_wood', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'muntins' => true, 'surrounds' => true, 'cornice' => true }
    },
    'rules' => rules(levels: [1, 2], roofs: %w[flat gable], ratio: [1.6, 2.4], walls: %w[blond_stone limestone])
  },
  'parisien_faubourien' => {
    'label' => 'Parisien faubourien', 'period' => 'Immeuble de faubourg parisien, XVIIIe-XIXe siècle', 'regions' => %w[paris], 'typologies' => %w[residential mixed_use],
    'requires' => %w[gable glazing muntins shutters surrounds],
    'defaults' => {
      'footprint' => { 'width_m' => 10, 'depth_m' => 9 },
      'levels' => { 'count' => 4, 'height_m' => 3.0, 'heights_m' => [] },
      'facade' => { 'front_bays' => 3, 'window_width_m' => 1.0, 'window_height_m' => 1.7, 'sill_m' => 0.9, 'entry_bay' => 1, 'door_width_m' => 1.1, 'door_height_m' => 2.4, 'muntin_rows' => 3 },
      'roof' => gable(30, 0.2),
      'materials' => { 'wall' => 'light_render', 'roof' => 'mechanical_tile', 'frames' => 'painted_wood', 'glass' => 'glass', 'shutters' => 'painted_wood_grey' },
      'features' => { 'glazing' => true, 'muntins' => true, 'shutters' => true, 'surrounds' => true }
    },
    'rules' => rules(levels: [3, 6], roofs: %w[gable mansard], ratio: [1.4, 2.0], walls: %w[light_render ochre_render limestone])
  },
  'flamand' => {
    'label' => 'Flamand', 'period' => 'Maison de ville flamande, XVIIe-XIXe siècle', 'regions' => %w[flandre], 'typologies' => %w[residential mixed_use],
    'requires' => %w[gable cross_ridge stepped_gable glazing muntins surrounds],
    'defaults' => {
      'footprint' => { 'width_m' => 7, 'depth_m' => 12 },
      'levels' => { 'count' => 3, 'height_m' => 3.0, 'heights_m' => [] },
      'facade' => { 'front_bays' => 2, 'window_width_m' => 1.1, 'window_height_m' => 1.9, 'sill_m' => 0.8, 'entry_bay' => 0, 'door_width_m' => 1.1, 'door_height_m' => 2.6, 'muntin_rows' => 4 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.0, 'pitch_deg' => 50, 'ridge' => 'perpendicular' },
      'materials' => { 'wall' => 'red_brick', 'roof' => 'mechanical_tile', 'frames' => 'painted_wood', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'muntins' => true, 'surrounds' => true, 'stepped_gable' => true }
    },
    'rules' => rules(levels: [2, 5], roofs: %w[gable], ratio: [1.4, 2.2], walls: %w[red_brick brick_foraine])
  },
  'savoyard_chalet' => {
    'label' => 'Savoyard — chalet', 'period' => 'Chalet savoyard, XIXe-XXe siècle', 'regions' => %w[savoie], 'typologies' => %w[residential],
    'requires' => %w[gable cross_ridge cladding balcony shutters glazing muntins],
    'defaults' => {
      'footprint' => { 'width_m' => 10, 'depth_m' => 10 },
      'levels' => { 'count' => 3, 'height_m' => 2.7, 'heights_m' => [] },
      'facade' => { 'front_bays' => 3, 'window_width_m' => 0.9, 'window_height_m' => 1.2, 'sill_m' => 0.9, 'entry_bay' => 1, 'door_width_m' => 1.0, 'door_height_m' => 2.1, 'muntin_rows' => 3 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 1.0, 'pitch_deg' => 25, 'ridge' => 'perpendicular' },
      'materials' => { 'wall' => 'limestone', 'roof' => 'slate', 'frames' => 'painted_wood', 'glass' => 'glass', 'shutters' => 'dark_wood', 'cladding' => 'natural_wood' },
      'features' => { 'glazing' => true, 'muntins' => true, 'shutters' => true, 'cladding' => true, 'balcony' => true }
    },
    'rules' => rules(levels: [2, 4], roofs: %w[gable], ratio: [1.1, 1.6], walls: %w[limestone granite light_render])
  },
  'colombages' => {
    'label' => 'Maison à colombages', 'period' => 'Maison à pan de bois, XVe-XVIIIe siècle', 'regions' => %w[france], 'typologies' => %w[residential mixed_use], 'family' => 'timber_vernacular',
    'requires' => %w[gable timber_frame glazing muntins],
    'defaults' => {
      'footprint' => { 'width_m' => 9, 'depth_m' => 9 },
      'levels' => { 'count' => 3, 'height_m' => 2.8, 'heights_m' => [] },
      'facade' => { 'front_bays' => 3, 'window_width_m' => 1.0, 'window_height_m' => 1.4, 'sill_m' => 0.9, 'entry_bay' => 1, 'door_width_m' => 1.0, 'door_height_m' => 2.1, 'muntin_rows' => 3 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.3, 'pitch_deg' => 45 },
      'materials' => { 'wall' => 'light_render', 'roof' => 'mechanical_tile', 'frames' => 'painted_wood', 'glass' => 'glass', 'timber' => 'dark_wood' },
      'features' => { 'glazing' => true, 'muntins' => true, 'timber_frame' => true }
    },
    'rules' => rules(levels: [2, 4], roofs: %w[gable hip], ratio: [1.2, 1.8], walls: %w[light_render ochre_render])
  },
  'normand' => {
    'label' => 'Normand', 'period' => 'Maison normande à pan de bois, XVIe-XIXe siècle', 'regions' => %w[normandie], 'typologies' => %w[residential mixed_use], 'family' => 'timber_vernacular',
    'requires' => %w[gable timber_frame dormers chimneys glazing muntins],
    'defaults' => {
      'footprint' => { 'width_m' => 10, 'depth_m' => 8 },
      'levels' => { 'count' => 2, 'height_m' => 2.7, 'heights_m' => [] },
      'facade' => { 'front_bays' => 3, 'window_width_m' => 0.9, 'window_height_m' => 1.3, 'sill_m' => 0.9, 'entry_bay' => 1, 'door_width_m' => 1.0, 'door_height_m' => 2.1, 'muntin_rows' => 3 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.3, 'pitch_deg' => 50 },
      'materials' => { 'wall' => 'light_render', 'roof' => 'slate', 'frames' => 'painted_wood', 'glass' => 'glass', 'timber' => 'dark_wood' },
      'features' => { 'glazing' => true, 'muntins' => true, 'timber_frame' => true, 'dormers' => true, 'chimneys' => true }
    },
    'rules' => rules(levels: [1, 3], roofs: %w[gable hip], ratio: [1.2, 1.8], walls: %w[light_render])
  },
  'alsacien' => {
    'label' => 'Alsacien', 'period' => 'Maison alsacienne à colombages, XVIe-XIXe siècle', 'regions' => %w[alsace], 'typologies' => %w[residential mixed_use], 'family' => 'timber_vernacular',
    'requires' => %w[gable timber_frame dormers glazing muntins],
    'defaults' => {
      'footprint' => { 'width_m' => 10, 'depth_m' => 10 },
      'levels' => { 'count' => 3, 'height_m' => 2.7, 'heights_m' => [] },
      'facade' => { 'front_bays' => 3, 'window_width_m' => 0.9, 'window_height_m' => 1.3, 'sill_m' => 0.9, 'entry_bay' => 1, 'door_width_m' => 1.0, 'door_height_m' => 2.1, 'muntin_rows' => 3 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.3, 'pitch_deg' => 55 },
      'materials' => { 'wall' => 'ochre_render', 'roof' => 'mechanical_tile', 'frames' => 'painted_wood', 'glass' => 'glass', 'timber' => 'dark_wood' },
      'features' => { 'glazing' => true, 'muntins' => true, 'timber_frame' => true, 'dormers' => true }
    },
    'rules' => rules(levels: [2, 4], roofs: %w[gable], ratio: [1.2, 1.8], walls: %w[ochre_render light_render])
  },
  'basque' => {
    'label' => 'Basque', 'period' => 'Maison basque (etxe), XVIIe-XIXe siècle', 'regions' => %w[pays_basque], 'typologies' => %w[residential mixed_use], 'family' => 'timber_vernacular',
    'requires' => %w[gable cross_ridge timber_frame glazing muntins],
    'defaults' => {
      'footprint' => { 'width_m' => 10, 'depth_m' => 12 },
      'levels' => { 'count' => 3, 'height_m' => 2.8, 'heights_m' => [] },
      'facade' => { 'front_bays' => 3, 'window_width_m' => 1.0, 'window_height_m' => 1.4, 'sill_m' => 0.9, 'entry_bay' => 1, 'door_width_m' => 1.0, 'door_height_m' => 2.1, 'muntin_rows' => 3 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.6, 'pitch_deg' => 30, 'ridge' => 'perpendicular' },
      'materials' => { 'wall' => 'light_render', 'roof' => 'terracotta_canal', 'frames' => 'painted_wood', 'glass' => 'glass', 'timber' => 'painted_wood_red' },
      'features' => { 'glazing' => true, 'muntins' => true, 'timber_frame' => true }
    },
    'rules' => rules(levels: [2, 4], roofs: %w[gable], ratio: [1.2, 1.8], walls: %w[light_render])
  },
  'maison_romane' => {
    'label' => 'Maison romane', 'period' => 'Maison de ville romane, XIIe siècle', 'regions' => %w[france], 'typologies' => %w[residential mixed_use], 'family' => 'historic_monumental',
    'requires' => %w[gable arches glazing],
    'defaults' => {
      'footprint' => { 'width_m' => 8, 'depth_m' => 9 },
      'levels' => { 'count' => 2, 'height_m' => 3.0, 'heights_m' => [] },
      'facade' => { 'front_bays' => 2, 'window_width_m' => 0.7, 'window_height_m' => 1.3, 'sill_m' => 1.0, 'entry_bay' => 1, 'door_width_m' => 1.0, 'door_height_m' => 2.4, 'arch' => 'round' },
      'structure' => { 'wall_m' => 0.6 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.2, 'pitch_deg' => 30 },
      'materials' => { 'wall' => 'limestone', 'roof' => 'terracotta_canal', 'frames' => 'painted_wood', 'glass' => 'glass' },
      'features' => { 'glazing' => true }
    },
    'rules' => rules(levels: [1, 3], roofs: %w[gable], ratio: [1.4, 2.2], walls: %w[limestone granite])
  },
  'maison_gothique' => {
    'label' => 'Maison gothique', 'period' => 'Maison de ville gothique, XIIIe-XVe siècle', 'regions' => %w[france], 'typologies' => %w[residential mixed_use], 'family' => 'historic_monumental',
    'requires' => %w[gable cross_ridge arches glazing muntins],
    'defaults' => {
      'footprint' => { 'width_m' => 7, 'depth_m' => 10 },
      'levels' => { 'count' => 3, 'height_m' => 3.2, 'heights_m' => [] },
      'facade' => { 'front_bays' => 2, 'window_width_m' => 0.9, 'window_height_m' => 2.0, 'sill_m' => 0.8, 'entry_bay' => 1, 'door_width_m' => 1.1, 'door_height_m' => 2.6, 'muntin_rows' => 3, 'arch' => 'pointed' },
      'structure' => { 'wall_m' => 0.5 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.1, 'pitch_deg' => 55, 'ridge' => 'perpendicular' },
      'materials' => { 'wall' => 'limestone', 'roof' => 'slate', 'frames' => 'painted_wood', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'muntins' => true }
    },
    'rules' => rules(levels: [2, 5], roofs: %w[gable], ratio: [1.6, 2.6], walls: %w[limestone])
  },
  'renaissance' => {
    'label' => 'Renaissance', 'period' => 'Hôtel urbain Renaissance, XVIe siècle', 'regions' => %w[france], 'typologies' => %w[residential mixed_use], 'family' => 'ordered_facade',
    'requires' => %w[gable glazing muntins surrounds dormers],
    'defaults' => {
      'footprint' => { 'width_m' => 12, 'depth_m' => 10 },
      'levels' => { 'count' => 3, 'height_m' => 3.3, 'heights_m' => [] },
      'facade' => { 'front_bays' => 4, 'window_width_m' => 1.2, 'window_height_m' => 2.0, 'sill_m' => 0.8, 'entry_bay' => 2, 'door_width_m' => 1.2, 'door_height_m' => 2.6, 'muntin_rows' => 2 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.2, 'pitch_deg' => 50 },
      'materials' => { 'wall' => 'blond_stone', 'roof' => 'slate', 'frames' => 'painted_wood', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'muntins' => true, 'surrounds' => true, 'dormers' => true }
    },
    'rules' => rules(levels: [2, 4], roofs: %w[gable hip], ratio: [1.4, 2.0], walls: %w[blond_stone limestone])
  },
  'neoclassique' => {
    'label' => 'Néoclassique', 'period' => 'Immeuble néoclassique, fin XVIIIe-début XIXe siècle', 'regions' => %w[france], 'typologies' => %w[residential mixed_use], 'family' => 'ordered_facade',
    'requires' => %w[gable classical cornice glazing muntins],
    'defaults' => {
      'footprint' => { 'width_m' => 14, 'depth_m' => 10 },
      'levels' => { 'count' => 4, 'height_m' => 3.2, 'heights_m' => [] },
      'facade' => { 'front_bays' => 5, 'window_width_m' => 1.1, 'window_height_m' => 2.0, 'sill_m' => 0.8, 'entry_bay' => 2, 'door_width_m' => 1.2, 'door_height_m' => 2.3, 'muntin_rows' => 3 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.3, 'pitch_deg' => 20 },
      'materials' => { 'wall' => 'limestone', 'roof' => 'slate', 'frames' => 'painted_wood', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'muntins' => true, 'classical' => true, 'cornice' => true }
    },
    'rules' => rules(levels: [3, 6], roofs: %w[hip gable], ratio: [1.6, 2.2], walls: %w[limestone blond_stone])
  },
  'baroque' => {
    'label' => 'Baroque', 'period' => 'Hôtel baroque, XVIIe-XVIIIe siècle', 'regions' => %w[france], 'typologies' => %w[residential mixed_use], 'family' => 'ordered_facade',
    'requires' => %w[mansard classical cornice arches glazing muntins],
    'defaults' => {
      'footprint' => { 'width_m' => 14, 'depth_m' => 11 },
      'levels' => { 'count' => 4, 'height_m' => 3.3, 'heights_m' => [] },
      'facade' => { 'front_bays' => 5, 'window_width_m' => 1.1, 'window_height_m' => 2.2, 'sill_m' => 0.7, 'entry_bay' => 2, 'door_width_m' => 1.2, 'door_height_m' => 2.4, 'muntin_rows' => 3, 'arch' => 'round' },
      'roof' => { 'type' => 'mansard', 'overhang_m' => 0.15, 'pitch_deg' => 25, 'lower_pitch_deg' => 65, 'inset_m' => 0.9 },
      'materials' => { 'wall' => 'golden_stone', 'roof' => 'slate', 'frames' => 'painted_wood', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'muntins' => true, 'classical' => true, 'cornice' => true }
    },
    'rules' => rules(levels: [3, 5], roofs: %w[mansard], ratio: [1.6, 2.4], walls: %w[golden_stone blond_stone limestone])
  },
  'art_deco' => {
    'label' => 'Art déco', 'period' => 'Immeuble Art déco, 1920-1939', 'regions' => %w[france], 'typologies' => %w[residential mixed_use], 'family' => 'ornamental',
    'requires' => %w[flat classical cornice glazing muntins],
    'defaults' => {
      'footprint' => { 'width_m' => 14, 'depth_m' => 12 },
      'levels' => { 'count' => 6, 'height_m' => 3.0, 'heights_m' => [] },
      'facade' => { 'front_bays' => 5, 'window_width_m' => 1.4, 'window_height_m' => 1.8, 'sill_m' => 0.9, 'entry_bay' => 2, 'door_width_m' => 1.2, 'door_height_m' => 2.1, 'muntin_rows' => 3 },
      'roof' => { 'type' => 'flat', 'overhang_m' => 0.0, 'pitch_deg' => 0 },
      'materials' => { 'wall' => 'concrete', 'roof' => 'concrete', 'frames' => 'painted_wood', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'muntins' => true, 'classical' => true, 'cornice' => true }
    },
    'rules' => rules(levels: [4, 8], roofs: %w[flat], ratio: [1.0, 1.6], walls: %w[concrete light_render])
  },
  'art_nouveau' => {
    'label' => 'Art nouveau', 'period' => 'Immeuble Art nouveau, 1895-1914', 'regions' => %w[france], 'typologies' => %w[residential mixed_use], 'family' => 'ornamental',
    'requires' => %w[mansard arches balcony glazing muntins],
    'defaults' => {
      'footprint' => { 'width_m' => 12, 'depth_m' => 11 },
      'levels' => { 'count' => 5, 'height_m' => 3.2, 'heights_m' => [] },
      'facade' => { 'front_bays' => 4, 'window_width_m' => 1.2, 'window_height_m' => 2.0, 'sill_m' => 0.8, 'entry_bay' => 2, 'door_width_m' => 1.2, 'door_height_m' => 2.5, 'muntin_rows' => 3, 'arch' => 'round' },
      'roof' => { 'type' => 'mansard', 'overhang_m' => 0.15, 'pitch_deg' => 25, 'lower_pitch_deg' => 65, 'inset_m' => 0.9 },
      'materials' => { 'wall' => 'blond_stone', 'roof' => 'zinc', 'frames' => 'painted_wood', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'muntins' => true, 'balcony' => true }
    },
    'rules' => rules(levels: [4, 7], roofs: %w[mansard], ratio: [1.4, 2.2], walls: %w[blond_stone limestone])
  },
  'mediterraneen_cycladique' => {
    'label' => 'Méditerranéen — cycladique', 'period' => 'Maison des Cyclades, XIXe-XXe siècle', 'regions' => %w[cyclades], 'typologies' => %w[residential mixed_use], 'family' => 'masonry_vernacular',
    'requires' => %w[flat arches shutters glazing],
    'defaults' => {
      'footprint' => { 'width_m' => 8, 'depth_m' => 8 },
      'levels' => { 'count' => 2, 'height_m' => 2.8, 'heights_m' => [] },
      'facade' => { 'front_bays' => 2, 'window_width_m' => 0.8, 'window_height_m' => 1.3, 'sill_m' => 0.9, 'entry_bay' => 1, 'door_width_m' => 0.9, 'door_height_m' => 2.2, 'arch' => 'round' },
      'roof' => { 'type' => 'flat', 'overhang_m' => 0.0, 'pitch_deg' => 0 },
      'materials' => { 'wall' => 'light_render', 'roof' => 'light_render', 'frames' => 'painted_wood', 'glass' => 'glass', 'shutters' => 'painted_wood_blue' },
      'features' => { 'glazing' => true, 'shutters' => true }
    },
    'rules' => rules(levels: [1, 3], roofs: %w[flat], ratio: [1.3, 2.0], walls: %w[light_render])
  },
  'mediterraneen_andalou' => {
    'label' => 'Méditerranéen — andalou', 'period' => 'Maison andalouse, XVIIIe-XIXe siècle', 'regions' => %w[andalousie], 'typologies' => %w[residential mixed_use], 'family' => 'masonry_vernacular',
    'requires' => %w[gable arches shutters glazing],
    'defaults' => {
      'footprint' => { 'width_m' => 10, 'depth_m' => 10 },
      'levels' => { 'count' => 2, 'height_m' => 3.0, 'heights_m' => [] },
      'facade' => { 'front_bays' => 3, 'window_width_m' => 1.0, 'window_height_m' => 1.6, 'sill_m' => 0.9, 'entry_bay' => 1, 'door_width_m' => 1.1, 'door_height_m' => 2.4, 'arch' => 'round' },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.3, 'pitch_deg' => 20 },
      'materials' => { 'wall' => 'light_render', 'roof' => 'terracotta_canal', 'frames' => 'painted_wood', 'glass' => 'glass', 'shutters' => 'painted_wood_green' },
      'features' => { 'glazing' => true, 'shutters' => true }
    },
    'rules' => rules(levels: [1, 3], roofs: %w[hip gable], ratio: [1.3, 2.0], walls: %w[light_render ochre_render])
  },
  'bauhaus' => {
    'label' => 'Bauhaus', 'period' => 'Architecture Bauhaus, 1919-1933', 'regions' => %w[europe], 'typologies' => %w[residential mixed_use], 'family' => 'modern_modular',
    'requires' => %w[flat ribbon glazing],
    'defaults' => {
      'footprint' => { 'width_m' => 14, 'depth_m' => 10 },
      'levels' => { 'count' => 3, 'height_m' => 3.0, 'heights_m' => [] },
      'facade' => { 'front_bays' => 4, 'window_width_m' => 1.4, 'window_height_m' => 1.2, 'sill_m' => 0.9, 'entry_bay' => 2, 'door_width_m' => 1.0, 'door_height_m' => 2.2, 'ribbon' => 'band' },
      'roof' => { 'type' => 'flat', 'overhang_m' => 0.0, 'pitch_deg' => 0 },
      'materials' => { 'wall' => 'light_render', 'roof' => 'concrete', 'frames' => 'dark_metal', 'glass' => 'glass' },
      'features' => { 'glazing' => true }
    },
    'rules' => rules(levels: [2, 5], roofs: %w[flat], ratio: [0.4, 1.2], walls: %w[light_render concrete])
  },
  'moderniste' => {
    'label' => 'Moderniste', 'period' => 'Mouvement moderne, 1925-1960', 'regions' => %w[europe], 'typologies' => %w[residential mixed_use], 'family' => 'modern_modular',
    'requires' => %w[flat ribbon pilotis glazing],
    'defaults' => {
      'footprint' => { 'width_m' => 16, 'depth_m' => 11 },
      'levels' => { 'count' => 4, 'height_m' => 3.0, 'heights_m' => [] },
      'facade' => { 'front_bays' => 5, 'window_width_m' => 1.4, 'window_height_m' => 1.3, 'sill_m' => 0.9, 'entry_bay' => 2, 'door_width_m' => 1.0, 'door_height_m' => 2.2, 'ribbon' => 'band' },
      'roof' => { 'type' => 'flat', 'overhang_m' => 0.0, 'pitch_deg' => 0 },
      'materials' => { 'wall' => 'concrete', 'roof' => 'concrete', 'frames' => 'dark_metal', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'pilotis' => true }
    },
    'rules' => rules(levels: [2, 8], roofs: %w[flat], ratio: [0.4, 1.2], walls: %w[concrete light_render])
  },
  'mid_century' => {
    'label' => 'Mid-century', 'period' => 'Architecture mid-century, 1945-1970', 'regions' => %w[europe], 'typologies' => %w[residential mixed_use], 'family' => 'modern_modular',
    'requires' => %w[flat ribbon glazing],
    'defaults' => {
      'footprint' => { 'width_m' => 14, 'depth_m' => 10 },
      'levels' => { 'count' => 2, 'height_m' => 2.8, 'heights_m' => [] },
      'facade' => { 'front_bays' => 4, 'window_width_m' => 1.6, 'window_height_m' => 1.8, 'sill_m' => 0.6, 'entry_bay' => 2, 'door_width_m' => 1.0, 'door_height_m' => 2.2, 'ribbon' => 'band' },
      'roof' => { 'type' => 'flat', 'overhang_m' => 1.0, 'pitch_deg' => 0 },
      'materials' => { 'wall' => 'red_brick', 'roof' => 'concrete', 'frames' => 'dark_metal', 'glass' => 'glass' },
      'features' => { 'glazing' => true }
    },
    'rules' => rules(levels: [1, 3], roofs: %w[flat gable], ratio: [0.4, 1.4], walls: %w[red_brick natural_wood light_render])
  },
  'minimaliste' => {
    'label' => 'Contemporain minimaliste', 'period' => 'Architecture contemporaine, depuis 1990', 'regions' => %w[europe], 'typologies' => %w[residential mixed_use], 'family' => 'modern_modular',
    'requires' => %w[flat ribbon glazing],
    'defaults' => {
      'footprint' => { 'width_m' => 12, 'depth_m' => 10 },
      'levels' => { 'count' => 3, 'height_m' => 3.0, 'heights_m' => [] },
      'facade' => { 'front_bays' => 4, 'window_width_m' => 1.4, 'window_height_m' => 2.0, 'sill_m' => 0.6, 'entry_bay' => 2, 'door_width_m' => 1.1, 'door_height_m' => 2.4, 'ribbon' => 'curtain' },
      'roof' => { 'type' => 'flat', 'overhang_m' => 0.0, 'pitch_deg' => 0 },
      'materials' => { 'wall' => 'light_render', 'roof' => 'concrete', 'frames' => 'dark_metal', 'glass' => 'glass' },
      'features' => { 'glazing' => true }
    },
    'rules' => rules(levels: [2, 6], roofs: %w[flat], ratio: [0.4, 2.0], walls: %w[light_render concrete])
  },
  'industriel' => {
    'label' => 'Industriel', 'period' => 'Bâtiment industriel, 1880-1960', 'regions' => %w[europe], 'typologies' => %w[residential mixed_use], 'family' => 'tech_environment',
    'requires' => %w[sawtooth glazing muntins],
    'defaults' => {
      'footprint' => { 'width_m' => 16, 'depth_m' => 12 },
      'levels' => { 'count' => 2, 'height_m' => 4.5, 'heights_m' => [] },
      'facade' => { 'front_bays' => 4, 'window_width_m' => 1.6, 'window_height_m' => 2.4, 'sill_m' => 1.0, 'entry_bay' => 2, 'door_width_m' => 2.4, 'door_height_m' => 3.4, 'muntin_rows' => 4 },
      'roof' => { 'type' => 'sawtooth', 'overhang_m' => 0.0, 'pitch_deg' => 30 },
      'materials' => { 'wall' => 'red_brick', 'roof' => 'dark_metal', 'frames' => 'dark_metal', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'muntins' => true }
    },
    'rules' => rules(levels: [1, 3], roofs: %w[sawtooth flat gable], ratio: [1.0, 1.6], walls: %w[red_brick concrete])
  },
  'high_tech' => {
    'label' => 'High-tech', 'period' => 'Architecture high-tech, depuis 1970', 'regions' => %w[europe], 'typologies' => %w[residential mixed_use], 'family' => 'tech_environment',
    'requires' => %w[flat ribbon structural_grid glazing],
    'defaults' => {
      'footprint' => { 'width_m' => 14, 'depth_m' => 12 },
      'levels' => { 'count' => 5, 'height_m' => 3.2, 'heights_m' => [] },
      'facade' => { 'front_bays' => 4, 'window_width_m' => 1.4, 'window_height_m' => 2.0, 'sill_m' => 0.6, 'entry_bay' => 2, 'door_width_m' => 1.2, 'door_height_m' => 2.4, 'ribbon' => 'curtain' },
      'roof' => { 'type' => 'flat', 'overhang_m' => 0.0, 'pitch_deg' => 0 },
      'materials' => { 'wall' => 'dark_metal', 'roof' => 'dark_metal', 'frames' => 'dark_metal', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'structural_grid' => true }
    },
    'rules' => rules(levels: [3, 8], roofs: %w[flat], ratio: [0.4, 2.0], walls: %w[dark_metal concrete])
  },
  'bioclimatique' => {
    'label' => 'Bioclimatique', 'period' => 'Architecture bioclimatique, depuis 1975', 'regions' => %w[europe], 'typologies' => %w[residential mixed_use], 'family' => 'tech_environment',
    'requires' => %w[gable cladding sun_shades glazing],
    'defaults' => {
      'footprint' => { 'width_m' => 12, 'depth_m' => 10 },
      'levels' => { 'count' => 3, 'height_m' => 2.8, 'heights_m' => [] },
      'facade' => { 'front_bays' => 4, 'window_width_m' => 1.4, 'window_height_m' => 1.6, 'sill_m' => 0.8, 'entry_bay' => 2, 'door_width_m' => 1.0, 'door_height_m' => 2.2 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.6, 'pitch_deg' => 25 },
      'materials' => { 'wall' => 'light_render', 'roof' => 'dark_metal', 'frames' => 'dark_metal', 'glass' => 'glass', 'cladding' => 'natural_wood' },
      'features' => { 'glazing' => true, 'cladding' => true, 'sun_shades' => true }
    },
    'rules' => rules(levels: [1, 4], roofs: %w[gable flat], ratio: [0.8, 1.6], walls: %w[light_render natural_wood])
  },
  # AG-133 (ADR-61) : styles côtiers de la presqu'île guérandaise.
  'baule_front_de_mer' => {
    'label' => 'Côtier — front de mer (La Baule)', 'period' => 'Immeuble balnéaire du front de mer, 1960 à aujourd\'hui', 'regions' => %w[loire_atlantique], 'typologies' => %w[residential mixed_use], 'family' => 'modern_modular',
    'requires' => %w[flat balcony glazing],
    'defaults' => {
      'footprint' => { 'width_m' => 22, 'depth_m' => 14 },
      'levels' => { 'count' => 8, 'height_m' => 2.8, 'heights_m' => [], 'attic_setback_m' => 2.5 },
      'facade' => { 'front_bays' => 6, 'window_width_m' => 2.0, 'window_height_m' => 2.2, 'sill_m' => 0.3, 'entry_bay' => 2, 'door_width_m' => 1.4, 'door_height_m' => 2.4 },
      'shop' => { 'height_m' => 3.6 },
      'roof' => { 'type' => 'flat', 'overhang_m' => 0.0, 'pitch_deg' => 0 },
      'materials' => { 'wall' => 'light_render', 'roof' => 'concrete', 'frames' => 'painted_wood', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'balcony' => true, 'balcony_levels' => 'all', 'balcony_depth_m' => 1.8, 'balcony_rail' => 'glass' }
    },
    'rules' => rules(levels: [4, 12], roofs: %w[flat], ratio: [0.8, 1.6], walls: %w[light_render concrete])
  },
  'maison_moderne' => {
    'label' => 'Maison individuelle moderne', 'period' => 'Maison individuelle contemporaine, depuis 2000', 'regions' => %w[france], 'typologies' => %w[residential], 'family' => 'modern_modular',
    'requires' => %w[flat cladding glazing],
    'defaults' => {
      'footprint' => { 'width_m' => 12, 'depth_m' => 9 },
      'levels' => { 'count' => 2, 'height_m' => 2.7, 'heights_m' => [] },
      'facade' => { 'front_bays' => 3, 'window_width_m' => 1.8, 'window_height_m' => 2.1, 'sill_m' => 0.3, 'entry_bay' => 1, 'door_width_m' => 1.0, 'door_height_m' => 2.2 },
      'roof' => { 'type' => 'flat', 'overhang_m' => 0.0, 'pitch_deg' => 0 },
      'materials' => { 'wall' => 'light_render', 'roof' => 'concrete', 'frames' => 'dark_metal', 'glass' => 'glass', 'cladding' => 'natural_wood' },
      'features' => { 'glazing' => true, 'cladding' => true }
    },
    'rules' => rules(levels: [1, 2], roofs: %w[flat gable], ratio: [0.5, 1.6], walls: %w[light_render concrete natural_wood])
  },
  'baule_villa' => {
    'label' => 'Côtier — villa balnéaire (La Baule, Pornichet)', 'period' => 'Villa balnéaire néo-régionaliste, 1880-1939', 'regions' => %w[loire_atlantique], 'typologies' => %w[residential], 'family' => 'timber_vernacular',
    'requires' => %w[gable cross_ridge timber_frame glazing muntins chimneys],
    'defaults' => {
      'footprint' => { 'width_m' => 10, 'depth_m' => 11 },
      'levels' => { 'count' => 2, 'height_m' => 2.9, 'heights_m' => [] },
      'facade' => { 'front_bays' => 3, 'window_width_m' => 1.0, 'window_height_m' => 1.5, 'sill_m' => 0.9, 'entry_bay' => 1, 'door_width_m' => 1.0, 'door_height_m' => 2.2, 'muntin_rows' => 3 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.6, 'pitch_deg' => 50, 'ridge' => 'perpendicular' },
      'materials' => { 'wall' => 'light_render', 'roof' => 'slate', 'frames' => 'painted_wood', 'glass' => 'glass', 'timber' => 'dark_wood' },
      'features' => { 'glazing' => true, 'muntins' => true, 'timber_frame' => true, 'chimneys' => true }
    },
    'rules' => rules(levels: [1, 3], roofs: %w[gable hip], ratio: [1.1, 1.8], walls: %w[light_render red_brick granite])
  },
  # AG-142 (ADR-67) : maisons traditionnelles de La Baule et Pornichet, d'après les photos du propriétaire.
  # Une palette par style : chaque maison tire sa variante avec sa graine (AG-141).
  'baule_villa.r2' => {
    'id' => 'baule_villa', 'revision' => 2,
    'label' => 'Côtier — villa balnéaire (La Baule, Pornichet)', 'period' => 'Villa balnéaire néo-régionaliste, 1880-1939', 'regions' => %w[loire_atlantique], 'typologies' => %w[residential mixed_use], 'family' => 'timber_vernacular',
    'requires' => %w[gable cross_ridge timber_frame glazing muntins chimneys surrounds],
    'defaults' => {
      'footprint' => { 'width_m' => 9, 'depth_m' => 10 },
      'levels' => { 'count' => 2, 'height_m' => 2.9, 'heights_m' => [] },
      'facade' => { 'front_bays' => 3, 'window_width_m' => 1.0, 'window_height_m' => 1.5, 'sill_m' => 0.9, 'entry_bay' => 1, 'door_width_m' => 1.0, 'door_height_m' => 2.2, 'muntin_rows' => 3 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.6, 'pitch_deg' => 50, 'ridge' => 'perpendicular' },
      'materials' => { 'wall' => 'light_render', 'roof' => 'slate', 'frames' => 'painted_wood', 'glass' => 'glass', 'timber' => 'painted_wood_red' },
      'features' => { 'glazing' => true, 'muntins' => true, 'timber_frame' => true, 'chimneys' => true }
    },
    # Pan de bois et encadrements occupent la même épaisseur : une variante prend l'un ou l'autre.
    'palette' => [
      {},
      { 'materials' => { 'wall' => 'granite' }, 'features' => { 'turret' => true } },
      { 'materials' => { 'timber' => 'dark_wood' } },
      { 'materials' => { 'timber' => 'painted_wood_green' } },
      { 'materials' => { 'surrounds' => 'red_brick' }, 'features' => { 'timber_frame' => false, 'surrounds' => true, 'string_courses' => true } },
      { 'materials' => { 'wall' => 'granite', 'surrounds' => 'light_render' }, 'features' => { 'timber_frame' => false, 'surrounds' => true, 'turret' => true } }
    ],
    'rules' => rules(levels: [1, 3], roofs: %w[gable hip], ratio: [1.1, 1.8], walls: %w[light_render red_brick granite])
  },
  'baule_villa_toit' => {
    'label' => 'Côtier — villa à quatre pans (La Baule)', 'period' => 'Villa balnéaire, 1900-1950', 'regions' => %w[loire_atlantique], 'typologies' => %w[residential], 'family' => 'masonry_vernacular',
    'requires' => %w[hip glazing muntins shutters surrounds chimneys dormers],
    'defaults' => {
      'footprint' => { 'width_m' => 11, 'depth_m' => 9 },
      'levels' => { 'count' => 2, 'height_m' => 2.9, 'heights_m' => [] },
      'facade' => { 'front_bays' => 3, 'window_width_m' => 1.1, 'window_height_m' => 1.5, 'sill_m' => 0.8, 'entry_bay' => 1, 'door_width_m' => 1.0, 'door_height_m' => 2.2, 'muntin_rows' => 2 },
      'roof' => { 'type' => 'hip', 'overhang_m' => 0.4, 'pitch_deg' => 35 },
      'materials' => { 'wall' => 'light_render', 'roof' => 'slate', 'frames' => 'painted_wood', 'glass' => 'glass', 'shutters' => 'painted_wood_red', 'surrounds' => 'granite' },
      'features' => { 'glazing' => true, 'muntins' => true, 'shutters' => true, 'surrounds' => true, 'chimneys' => true }
    },
    'palette' => [
      {},
      { 'materials' => { 'shutters' => 'painted_wood_blue' }, 'features' => { 'dormers' => true, 'wall_dormers' => true } },
      { 'materials' => { 'shutters' => 'painted_wood_green', 'surrounds' => 'red_brick' }, 'features' => { 'string_courses' => true } },
      { 'materials' => { 'shutters' => 'painted_wood_blue', 'surrounds' => 'red_brick' }, 'features' => { 'turret' => true, 'string_courses' => true } },
      { 'materials' => { 'shutters' => 'painted_wood_grey', 'wall' => 'granite', 'surrounds' => 'light_render' }, 'features' => { 'turret' => true } },
      { 'materials' => { 'shutters' => 'painted_wood_red', 'surrounds' => 'red_brick' }, 'features' => { 'dormers' => true, 'wall_dormers' => true, 'string_courses' => true } }
    ],
    'rules' => rules(levels: [1, 3], roofs: %w[hip gable], ratio: [1.1, 1.8], walls: %w[light_render granite])
  },
  'baule_maison_de_ville' => {
    'label' => 'Côtier — maison de ville (La Baule)', 'period' => 'Maison de ville balnéaire, 1900-1939', 'regions' => %w[loire_atlantique], 'typologies' => %w[residential mixed_use], 'family' => 'masonry_vernacular',
    'requires' => %w[gable glazing muntins surrounds dormers chimneys],
    'defaults' => {
      'footprint' => { 'width_m' => 8, 'depth_m' => 10 },
      'levels' => { 'count' => 2, 'height_m' => 3.0, 'heights_m' => [] },
      'facade' => { 'front_bays' => 2, 'window_width_m' => 1.1, 'window_height_m' => 1.6, 'sill_m' => 0.9, 'entry_bay' => 0, 'door_width_m' => 1.0, 'door_height_m' => 2.3, 'muntin_rows' => 2 },
      'shop' => { 'height_m' => 3.6 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.3, 'pitch_deg' => 45 },
      'materials' => { 'wall' => 'granite', 'roof' => 'slate', 'frames' => 'painted_wood', 'glass' => 'glass', 'surrounds' => 'red_brick' },
      'features' => { 'glazing' => true, 'muntins' => true, 'surrounds' => true, 'dormers' => true, 'chimneys' => true, 'wall_dormers' => true, 'string_courses' => true }
    },
    'palette' => [
      {},
      { 'materials' => { 'wall' => 'light_render' }, 'features' => { 'balconettes' => true } },
      { 'materials' => { 'wall' => 'light_render', 'surrounds' => 'granite' } },
      { 'materials' => { 'surrounds' => 'light_render' }, 'features' => { 'balconettes' => true, 'string_courses' => false } },
      { 'materials' => { 'wall' => 'schist' }, 'features' => { 'wall_dormers' => false } }
    ],
    'rules' => rules(levels: [2, 4], roofs: %w[gable], ratio: [1.2, 1.8], walls: %w[granite light_render schist])
  },
  # AG-144 (ADR-69) : édifices religieux, à placer comme bâtiments seuls. Nef à pignon sur rue, baies en
  # arc sur les murs latéraux, clocher, abside au chevet, transept pour les grands édifices.
  'chapelle' => {
    'label' => 'Chapelle', 'period' => 'Chapelle de campagne, XVe-XVIIe siècle', 'regions' => %w[bretagne france], 'typologies' => %w[religious], 'family' => 'historic_monumental',
    'requires' => %w[gable cross_ridge arches glazing bell_tower apse],
    'defaults' => {
      'footprint' => { 'width_m' => 7, 'depth_m' => 14 },
      'levels' => { 'count' => 1, 'height_m' => 5.5, 'heights_m' => [] },
      'facade' => { 'front_bays' => 1, 'side_bays' => 3, 'window_width_m' => 0.8, 'window_height_m' => 2.2, 'sill_m' => 1.8, 'entry_bay' => 0, 'door_width_m' => 1.4, 'door_height_m' => 2.8, 'arch' => 'pointed' },
      'structure' => { 'wall_m' => 0.6 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.2, 'pitch_deg' => 50, 'ridge' => 'perpendicular' },
      'materials' => { 'wall' => 'granite', 'roof' => 'slate', 'frames' => 'dark_wood', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'bell_tower' => 'porch', 'apse' => true }
    },
    'palette' => [{}, { 'materials' => { 'wall' => 'schist' } }, { 'materials' => { 'wall' => 'light_render' } }, { 'materials' => { 'wall' => 'limestone' } }],
    'rules' => rules(levels: [1, 1], roofs: %w[gable], ratio: [2.0, 3.5], walls: %w[granite schist light_render limestone])
  },
  'eglise_romane' => {
    'label' => 'Église romane', 'period' => 'Église romane, XIe-XIIe siècle', 'regions' => %w[france], 'typologies' => %w[religious], 'family' => 'historic_monumental',
    'requires' => %w[gable cross_ridge arches glazing bell_tower apse],
    'defaults' => {
      'footprint' => { 'width_m' => 11, 'depth_m' => 26 },
      'levels' => { 'count' => 2, 'height_m' => 5.0, 'heights_m' => [] },
      'facade' => { 'front_bays' => 1, 'side_bays' => 5, 'window_width_m' => 1.0, 'window_height_m' => 2.0, 'sill_m' => 2.0, 'entry_bay' => 0, 'door_width_m' => 1.8, 'door_height_m' => 3.5, 'arch' => 'round' },
      'structure' => { 'wall_m' => 0.8 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.3, 'pitch_deg' => 30, 'ridge' => 'perpendicular' },
      'materials' => { 'wall' => 'limestone', 'roof' => 'terracotta_canal', 'frames' => 'dark_wood', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'bell_tower' => 'porch', 'apse' => true }
    },
    'palette' => [{}, { 'materials' => { 'wall' => 'blond_stone' } }, { 'materials' => { 'wall' => 'granite', 'roof' => 'slate' } }, { 'materials' => { 'roof' => 'slate' } }],
    'rules' => rules(levels: [1, 3], roofs: %w[gable], ratio: [1.5, 3.0], walls: %w[limestone blond_stone granite golden_stone])
  },
  'eglise_gothique' => {
    'label' => 'Église gothique', 'period' => 'Église gothique, XIIIe-XVe siècle', 'regions' => %w[france], 'typologies' => %w[religious], 'family' => 'historic_monumental',
    'requires' => %w[gable cross_ridge arches glazing muntins bell_tower apse transept],
    'defaults' => {
      'footprint' => { 'width_m' => 14, 'depth_m' => 34 },
      'levels' => { 'count' => 2, 'height_m' => 6.0, 'heights_m' => [] },
      'facade' => { 'front_bays' => 1, 'side_bays' => 6, 'window_width_m' => 1.4, 'window_height_m' => 3.6, 'sill_m' => 1.6, 'entry_bay' => 0, 'door_width_m' => 2.4, 'door_height_m' => 4.0, 'muntin_rows' => 4, 'arch' => 'pointed' },
      'structure' => { 'wall_m' => 0.9 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.3, 'pitch_deg' => 55, 'ridge' => 'perpendicular' },
      'materials' => { 'wall' => 'limestone', 'roof' => 'slate', 'frames' => 'dark_metal', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'muntins' => true, 'bell_tower' => 'porch', 'apse' => true, 'transept' => true }
    },
    'palette' => [{}, { 'materials' => { 'wall' => 'granite' } }, { 'materials' => { 'wall' => 'blond_stone' } }],
    'rules' => rules(levels: [2, 3], roofs: %w[gable], ratio: [2.0, 3.5], walls: %w[limestone granite blond_stone])
  },
  'cathedrale' => {
    'label' => 'Cathédrale', 'period' => 'Cathédrale gothique, XIIe-XIVe siècle', 'regions' => %w[france], 'typologies' => %w[religious], 'family' => 'historic_monumental',
    'requires' => %w[gable cross_ridge arches glazing muntins bell_tower apse transept],
    'defaults' => {
      'footprint' => { 'width_m' => 22, 'depth_m' => 58 },
      'levels' => { 'count' => 3, 'height_m' => 6.0, 'heights_m' => [] },
      'facade' => { 'front_bays' => 1, 'side_bays' => 9, 'window_width_m' => 1.8, 'window_height_m' => 4.0, 'sill_m' => 1.4, 'entry_bay' => 0, 'door_width_m' => 3.0, 'door_height_m' => 4.0, 'muntin_rows' => 5, 'arch' => 'pointed' },
      'structure' => { 'wall_m' => 1.0 },
      'roof' => { 'type' => 'gable', 'overhang_m' => 0.3, 'pitch_deg' => 55, 'ridge' => 'perpendicular' },
      'materials' => { 'wall' => 'limestone', 'roof' => 'slate', 'frames' => 'dark_metal', 'glass' => 'glass' },
      'features' => { 'glazing' => true, 'muntins' => true, 'bell_tower' => 'twin', 'apse' => true, 'transept' => true }
    },
    'palette' => [{}, { 'materials' => { 'wall' => 'blond_stone' } }, { 'materials' => { 'wall' => 'granite' } }],
    'rules' => rules(levels: [3, 3], roofs: %w[gable], ratio: [2.0, 3.0], walls: %w[limestone blond_stone granite])
  }
}.freeze

def document(id, spec)
  doc = {
    'schema_version' => 1, 'id' => spec.fetch('id', id), 'revision' => spec.fetch('revision', 1), 'kind' => 'profile', 'status' => 'active',
    'parent' => { 'id' => spec.fetch('family', 'masonry_vernacular'), 'revision' => 1 }, 'family_id' => spec.fetch('family', 'masonry_vernacular'), 'label' => spec['label'],
    'context' => { 'period' => spec['period'], 'regions' => spec['regions'], 'typologies' => spec['typologies'] },
    'requires' => spec['requires'], 'defaults' => spec['defaults'], 'rules' => spec['rules']
  }
  doc['palette'] = spec['palette'] if spec['palette']
  doc
end

ARGV.each do |id|
  spec = PROFILES.fetch(id)
  text = "#{JSON.pretty_generate(document(id, spec))}\n"
  DIRS.each do |dir|
    revision = spec.fetch('revision', 1)
    path = File.join(ROOT, dir, revision > 1 ? "#{spec.fetch('id', id)}.r#{revision}.json" : "#{id}.json")
    abort "#{path} existe déjà avec un autre contenu : nouvelle révision nécessaire" if File.exist?(path) && File.read(path, encoding: 'utf-8') != text
    File.binwrite(path, text)
  end
  puts "écrit #{id}"
end
