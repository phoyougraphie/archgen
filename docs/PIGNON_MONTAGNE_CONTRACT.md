# Contrat du pignon sur rue et des styles de montagne — J14 (AG-079 à AG-082)

Lot J14 du plan des styles ([régionaux](STYLES_REGIONAUX_CONTRACT.md), ADR-48 : choix de détail délégués, options recommandées retenues et consignées ici). Valeurs « départ » à calibrer à la recette.

## Règle commune de format

Comme J11 à J13 : chaque réglage est une clé facultative, sans changement de version de format ; absente, elle vaut « désactivé » et n'est pas écrite. L'existant garde son plan.

## 1. Faîtage perpendiculaire à la rue — AG-079

Réglage `roof.ridge` : `"parallel"` (défaut, non écrit) ou `"perpendicular"`, **toit à deux pans seulement** ; donné avec un autre toit, refus `E_ROOF_GEOMETRY`, `ridge_axis_roof`, sur `/roof/ridge`. Un style qui le coche par défaut le perd sans bruit si l'on choisit un autre toit : c'est la valeur du style, pas une saisie.

| Élément | Géométrie |
|---|---|
| **Bâtiment seul** | Faîtage au milieu de la largeur, de l'avant à l'arrière ; pignons triangulaires sur les façades avant et arrière ; pans sur les côtés, débord sur les quatre rives |
| **Rangée** | Même toit, sans débord latéral (les égouts se rejoignent au-dessus du mur mitoyen) ; débord avant et arrière gardé |
| **Parcelle d'angle** | Garde un faîtage parallèle à la rue (son plan d'onglet n'a pas de pignon droit) ; avertissement `W_DETAIL`, `ridge_corner` — rien n'est changé en silence |
| **Détails** | Cheminées : au faîtage, contre les murs avant et arrière. Lucarnes : aucune, avertissement `dormer_ridge`. Génoise : aucune, avertissement `genoise_roof`. Corniche : sous le pignon, inchangée |

- **Fait (AG-079).** `RoofSolver.cross_gable` (pans `roof/left`, `roof/right`, pignons `roof/gable/front`, `roof/gable/rear`) ; en rangée, `side_overhang: false`. Le moteur passe au détail le faîtage effectivement posé. Tests U53 (`test/unit/cross_ridge_test.rb`) ; empreintes des ensembles types identiques. Pas de liste au panneau avant AG-082.

## 2. Pignon à redents — AG-080

Option `features.stepped_gable` (booléen), LOD 1, **seulement avec un faîtage perpendiculaire** (sinon refus `stepped_gable_ridge`). Le pignon avant monte au-dessus du toit en marches : 5 marches de chaque côté (départ), chaque marche dépassant la pente de 0,30 m, couronnée au faîte par un pinacle de 0,40 m ; épaisseur 0,30 m, posée 0,05 m devant le nu du mur pour couvrir le pignon du toit. Matière `materials.wall`.

- **Fait (AG-080).** Marches empilées en solides, catégorie `stepped_gable` ; refus `stepped_gable_ridge` et, pour qu'aucun débord ne passe devant les marches, `stepped_gable_overhang` au-delà de 0,05 m de débord ; parcelle d'angle : omis et dit (`stepped_gable_corner`).

## 3. Bardage bois et débords profonds — AG-081

Option `features.cladding` (booléen), avec un rôle de matière `materials.cladding` (écrit seulement avec l'option ; par défaut `natural_wood`, nouvelle entrée « Bois naturel », et « Bois sombre »). Les murs du **dernier niveau** et les pignons prennent la matière du bardage ; les balcons aussi. Les débords de toit jusqu'à 1,00 m existent déjà (`roof.overhang_m`).

- **Fait (AG-081).** Les cellules de mur du dernier niveau prennent la matière du bardage (les deux modes) ; pignons du toit et balcons aussi. Catalogue : bois naturel, bois sombre, brique rouge (pour le Flamand). Tests U54 (`test/unit/gable_and_cladding_test.rb`) ; empreintes des ensembles types identiques.

## 4. Profils et panneaux — AG-082

| Profil | Volume et toit | Matières | Détails |
|---|---|---|---|
| **Flamand** | 3 niveaux de 3,0 m, façade étroite (7 m), deux pans à 50°, faîtage perpendiculaire | Brique rouge, tuile mécanique | Pignon à redents, petits bois, vitrage, encadrements |
| **Savoyard — chalet** | 2 niveaux de 2,7 m, deux pans à 25°, débord 1,00 m, faîtage perpendiculaire | Pierre en bas, bois naturel en haut, ardoise | Bardage, balcons, volets (bois sombre), petits bois, vitrage |

Panneaux : liste « Faîtage » (parallèle, perpendiculaire) pour un toit à deux pans ; cases Pignon à redents et Bardage (avec sa matière) aux trois panneaux. **RBZ 0.15.0** ; recette **H30** à la main.

- **Fait (AG-082).** Profils `flamand` (débord 0) et `savoyard_chalet` (trois niveaux, pour que le balcon du niveau 2 existe sous le bardage). Liste Faîtage au panneau du bâtiment, montrée pour deux pans seulement ; cases Pignon à redents et Bardage (avec sa matière) aux trois panneaux ; au panneau de rue et de parcelle, le faîtage reste celui du style. RBZ 0.15.0. **Recette H30 dans SketchUp non faite** (laissée au propriétaire).

## Tests

- **U53** faîtage perpendiculaire : pans et pignons, rangée sans débord latéral, angle averti, refus hors deux pans, détails.
- **U54** pignon à redents et bardage.
- **U52** étendu aux deux profils.
