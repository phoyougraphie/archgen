# Contrat d'ensemble : rue et îlot au tracé — EXT-07

Contrat de la version 0.3, à valider avant le code. Il complète [le contrat géométrique](GEOMETRY_CONTRACT.md) et [la régénération](REGENERATION.md) sans modifier le plan d'un bâtiment seul : **à configuration égale, `plan_digest` reste identique**. Décisions : ADR-30 à ADR-32. Les valeurs marquées « départ » sont à calibrer à la recette, par une décision écrite. Le besoin d'origine est dans [RUE_ILOT_TERRAIN](RUE_ILOT_TERRAIN.md).

## Principes

- **Un tracé, un ensemble.** L'utilisateur trace une ligne au geste du Mur connecté de YSKE. Une forme ouverte donne une rue, une forme fermée un îlot avec sa cour.
- **Une validation, un Annuler,** quel que soit le nombre de bâtiments. Un tracé refusé laisse le document intact.
- **Noyau pur :** réglages et polyligne en mètres → parcelles → configurations → plans. Seuls l'outil de tracé et le writer touchent à SketchUp.
- **Déterministe :** mêmes tracé, réglages et seed, même résultat. La seed de chaque parcelle dérive de celle de l'ensemble par une clé stable.
- **Aucune adaptation silencieuse :** un tracé impossible est refusé avec un diagnostic sur le segment ou la parcelle en cause.

## Format `ensemble` V1

Format séparé de la configuration du bâtiment, qui reste en V1 fermée. Clés inconnues refusées.

| Champ | Valeurs | Défaut (départ) | Sens |
|---|---|---|---|
| `ensemble_version` | 1 | 1 | Version du format |
| `seed` | Entier non signé 32 bits | 1 | Seed de l'ensemble |
| `trace.points_m` | 2 à 64 points `[x, y]` | — | Polyligne horizontale, dans le repère de la racine ; le premier point est (0, 0) |
| `trace.closed` | Booléen | — | Le dernier point rejoint le premier ; il n'est pas répété |
| `layout.side` | `left`, `right`, `both` | `left` | Forme ouverte : côté bâti, dans le sens du tracé ; `both` fait du tracé l'axe de la rue. Forme fermée : champ refusé, le bâti est toujours à l'intérieur |
| `layout.street_width_m` | [3, 60] | 12 | Avec `both` seulement : distance entre façades |
| `parcel.target_width_m` | [6, 60] | 12 | Largeur visée en façade |
| `parcel.depth_m` | [4, 60] | 9 | Profondeur, commune à tout l'ensemble |
| `parcel.bay_width_m` | [1,5 ; 12] | 3 | Pas des travées : le nombre de travées est calculé par parcelle |
| `access.count` | `auto`, 1, 2, 3 | `auto` | Forme fermée seulement : `auto` donne 1 sous 80 m de périmètre, 2 sous 160 m, 3 au-delà |
| `access.width_m`, `access.height_m` | [2,5 ; 6] | 3,5 et 2,7 | Valeurs de conception, pas une règle d'accès pompiers ou d'urbanisme. La hauteur ne vaut que pour un porche : 2,7 m tient sous le RDC des styles livrés, qui ne laissent que 2,8 et 2,9 m |
| `building` | Brouillon de bâtiment V1 | Profil | Style, mode, LOD, niveaux, matériaux. Refusés ici car calculés : `footprint`, `facade.front_bays`, `facade.side_bays`, `facade.entry_bay`, `seed` |

**Même gabarit partout :** tous les bâtiments d'un ensemble ont les mêmes niveaux et la même profondeur.

## Tracé et segments

