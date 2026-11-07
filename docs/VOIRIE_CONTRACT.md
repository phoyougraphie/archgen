# Contrat de voirie : coupe, tronçon, carrefour — EXT-11

Contrat de départ, à valider avant le code, sur la [maquette](maquettes/voirie-coupe.html). Il ne change ni le plan d'un bâtiment, ni celui d'un ensemble. Décisions : ADR-34 ; questions ouvertes : D-07 à D-10. Les valeurs marquées « départ » sont à calibrer à la recette, par une décision écrite.

**Besoin du propriétaire (2026-11-07).** Trottoir, chaussée, chemin piéton, voie cyclable, barrières, haies, « clous », arbres et lampadaires de plusieurs types et hauteurs. D'abord une vue en coupe avec un repère d'échelle humain. Dire facilement combien d'éléments, quelle mesure pour chacun, dans quel ordre. Des carrefours : simple, à feux, rond-point, double rond-point. Des routes de l'autoroute à la route de campagne à fossés et au chemin piéton. Des rails de train et de tramway, et une voie où tram et voiture roulent ensemble. Le mobilier urbain pur viendra ensuite, peut-être en module séparé (EXT-12).

## Principes

- **La coupe est la source.** Une voie se compose dans la coupe. Le tronçon, le plan et les branches de carrefour en sont déduits : aucune largeur n'est ressaisie ailleurs.
- **Échelle réelle.** La coupe du panneau est dessinée à l'échelle unique en largeur et en hauteur, avec un personnage de 1,75 m et, en option, les gabarits de véhicules. Ces repères ne sont jamais écrits dans le modèle.
- **Registre fermé.** Types de bandes et d'éléments viennent de catalogues versionnés. Une clé inconnue est refusée ; un profil n'exécute jamais de code.
- **Valeurs de conception.** Plages et préréglages servent à composer une maquette. **Ce n'est pas une vérification du code de la route, de l'accessibilité ni des normes de voirie**, et le panneau le dit.
- **Noyau pur :** coupe et tracé en mètres → plan de voie déterministe. Seuls l'outil de tracé et le writer touchent à SketchUp.
- **Une validation, un Annuler.** Un refus laisse le document intact, avec un diagnostic sur la bande, l'élément, le segment ou le nœud en cause. Rien n'est corrigé en silence : une largeur hors plage n'est pas ramenée dans la plage.

## Format `road_profile` V1

Format séparé, clés inconnues refusées. Les bandes vont de gauche à droite dans le sens du tracé ; un bouton Miroir inverse l'ordre.

```json
{ "road_profile_version": 1, "name": "Rue de ville",
  "bands": [ { "type": "sidewalk", "width_m": 2.5,
               "items": [ { "kind": "lamp", "variant": "heritage", "height_m": 5, "spacing_m": 22 } ] } ] }
```

De 1 à 32 bandes (départ), au plus 6 éléments par bande (départ). Un préréglage n'est qu'un profil de départ recopié : la voie enregistre ses valeurs effectives, pas une référence au préréglage.

**Champs** ([schéma](../schemas/road-profile.v1.schema.json)) : `bands` obligatoire ; `road_profile_version` vaut 1, une autre valeur donne `E_VERSION` ; `name` facultatif, de 1 à 60 caractères, absent s'il n'est pas saisi. Une bande exige `type` et `width_m`. Un élément exige `kind` ; `variant`, `height_m` et `spacing_m` prennent les valeurs du catalogue. Le profil effectif est complet : chaque élément répété porte son pas, chaque arbre sa variation (0 par défaut). Les longueurs sont quantifiées au micromètre, comme ailleurs.

**Catalogues :** références dans `examples/`, copies embarquées identiques dans `archgen/styles/road/`, vérifiées par test (ADR-13). Chaque bande porte aussi son rôle (`carriageway`, `tram`, `rail`, `cycle`, `pedestrian`, `median`, `verge`, `planting`, `ditch`, `bank`), ses rails (`none`, `embedded`, `platform`, `ballast`), `accepts_items` et, pour les voies où passent des véhicules, `clearance_m` : 4,5 m (départ) sur `lane`, `tram_lane`, `tram` et `rail`.

### Bandes (`road_bands.v1.json`)

