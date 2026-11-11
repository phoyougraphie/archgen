# Contrat des styles régionaux maçonnés — J13 (AG-074 à AG-078)

**Demande du propriétaire (2026-11-09).** « On les fait tous, en créant les éléments nécessaires au fur et à mesure » : tous les styles du [catalogue](../examples/style-catalogue.v1.json), plus des régionaux faisables avec l'existant. Le propriétaire délègue les choix de détail (ADR-48) : chaque contrat de lot retient les options recommandées, les consigne, et reste révisable par lui.

## Plan d'ensemble des lots

Un style n'est publié qu'avec les capacités qu'il requiert, chacune livrée et testée avant lui (AGENTS, règle 5). Les lots vont du moins au plus de géométrie nouvelle ; chacun a son contrat écrit au moment de le commencer.

| Lot | Capacités nouvelles | Styles |
|---|---|---|
| **J13 — Régionaux maçonnés** (ce contrat) | Génoises ; matières régionales | Provençal (mas, maison de village), Breton (longère, maison de bourg), Lyonnais, Bordelais (échoppe), Parisien faubourien |
| J14 — Pignon sur rue et montagne (fait, [contrat](PIGNON_MONTAGNE_CONTRACT.md)) | Axe de faîtage perpendiculaire à la rue, pignon à redents, grands débords, bardage bois | Flamand, Savoyard |
| J15 — Pan de bois (EXT-02, fait, [contrat](PAN_DE_BOIS_CONTRACT.md) ; encorbellement reporté) | Ossature apparente, encorbellement | Maison à colombages, Normand, Alsacien, Basque |
| J16 — Arcs et ornements (EXT-03, fait, [contrat](ARCS_ORNEMENTS_CONTRACT.md)) | Arc plein cintre et brisé, meneaux, ordres, fronton, avant-corps, reliefs, baies courbes, patio | Roman, Gothique, Renaissance, Néoclassique, Baroque, Art déco, Art nouveau, Méditerranéen (variantes cycladique, andalouse) |
| J17 — Volumes modernes (EXT-04, fait, [contrat](VOLUMES_MODERNES_CONTRACT.md)) | Volumes assemblés, mur-rideau, fenêtres en bandeau, pilotis, sheds, trame structurelle, protections solaires | Bauhaus, Moderniste, Mid-century, Contemporain minimaliste, Industriel, High-tech, Bioclimatique |

**Variantes régionales.** Le catalogue demande de distinguer, par exemple, longère et maison de bourg bretonnes. Une variante est un **profil à part** de la même famille, nommé « Breton — longère » : aucune capacité `regional_variant` n'est nécessaire, et chaque variante garde ses calibrages et règles.

## 1. Génoises — AG-074

Option `features.genoise` (booléen), LOD 1 ; décochée, non écrite (refus `genoise_false_written`).

| Élément | Géométrie (départ) |
|---|---|
| **Rangs** | Deux rangs de tuiles en encorbellement sous l'égout, façades avant et arrière : rang du haut de z = H − 0,10 à H, en saillie de 0,16 m ; rang du bas de H − 0,20 à H − 0,10, en saillie de 0,08 m. Matière `materials.roof` (terre cuite) |
| **Étendue** | D'un bout de la façade à l'autre ; en rangée d'angle, coupée à l'onglet en façade avant comme la corniche, raccourcie de sa saillie à chaque bout en façade arrière |
| **Toits** | Deux pans et croupe seulement ; sur un toit plat ou une mansarde, rien et un avertissement `W_DETAIL` (`genoise_roof`) |
| **Refus** | Avec une corniche : `genoise_with_cornice` sur `/features/genoise`. Une fenêtre dont la tête passe au-dessus de H − 0,30 : `genoise_head_margin`, avec son id |

- **Fait (AG-074).** Le rang du haut s'arrête sous la peau du toit prolongée au droit de sa saillie (H − pente × 0,16) : rien ne traverse le toit. Catégorie `genoise`. Tests U51 (`test/unit/genoise_test.rb`) ; empreintes des ensembles types identiques. Pas de case au panneau avant AG-078.

## 2. Matières régionales — avec AG-075