1. **Sens de calcul :** chaque rangée est parcourue le bâti à sa gauche, comme la façade `front` du contrat géométrique. Un contour fermé est ramené au sens antihoraire ; `right` inverse le tracé ; `both` calcule deux rangées, décalées de `street_width_m / 2` de chaque côté de l'axe.
2. **Refus du tracé, `E_STREET_TRACE` :** moins de 2 points, ou 3 pour un contour fermé, ou premier point ailleurs qu'en (0, 0), sur `/trace/points_m` ; point hors de ±2 000 m, sur `/trace/points_m/<i>` ; segment de moins de 6 m (départ) ou tracé qui se coupe ou se replie, avec les deux segments en cause, sur `/trace/segments/<i>`. Avec `both`, la longueur minimale vaut aussi pour les façades décalées, qui peuvent raccourcir ou s'inverser dans un angle. Les numéros de segment restent ceux du tracé saisi, même quand le calcul le parcourt en sens inverse.
3. **Angle au sommet :** φ est l'angle signé dont tourne le tracé, positif vers le bâti. La coupe d'onglet suit la bissectrice, de la façade à l'arrière. **δ = D × tan(φ / 2)** est le recul de l'arrière à ce sommet, D étant la profondeur : positif sur un angle saillant, négatif sur un angle rentrant, 0 à l'extrémité d'une rue.

## Découpe en parcelles

Chaque segment de longueur L, mesurée en façade, est découpé ainsi :

1. Une extrémité avec onglet réserve une **parcelle d'angle** de largeur `c = max(target, δ + rear_min)`, avec `rear_min = 2 m` (départ). Une extrémité sans onglet ne réserve rien.
2. Le reste R est découpé en `m = round(R / target)` parcelles égales, l'arrondi étant celui de `Quant`.
3. Si m = 0, R est réparti à parts égales entre les parcelles d'angle, ou forme une parcelle unique s'il n'y en a pas.
4. Si L ne permet pas les deux parcelles d'angle, le segment forme une seule parcelle, avec ses deux onglets. Son arrière doit valoir au moins `rear_min`, sinon `E_STREET_CORNER` sur `/trace/segments/<i>`, qui indique la longueur manquante.

Une parcelle a un `id` stable : `<rangée>/<segment>/<rang>`.

**Exemple de référence :** carré de 40 m, D = 9, cible 12. Les angles sont à 90°, donc δ = 9 et c = 12. Sur chaque côté : R = 16 et m = 1, soit des parcelles de 12, 16 et 12 m. L'arrière vaut 3, 16 et 3 m, soit les 22 m du côté de la cour. L'îlot compte 12 parcelles, 160 m de périmètre et 3 accès.

**Forme d'une parcelle.** Un trapèze dont la façade et l'arrière restent parallèles. Dans son repère local, avec W la largeur et δg, δd les reculs :

`(0, 0)`, `(W, 0)`, `(W − δd, D)`, `(δg, D)`

Il est toujours convexe : c'est ce qui garde la géométrie simple. Sans onglet, c'est le rectangle du contrat V1.

**Contrôles de l'ensemble.**

| Situation | Code | Effet |
|---|---|---|
| Arrière d'une parcelle sous `rear_min` | `E_STREET_CORNER` | Refus sur le segment |
| Deux parcelles non voisines qui se recouvrent ; ou, sur des segments non contigus ou des rangées différentes, à moins de 3 m (départ) | `E_STREET_OVERLAP` sur `/parcels/<id>` | Refus, avec les deux parcelles. Couvre un tracé qui se replie et une cour trop étroite. Sur deux segments contigus, seul le recouvrement compte : ils se rejoignent à l'angle, où `rear_min` fait déjà foi |
| Plus de 200 parcelles (départ) ou plafonds d'ensemble dépassés | `E_STREET_BUDGET` | Refus avant écriture |
| Refus du moteur pour une parcelle | Code du moteur, sur `/parcels/<id>/…` | Refus de tout l'ensemble |

Voisines : consécutives dans une même rangée, onglets compris. Elles se touchent par construction.

## Bâtiment de rangée