| Clé | Libellé | Défaut (m) | Plage (m) | Niveau (m) | Forme |
|---|---|---|---|---|---|
| `lane` | Voie de circulation | 3,5 | 2,5 à 4,5 | 0 | Plane |
| `hard` | Bande d'arrêt d'urgence | 2,5 | 1,5 à 3,5 | 0 | Plane |
| `edge` | Bande dérasée | 1 | 0,3 à 2 | 0 | Plane |
| `parking` | Stationnement | 2,2 | 1,8 à 5,5 | 0 | Plane, places marquées |
| `tram_lane` | Voie mixte tram et voitures | 3,3 | 2,9 à 4,5 | 0 | Plane, rails encastrés |
| `tram` | Plateforme tram | 3,2 | 2,8 à 4,5 | 0,05 | Plane, rails |
| `rail` | Voie ferrée sur ballast | 4,5 | 3,5 à 6 | 0,35 | Ballast, traverses, rails |
| `cycle` | Voie cyclable | 2 | 1 à 5 | 0,02 | Plane |
| `sidewalk` | Trottoir | 2,5 | 0,9 à 12 | 0,14 | Plane |
| `path` | Chemin piéton | 2 | 0,9 à 8 | 0,02 | Plane |
| `track` | Chemin empierré | 3 | 2 à 6 | 0,02 | Plane |
| `median` | Terre-plein central | 3 | 0,5 à 20 | 0,14 | Plane |
| `verge` | Accotement | 1,5 | 0,3 à 6 | 0 | Plane |
| `plant` | Bande plantée | 1,5 | 0,5 à 15 | 0,05 | Plane |
| `ditch` | Fossé | 1,5 | 0,6 à 5 | 0 | Trapèze de 0,6 m de creux |
| `bank` | Talus | 2,5 | 1 à 12 | 0 | Pente de 40 %, montant vers l'extérieur |

Hors plage ou type inconnu : `E_ROAD_BAND` sur `/bands/<i>/…`. **Bordure :** entre deux bandes planes dont le niveau diffère d'au moins 0,10 m, une bordure de 0,16 m est ajoutée d'office, à l'intérieur de la largeur des bandes. Aucune colonne de largeur n'est donc cachée.

**Rails :** écartement standard de 1,435 m, centré sur la bande. Plusieurs voies parallèles sont plusieurs bandes. D'autres écartements, comme le métrique, sont hors de cette version.

**Rails dans le plan (AG-041, U26) :** deux rails par bande, à ± 0,7175 m de son milieu, suivis le long de l'axe comme toute ligne de pose : l'écartement reste exact en droite, en courbe et à l'onglet.

- **Voie mixte et plateforme tram :** champignon de 0,07 m **dans le plan de la surface**, en bande de matière `road/rail_steel` qui partage les sommets de la chaussée. Aucune face n'est superposée à une autre, ce qui évite le scintillement de deux faces coplanaires dans SketchUp. Pas de gorge.
- **Voie sur ballast :** chaque rail est un profilé fermé de 0,07 × 0,17 m, dessus à la cote de la coupe (niveau du ballast + 0,17 m). Les traverses font 2,60 × 0,25 × 0,15 m, au milieu de la bande, tous les 0,60 m à partir de 0,30 m ; leur dessus dépasse le ballast de 2 cm. Elles forment une définition partagée, `sleeper`, sous un groupe `road/sleepers`.
- **Plafond, `road_sleepers` :** 20 000 traverses (départ), à part des 5 000 objets : une voie double de 2 km en compte 6 666.
- **Matériau :** `road/rail_steel`, distinct de `road/rail`, qui est la bande de ballast.
- **Métriques :** `rail_count` (rails sur ballast), `sleeper_count` ; `item_count` compte toutes les instances, traverses comprises.

### Éléments (`road_items.v1.json`)

Un élément appartient à une bande. Ses positions en travers se répartissent à parts égales dans la bande : avec n éléments, le j-ième est à `(j + 1) / (n + 1)` de sa largeur.

| Clé | Variantes | Hauteur (m) | Répétition | Écriture |
|---|---|---|---|---|
| `tree` | `round`, `columnar`, `wide`, `conifer` | 3 à 30 | Pas de 1 m au moins, 9 m par défaut | Définition partagée par couple variante/hauteur |
| `lamp` | `single`, `double`, `ped`, `heritage`, `high` | 3 à 30 | Pas de 1 m au moins, 28 m par défaut | Idem ; la crosse se tourne vers la chaussée la plus proche |
| `bollard` | `bollard` | 0,5 à 1,5 | Pas de 1 m au moins, 2,5 m par défaut | Idem |
| `pole` | `pole` | 5 à 10 | Pas de 1 m au moins, 40 m par défaut | Poteau avec potence, sans fil continu au départ |
| `hedge` | `hedge` | 0,5 à 5 | Continu | Extrusion le long de l'axe |
| `fence` | `fence`, `mesh` | 0,6 à 3 | Continu | Extrusion simple |
| `guard` | `guard`, `concrete` | 0,6 à 1,5 | Continu | Extrusion simple |

