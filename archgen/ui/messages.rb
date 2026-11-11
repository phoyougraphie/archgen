# frozen_string_literal: true

module Archgen
  module UI
    # Textes du panneau, identifiés par raison : l'interface ne reproduit aucune règle,
    # elle affiche ce que le noyau a décidé. Français au départ, traduisible ici.
    module Messages
      SIGNATURES = {
        'haussmann' => 'Pierre claire, baies verticales, mansarde ; corniche et balcon filant au LOD 1.',
        'toulousain' => 'Brique foraine, toit en tuile canal, baies verticales ; encadrements au LOD 1.',
        'provencal_mas' => 'Enduit ocre, deux niveaux, toit bas en tuile canal ; génoise, volets verts au LOD 1.',
        'provencal_village' => 'Enduit clair, maison étroite de trois niveaux ; génoise, volets bleu pastel au LOD 1.',
        'breton_longere' => 'Granit et ardoise, longère basse et allongée ; lucarnes et cheminées au LOD 1.',
        'breton_bourg' => 'Schiste et ardoise, maison de bourg à toit pentu ; lucarnes, cheminées et encadrements au LOD 1.',
        'lyonnais' => 'Pierre dorée, cinq niveaux, hautes fenêtres ; encadrements et volets gris au LOD 1.',
        'bordelais_echoppe' => 'Pierre blonde, un seul niveau à toit caché ; corniche et encadrements au LOD 1.',
        'parisien_faubourien' => 'Enduit clair, quatre niveaux, tuile mécanique ; encadrements et volets gris au LOD 1.',
        'flamand' => 'Brique rouge, façade étroite à pignon sur rue ; pignon à redents au LOD 1.',
        'savoyard_chalet' => 'Pierre et bois, pignon sur rue sous un grand débord ; bardage, balcon et volets au LOD 1.',
        'colombages' => 'Enduit clair et pan de bois sombre aux étages, toit à deux pans ; pan de bois au LOD 1.',
        'normand' => 'Pan de bois sombre, toit d’ardoise pentu ; lucarnes et cheminées au LOD 1.',
        'alsacien' => 'Enduit ocre et pan de bois, toit très pentu ; lucarnes au LOD 1.',
        'basque' => 'Enduit blanc et bois rouge, pignon sur rue sous un large débord ; pan de bois au LOD 1.',
        'maison_romane' => 'Pierre, murs épais, petites baies en plein cintre ; arcs au LOD 1.',
        'maison_gothique' => 'Pierre, pignon sur rue pentu, baies en arc brisé ; arcs au LOD 1.',
        'renaissance' => 'Pierre blonde, croisées et lucarnes, encadrements au LOD 1.',
        'neoclassique' => 'Pierre claire, pilastres, fronton d’entrée et corniche au LOD 1.',
        'baroque' => 'Pierre dorée, baies cintrées, pilastres et fronton, mansarde au LOD 1.',
        'art_deco' => 'Béton clair, toit plat, bandes verticales et corniche au LOD 1.',
        'art_nouveau' => 'Pierre blonde, baies cintrées, balcons, mansarde au LOD 1.',
        'mediterraneen_cycladique' => 'Enduit blanc, toit plat, baies cintrées, volets bleus au LOD 1.',
        'mediterraneen_andalou' => 'Enduit blanc, tuile canal, baies cintrées, volets verts au LOD 1.',
        'bauhaus' => 'Enduit blanc, toit plat, fenêtres en bandeau aux étages.',
        'moderniste' => 'Béton clair sur pilotis, fenêtres en bandeau, toit plat.',
        'mid_century' => 'Brique, deux niveaux, grands bandeaux vitrés, toit plat très débordant.',
        'minimaliste' => 'Enduit blanc, murs-rideaux aux étages, toit plat.',
        'industriel' => 'Brique rouge, deux hauts niveaux, toit en sheds vitrés, grande porte.',
        'high_tech' => 'Métal sombre, murs-rideaux et trame structurelle apparente.',
        'bioclimatique' => 'Bardage bois en haut, brise-soleil sur les baies, deux pans débordants.',
        'brutalist' => 'Béton, toit plat, grille répétitive ; baies en retrait au LOD 1 Structural.'
      }.freeze

      FIELDS = {
        '/name' => 'Nom', '/profile' => 'Style', '/profile/id' => 'Style', '/building_type' => 'Type de bâtiment', '/mode' => 'Mode', '/lod' => 'Niveau de détail',
        '/seed' => 'Graine', '/fidelity' => 'Fidélité',
        '/footprint/width_m' => 'Largeur', '/footprint/depth_m' => 'Profondeur',
        '/levels' => 'Hauteur totale', '/levels/count' => 'Niveaux', '/levels/height_m' => 'Hauteur courante', '/levels/heights_m' => 'Hauteurs par niveau',
        '/facade/front_bays' => 'Travées avant et arrière', '/facade/side_bays' => 'Travées latérales', '/facade/margin_m' => 'Marge de trame',
        '/facade/window_width_m' => 'Largeur de fenêtre', '/facade/window_height_m' => 'Hauteur de fenêtre', '/facade/sill_m' => 'Allège',
        '/facade/entry_bay' => 'Travée d’entrée', '/facade/door_width_m' => 'Largeur de porte', '/facade/door_height_m' => 'Hauteur de porte',
        '/facade/jitter_m' => 'Variation des baies',
        '/structure/wall_m' => 'Épaisseur de mur', '/structure/slab_m' => 'Épaisseur de dalle',
        '/roof/type' => 'Type de toit', '/roof/overhang_m' => 'Débord', '/roof/pitch_deg' => 'Pente', '/roof/lower_pitch_deg' => 'Pente basse', '/roof/inset_m' => 'Retrait du brisis',
        '/materials/wall' => 'Matériau des murs', '/materials/roof' => 'Matériau du toit', '/materials/frames' => 'Matériau des cadres',
        '/features/cornice' => 'Corniche', '/features/balcony' => 'Balcon', '/features/surrounds' => 'Encadrements',
        '/facade/tint' => 'Teintes', '/features/balcony_rail' => 'Garde-corps des balcons', '/features/glazing' => 'Vitrage', '/features/chimneys' => 'Cheminées', '/features/muntins' => 'Petits bois', '/features/shutters' => 'Volets', '/features/dormers' => 'Lucarnes', '/features/genoise' => 'Génoise', '/roof/ridge' => 'Faîtage', '/features/stepped_gable' => 'Pignon à redents', '/features/cladding' => 'Bardage', '/features/timber_frame' => 'Pan de bois', '/features/classical' => 'Ornements classiques', '/facade/ribbon' => 'Baies en bandeau', '/features/pilotis' => 'Pilotis', '/style' => 'Style', '/structure/ground_slab' => 'Dalle et seuils', '/features/shop_front' => 'Devanture', '/materials/awning' => 'Toile du store', '/features/structural_grid' => 'Trame structurelle', '/features/sun_shades' => 'Brise-soleil', '/facade/arch' => 'Arcs', '/materials/timber' => 'Matériau du pan de bois', '/materials/cladding' => 'Matériau du bardage', '/materials/shutters' => 'Matériau des volets', '/facade/muntin_rows' => 'Rangs de petits bois', '/materials/glass' => 'Matériau du verre', '/ground_floor' => 'Rez-de-chaussée', '/shop' => 'Commerce', '/shop/height_m' => 'Hauteur du commerce',
        '/site/platform' => 'Plateforme', '/site/platform/policy' => 'Altitude de plateforme', '/site/platform/offset_m' => 'Décalage de plateforme',
        '/site/earthwork' => 'Terrassement', '/site/embankment_ratio' => 'Pente du talus', '/site/plinth_material' => 'Matériau du soubassement', '/site/entrance' => 'Devant la porte',
        '/site/terrain' => 'Terrain', '/site/placement' => 'Placement', '/site/survey' => 'Relevé du terrain', '/site/survey/step_m' => 'Pas du relevé'
      }.freeze

      REASONS = {
        # Structure
        'required' => 'Cette valeur est obligatoire.',
        'unknown_key' => 'Ce réglage n’existe pas.',
        'type' => 'Le format de cette valeur n’est pas valide.',
        'enum' => 'Cette option n’est pas disponible.',
        'const' => 'Cette valeur n’est pas prise en charge.',
        'minimum' => 'La valeur minimale est %{limit}.',
        'maximum' => 'La valeur maximale est %{limit}.',
        'min_length' => 'Ce texte est trop court.',
        'max_length' => 'Ce texte ne doit pas dépasser %{limit} caractères.',
        'pattern' => 'Cet identifiant n’est pas valide.',
        'min_items' => 'Cette liste est trop courte.',
        'max_items' => 'Cette liste ne doit pas dépasser %{limit} valeurs.',
        'unique_items' => 'Cette liste contient des doublons.',
        'blank' => 'Saisissez un nom.',
        # Lecture des données
        'not_a_string' => 'Les données reçues ne sont pas lisibles.',
        'too_large' => 'Les données dépassent la taille permise.',
        'too_deep' => 'Les données sont trop imbriquées.',
        'invalid_utf8' => 'Les données contiennent des caractères illisibles.',
        'duplicate_key' => 'Les données contiennent un réglage en double.',
        'non_finite_number' => 'Ce nombre n’est pas valide.',
        'number_too_long' => 'Ce nombre est trop long.',
        'invalid_json' => 'Les données reçues ne sont pas lisibles.',
        'trailing_data' => 'Les données reçues ne sont pas lisibles.',
        'control_character' => 'Ce texte contient un caractère non autorisé.',
        'invalid_escape' => 'Ce texte contient un caractère non autorisé.',
        'lone_surrogate' => 'Ce texte contient un caractère non autorisé.',
        'invalid_metadata' => 'Les données enregistrées sur ce bâtiment sont altérées. Il reste consultable mais ne peut pas être régénéré.',
        # Niveaux et façade
        'count_mismatch' => 'Indiquez %{expected} hauteurs, ou videz ce champ pour utiliser la hauteur courante.',
        'wall_top' => 'La hauteur sous toit dépasse %{limit} m. Réduisez les niveaux ou leur hauteur.',
        'entry_bay_out_of_range' => 'La travée d’entrée doit être inférieure au nombre de travées (%{limit}).',
        'margin_exceeds_half_length' => 'La marge est trop grande pour cette façade. Réduisez-la ou agrandissez le bâtiment.',
        'facade_end' => 'Cette baie est trop près de l’angle. Réduisez sa largeur, la marge ou l’épaisseur de mur.',
        'level_top' => 'Cette baie dépasse du niveau. Réduisez sa hauteur ou l’allège, ou augmentez la hauteur d’étage.',
        'opening_spacing' => 'Cette fenêtre ne tient pas dans la travée. Réduisez sa largeur ou le nombre de travées.',
        'cuts_too_close' => 'Deux bords de baies tombent à moins de 2 mm l’un de l’autre. Changez la graine ou la variation, ou modifiez légèrement les cotes.',
        # Toiture
        'inactive_field_not_zero' => 'Ce réglage ne s’applique pas à ce type de toit.',
        'out_of_range' => 'Pour ce type de toit, la valeur doit être entre %{min} et %{max}.',
        'lower_not_steeper' => 'La pente basse doit être plus forte que la pente haute.',
        'inset_not_positive' => 'Le retrait du brisis doit être supérieur à zéro.',
        'no_remaining_span' => 'Le retrait du brisis est trop grand pour cette emprise. Maximum : %{limit} m.',
        'eave_below_ground' => 'La rive du toit descend sous le sol. Réduisez le débord ou la pente.',
        'ridge_too_short' => 'Largeur et profondeur sont presque égales : le faîtage serait trop court. Rendez-les égales ou plus différentes.',
        # Détails
        'cornice_head_margin' => 'La corniche touche la tête des fenêtres. Réduisez leur hauteur ou retirez la corniche.',
        'cornice_coplanar_with_roof' => 'Une corniche n’est pas possible sur un toit plat à débord. Retirez l’un des deux.',
        'balcony_over_opening' => 'Le balcon passe devant une fenêtre. Réduisez sa hauteur ou retirez le balcon.',
        'no_balcony_level' => 'Le balcon apparaît aux niveaux d’index 2 et 5 : ce bâtiment n’en a aucun.',
        # Matériaux et profils
        'unknown_material' => 'Ce matériau n’est pas dans le catalogue.',
        'glass_required' => 'Le vitrage demande une matière de verre.',
        'glass_without_glazing' => 'Une matière de verre est donnée sans vitrage.',
        'glazing_false_written' => 'Un vitrage décoché ne s’enregistre pas : retirez ce champ.',
        'genoise_false_written' => 'Une génoise décochée ne s’enregistre pas : retirez ce champ.',
        'genoise_with_cornice' => 'Une génoise et une corniche ne vont pas ensemble : décochez l’une des deux.',
        'genoise_head_margin' => 'La fenêtre %{id} monte trop haut sous la génoise : %{limit} m au plus. Réduisez la hauteur des fenêtres.',
        'genoise_roof' => 'La génoise ne se pose que sous un toit à deux pans ou une croupe.',
        'dormers_false_written' => 'Des lucarnes décochées ne s’enregistrent pas : retirez ce champ.',
        'arch_too_low' => 'La baie %{id} est trop basse pour son arc : il lui faut la flèche de l’arc et 0,30 m de plus. Augmentez sa hauteur ou choisissez des baies droites.',
        'classical_false_written' => 'Des ornements décochés ne s’enregistrent pas : retirez ce champ.',
        'classical_with_timber' => 'Les ornements classiques et le pan de bois ne vont pas ensemble : décochez l’un des deux.',
        'pilaster_no_room' => 'Un pilastre toucherait la baie %{id} (ou ses volets, son encadrement). Réduisez la largeur des fenêtres ou retirez les volets.',
        'pilaster_porch' => 'Pas de pilastre devant le passage du porche.',
        'pediment_no_room' => 'Le fronton de l’entrée ne tient pas : il toucherait un pilastre ou le premier étage.',
        'pilotis_false_written' => 'Des pilotis décochés ne s’enregistrent pas : retirez ce champ.',
        'structural_grid_false_written' => 'Une trame décochée ne s’enregistre pas : retirez ce champ.',
        'sun_shades_false_written' => 'Des brise-soleil décochés ne s’enregistrent pas : retirez ce champ.',
        'structural_grid_with_timber_frame' => 'La trame structurelle et le pan de bois occupent la même place : décochez l’un des deux.',
        'structural_grid_with_classical' => 'La trame structurelle et les pilastres occupent la même place : décochez l’un des deux.',
        'structural_grid_with_shutters' => 'Les poteaux de la trame toucheraient les volets : décochez l’un des deux.',
        'shop_front_without_shop' => 'Un store ou une pergola demande un rez-de-chaussée commerçant.',
        'awning_material_required' => 'Le store demande sa toile.',
        'awning_material_without_awning' => 'Une toile est donnée sans store.',
        'ramp_too_long' => 'La rampe ferait %{value} m et la façade n’offre que %{limit} m à côté de la porte : choisissez un perron ou abaissez la plateforme.',
        'export_face' => 'La pièce %{id} a une face dégénérée : elle ne peut pas être découpée en triangles pour l’export.',
        'export_primitive' => 'La pièce %{id} a une forme que l’export ne sait pas écrire.',
        'export_material' => 'La pièce %{id} utilise une matière absente du catalogue : l’export ne peut pas la décrire.',
        'export_volume' => 'Le bâtiment %{id} n’a pas de volume simple : murs et toit sont plats.',
        'lod1_skipped' => 'Le bâtiment est déjà au niveau de détail 0 : le fichier LOD1 n’est pas écrit.',
        'lod_not_decreasing' => 'Les triangles ne décroissent pas d’un niveau de détail au suivant (%{value}).',
        'map_file' => 'Le fichier de carte n’est pas lisible (%{reason_detail}) : prenez un extrait .osm ou un GeoJSON.',
        'map_coordinates' => 'Le fichier de carte contient une coordonnée hors des bornes, ligne %{line}.',
        'map_too_large' => 'La carte donne %{value} éléments : %{limit} au plus. Prenez une zone plus petite.',
        'terrain_file' => 'Le fichier de terrain n’est pas un ASCII Grid lisible (%{reason_detail}).',
        'terrain_too_large' => 'Le terrain compte %{value} points : %{limit} au plus.',
        'terrain_nodata' => 'Le terrain a %{value} points sans altitude : %{limit} au plus.',
        'terrain_outside_map' => 'Le terrain ne recouvre pas la carte : vérifiez qu’il est en Lambert-93 et couvre la même zone.',
        'map_empty' => 'Le fichier de carte ne contient ni voie ni bâtiment.',
        'export_selection' => 'Sélectionnez un seul bâtiment ou une seule rue ARCHGEN, puis relancez l’export.',
        'export_unsupported' => 'Les routes, réseaux et terrains ne s’exportent pas encore : sélectionnez un bâtiment ou une rue.',
        'street_ground_excluded' => 'Le terrain et les routes ne sont pas exportés avec la rue.',
        'export_definition' => 'La pièce %{id} renvoie à une définition absente du plan.',
        'ground_slab_false_written' => 'Une dalle décochée ne s’enregistre pas : retirez ce champ.',
        'roads_merged' => 'Cette voie rejoint %{count} voie(s) ou réseau(x) : elles forment maintenant un réseau avec ses carrefours.',
        'network_on_terrain' => 'Une voie qui suit le terrain ne peut pas entrer dans un réseau (il reste horizontal) : tracez-la à l’écart ou à plat.',
        'network_merge_levels' => 'Cette voie touche une voie posée à une autre hauteur : elles ne peuvent pas former un réseau.',
        'network_merge_rotated' => 'Cette voie touche une voie inclinée : elles ne peuvent pas former un réseau.',
        'network_too_many_roads' => 'Le réseau compterait %{value} voies : %{limit} au plus.',
        'pilotis_levels' => 'Des pilotis demandent deux niveaux au moins.',
        'pilotis_with_shop' => 'Des pilotis laissent le rez-de-chaussée ouvert : pas de commerce.',
        'pilotis_in_row' => 'Dans une rue, les voisins s’appuient sur le rez-de-chaussée : pas de pilotis ici.',
        'timber_false_written' => 'Un pan de bois décoché ne s’enregistre pas : retirez ce champ.',
        'timber_material_required' => 'Le pan de bois demande son matériau.',
        'timber_material_without_timber' => 'Un matériau de pan de bois est donné sans pan de bois.',
        'timber_with_surrounds' => 'Le pan de bois et les encadrements occupent la même place devant le mur : décochez l’un des deux.',
        'timber_with_shutters' => 'Le pan de bois et les volets occupent la même place devant le mur : décochez l’un des deux.',
        'timber_with_cornice' => 'Le pan de bois et la corniche se recouvrent sous le toit : décochez l’un des deux.',
        'timber_with_cladding' => 'Le pan de bois et le bardage ne vont pas ensemble : décochez l’un des deux.',
        'cladding_false_written' => 'Un bardage décoché ne s’enregistre pas : retirez ce champ.',
        'cladding_material_required' => 'Le bardage demande son matériau.',
        'cladding_material_without_cladding' => 'Un matériau de bardage est donné sans bardage.',
        'stepped_gable_false_written' => 'Un pignon à redents décoché ne s’enregistre pas : retirez ce champ.',
        'stepped_gable_ridge' => 'Le pignon à redents demande un faîtage perpendiculaire à la rue.',
        'stepped_gable_overhang' => 'Le pignon à redents demande un débord de toit de %{limit} m au plus.',
        'stepped_gable_corner' => 'Ce bâtiment d’angle garde un faîtage parallèle : pas de pignon à redents.',
        'ridge_axis_roof' => 'Un faîtage perpendiculaire à la rue demande un toit à deux pans.',
        'ridge_corner' => 'Ce bâtiment d’angle garde un faîtage parallèle à la rue : son pignon ne serait pas droit.',
        'dormer_ridge' => 'Avec un faîtage perpendiculaire, la façade est un pignon : pas de lucarne.',
        'dormer_skipped' => 'Pas de lucarne sur %{ids} : trop près d’une croupe ou de l’angle de la parcelle.',
        'dormer_flat_roof' => 'Ce toit (plat ou en sheds) n’a pas de lucarne.',
        'dormer_too_low' => 'La lucarne %{id} ne tient pas sous le toit : il est trop bas pour une fenêtre de 0,60 m. Augmentez la pente ou la profondeur.',
        'dormer_no_room' => 'La lucarne %{id} manque de place sur la façade (marges, voisine, croupe ou mur latéral). Réduisez la largeur des fenêtres ou le nombre de travées.',
        'dormer_on_chimney' => 'La lucarne %{id} tomberait sur une cheminée. Retirez les cheminées ou les lucarnes, ou changez la graine.',
        'shutters_false_written' => 'Des volets décochés ne s’enregistrent pas : retirez ce champ.',
        'shutters_material_required' => 'Les volets demandent leur matériau.',
        'shutters_material_without_shutters' => 'Un matériau de volets est donné sans volets.',
        'shutters_skipped' => 'Pas de volets sur %{ids} : le passage du porche ne leur laisse pas la place.',
        'shutters_no_room' => 'Les volets ouverts de la fenêtre %{id} ne tiennent pas : il manque de la place à côté. Réduisez la largeur des fenêtres ou leur nombre.',
        'muntins_false_written' => 'Des petits bois décochés ne s’enregistrent pas : retirez ce champ.',
        'muntins_without_glazing' => 'Les petits bois demandent le vitrage : cochez Vitrage.',
        'muntin_rows_required' => 'Les petits bois demandent leur nombre de rangs.',
        'muntin_rows_without_muntins' => 'Un nombre de rangs de petits bois est donné sans petits bois.',
        'chimneys_false_written' => 'Des cheminées décochées ne s’enregistrent pas : retirez ce champ.',
        'shop_without_ground_floor' => 'Une hauteur de commerce est donnée sans rez-de-chaussée commerçant.',
        'shop_height_required' => 'Un rez-de-chaussée commerçant demande sa hauteur.',
        'shop_with_heights' => 'Les hauteurs par niveau sont saisies : elles fixent déjà le rez-de-chaussée. Retirez la hauteur du commerce.',
        'shop_ground_too_low' => 'Un commerce demande un rez-de-chaussée de %{limit} m au moins ; il en a %{value}.',
        'shopfront_too_narrow' => 'Une vitrine demande %{limit} m de large ; la travée n’en laisse que %{value}. Réduisez le nombre de travées ou élargissez le bâtiment.',
        'fascia_over_entrance' => 'Le bandeau du commerce passerait devant l’entrée de l’immeuble. Montez le rez-de-chaussée ou baissez la porte.',
        'profile_required' => 'Choisissez un style.',
        'exact_revision_required' => 'Le style choisi doit préciser sa révision.',
        'unknown_profile' => 'Ce style n’existe pas dans cette version.',
        'missing_revision' => 'La révision de ce style n’est pas installée. Ce bâtiment reste consultable.',
        'not_selectable' => 'Ce style n’est pas encore disponible.',
        'missing_capability' => 'Ce style demande une capacité qui n’est pas encore disponible.',
        # Budgets
        'width_m' => 'La largeur dépasse la limite de %{limit} m.',
        'depth_m' => 'La profondeur dépasse la limite de %{limit} m.',
        'wall_top_z_m' => 'La hauteur sous toit dépasse la limite de %{limit} m.',
        'roof_top_z_m' => 'Le sommet dépasse la limite de %{limit} m.',
        'opening_count' => 'Trop d’ouvertures. Réduisez les travées ou les niveaux.',
        'unique_face_count' => 'Ce bâtiment est trop détaillé. Réduisez les travées, les niveaux ou le niveau de détail.',
        'expanded_face_count' => 'Ce bâtiment est trop détaillé. Réduisez les travées, les niveaux ou le niveau de détail.',
        'wall_cell_count' => 'Ce bâtiment est trop détaillé. Réduisez les travées, les niveaux ou le niveau de détail.',
        'detail_definition_count' => 'Trop de cadres différents. Réduisez le niveau de détail.',
        # Terrain
        'missing_points' => 'Le terrain manque sous le bâtiment en %{count} points. Complétez-le ou déplacez le bâtiment.',
        'too_few_points' => 'Ce tracé n’a que %{value} point(s), il en faut au moins %{limit}.',
        'first_point_not_origin' => 'Le tracé doit partir de l’origine de l’ensemble.',
        'point_out_of_range' => 'Ce point du tracé est à plus de %{limit} m de l’origine.',
        'segment_short' => 'Ce segment mesure %{value} m en façade, pour un minimum de %{limit} m.',
        'self_intersection' => 'Le tracé se coupe ou se replie sur lui-même à ce segment.',
        'rear_too_short' => 'L’angle est trop fermé pour cette profondeur : il manque %{missing_m} m à l’arrière de la parcelle. Allongez le segment ou réduisez la profondeur.',
        'parcel_count' => 'Ce tracé donnerait %{value} parcelles, pour une limite de %{limit}. Augmentez la largeur des parcelles ou raccourcissez le tracé.',
        'parcels_overlap' => 'Deux parcelles se recouvrent : le tracé revient trop près de lui-même, ou la profondeur est trop grande.',
        'parcels_too_close' => 'Deux parcelles ne sont qu’à %{value} m l’une de l’autre, pour un minimum de %{limit} m. Agrandissez la cour ou écartez le tracé.',
        'computed_by_parcel' => 'Ce réglage est calculé pour chaque parcelle et ne peut pas être saisi.',
        'layout_on_closed_trace' => 'Une forme fermée construit toujours à l’intérieur du tracé : le côté ne se règle pas.',
        'access_on_open_trace' => 'Une rue ouverte n’a pas de cour : les accès ne s’y règlent pas.',
        'street_width_without_both' => 'La largeur de rue ne s’applique que si l’on construit des deux côtés.',
        'access_form_unavailable' => 'Les îlots fermés ne sont pas pris en charge pour ce style : il ne sait pas encore ouvrir un accès à la cour. Tracez une rue ouverte, ou choisissez un autre style.',
        'access_no_room' => 'Ce contour ne peut pas recevoir %{value} accès à la cour : il n’y a de la place que pour %{placed}. Allongez les côtés, réduisez leur nombre ou leur largeur. Une cour sans accès n’est jamais produite.',
        'ensemble_unique_faces' => 'Cet ensemble compte %{value} faces distinctes, pour une limite de %{limit}. Réduisez le niveau de détail ou le nombre de parcelles.',
        'ensemble_expanded_faces' => 'Cet ensemble compte %{value} faces au total, pour une limite de %{limit}. Réduisez le niveau de détail ou le nombre de parcelles.',
        'not_an_ensemble_root' => 'Sélectionnez un ensemble ARCHGEN, au niveau du modèle.',
        'invalid_origin' => 'Le point de départ du tracé est invalide.',
        'trace_not_ready' => 'Terminez d’abord le tracé : double-clic ou Échap.',
        'preview_changed' => 'Le résultat a changé depuis l’affichage. Vérifiez-le, puis cliquez de nouveau sur Créer.',
        'porch_too_high' => 'Ce passage de %{value} m ne tient pas sous le plafond du rez-de-chaussée : %{limit} m au plus. Réduisez sa hauteur ou augmentez celle du premier niveau.',
        'porch_no_room' => 'Ce passage ne laisse pas assez de mur de chaque côté : réduisez sa largeur ou élargissez les parcelles.',
        'ensemble_selection_not_single' => 'Sélectionnez un seul ensemble ARCHGEN.',
        'edit_not_loaded' => 'Rechargez d’abord la sélection.',
        'hip_in_row' => 'Un toit en croupe n’a pas de sens dans une rangée : choisissez un toit plat, à deux pans ou une mansarde.',
        'wall_too_short' => 'L’angle est trop fermé pour l’épaisseur des murs de cette parcelle.',
        'roof_rear_too_short' => 'Le débord du toit croise les onglets à l’arrière de cette parcelle : réduisez le débord ou ouvrez l’angle.',
        'balcony_no_room' => 'Le balcon n’a pas la place de tenir dans cet angle : il est omis.',
        'relief_exceeded' => 'Le terrain varie de %{value} m sous le bâtiment, au-delà de la limite de %{limit} m.',
        'survey_points' => 'Ce relevé demanderait %{value} points, pour une limite de %{limit}. Augmentez le pas du relevé.',
        'grid_axes' => 'Le relevé ne correspond pas à ce bâtiment. Relevez de nouveau.',
        'grid_shape' => 'Le relevé du terrain est incomplet. Relevez de nouveau.',
        'terrain_selection' => 'Sélectionnez un seul groupe ou composant comme terrain.',
        'terrain_kind' => 'Le terrain doit être un groupe ou un composant. Groupez ses faces.',
        'terrain_nested' => 'Ce terrain est dans un groupe ou un composant. Sortez-le au niveau du modèle.',
        'terrain_is_building' => 'Un bâtiment ARCHGEN ne peut pas servir de terrain.',
        'terrain_hidden' => 'Ce terrain est masqué. Affichez-le pour le relever.',
        'terrain_missing' => 'Le terrain retenu n’existe plus. Retenez-en un autre.',
        'terrain_other_document' => 'Le terrain retenu appartient à un autre document. Retenez-en un dans celui-ci.',
        'not_horizontal' => 'Ce bâtiment est incliné. Rétablissez son axe vertical pour l’adapter au terrain.',
        'too_many_obstacles' => 'Trop d’objets au-dessus du terrain en %{count} points. Masquez-les ou déplacez le bâtiment.',
        'terrain_changed' => 'Le terrain a changé depuis l’aperçu. Relevez de nouveau.',
        'site_absent' => 'Il n’y a pas d’assise à retirer.',
        'terrain_not_retained' => 'Sélectionnez d’abord le terrain, puis cliquez sur Retenir ce terrain.',
        'toe_not_found' => 'Le talus n’atteint pas le terrain de ce côté, qui descend trop vite. Raidissez la pente ou choisissez le soubassement.',
        'door_buried' => 'Le terrain dépasse le seuil de la porte de %{value} m. Remontez la plateforme ou changez la travée d’entrée.',
        'embankment_in_row' => 'Un talus déborderait chez le voisin : dans un ensemble, seul le soubassement est possible.',
        'embankment_bend' => 'Le talus n’est possible que sur une rangée droite : ces parcelles sont à un angle (%{ids}). Choisissez Soubassement.',
        'passage_buried' => 'Le terrain dépasse le sol de ce passage de %{value} m. Remontez la plateforme.',
        'passage_gap' => 'Le sol de ce passage est à %{value} m au-dessus du terrain : aucune rampe n’est générée.',
        'door_gap_many' => '%{count} parcelles ont un seuil au-dessus du terrain, jusqu’à %{value} m : aucun escalier n’est généré.',
        'terrain_above_many' => 'Le terrain traverse %{count} bâtiments, jusqu’à %{value} m au-dessus de leur plateforme.',
        'door_gap' => 'Le seuil de la porte est à %{value} m au-dessus du terrain : choisissez Perron ou Rampe devant la porte.',
        'terrain_above_platform' => 'Le terrain dépasse la plateforme de %{value} m et traverse le bâtiment. Baies touchées : %{count}.',
        'site_faces' => 'Le terrassement est trop détaillé. Augmentez le pas du relevé.',
        'total_faces' => 'Le bâtiment et son terrassement dépassent la limite de %{limit} faces. Augmentez le pas du relevé ou réduisez le niveau de détail.',
        # Voirie : coupe (docs/VOIRIE_CONTRACT.md)
        # Rues variées (docs/RUE_VARIEE_CONTRACT.md)
        'parcel_not_loaded' => 'Aucun bâtiment choisi : ouvrez la rue, faites un clic droit sur un bâtiment, puis ARCHGEN → Personnaliser ce bâtiment.',
        'unknown_parcel' => 'Ce réglage propre désigne la parcelle %{id}, qui n’existe plus (le tracé a changé). Retirez-le.',
        'width_locked' => 'La largeur de cette parcelle ne peut pas changer : parcelle d’angle, sans voisine sur son segment, ou voisine qui a déjà sa propre largeur.',
        'neighbour_too_narrow' => 'Sa voisine %{other} passerait à %{value} m : %{limit} m au moins. Choisissez une largeur plus proche.',
        'empty_parcel' => 'Ce réglage propre est vide : retirez-le.',
        'variety_levels_order' => 'Le nombre de niveaux minimal (%{min}) dépasse le maximal (%{max}).',
        'variety_with_levels' => 'Une rue variée tire le nombre de niveaux : retirez la liste des hauteurs par niveau.',
        'variety_style_levels' => 'Ce style demande de %{min} à %{max} niveaux : resserrez la fourchette, ou passez en fidélité plausible.',
        'variety_style_roof' => 'Ce style ne permet pas ce toit. Toits permis : %{allowed}.',
        'variety_hip_roof' => 'Un toit en croupe n’a pas de sens dans une rangée : retirez-le de la liste.',
        'unsupported_road_profile' => 'Cette coupe vient d’une version plus récente d’ARCHGEN.',
        'unknown_type' => 'Ce type de bande n’existe pas dans le catalogue.',
        'width_range' => 'Cette bande mesure %{value} m : choisissez une largeur de %{min} à %{max} m.',
        'band_accepts_no_items' => 'Rien ne se pose sur cette bande (fossé, eau, falaise, estran ou mer). Placez cet élément sur une bande voisine.',
        'unknown_kind' => 'Ce type d’élément n’existe pas dans le catalogue.',
        'unknown_variant' => 'Cette variante n’existe pas pour cet élément.',
        'height_range' => 'Cet élément mesure %{value} m : choisissez une hauteur de %{min} à %{max} m.',
        'variation_unavailable' => 'Seuls les arbres ont une hauteur variable.',
        'variation_range' => 'Avec cette variation, certains arbres sortiraient de la plage de %{min} à %{max} m. Réduisez la variation ou changez la hauteur.',
        'continuous_item' => 'Cet élément est continu : il n’a pas de pas.',
        'spacing_range' => 'Le pas doit être d’au moins %{min} m.',
        'crown_over_band' => 'La couronne de cet arbre passe au-dessus de la bande %{band_number}, à moins de %{clearance_m} m du sol.',
        'rail_next_to_carriageway' => 'Les bandes %{band_number} et %{next_number} placent une voie ferrée contre une chaussée, sans séparation.',
        'unsupported_road' => 'Cette voie vient d’une version plus récente d’ARCHGEN.',
        'first_point_not_road_origin' => 'Le tracé doit partir de l’origine de la voie.',
        'coordinate_range' => 'Ce point est trop loin de l’origine : %{limit} m au plus.',
        'radii_count' => 'Il faut un rayon par sommet intérieur : %{expected}, et non %{value}.',
        'segment_too_short' => 'Ce segment est trop court : %{min} m au moins.',
        'reversal' => 'Le tracé fait demi-tour à ce sommet. Ajoutez un sommet intermédiaire.',
        'radius_too_small' => 'Ce rayon est trop petit pour la largeur de la voie : %{min} m au moins.',
        'arcs_too_long' => 'Les virages de ce segment demandent %{value} m, il n’en mesure que %{length}. Réduisez les rayons ou allongez le segment.',
        'inner_edge_folds' => 'À cet angle vif, le bord intérieur de la voie se replierait. Donnez un rayon à ce sommet ou allongez les segments.',
        'self_overlap' => 'La voie se recouvre elle-même ici. Les croisements viendront avec les carrefours.',
        'road_items' => 'Cette voie poserait %{value} objets, pour une limite de %{limit}. Augmentez les pas ou raccourcissez-la.',
        'road_expanded_faces' => 'Cette voie et ses objets dépasseraient %{limit} faces au total (%{value}). Augmentez les pas ou raccourcissez-la.',
        'not_a_road_root' => 'Ce composant n’est pas une voie ARCHGEN.',
        'road_selection_not_single' => 'Sélectionnez une seule voie ARCHGEN.',
        'trace_unfinished' => 'Terminez d’abord le tracé dans la vue : double-clic ou Échap.',
        'road_sleepers' => 'Cette voie ferrée poserait %{value} traverses, pour une limite de %{limit}. Raccourcissez-la ou réduisez le nombre de voies.',
        'road_faces' => 'Cette voie demanderait %{value} faces, pour une limite de %{limit}. Raccourcissez-la ou simplifiez la coupe.',
        # Eau (docs/EAU_CONTRACT.md)
        'band_setting_unavailable' => 'Ce réglage n’existe pas pour ce type de bande.',
        'setting_range' => 'Valeur %{value} : choisissez de %{min} à %{max}.',
        'water_unbounded' => 'Ce plan d’eau n’a ni quai ni berge de ce côté. Ajoutez-en un contre lui.',
        'water_too_narrow' => 'Ce plan d’eau est trop étroit pour les pentes de ses berges : %{min} m au moins. Élargissez-le ou réduisez la profondeur.',
        'bank_without_water' => 'Une berge borde un seul plan d’eau, placé juste à côté d’elle.',
        'bank_too_steep' => 'Cette berge est trop raide : %{min} m de large au moins pour cette revanche.',
        'sea_not_outer' => 'La mer est la première ou la dernière bande de la coupe, et une seule.',
        'coast_without_sea' => 'Une falaise ou une plage descend vers la mer : ajoutez une mer au bout de la coupe.',
        'bus_stop_band_too_narrow' => 'Un abri de bus demande une bande de %{min} m au moins (celle-ci fait %{value} m) : élargissez-la ou choisissez le mât seul.',
        'bus_stop_clearance' => 'Un élément de la même bande est à moins de 2 m de l’abri (position %{value} m) : il le gênera.',
        'facing_unavailable' => 'Seul un panneau a un sens.',
        'positions_required' => 'Cet élément se pose à des endroits précis : donnez ses positions, en mètres depuis le début de la voie.',
        'positions_with_spacing' => 'Donnez des positions ou un pas, pas les deux.',
        'positions_order' => 'Les positions doivent aller en croissant, sans doublon.',
        'position_out_of_road' => 'La position %{value} m dépasse la voie, longue de %{limit} m.',
        'count_unavailable' => 'Seule une attache vélos a un nombre d’arceaux.',
        'count_range' => 'Une attache vélos compte de %{min} à %{max} arceaux.',
        'item_band_mismatch' => 'Cet élément ne se pose pas sur cette bande : une ganivelle va sur une dune ou une plage, un muret sur un trottoir, un chemin, un accotement, un quai ou une plage.',
        'sea_needs_flat' => 'Une côte reste à un seul niveau : choisissez ce régime pour l’eau.',
        'water_mode_missing' => 'Cette voie porte de l’eau : choisissez son régime (rivière, canal ou un seul niveau).',
        'water_without_band' => 'Cette voie n’a pas de plan d’eau : retirez le régime de l’eau.',
        'lock_too_wide' => 'Une écluse mesure %{limit} m de large au plus : réduisez la largeur du canal.',
        'canal_needs_quays' => 'Sur un terrain, un canal est bordé de quais : les écluses ont des murs droits. Remplacez la berge par un quai.',
        'lock_on_curve' => 'L’écluse à %{s_m} m du départ tomberait dans un virage : elle demande une ligne droite, approches comprises. Réduisez la chute ou allongez la ligne droite.',
        'locks_too_close' => 'L’écluse à %{s_m} m du départ toucherait la précédente : augmentez la chute ou adoucissez le tracé.',
        'lock_outside_trace' => 'L’écluse à %{s_m} m du départ sortirait du tracé avec ses approches de %{limit} m. Allongez le canal ou changez la chute.',
        'river_upstream' => 'Le terrain monte de %{value} m du début à la fin : une rivière se trace de l’amont vers l’aval. Inversez le tracé.',
        'water_crossing' => 'Un cours d’eau ne se croise que par un pont : choisissez le type Pont pour ce carrefour.',
        'water_confluence' => 'Deux cours d’eau ne se rejoignent pas encore, et un cours d’eau ne finit pas sur une voie : écartez les tracés.',
        'bridge_roads' => 'Un pont réunit exactement deux voies.',
        'bridge_through' => 'Les deux voies doivent traverser le pont, sans y finir.',
        'bridge_angle' => 'Les deux voies se croisent à %{value_deg}°, pour %{min_deg}° au moins sous un pont.',
        'bridge_over_missing' => 'Choisissez la voie qui passe sur le pont.',
        'bridge_over_unknown' => 'La voie portée doit être une des deux voies du pont, et pas un cours d’eau.',
        'bridge_span_too_long' => 'Ce pont porterait %{value} m, pour %{limit} m au plus : choisissez un arc ou croisez plus droit.',
        'bridge_clearance' => 'Sous ce pont, l’arc ou la voûte entre dans le gabarit de la bande %{band_number} : relevez la hauteur libre à %{needed_m} m, ou choisissez une poutre.',
        'bridge_clearance_impossible' => 'Sous ce pont, l’arc ou la voûte entre dans le gabarit de la bande %{band_number}, quelle que soit la hauteur : choisissez une poutre ou un arc.',
        'pier_on_traffic' => 'Une pile de la voûte tomberait sur la bande %{band_number}, où l’on circule : choisissez un arc ou une poutre.',
        'crossing_studs_unavailable' => 'Les clous de passage piéton ne vont qu’à un carrefour à feux, qui a des passages piétons.',
        'bridge_setting_unavailable' => 'Ce réglage n’existe que pour un pont.',
        'ditch_next_to_carriageway' => 'Les bandes %{band_number} et %{next_number} placent un fossé contre la chaussée, sans accotement.',
        # Voirie : réseau et carrefours (ADR-36)
        'unsupported_network' => 'Ce réseau vient d’une version plus récente d’ARCHGEN.',
        'first_point_not_network_origin' => 'La première voie doit partir de l’origine du réseau.',
        'duplicate_road_id' => 'Deux voies portent le même nom dans ce réseau.',
        'duplicate_junction' => 'Ce carrefour est réglé deux fois.',
        'unknown_junction' => 'Ce carrefour n’existe plus : les voies ne s’y croisent pas.',
        'motorway_at_grade' => 'Une autoroute ne se croise pas à niveau. Un échangeur viendra plus tard ; écartez les tracés.',
        'rails_at_junction' => 'Une voie ferrée ne croise une route qu’en passage à niveau : choisissez ce type pour ce carrefour, ou écartez les tracés.',
        'too_many_arms' => 'Ce carrefour aurait %{value} branches, pour %{limit} au plus.',
        'arms_too_close' => 'Deux branches de ce carrefour font %{value_deg}°, pour %{min_deg}° au moins. Ouvrez l’angle.',
        'junction_on_curve' => 'Le carrefour touche un virage de la voie %{road}. Éloignez le sommet du croisement.',
        'arm_too_short' => 'La voie %{road} est trop courte pour entrer dans ce carrefour. Allongez-la.',
        'junctions_too_close' => 'Ce carrefour et le suivant se touchent sur la voie %{road}. Écartez les croisements.',
        'junction_shape' => 'La forme de ce carrefour ne se construit pas. Changez l’angle ou le rayon des bordures.',
        'signals_without_carriageway' => 'Un carrefour à feux demande au moins une chaussée. Gardez un carrefour simple.',
        'no_room_for_signal' => 'Aucune bande ne porte le feu à droite de la chaussée de la voie %{road}. Ajoutez un trottoir ou un accotement.',
        'roundabout_without_carriageway' => 'Chaque branche d’un giratoire doit avoir une chaussée. Raccordez le chemin plus loin.',
        'ring_too_small' => 'La chaussée de la voie %{road} est trop large pour cet anneau. Agrandissez le rayon extérieur ou réduisez la largeur de l’anneau.',
        'roundabout_arms_too_close' => 'Deux entrées de ce giratoire se chevauchent. Agrandissez le rayon extérieur, réduisez le rayon d’entrée ou écartez les branches.',
        'pair_missing' => 'Un double giratoire nomme son second carrefour.',
        'unknown_pair' => 'Le second carrefour de ce double giratoire n’existe pas ou est le même.',
        'pair_already_set' => 'Le second carrefour de ce double giratoire est déjà réglé ou déjà jumelé.',
        'not_neighbours' => 'Les deux carrefours de ce double giratoire ne se suivent pas sur une même voie.',
        'link_too_short' => 'La liaison entre les deux anneaux ne fait que %{value} m, pour %{limit} m au moins. Écartez les carrefours ou réduisez les anneaux.',
        'tram_not_through' => 'Le tram doit traverser ce carrefour tout droit, sur une seule voie. Une seule voie à rails par carrefour ; pas de courbe de rails.',
        'tram_outside_carriageway' => 'Les rails de la voie %{road} sont hors de la chaussée : au carrefour, le tram roule dans la chaussée.',
        'add_road_in_edit' => 'Une voie s’ajoute en traçant un réseau. Ici, on règle les carrefours ou on retire une voie.',
        'too_many_roads' => 'Un réseau compte %{limit} voies au plus.',
        'unknown_road' => 'Cette voie n’est plus dans le réseau.',
        'first_road_kept' => 'La première voie porte l’origine du réseau : elle reste.',
        'no_road' => 'Tracez et ajoutez au moins une voie.',
        'not_a_network_root' => 'Ce composant n’est pas un réseau de voies ARCHGEN.',
        'survey_missing' => 'Cette voie suit un terrain : relevez-le d’abord.',
        'survey_axes' => 'Le relevé ne correspond plus à la voie. Relevez de nouveau.',
        'ground_missing' => 'Pas de terrain sous la voie à %{s_m} m du départ.',
        'ground_points' => 'Le relevé compterait %{value} points, pour %{limit} au plus. Augmentez le pas du relevé.',
        'grade_too_steep' => 'À %{s_m} m du départ, la pente atteint %{value} %, pour %{limit} % au plus.',
        'earthwork_too_high' => 'À %{s_m} m du départ, le terrain est à %{value} m de la voie, pour %{limit} m au plus.',
        'road_toe_not_found' => 'À %{s_m} m du départ, le talus n’atteint pas le terrain. Changez la pente du talus ou le tracé.',
        'not_on_ground' => 'Cette voie ne suit pas de terrain.',
        'ground_road_rotated' => 'Une voie posée sur un terrain ne doit pas être tournée. Annulez la rotation.',
        'crossing_roads' => 'Un passage à niveau réunit exactement une voie ferrée et une route sans rail.',
        'crossing_through' => 'La route et la voie ferrée doivent traverser le passage à niveau, sans y finir.',
        'crossing_angle' => 'La route croise la voie ferrée à %{value_deg}°, pour %{min_deg}° au moins.',
        'junction_levels' => 'Les niveaux de la voie %{road} ne se raccordent pas dans ce carrefour.',
        # Cible
        'target_not_found' => 'Le bâtiment sélectionné a changé. Rechargez la sélection.',
        'deleted_target' => 'Le bâtiment sélectionné a été supprimé. Rechargez la sélection.',
        'selection_not_single' => 'Sélectionnez un seul bâtiment ARCHGEN.',
        'selection_changed' => 'Le bâtiment sélectionné a changé. Rechargez la sélection.',
        'document_changed' => 'Le document a changé ou vient d’être enregistré. Rechargez la sélection.',
        'definition_changed' => 'Le bâtiment sélectionné a changé. Rechargez la sélection.',
        'revision_changed' => 'Le bâtiment sélectionné a changé. Rechargez la sélection.',
        'config_changed' => 'Le bâtiment sélectionné a changé. Rechargez la sélection.',
        'invalid_target' => 'Rechargez la sélection.',
        'unknown_token' => 'Rechargez la sélection.',
        'other_model' => 'Le document a changé ou vient d’être enregistré. Rechargez la sélection.',
        'not_a_component_instance' => 'Sélectionnez un bâtiment ARCHGEN.',
        'not_an_archgen_root' => 'Ce composant n’a pas été créé par ARCHGEN.',
        'not_at_model_root' => 'Ce bâtiment est dans un groupe ou un composant. Sortez-le au niveau du modèle.',
        'target_locked' => 'Ce bâtiment est verrouillé. Déverrouillez-le pour le modifier.',
        'non_rigid_transform' => 'Ce bâtiment a été mis à l’échelle ou en miroir. Rétablissez son échelle d’origine pour le régénérer.',
        'nested_edit_context' => 'Fermez le groupe ou le composant en cours d’édition.',
        'model_unavailable' => 'Aucun document n’est disponible.',
        # Version
        'unsupported' => 'Ce bâtiment vient d’une version plus récente d’ARCHGEN. Il reste consultable.',
        'newer_engine' => 'Ce bâtiment vient d’une version plus récente d’ARCHGEN. Il reste consultable.',
        'newer_materials' => 'Ce bâtiment utilise un catalogue de matériaux plus récent. Il reste consultable.',
        # Écriture
        'operation_in_progress' => 'Une écriture est déjà en cours.',
        'operation_not_started' => 'SketchUp n’a pas pu démarrer l’opération. Le modèle n’a pas été modifié.',
        'write_failed' => 'L’écriture a échoué et le modèle a été restauré.',
        'commit_failed' => 'L’écriture n’a pas pu être validée et le modèle a été restauré.',
        'abort_failed' => 'L’écriture a échoué et SketchUp n’a pas pu la défaire. Vérifiez le modèle avant de continuer.',
        'restore_incomplete' => 'L’écriture a échoué et le modèle n’a pas été entièrement restauré. Vérifiez le modèle avant de continuer.',
        'internal_error' => 'Une erreur inattendue est survenue. Le modèle n’a pas été modifié.',
        # Confirmation
        'confirmation_unknown' => 'Cette confirmation n’est plus valable. Un nouvel aperçu a été demandé.',
        'confirmation_expired' => 'La confirmation a expiré. Un nouvel aperçu a été demandé.',
        'confirmation_mismatch' => 'Les réglages ont changé depuis l’aperçu. Un nouvel aperçu a été demandé.',
        # Protocole
        'invalid_envelope' => 'Le panneau a envoyé une demande invalide. Rouvrez-le.',
        'unknown_action' => 'Le panneau a envoyé une demande inconnue. Rouvrez-le.',
        'unsupported_protocol' => 'Le panneau n’est pas à jour. Rouvrez-le.'
      }.freeze

      RULES = {
        'window_ratio' => 'Les proportions de fenêtre s’écartent de ce style (%{min} à %{max}).',
        'level_count' => 'Ce style compte habituellement de %{min} à %{max} niveaux.',
        'roof_type' => 'Ce type de toit s’écarte de ce style.',
        'material_allowed' => 'Ce matériau s’écarte de ce style.'
      }.freeze

      DEFAULT = 'Cette valeur n’est pas acceptée.'

      ENUM_LABELS = {
        '/roof/type' => { 'flat' => 'Plat', 'gable' => 'Deux pans', 'hip' => 'Croupe', 'mansard' => 'Mansarde' },
        '/mode' => { 'shell' => 'Shell', 'structural' => 'Structural' },
        '/building_type' => { 'residential' => 'Résidentiel', 'mixed_use' => 'Mixte' },
        '/fidelity' => { 'strict' => 'Stricte', 'plausible' => 'Plausible', 'creative' => 'Créative' },
        '/lod' => { 0 => 'LOD 0', 1 => 'LOD 1' }
      }.freeze

      # Texte imposé par le contrat de régénération, affiché à chaque remplacement.
      REPLACE_WARNING = 'La géométrie générée de ce bâtiment sera remplacée. Placez les ajouts à conserver dans des groupes séparés.'

      SITE_KEPT_WARNING = 'Son assise est conservée : le terrain sera relevé de nouveau et son altitude suivra la plateforme.'
      SITE_ADAPT_WARNING = 'La géométrie générée de ce bâtiment sera remplacée. Son altitude suivra la plateforme. Le terrain n’est pas modifié.'
      SITE_REMOVE_WARNING = 'L’assise de ce bâtiment sera retirée. Son altitude ne change pas et le terrain n’est pas modifié.'

      NOTICES = {
        'undo' => 'Une annulation a eu lieu. Rechargez la sélection.',
        'redo' => 'Un rétablissement a eu lieu. Rechargez la sélection.',
        'selection' => 'La sélection a changé. Rechargez-la pour continuer l’édition.',
        'document' => 'Le document a changé. Rechargez la sélection.'
      }.freeze

      module_function

      def text(diagnostic)
        params = diagnostic.params
        template = (params['rule'] && RULES[params['rule']]) || REASONS[params['reason']] || DEFAULT
        template.gsub(/%\{(\w+)\}/) { decimal(params[Regexp.last_match(1)]) }
      end

      # Les valeurs d'une assise, telles que le panneau les montre avant de confirmer.
      def site_lines(metrics)
        lines = ["Altitude de la plateforme : #{decimal(metrics['platform_z_m'])} m",
                 "Remblai maximal : #{decimal(metrics['fill_max_m'])} m, soit #{decimal(metrics['fill_volume_m3'])} m³",
                 "Déblai maximal, non représenté : #{decimal(metrics['cut_max_m'])} m, soit #{decimal(metrics['cut_volume_m3'])} m³"]
        lines << "Emprise du talus : #{decimal(metrics['embankment_reach_m'])} m" if metrics['embankment_reach_m'].positive?
        lines
      end

      # Les valeurs d'un étagement, telles que le panneau les montre avant de confirmer.
      def ensemble_site_lines(metrics)
        ["Plateformes : de #{decimal(metrics['platform_min_z_m'])} à #{decimal(metrics['platform_max_z_m'])} m ; ressaut maximal : #{decimal(metrics['max_step_m'])} m",
         "Remblai maximal : #{decimal(metrics['fill_max_m'])} m, soit #{decimal(metrics['fill_volume_m3'])} m³",
         "Déblai maximal, non représenté : #{decimal(metrics['cut_max_m'])} m, soit #{decimal(metrics['cut_volume_m3'])} m³",
         "Relevé : #{metrics['survey_point_count']} points ; assises : #{metrics['expanded_site_face_count']} faces"]
      end

      def field_label(path)
        FIELDS[path]
      end

      # Virgule française pour les nombres affichés ; pas de séparateur pour le reste.
      def decimal(value)
        return value.to_s unless value.is_a?(Numeric)

        rounded = value.is_a?(Float) ? value.round(2) : value
        rounded = rounded.to_i if rounded.is_a?(Float) && rounded == rounded.floor
        rounded.to_s.tr('.', ',')
      end

      # Une valeur lisible pour le résumé des changements.
      def value_text(value, path = nil)
        label = ENUM_LABELS.dig(path, value)
        return label if label

        case value
        when true then 'oui'
        when false then 'non'
        when nil then '—'
        when Array then value.empty? ? '—' : value.map { |v| decimal(v) }.join(' ; ')
        when Numeric then decimal(value)
        else value.to_s
        end
      end

      def to_h(diagnostic)
        diagnostic.to_h.merge('message' => text(diagnostic), 'field' => field_label(diagnostic.path))
      end
    end
  end
end