Chaque parcelle reçoit une configuration effective complète : largeur W, profondeur D, seed dérivée, travées calculées. Le plan de rangée est une voie à part du moteur, de même structure que `GeometryPlan` : un bâtiment seul ne passe pas par elle, et `ENGINE_VERSION` ne change donc pas pour lui.

| Élément | Règle |
|---|---|
| **Travées** | `front_bays = max(1, floor(W / bay))` ; `rear_bays = floor(arrière / bay)`, 0 permis ; `entry_bay = floor(front_bays / 2)`. Les baies suivent les règles et les refus du contrat géométrique |
| **Murs latéraux** | Toujours aveugles et toujours émis, en entier, dans les deux modes, y compris les extrémités libres d'une rue (ADR-32) |
| **Structural** | Le joint entre deux murs suit l'angle réel du trapèze : à l'intérieur, l'extrémité recule de `t × tan(virage / 2)`, soit t à angle droit. Dalles sur le trapèze intérieur. Deux murs mitoyens se touchent sans se recouvrir. Un mur dont les deux joints se rejoindraient : `E_STREET_CORNER` |
| **Toit** | Une section constante dans le plan (y, z), balayée le long de la rangée et coupée par les deux plans latéraux. Faîtage parallèle à la façade, à y = D/2. Pas de débord latéral : un toit ne déborde jamais chez le voisin. Les toits de deux parcelles se rejoignent donc exactement sur l'onglet |
| Plat, deux pans | Même section qu'en V1, débord en façade et à l'arrière |
| Mansarde | Pans bas et hauts en façade et à l'arrière, sans pans latéraux : la croupe de couronnement disparaît. Un pignon aveugle de chaque côté, comme en deux pans |
| Croupe | `E_STREET_ROOF` sur `/building/roof/type` : elle n'a pas de sens en rangée, et aucun autre toit ne lui est substitué. Aucun profil actif ne l'utilise |
| **Corniche** | Coupée par le plan d'onglet : deux voisines se rejoignent sur un angle saillant et ne se recouvrent pas sur un angle rentrant |
| **Balcon** | De marge à marge, comme ailleurs : il n'atteint donc pas l'angle. Sur un angle rentrant, son bord extérieur s'arrête à l'onglet. S'il n'a plus la place : `W_DETAIL`, sans balcon sur cette parcelle |
| **Baies d'angle** | La trame se resserre entre les joints intérieurs : `P = (haut − bas) / N`, avec `bas = max(M, début du joint)` et `haut = min(L − M, fin du joint)`. Une baie ne tombe donc pas dans un angle fermé. Le dégagement aux extrémités se mesure depuis le joint. Si les baies ne tiennent plus : `E_OPENING_CLEARANCE` |
| **Débord arrière** | Les plans d'onglet se rapprochent vers l'arrière. Si le débord les croiserait : `E_STREET_CORNER` |
| **Cadres, encadrements** | Inchangés |

**Arrière :** il suit la trame de la façade arrière V1, avec ses propres travées. Pas de vitrage ni de traitement particulier côté cour.

## Accès à la cour

Une forme fermée en reçoit toujours : une cour sans accès n'est jamais produite. Si le nombre demandé ne tient pas, le tracé est refusé, sans réduire ce nombre en silence. Exemple de référence, le carré de 40 m : 3 accès sur 3 côtés, 9 parcelles au lieu de 12, voisines de 18,25 m autour d'un vide de 3,5 m.

**Placement.** Les candidates sont les parcelles rectangulaires dont les deux voisines sont sur le même segment, jamais une parcelle d'angle. Les segments sont classés par `unit(seed, "access/<i>")`, puis un accès est donné à chaque segment dans cet ordre, en reprenant au début s'il en manque. Dans un segment, l'accès prend la parcelle candidate la plus proche du milieu ; à égalité, celle de plus petit rang. Une candidate doit être plus large que `access.width_m`. Deux accès ne sont jamais voisins. Faute de candidate : `E_STREET_ACCESS` sur `/access/count`.