- **Répétition :** le premier objet est à `spacing_m / 2` de l'origine du tronçon, puis tous les `spacing_m` mesurés le long de la ligne de pose. Un objet qui tomberait hors du tronçon n'est pas posé.
- **Variation :** `height_variation` optionnel, de 0 à 0,3, arbres seulement. Pour une hauteur h et une variation v, chaque arbre prend l'une des trois hauteurs h(1 − v), h, h(1 + v), tirée par `unit(seed, "road/item/<bande>/<élément>/<rang>")`. Les trois doivent rester dans la plage de hauteur. Chaque hauteur reste une définition partagée. Sans variation, tous les arbres ont la même hauteur.
- **Refus, `E_ROAD_ITEM` :** type, variante inconnus ; hauteur hors plage (`height_range`) ; pas sous le minimum (`spacing_range`) ; pas sur un élément continu (`continuous_item`) ; variation sur un autre élément qu'un arbre (`variation_unavailable`) ou qui sort de la plage (`variation_range`) ; tout élément dans un `ditch` (`band_accepts_no_items`).
- **Avertissement, `W_ROAD_CLEARANCE`,** sur l'élément : la couronne d'un arbre recouvre en plan une bande à `clearance_m`, et son bas est plus bas que cette hauteur, pour l'une des trois hauteurs. Couronne : rayon et hauteur du bas en proportion de la hauteur, par variante, dans le catalogue ; position en travers comme ci-dessus.
- **Avertissement, `W_ROAD_COMPOSITION`,** sur la première des deux bandes : voie ferrée contre une chaussée (`rail_next_to_carriageway`), fossé contre une chaussée sans accotement (`ditch_next_to_carriageway`). Les avertissements ne bloquent pas.

### Pose le long de la voie (AG-040, U25, ADR-35)

- **Ligne de pose :** la ligne de l'axe décalée à la position en travers de l'élément ; sur un arc elle est plus courte ou plus longue que l'axe, et la répétition se mesure sur elle.
- **Répétés :** une instance par position, à `spacing_m / 2` puis tous les `spacing_m`, jamais au-delà de la ligne. Repère de l'instance : X le long de la ligne, Y vers la chaussée la plus proche (`toward` de la coupe ; sans chaussée, à gauche), Z vers le haut, pied au niveau de la surface. Une crosse, une potence de caténaire ou un bras de lampadaire pointe donc vers la voie.
- **Définitions partagées :** une par type, variante et hauteur au millimètre, identifiant `<type>/<variante>/<hauteur en mm>`.
- **Formes (ADR-35) :** volumes fermés à facettes, couleurs unies, mêmes proportions que la coupe de l'éditeur. Arbre : tronc hexagonal, couronne ellipsoïde à 8 pans (cône pour le conifère) inscrite dans le rayon et la base du catalogue ; vue de face, un octogone paraît jusqu'à 8 % plus étroit que son rayon. Lampadaire : mât, crosse de 1,5 m et tête ; globe, lanterne ou plateau de grand mât sans jamais dépasser la hauteur. Potelet : cylindre de 0,10 m. Poteau de caténaire : mât et potence de 2,6 m, sans fil. 24 à 50 faces par définition.
- **Continus :** solide fermé extrudé le long de la ligne, fermé aux deux bouts. Haie : 0,80 m de large. Barrière à lisses : deux lisses, poteaux de 0,10 m tous les 2 m. Grillage : panneau, poteaux de 0,06 m tous les 2,5 m. Glissière métallique : lisse de 0,31 m en tête, poteaux tous les 2 m. Glissière béton : profil en trapèze de 0,60 m à la base et 0,16 m en tête. Un poteau à chaque bout et à chaque pas.
- **Plafonds, `E_ROAD_BUDGET` sur `/trace` :** `road_items` au-delà de 5 000 objets et poteaux, estimé avant la pose ; `road_faces` au-delà de 60 000 faces distinctes (surface, éléments continus, définitions) ; `road_expanded_faces` au-delà de 600 000 faces une fois les instances comptées (départ).
- **Plan :** sous la racine `road`, la surface, un groupe `linear` et un groupe `item` d'instances ; `definitions` à part. Métriques ajoutées : `linear_face_count`, `definition_count`, `item_count`, `unique_face_count`, `expanded_face_count` ; `face_count` devient `surface_face_count`.

### Préréglages (`road_presets.v1.json`)

Autoroute, route à deux voies, route de campagne à fossés, chemin rural, boulevard planté, rue de ville, rue tram et voitures, tram en site propre, voie ferrée double, voie verte, chemin piéton. Leur composition est figée dans le fichier, dans cet ordre, et chacun est accepté sans avertissement (U23). Le contrôle de couronne a corrigé la maquette : sur un terre-plein de 4 m, l'arbre colonnaire de 14 m du boulevard surplombait une voie à 2,24 m du sol ; le terre-plein mesure donc 6 m.

