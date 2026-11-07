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
- **Variation :** `height_variation` optionnel, de 0 à 0,3, tire pour un arbre l'une de trois hauteurs par `unit(seed, "road/item/<bande>/<élément>/<rang>")`. Chaque hauteur reste une définition partagée. Sans ce champ, tous les arbres ont la même hauteur.
- **Refus, `E_ROAD_ITEM` :** hauteur ou pas hors plage ; tout élément dans un `ditch`. **Avertissement, `W_ROAD_CLEARANCE` :** couronne d'arbre au-dessus d'une voie, à moins de 4,50 m du sol (départ).
- **Avertissements de composition :** voie ferrée contre une chaussée, fossé contre une chaussée sans accotement. Ils ne bloquent pas.

### Préréglages (`road_presets.v1.json`)

Autoroute, route à deux voies, route de campagne à fossés, chemin rural, boulevard planté, rue de ville, rue tram et voitures, tram en site propre, voie ferrée double, voie verte, chemin piéton. Leur composition exacte est dans la maquette et sera figée par fixture en AG-037.

## Éditeur de coupe

Panneau local, modeless, sans réseau, français, mêmes règles que le panneau existant. Le noyau reste seul juge : le panneau affiche ses diagnostics et ne reproduit aucune règle.

- **Combien :** ajouter, retirer, dupliquer une bande.
- **Quelle mesure :** saisir la largeur, ou glisser la limite d'une bande dans la coupe.
- **Quel ordre :** déplacer une bande vers la gauche ou la droite, Miroir.
- **Quoi dessus :** pour la bande choisie, ajouter un élément, sa variante, sa hauteur, son pas.
- **Repères :** personnage de 1,75 m qu'on déplace le long de la coupe, gabarits de voiture, bus, tram, train, cycliste, emprise totale, barre d'échelle.
- **Vue en plan** du tronçon, avec le nombre d'objets pour 100 m.

## Tronçon

**Tracé :** polyligne de 2 à 64 points au geste de l'outil existant, chaque sommet intérieur portant un rayon `radius_m`. L'arc est discrétisé avec un écart à la corde d'au plus 5 cm (départ). Un sommet de rayon 0 reste un angle vif avec onglet. La courbe est nécessaire ici : ni une route ni un rail ne se tracent en lignes brisées.

**Géométrie :** chaque bande est un ruban entre deux lignes décalées de l'axe ; les rubans voisins partagent leurs sommets. Une ligne d'axe d'une coupe asymétrique reste l'axe du tracé : le décalage peut viser le milieu ou un bord (`axis`, `center` par défaut).

**Refus, `E_ROAD_TRACE`, sur `/trace/…` :** tracé qui se coupe avant les carrefours (AG-043), segment trop court pour ses deux arcs, rayon qui replierait le bord intérieur (rayon intérieur sous 1 m, départ), point hors de ±2 000 m.

**Plafonds, `E_ROAD_BUDGET` (départ, à revoir après mesure) :** 5 000 objets répétés, 60 000 faces uniques, 600 000 faces étendues.

**Plan :** `RoadPlan = {schema_version:1, units:"m", definitions, strips, instances, metrics}`, avec sa propre empreinte `road_digest` et son validateur. Écart de cote attendu dans SketchUp : au plus 1 mm, comme ailleurs.

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