**Forme : selon le style (ADR-31).** Un catalogue séparé `ensemble_rules.v1.json` associe chaque couple profil/révision à une forme. Les profils et leur révision ne changent pas. Valeurs publiées :

| Profil | Forme |
|---|---|
| Haussmannien | `porch` |
| Toulousain | `porch` |
| Brutaliste | `gap` |

Un profil absent du catalogue ne peut pas fermer un îlot : `E_STREET_ACCESS` sur `/building/profile`. Le panneau montre alors les parcelles, en rouge, sans permettre de créer. Une entrée n'est publiée qu'avec sa capacité et ses tests.

- **`gap` (interruption) :** la parcelle est retirée, et ses voisines s'étendent pour laisser un vide de `access.width_m`, à parts égales. Elles restent des bâtiments complets, à murs latéraux aveugles.
- **`porch` (porche) :** passage de `access.width_m`, centré sur la parcelle, au RDC, de la façade à l'arrière, de z = 0 à `access.height_m`. La parcelle reste, mais n'a pas de porte : le passage tient lieu d'entrée, et la travée d'entrée redevient une fenêtre. Les baies de RDC à moins de 0,10 m du passage sont retirées. Deux parois et un plafond ferment le passage ; les étages passent au-dessus. Baies et dégagements du contrat géométrique s'appliquent aux étages et au RDC restant. Le haut doit rester sous `top − slab_m − 0,10` au RDC, sinon `E_STREET_ACCESS` sur `/parcels/<id>/access/height_m`. Il reste au moins `wall_m + 0,10` de mur de chaque côté, sinon le même code sur `…/access/width_m`. Les parois et le plafond sont des surfaces, en Shell de la façade à l'arrière, en Structural entre les faces intérieures des murs, où les jambages et le linteau ferment déjà l'épaisseur.

## Plan d'ensemble

`EnsemblePlan = {schema_version:1, units:"m", definitions:{id:RowPlan}, parcels:[{id, definition_id, matrix}], accesses:[...], metrics:{...}}`, avec sa propre empreinte `ensemble_digest`.

- **Définitions partagées :** deux parcelles partagent une définition si leurs configurations effectives, leurs reculs et leurs travées arrière sont identiques, hors nom. La seed n'entre dans la comparaison que si le jitter n'est pas nul. L'identifiant d'une définition vient de ce contenu. Les tirages de style par parcelle changent la configuration effective : ils peuvent donc réduire le partage.
- **Placement :** `matrix` a les colonnes (T, gauche, K) et la translation de l'origine de la parcelle : une rotation autour de Z, sans autre transformation.
- **Métriques :** `parcel_count`, `definition_count`, `unique_face_count`, `expanded_face_count`, `facade_length_m`, `access_count`.
- **Accès :** `accesses` donne pour chacun `id`, `segment`, `form`, `width_m` et le centre `center_m`, dans le repère de la racine. Le périmètre est `facade_length_m`, mesuré avant l'ouverture des accès.
- **Avertissements :** un avertissement de définition est répété pour chaque parcelle qui l'utilise, sur `/parcels/<id>/…`.
- **Plafonds :** 120 000 faces uniques et 600 000 faces étendues, d'après la mesure de [H15](recette/H15.md) : le coût d'écriture suit les faces uniques.

## Écriture et persistance