## Éditeur de coupe

Menu **Extensions > ARCHGEN > Composer une coupe de voirie** (AG-038, recette [H19](recette/H19.md)). Panneau local, modeless, sans réseau, français, mêmes règles que le panneau existant. Le noyau reste seul juge : le panneau affiche ses diagnostics et ne reproduit aucune règle. **Il n'écrit rien dans le modèle** et n'ajoute aucune ligne d'Annuler.

- **Combien :** ajouter une bande après la bande choisie, la retirer, changer son type (la largeur reprend alors celle du catalogue). Pas de duplication dans cette version.
- **Quelle mesure :** saisir la largeur (virgule ou point), ou glisser la poignée bleue sous la limite de deux bandes ; le glissement règle la bande de gauche, au pas de 5 cm, dans la plage du catalogue.
- **Quel ordre :** déplacer une bande vers la gauche ou la droite, Miroir.
- **Quoi dessus :** pour la bande choisie, ajouter un élément, sa variante, sa hauteur, son pas, et la variation d'un arbre.
- **Repères :** personnage de 1,75 m qu'on déplace le long de la coupe, gabarits de voiture, bus, tram, train, cycliste, emprise totale, barre d'échelle. Ils ne sont jamais écrits dans le modèle.
- **Vue en plan** du tronçon, avec le nombre d'objets pour 100 m.
- **Refus :** la bande en cause passe en rouge avec son message ; la coupe affichée reste la dernière acceptée, grisée. Une saisie illisible n'est jamais envoyée.
- **Mémoire :** fermer puis rouvrir le panneau rend la dernière coupe acceptée, jusqu'à la fin de la session SketchUp. Elle n'est pas enregistrée dans le fichier : c'est la voie tracée qui la portera (AG-042).
- **Pont :** actions `init` et `preview` (protocole 1, même enveloppe que les autres panneaux). `preview` renvoie le profil effectif et sa coupe dessinée.

### Coupe dessinée (`Geometry::RoadSection`)

Calcul pur, repris par le tronçon. x part du bord gauche, z du niveau 0.

- **Surface :** une ligne par bande. Plane à son niveau ; fossé en trapèze, fond de 30 % de la largeur à −`depth_m` ; talus montant de `slope` × largeur vers l'extérieur, c'est-à-dire vers le bord gauche si son milieu est à gauche du milieu de l'emprise, sinon vers le droit.
- **Bordure :** entre deux bandes planes dont le niveau diffère d'au moins 0,10 m ; 0,16 m de large, prise dans la bande haute contre la bande basse.
- **Rails :** à ± 0,7175 m du milieu de la bande ; dessus au niveau de la bande, ou 0,17 m au-dessus du ballast.
- **Éléments :** position en travers comme au format ; altitude prise sur la surface ; côté de la voie la plus proche (`carriageway`, `tram`, `rail`), vers lequel se tourne une crosse ; couronne des arbres d'après le catalogue ; nombre pour 100 m d'après la règle de répétition.

## Tronçon

Livré dans le noyau par AG-039 (U24) ; l'écriture dans SketchUp et l'outil de tracé viennent en AG-042.

**Format `road` V1** ([schéma](../schemas/road-settings.v1.schema.json)), clés inconnues refusées :

```json
{ "road_version": 1, "seed": 1, "axis": "center",
  "trace": { "points_m": [[0, 0], [100, 0], [100, 80]], "radii_m": [40] },
  "profile": { "bands": [ … ] } }
```

- `trace.points_m` : 2 à 64 points `[x, y]`, dans le repère de la racine ; le premier est (0, 0). `trace.radii_m` : un rayon par sommet intérieur, de 0 à 5 000 m, ni plus ni moins.
- `axis` : `center` (défaut), `left` ou `right` : le tracé suit le milieu ou un bord de l'emprise.
- `seed` : 1 par défaut, réservée à la variation des arbres (AG-040).
- `profile` : une coupe `road_profile`, jugée comme au panneau ; ses diagnostics sont rapportés sous `/profile/…`.

**Axe.** Un rayon nul garde un angle vif à **onglet** : la normale suit la bissectrice, allongée de 1 / cos(φ/2), si bien que chaque bande garde sa largeur perpendiculairement aux deux segments. Un rayon non nul pose un **arc tangent**, de longueur de tangente R × tan(|φ|/2) de chaque côté du sommet. L'arc est découpé pour qu'au bord le plus éloigné de l'axe l'écart à la corde reste sous 5 cm (départ) : pas de 2 × acos(1 − 0,05 / (R + portée)). La courbe est nécessaire ici : ni une route ni un rail ne se tracent en lignes brisées.