Nouvelles entrées du catalogue : enduit ocre, enduit clair, pierre blonde, pierre dorée (Lyon), granit, schiste, ardoise, tuile mécanique, bois peint gris, bois peint rouge basque (pour J15). Couleurs moyennes, sans texture.

## 3. Profils — AG-075 à AG-077

Calibrages du catalogue (niveaux ; hauteur d'étage ; pente) et règles historiques (`level_count`, `roof_type`, `window_ratio`, `material_allowed`) pour chaque profil.

| Profil | Volume et toit | Matières | Détails cochés |
|---|---|---|---|
| **Provençal — mas** (AG-075) | 2 niveaux de 2,8 m, deux pans à 22°, débord 0,10 | Enduit ocre, tuile canal, bois peint | Génoise, volets (vert), petits bois, vitrage, cheminées |
| **Provençal — maison de village** | 3 niveaux de 2,9 m, deux pans à 22° | Enduit clair, tuile canal | Génoise, volets (bleu pastel), petits bois, vitrage |
| **Breton — longère** (AG-076) | 1 niveau de 2,6 m, deux pans à 45°, façade large et peu profonde | Granit, ardoise | Lucarnes, cheminées, petits bois, vitrage |
| **Breton — maison de bourg** | 2 niveaux de 2,8 m, deux pans à 45° | Schiste ou granit enduit, ardoise | Lucarnes, cheminées, encadrements, petits bois, vitrage |
| **Lyonnais** (AG-077) | 5 niveaux de 3,0 m, deux pans à 20°, fenêtres hautes | Pierre dorée, tuile canal | Encadrements, petits bois, vitrage, volets (gris) |
| **Bordelais — échoppe** | 1 niveau de 3,6 m, toit plat caché, corniche | Pierre blonde | Corniche, encadrements, petits bois, vitrage |
| **Parisien faubourien** | 4 niveaux de 3,0 m (2,9 m ne laissait pas passer le porche d'îlot), deux pans à 30° | Enduit clair, tuile mécanique | Encadrements, volets (gris), petits bois, vitrage |

- **Fait (AG-075).** Profils `provencal_mas` et `provencal_village` (famille `masonry_vernacular`), écrits par `scripts/regional_profiles.rb` (qui refuse d'écraser une révision publiée changée) ; dix matières régionales au catalogue ; règle `material_allowed` du mur en `soft`. Tests U52 (`test/unit/regional_profiles_test.rb`), à étendre à chaque profil du lot.
- **Fait (AG-076).** Profils `breton_longere` et `breton_bourg`.
- **Fait (AG-077).** Profils `lyonnais`, `bordelais_echoppe`, `parisien_faubourien`.
- Formes d'accès d'îlot : porche pour Lyonnais et Parisien faubourien ; accès par interruption pour les autres.
- Chaque profil est vérifié par défaut en bâtiment seul (deux modes, LOD 0 et 1), en rue droite, en rue à angle et en îlot, avant d'être publié.

## 4. Panneaux et version — AG-078

Le panneau propose déjà tous les styles actifs ; la liste devient longue : groupement par famille (« Vernaculaire maçonné », « Façade ordonnancée », « Moderne modulaire »). Case Génoise dans les trois panneaux. Guide, journal ; **RBZ 0.14.0** ; recette **H29** à la main.

- **Fait (AG-078).** Le panneau du bâtiment et celui de la rue reçoivent, avec chaque style, le libellé de sa famille et rangent la liste en groupes ; même ordre dans les deux. Case Génoise aux trois panneaux (champ `genoise` des réglages propres). RBZ 0.14.0. **Recette H29 dans SketchUp non faite** (laissée au propriétaire).

## 5. Styles côtiers et maison moderne — AG-133 (ADR-61)

**Balcons à tous les étages.** Option `features.balcony_levels` : `noble` (défaut, niveaux d'index 2 et 5, non écrite dans la configuration) ou `all` (un balcon au plancher de chaque étage au-dessus du rez-de-chaussée, façade avant). Mêmes balcons, garde-corps et refus qu'avant (`balcony_over_opening`). Liste « Étages des balcons » au panneau du bâtiment.

| Profil | Famille | Volume et toit | Matières | Détails |
|---|---|---|---|---|
| **Côtier — front de mer (La Baule)** `baule_front_de_mer` | Moderne modulaire | 8 niveaux de 2,8 m (4 à 12), 22 × 14 m, toit plat ; baies de 2,0 × 2,2 m ; commerce de 3,6 m si coché | Enduit clair, menuiseries peintes claires | Balcons filants de 1,8 m à chaque étage, garde-corps à barreaux, vitrage |
| **Maison individuelle moderne** `maison_moderne` | Moderne modulaire | 2 niveaux de 2,7 m (1 à 2), 12 × 9 m, toit plat (deux pans permis) ; baies de 1,8 × 2,1 m | Enduit clair en bas, bardage bois naturel à l'étage, menuiseries anthracite | Bardage, vitrage |
| **Côtier — villa balnéaire (La Baule, Pornichet)** `baule_villa` | Pan de bois | 2 niveaux de 2,9 m (1 à 3), 10 × 11 m, deux pans à 50°, débord 0,6 m, faîtage perpendiculaire (pignon sur rue) | Enduit clair, pan de bois sombre, ardoise | Pan de bois, petits bois, cheminées, vitrage |

- Accès d'îlot : interruption pour les trois (le porche ne tient pas sous un rez-de-chaussée de 2,8 m).
- **Fait (AG-133).** Profils écrits par `scripts/regional_profiles.rb`, vérifiés par U52 en bâtiment seul, rue, rue à angle et îlot ; U95 pour les balcons. RBZ 0.29.0. **Vu dans SketchUp : non** (laissé au propriétaire).
- **Recadrage (AG-134, ADR-62)**, sur photos du front de mer : option `features.balcony_depth_m` (0,6 à 2,5 m, défaut 0,90 non écrit), champ « Profondeur des balcons » au panneau du bâtiment ; balcons de 1,8 m à barreaux, baies de 2,0 m, commerce de 3,6 m. Reportés : garde-corps vitré, attique en retrait, balcons d'angle, bow-windows.
- **Attique et verre (AG-135, ADR-63).** `levels.attic_setback_m` et garde-corps `glass` ; le front de mer prend un attique de 2,5 m et un garde-corps vitré. Champs « Retrait de l'attique » et « Vitré » au panneau du bâtiment.
- **Bâtiments isolés (AG-136, ADR-64).** Voir [ENSEMBLE_CONTRACT](ENSEMBLE_CONTRACT.md), Bâtiments isolés.
- **Balcons d'angle et bow-windows (AG-137, ADR-65).** Case « Balcons qui tournent l'angle », liste « Bow-window » (travée centrale, travées des bouts) au panneau du bâtiment.
- **Maisons de La Baule (AG-140 à AG-142, ADR-67).** Palette tirée par la graine (`palette` du profil) ; rôle de matière `surrounds` ; villa révision 2 (pignon, pan de bois rouge, sombre ou vert, ou encadrements de brique ; mur enduit ou granit), villa à quatre pans (volets rouges, bleus, verts ou gris ; encadrements de granit ou de brique), maison de ville (granit, enduit ou schiste ; brique, granit ou blanc ; lucarnes ; commerce 3,6 m). Collées en rangée, ou isolées (case Bâtiments isolés) ; la villa à quatre pans, à croupe, ne se pose qu'isolée.
- **Détails de La Baule (AG-143, ADR-68).** Cases « Bandeaux aux planchers », « Lucarnes passantes », « Tourelle d'angle », « Balconnets en fer forgé » et bow-window « Rez-de-chaussée » au panneau du bâtiment ; tirés aussi par les palettes des trois styles de La Baule.
- **Ailes en L, T, U (AG-138, AG-139, ADR-66).** Liste « Forme » et dimensions de l'aile au panneau du bâtiment ; l'import de carte reconnaît les contours en L, T et U.

## Tests

- **U51** génoises : rangs et saillies, toits pris en charge, refus et avertissement, rangée d'angle.
- **U95** balcons à tous les étages : sept balcons sur un immeuble de huit niveaux ; `noble` garde 2 et 5 et n'est pas écrit.
- **U52** profils régionaux : chaque profil valide, ses règles, ses défauts en bâtiment, rue et îlot sous le budget.
- Ensembles types d'avant : mêmes empreintes.

## Hors périmètre

Les lots J14 à J17 (contrats à écrire au moment de les commencer) ; textures photographiques ; génoise sur pignon.