- **Racine d'ensemble (ADR-30) :** une instance de niveau racine, placée au premier point du tracé, à l'altitude de ce point. Sa définition contient une instance par parcelle, à laquelle s'appliquent les tags et les matériaux existants.
- **Transaction :** une validation = une opération « ARCHGEN : créer un ensemble », ou « ARCHGEN : régénérer l'ensemble ». Mêmes règles que `TransactionGuard` : pannes sans résidu, cible revalidée.
- **Attributs :** dictionnaire `archgen.ensemble` sur la racine : `ensemble_version`, `ensemble_json`, `ensemble_digest`, révisions du moteur et des catalogues. Les parcelles ne portent pas `archgen.building` : elles ne sont pas des cibles de l'édition d'un bâtiment seul.
- **Modifier :** « Modifier l'ensemble sélectionné » relit la racine dans le panneau, sans outil. Les réglages changent, jamais le tracé ni la seed : pour changer le tracé, on en trace un autre. Le bouton « Remplacer cet ensemble » n'est actif que si le résultat change, et renvoie l'empreinte montrée. L'ensemble se régénère en entier depuis ses réglages et son tracé, dans une définition fraîche. Une copie garde sa définition. La géométrie partagée n'est jamais modifiée sur place.
- **Refus :** sélection d'une parcelle à l'intérieur de l'ensemble, racine éclatée, mise à l'échelle ou en miroir, version future (`E_VERSION`). Une racine éclatée laisse des bâtiments ordinaires, sans lien avec l'ensemble.
- **Barre d'état :** elle suit les bâtiments écrits ; c'est le panneau qui annonce le nombre avant de commencer (AG-033).
- **Terrain :** une racine d'ensemble n'est pas une cible de la section Terrain d'un bâtiment. L'étagement, une plateforme par parcelle, a sa propre section dans ce panneau : voir [le contrat terrain](TERRAIN_CONTRACT.md).

## Outil de tracé

`Sketchup::Tool` dans l'adaptateur, au geste de `agen-sketchup/src/yske/tools/mur_tool.rb` :

- clic de départ, puis un clic par sommet, ou `longueur` ou `longueur;angle` dans la boîte de mesure ;
- flèche droite : axe rouge ; flèche gauche : axe vert ; flèche bas : perpendiculaire ou prolongement du segment précédent ; la même flèche débloque ;
- Ctrl : côté du tracé ; Alt : angle verrouillé à 90° ;
- cliquer le premier point, à 10 pixels près, ferme la forme ; Échap ou double-clic termine une forme ouverte ; Échap sur un tracé terminé l'efface ;
- pas d'arc : Tab n'est pas repris, car un segment courbe n'a pas de parcelle au contrat.

Les réglages viennent d'un panneau de rue séparé, ouvert par « Tracer une rue » ; il ne connaît jamais la géométrie du tracé, qui vient de l'outil seul. Le tracé en cours et ses parcelles sont dessinés dans la vue, sans écrire dans le modèle. Le tracé est horizontal : un point visé à une autre altitude est ramené dans le plan du premier, le long du rayon de vue. Le panneau annonce bâtiments, faces et diagnostics ; son bouton « Créer ces N bâtiments » vaut confirmation. Il renvoie l'empreinte montrée : si le résultat a changé, `E_CONFIRMATION_STALE`. Fermer le panneau quitte l'outil et oublie le tracé. Changer de document oublie le tracé. Créer laisse l'outil actif pour une autre rue, et sélectionne la racine créée.

## Charge

Le terrain a montré qu'une fenêtre figée se fait fermer : la recette a perdu un passage ainsi. **Chaque écriture de plus de quelques secondes annonce le nombre de bâtiments avant de commencer, et la barre d'état suit la progression.** Mesure de [H15](recette/H15.md) : 0,3 s pour 12 parcelles et 2,4 s pour 200 en rue droite, 14 à 17 s pour 76 parcelles qui ne partagent presque rien. Le plafond de 200 parcelles reste inchangé.

## Hors périmètre V1

Chaussées, trottoirs, carrefours et graphe de plusieurs rues ; collision avec un autre ensemble ou avec le modèle existant ; hauteurs, styles ou largeurs différents par parcelle ; modification d'une seule parcelle ; segments courbes ; baies sur les murs de fin de rangée ; suppression des faces mitoyennes cachées ; escaliers de cour ; quartier (EXT-08).