**Rubans.** La ligne de coupe est une polyligne continue de gauche à droite : surface de chaque bande, coupée au bord de ses bordures, et une **contremarche** verticale à chaque changement de niveau. Elle est balayée d'une station de l'axe à la suivante : une face par segment de coupe et par intervalle, quadrilatère plan. Seul un segment en pente, au droit d'un onglet, peut ne pas être plan : il est alors coupé en deux triangles. Sur un arc ou à l'onglet, les quadrilatères restent plans par construction. Tout est **une seule surface** : deux rubans voisins partagent leurs sommets, et les faces sont orientées vers le haut, les contremarches vers la bande basse. Une ligne droite n'a aucune station intermédiaire, ce qui n'en fait qu'une face par segment de coupe ; le terrain (AG-049) demandera de la redécouper. Matériaux, par clé : `road/<type de bande>`, `road/curb`, et pour les éléments `road/item/<partie>` (`trunk`, `crown`, `steel`, `lamp`, `hedge`, `wood`, `concrete`) ; leur catalogue vient en AG-042.

**Bordure, précision :** une bordure ne borde qu'une bande `pedestrian`, `median`, `planting` ou `cycle` plus haute. Une autre marche, comme celle du ballast, est une contremarche de la matière de la bande haute.

**Refus, `E_ROAD_TRACE` :**

| Raison | Chemin | Cas |
|---|---|---|
| `too_few_points`, `first_point_not_road_origin`, `coordinate_range`, `radii_count` | `/trace/points_m…`, `/trace/radii_m` | Forme du tracé ; point hors de ±2 000 m |
| `segment_too_short` | `/trace/segments/<k>` | Segment de moins de 0,5 m (départ) |
| `reversal` | `/trace/points_m/<i>` | Demi-tour de plus de 179° |
| `radius_too_small` | `/trace/radii_m/<j>` | Rayon intérieur sous 1 m (départ) : R doit valoir au moins la portée du côté intérieur + 1 m, ce que le paramètre `min` donne |
| `arcs_too_long` | `/trace/segments/<k>` | Les tangentes de ses deux arcs dépassent le segment |
| `inner_edge_folds` | `/trace/points_m/<i>` | À un onglet, le bord intérieur recule plus que la place disponible |
| `self_overlap` | `/trace/points_m/<i>` | Le contour de l'emprise se coupe : une voie ne se croise pas elle-même ; deux voies se croisent dans un réseau (Carrefours) |

**Plafond, `E_ROAD_BUDGET`, `road_faces`, sur `/trace` :** 60 000 faces (départ), estimées avant construction. Les objets et les faces étendues ont leurs propres plafonds : voir Pose le long de la voie.

