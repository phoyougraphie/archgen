# frozen_string_literal: true

module Archgen
  module UI
    # Textes du panneau, identifiés par raison : l'interface ne reproduit aucune règle,
    # elle affiche ce que le noyau a décidé. Français au départ, traduisible ici.
    module Messages
      SIGNATURES = {
        'haussmann' => 'Pierre claire, baies verticales, mansarde ; corniche et balcon filant au LOD 1.',
        'toulousain' => 'Brique foraine, toit en tuile canal, baies verticales ; encadrements au LOD 1.',
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
        '/site/platform' => 'Plateforme', '/site/platform/policy' => 'Altitude de plateforme', '/site/platform/offset_m' => 'Décalage de plateforme',
        '/site/earthwork' => 'Terrassement', '/site/embankment_ratio' => 'Pente du talus', '/site/plinth_material' => 'Matériau du soubassement',
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
        'toe_not_found' => 'Le talus n’atteint pas le terrain de ce côté, qui descend trop vite. Raidissez la pente ou choisissez le soubassement.',
        'door_buried' => 'Le terrain dépasse le seuil de la porte de %{value} m. Remontez la plateforme ou changez la travée d’entrée.',
        'door_gap' => 'Le seuil de la porte est à %{value} m au-dessus du terrain : aucun escalier n’est généré.',
        'terrain_above_platform' => 'Le terrain dépasse la plateforme de %{value} m et traverse le bâtiment. Baies touchées : %{count}.',
        'site_faces' => 'Le terrassement est trop détaillé. Augmentez le pas du relevé.',
        'total_faces' => 'Le bâtiment et son terrassement dépassent la limite de %{limit} faces. Augmentez le pas du relevé ou réduisez le niveau de détail.',
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
