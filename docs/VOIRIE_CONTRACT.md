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

**Rubans.** La ligne de coupe est une polyligne continue de gauche à droite : surface de chaque bande, coupée au bord de ses bordures, et une **contremarche** verticale à chaque changement de niveau. Elle est balayée d'une station de l'axe à la suivante : une face par segment de coupe et par intervalle, quadrilatère plan. Seul un segment en pente, au droit d'un onglet, peut ne pas être plan : il est alors coupé en deux triangles. Sur un arc ou à l'onglet, les quadrilatères restent plans par construction. Tout est **une seule surface** : deux rubans voisins partagent leurs sommets, et les faces sont orientées vers le haut, les contremarches vers la bande basse. Une ligne droite n'a aucune station intermédiaire, ce qui n'en fait qu'une face par segment de coupe ; le terrain (AG-049) demandera de la redécouper. Matériaux, par clé : `road/<type de bande>` et `road/curb` ; leur catalogue vient en AG-042.

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
| `self_overlap` | `/trace/points_m/<i>` | Le contour de l'emprise se coupe : un croisement attend les carrefours (AG-043) |

**Plafond, `E_ROAD_BUDGET`, `road_faces`, sur `/trace` :** 60 000 faces (départ), estimées avant construction. Les objets répétés et les faces étendues viendront avec AG-040.

**Plan :** `RoadPlan = {schema_version:1, engine_version, units:"m", nodes:[road > surface], metrics}`, métriques `face_count`, `vertex_count`, `station_count`, `cross_segment_count`, `width_m`, `length_m`. Il est validé par `RoadPlanValidator` (mêmes refus de maillage que le bâtiment : sommets quantifiés, faces planes, arêtes d'au moins 2 mm, orientation cohérente), et son empreinte `road_digest` est le SHA-256 du JSON canonique. Le moteur de voirie a sa propre version, `ROAD_ENGINE_VERSION`. Écart de cote attendu dans SketchUp : au plus 1 mm, comme ailleurs. Mesure Ruby : un kilomètre de route de campagne sinueuse en 22 ms, 968 faces ; au plus 26 ms sur 100 tracés tirés.

## Carrefours

Le réseau, les nœuds et leur création sont soumis à D-07. Types de nœud proposés :

| Type | Géométrie | Porte |
|---|---|---|
| `simple` | Surface de chaussée, trottoirs arrondis aux angles (rayon réglable), marquage de priorité. 3 à 6 branches (départ) | Toute coupe avec chaussée |
| `signals` | Comme `simple`, plus feux aux angles, lignes d'arrêt, passages piétons | Idem |
| `roundabout` | Anneau, îlot central, îlots séparateurs. Rayon extérieur et largeur d'anneau réglables : 13 m et 6 m au minimum (départ) | Idem |
| `double_roundabout` | Deux anneaux reliés par un tronçon de longueur `link_m`, branches réparties par angle | Idem, au moins 3 branches |
| `level_crossing` | Rails franchissant une route, à niveau | Voie ferrée × route (AG-047) |

Chaque branche garde sa coupe. Un trottoir contourne l'angle jusqu'à la branche voisine ; une piste cyclable s'interrompt au carrefour dans cette version, avec sa marque.

**Refus, `E_ROAD_JUNCTION`, sur `/nodes/<id>` :**

- une coupe avec `hard` à un nœud à niveau : **une autoroute se raccorde par un échangeur, hors de ce lot** ;
- une voie `rail` à un nœud autre que `level_crossing` ;
- une coupe sans chaussée à un nœud `signals` ou giratoire ;
- deux branches formant moins de 30° (départ), rayons qui ne tiennent pas, anneau qui recouvre une autre branche.

**Tram au carrefour :** les rails d'un tronçon passent droit à travers le nœud et l'îlot central, si deux branches à rails sont opposées à 15° près (départ). Toute autre disposition est refusée. Les courbes de rails d'un carrefour sont hors de cette version.

## Écriture et persistance

- **Racine :** une instance de niveau racine, dictionnaire `archgen.road` : version, `road_json`, `road_digest`, révisions du moteur et des catalogues. Une racine n'est pas une cible de l'édition d'un bâtiment ni d'un ensemble.
- **Transaction :** mêmes règles que `TransactionGuard` : une opération « ARCHGEN : créer une voie », pannes sans résidu, cible revalidée, géométrie partagée jamais modifiée sur place. Modifier regénère dans une définition fraîche ; une copie reste isolée.
- **Tags :** un tag par famille (chaussée, trottoirs, cycles, rails, végétation, éclairage, clôtures), pour tout masquer en un clic.
- **Matériaux :** catalogue `road_materials.v1.json`, matériaux unis marqués `archgen.resource`, homonymes de l'utilisateur intacts. Arêtes coplanaires masquées comme ailleurs (ADR-15).

## Terrain

Soumis à D-08. Jusqu'à cette décision, une voie est horizontale, posée au premier point du tracé, et ne regarde pas le terrain.

## Hors périmètre V1

Échangeurs et ponts ; tunnels ; dévers et pentes en travers ; marquage détaillé des directions ; plans de feux ; aiguillages et courbes de rails en carrefour ; écartements non standard ; vérification réglementaire ; raccord automatique avec un ensemble bâti (à ouvrir après AG-048) ; mobilier urbain pur : arrêts de bus, attaches vélos, panneaux de signalisation (EXT-12).