**Plan :** `RoadPlan = {schema_version:1, engine_version, units:"m", nodes:[road > surface], metrics}`, métriques `face_count`, `vertex_count`, `station_count`, `cross_segment_count`, `width_m`, `length_m`. Il est validé par `RoadPlanValidator` (mêmes refus de maillage que le bâtiment : sommets quantifiés, faces planes, arêtes d'au moins 2 mm, orientation cohérente), et son empreinte `road_digest` est le SHA-256 du JSON canonique. Le moteur de voirie a sa propre version, `ROAD_ENGINE_VERSION`. Écart de cote attendu dans SketchUp : au plus 1 mm, comme ailleurs. Mesure Ruby : un kilomètre de route de campagne sinueuse en 22 ms, 968 faces ; au plus 26 ms sur 100 tracés tirés.

## Carrefours

**Naissance (ADR-36).** Un réseau `road_network` V1 regroupe 1 à 24 voies, chacune avec son nom (`id`) et ses réglages de voie ; la première part de l'origine du réseau. Un nœud naît tout seul là où deux axes se croisent, où le bout d'une voie touche une autre voie à 1 m près, ou où deux bouts se rejoignent. Une abscisse à moins de 2 m d'un bout est ce bout : la voie finit au carrefour, sans moignon. Les touches à 2 m près se regroupent en un nœud, nommé `voie@abscisse+voie@abscisse` (abscisses au décimètre, triées). Le type se choisit ensuite dans le panneau (AG-048) ; sans réglage, le nœud est `simple`.

```json
{ "network_version": 1,
  "roads": [ { "id": "rue", "road": { "trace": { "points_m": [[0, 0], [100, 0]], "radii_m": [] }, "profile": { } } },
             { "id": "allee", "road": { "trace": { "points_m": [[50, 0], [50, 60]], "radii_m": [] }, "profile": { } } } ],
  "junctions": [ { "id": "allee@0.0+rue@50.0", "type": "signals", "corner_radius_m": 8 } ] }
```

Types de nœud, livrés ticket par ticket :

| Type | Géométrie | Porte | Ticket |
|---|---|---|---|
| `simple` | Plateau de chaussée, trottoirs qui tournent l'angle par une bordure arrondie, contremarches et murets. 2 à 6 branches | Toute coupe sans `hard`, sans rail ni tram | **AG-043, livré** |
| `signals` | Comme `simple`, plus passages piétons, lignes d'arrêt et un feu par branche à chaussée | Au moins une branche à chaussée | **AG-044, livré** |
| `roundabout` | Anneau, îlot central, îlots séparateurs, entrées arrondies. Rayon extérieur de 13 à 60 m, anneau de 6 à 12 m | Chaque branche avec chaussée | **AG-045, livré** |
| `double_roundabout` | Deux anneaux reliés par un tronçon de longueur `link_m`, branches réparties par angle | Idem, au moins 3 branches | AG-046 |
| `level_crossing` | Rails franchissant une route, à niveau | Voie ferrée × route | AG-047 |

### Carrefour simple (AG-043, U27)

`Geometry::RoadNetwork` trouve les nœuds et découpe les voies ; `Geometry::RoadJunction` dessine chaque carrefour ; `Core::RoadNetworkEngine` assemble un seul plan validé.

- **Branches.** Chaque voie donne une branche vers l'aval et une vers l'amont du nœud (une seule à son bout), triées dans le sens direct. Chaque branche part du point de l'axe de sa voie au nœud et garde sa coupe. La **bordure** d'une branche est le bord de ses bandes de chaussée ; sans chaussée (chemin), c'est le bord de l'emprise.
- **Coins.** Entre deux branches voisines :
  - angle de moins de 175° et les deux côtés bordés d'un trottoir ou d'un accotement : **bordure arrondie** de rayon `corner_radius_m` (6 m par défaut, 2 à 30 m), corde de 5 cm au plus. Le bord extérieur du trottoir garde l'angle vif quand il reste à 0,3 m au moins derrière la bordure ; sinon il s'arrondit, du plus grand rayon (par pas de 0,5 m, en partant de R − la plus petite largeur, concentrique quand les largeurs sont égales) qui reste à 0,3 m derrière la bordure ;
  - angle de 175° et plus, ou un seul côté bordé (un chemin rejoint une rue) : **onglet**, à l'intersection des bordures et des bords ; corde droite si l'onglet partirait à plus de deux emprises du nœud.
- **Coupe.** Chaque branche est coupée net, à 1 m au moins, assez loin pour que les arrondis, l'onglet et le recouvrement des deux emprises restent dans le carrefour. La zone coupée doit tenir dans un segment droit de la voie.
- **Faces.** Le cœur, entre les bordures, est un plateau à 0 s'il y a une chaussée (matière `road/lane`), sinon au plus bas des chemins (`road/path`). Chaque coin est un plateau au plus bas des deux bandes qui bordent la bordure, en matière de trottoir s'il y en a un. Une contremarche (`road/curb`) suit la bordure là où le coin la borde ; un coin vide, parce qu'un chemin prend la place du trottoir, reste au niveau du cœur. À chaque coupe, un muret (`road/curb`) ferme chaque segment de la coupe qui n'est pas au niveau de la face voisine, tourné vers le côté bas.
- **Soudure.** Tronçons et carrefours partagent un maillage. Un sommet de carrefour posé au milieu d'une arête y est inséré ; la face touchée est retriangulée dans son plan. Vu de dessus, chaque point des emprises est couvert une fois et une seule ; aucune arête n'est libre dans les emprises ni portée par plus de deux faces.
- **Tronçons.** Entre deux coupes, chaque voie donne un tronçon, balayé comme une voie seule, avec ses objets ; les objets prennent le nom de leur voie et de leur tronçon (`…@rue.2`) et partagent leurs formes. Aucun objet ne tombe dans un carrefour. Un réseau sans nœud donne exactement les voies seules.
- **Jonction de deux coupes différentes** bout à bout, alignées : les bords se raccordent en biseau sur les deux coupes de 1 m. Plus long : hors de cette version.
- **Plan.** Une racine `road`, la surface et les familles d'objets comme une voie seule ; `junctions` liste chaque nœud (`id`, `type`, branches, rayon, coupe de chaque branche `cuts_m`, bout de sa zone `reach_m`) ; `metrics` ajoute `road_count`, `junction_count`, `piece_count`, `junction_face_count`. Mêmes plafonds qu'une voie.

### Carrefour à feux (AG-044, U28)

`"type": "signals"` sur un nœud. Tout le carrefour simple, plus, sur chaque branche à chaussée, au-delà de sa coupe (`Geometry::RoadSignals`, circulation à droite) :

- **Passage piéton** si la coupe porte un trottoir ou un chemin : 4 m dans le sens de la voie, bandes de 0,5 m parallèles à l'axe, tous les 1 m, à 0,25 m au moins des bords de chaque bande roulante (stationnement exclu). Sans trottoir, pas de passage.
- **Garde** de 1 m, puis **ligne d'arrêt** de 0,5 m sur les seules voies (`lane`) qui entrent : celles à gauche de la branche vue du nœud, au-delà du milieu des voies. Bandes dérasées, arrêt d'urgence et stationnement n'en ont pas.
- Le marquage (`road/marking`) est **taillé dans la surface**, au niveau de la chaussée : aucune face superposée, donc aucun scintillement. La zone du carrefour s'allonge d'autant (`reach_m` : coupe + 5,5 m avec passage, + 1,5 m sans) ; les tronçons et leurs objets commencent après.
- **Un feu par branche à chaussée** (`signal/<nœud>/<rang>`, famille mobilier) : mât et boîtier de 3 m, trois optiques tournées vers ceux qui arrivent ; posé à droite de la circulation qui arrive, 0,5 m derrière la bordure (au milieu de la bande si elle est plus étroite), au droit de la ligne d'arrêt, à la cote de la bande. Une branche sans chaussée (chemin) n'a ni feu ni marquage.
- Plan : `type` et `reach_m` par nœud, `signal_count` dans `metrics`.

Refus : `signals_without_carriageway` (aucune branche à chaussée) ; `no_room_for_signal` (`road`) quand rien ne dépasse de 0,3 m au moins la bordure à droite des voies qui entrent.

### Giratoire (AG-045, U29)

`"type": "roundabout"`, réglages `outer_radius_m` (bord extérieur de l'anneau, 13 à 60 m, 15 par défaut), `ring_width_m` (6 à 12 m, 7 par défaut) et `corner_radius_m` (arrondi d'entrée, 6 m par défaut). Centre au nœud (`point_m`). `Geometry::RoadRoundabout`, circulation à droite :

- **Anneau** de chaussée (`road/lane`) entre l'îlot central et le bord extérieur, à 0. La chaussée est découpée en secteurs entre branches voisines, le long de la ligne médiane de chaque chaussée : aucun polygone à trou.
- **Îlot central** : disque du rayon intérieur (`outer − ring`), planté (`road/plant`) à 0,14 m, bordé d'une contremarche tournée vers l'anneau.
- **Entrées** : chaque bord de chaussée d'une branche se raccorde au bord extérieur par un arrondi tangent aux deux (rayon `corner_radius_m`, centre côté trottoir).
- **Îlot séparateur** (`road/median`, 0,14 m, contremarches) sur chaque branche dont chaque demi-chaussée fait au moins 4 m : triangle de 2 m de base à 1 m de l'anneau, pointe 8 m plus loin, sur la ligne médiane. Branche plus étroite : pas d'îlot.
- **Trottoirs de coin** : entre la bordure (bord de A, arrondi, anneau, arrondi, bord de B) et un bord extérieur fait d'un angle vif sur chaque bord de branche et d'un arc concentrique à l'anneau, à la plus petite des deux largeurs. L'angle vif doit rester à 0,3 m derrière l'arrondi d'entrée. Coin sans rien au-delà des bordures : vide.
- **Coupe** de chaque branche : 1 m au-delà de la pointe de l'îlot, et assez loin pour les arrondis, l'angle vif et le recouvrement des emprises voisines.
- Plan : `outer_radius_m`, `ring_width_m` et `point_m` par nœud.

Refus : `roundabout_without_carriageway` (une branche sans chaussée) ; `ring_too_small` (`road` : la demi-chaussée atteint le bord extérieur, ou la ligne médiane manque l'îlot central) ; `roundabout_arms_too_close` (les arrondis de deux entrées voisines se chevauchent) ; `junction_shape` (un seul côté d'un coin bordé, ou angle vif trop près de l'arrondi). Rayons hors bornes : `E_SCHEMA`.

**Refus, `E_ROAD_JUNCTION`, sur `/junctions/<id du nœud>` :**

| Raison | Quand |
|---|---|
| `motorway_at_grade` | Une branche porte une bande d'arrêt d'urgence (`hard`) : **une autoroute se raccorde par un échangeur, hors de ce lot** |
| `rails_at_junction` | Une branche porte un rail, un tram ou une voie mixte : jusqu'à AG-047 |
| `too_many_arms` | Plus de 6 branches |
| `arms_too_close` | Deux branches à moins de 30° |
| `junction_on_curve` | La zone coupée d'une branche touche un virage ou un sommet de sa voie (`road`) |
| `arm_too_short` | La voie est plus courte que sa coupe (`road`) |
| `junctions_too_close` | Les zones coupées de deux nœuds se touchent sur une voie (`road`, `other`) |
| `junction_shape` | Aucun coin ne se construit : bords extérieurs très inégaux pour ce rayon (par exemple 0,8 m contre 6 m à 125° : 8 m de rayon passent) |
| `junction_levels` | À une coupe, un segment passe d'un côté à l'autre du niveau voisin |
| `unknown_junction` | Un réglage vise un nœud qui n'existe pas (`/junctions/<id>`) |

La saisie refuse aussi `duplicate_road_id` (`E_ROAD_TRACE`, `/roads/<i>/id`), `duplicate_junction`, `first_point_not_network_origin` et `unsupported_network` (`E_VERSION`). Un refus d'une voie garde son chemin dans le réseau, `/roads/<i>/road/…`.

**Tram au carrefour (AG-047) :** les rails d'un tronçon passeront droit à travers le nœud et l'îlot central, si deux branches à rails sont opposées à 15° près (départ). Toute autre disposition sera refusée. Les courbes de rails d'un carrefour sont hors de cette version.

## Écriture et persistance

Livré par AG-042, recette [H20](recette/H20.md), RBZ 0.5.0.

- **Racine :** une instance de niveau racine nommée « Voie ARCHGEN », placée au premier point du tracé, à son altitude. Sa définition, « ARCHGEN voie », contient un groupe par famille. Dictionnaire `archgen.road` : `road_version` (1), `revision`, `road_json` (réglages effectifs), `road_digest`, `road_engine_version`, `material_revision`. Une racine de voie n'est une cible ni pour un bâtiment ni pour un ensemble, et réciproquement (`not_a_road_root`).
- **Transaction :** mêmes règles que `TransactionGuard` : une opération « ARCHGEN : créer une voie » ou « ARCHGEN : régénérer la voie », pannes sans résidu, cible revalidée avant d'écrire (sélection, verrou, échelle, définition, révision, empreinte), géométrie partagée jamais modifiée sur place. Modifier régénère dans une définition fraîche ; une copie garde la sienne.
- **Modifier :** la coupe, le rayon (appliqué à tous les sommets, ou ceux enregistrés si le champ est vide) et l'axe ; jamais le tracé : pour le changer, on en trace un autre. Un moteur de voirie ou un catalogue plus récent : consultable, jamais écrasé (`newer_engine`, `newer_materials`).
- **Balises :** une par famille, sur le groupe de premier niveau : `ARCHGEN Voirie chaussée et trottoirs` (toute la surface), `végétation` (arbres, haies), `éclairage`, `mobilier et clôtures` (potelets, poteaux, barrières, glissières et leurs poteaux), `rails` (rails sur ballast, traverses). **Écart au départ du contrat :** la surface est une seule maille à sommets partagés ; la scinder en chaussée, trottoirs et pistes casserait ce partage, d'où une seule balise pour elle.
- **Définitions partagées :** clé `road<moteur>/<type>/<variante>/<hauteur en mm>`, ainsi qu'une forme de voirie n'est jamais confondue avec un détail de bâtiment ni réutilisée après un changement du moteur de voirie.
- **Matériaux :** catalogue `road_materials.v1.json` (25 matières), ajouté au catalogue du bâtiment, matériaux unis marqués `archgen.resource`, homonymes de l'utilisateur intacts. Arêtes coplanaires de même matériau masquées comme ailleurs (ADR-15).
- **Panneau :** menu **Tracer une voie** (outil actif, la coupe et le tracé) et **Modifier la voie sélectionnée**. L'outil est celui de la rue, sans fermeture de forme ni côté bâti. Le contour de l'emprise se dessine dans la vue, rouge si la voie est refusée. Créer et Remplacer renvoient l'empreinte montrée : si le résultat a changé, `E_CONFIRMATION_STALE`. Un double clic ne crée qu'une voie.
## Terrain

Soumis à D-08. Jusqu'à cette décision, une voie est horizontale, posée au premier point du tracé, et ne regarde pas le terrain.

## Hors périmètre V1

Échangeurs et ponts ; tunnels ; dévers et pentes en travers ; marquage détaillé des directions ; plans de feux ; aiguillages et courbes de rails en carrefour ; écartements non standard ; vérification réglementaire ; raccord automatique avec un ensemble bâti (à ouvrir après AG-048) ; mobilier urbain pur : arrêts de bus, attaches vélos, panneaux de signalisation (EXT-12).
