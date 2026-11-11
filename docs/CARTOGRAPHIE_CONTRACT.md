# Contrat de la cartographie — J25 (AG-125 à AG-129)

**Demande du propriétaire (2026-11-10).** « ext 06 12 09 08 sont les chantiers prioritaires », dans cet ordre. EXT-06 et EXT-12 sont faits (0.23.0, 0.24.0). Le cadrage d'EXT-09 a été validé le même jour (« Go »).

**Révision du propriétaire (2026-11-11).** D-38 : « openstreetmap ». ARCHGEN **télécharge** l'extrait OpenStreetMap lui-même (ADR-57). Le fichier local reste possible.

**Révision (2026-11-11, ADR-58) : mode simple par défaut.** Voir §6 : rues à plat, commande en un clic depuis la géolocalisation de SketchUp. Les §2 (réseaux) et §5 (panneau) restent valables comme mode avancé.

**Périmètre.** EXT-09 importe un quartier réel à partir d'un **extrait OpenStreetMap téléchargé par ARCHGEN**, ou de fichiers locaux :

- les voies et les bâtiments d'un extrait OpenStreetMap, au format `.osm` (XML) ou GeoJSON ;
- éventuellement, un modèle numérique de terrain au format ASCII Grid (`.asc`), celui que l'IGN distribue pour le RGE ALTI.

ARCHGEN traduit ces fichiers en objets qu'il sait déjà produire : réseaux de voies, bâtiments et terrain. La provenance et la licence sont gardées et affichées.

**Hors périmètre :**

- tout autre service en ligne que l'API Overpass d'OpenStreetMap ; tout téléchargement du terrain ;
- les projections nationales exactes (Lambert-93, UTM) ;
- l'eau, les voies ferrées, la végétation et les points d'intérêt ;
- la mise à jour d'un import déjà fait ;
- les zones de plus de 2 × 2 km.

**Choix de détail.** Ils sont pris selon ADR-48 : la recommandation est appliquée, et le propriétaire peut la réviser (D-38 à D-43 ci-dessous). La décision d'ensemble est ADR-56.

## Décisions de détail appliquées (révisables)

| N° | Question | Choix appliqué | Autre option |
|---|---|---|---|
| D-38 | D'où viennent les données ? | **Tranchée par le propriétaire (2026-11-11) : OpenStreetMap, téléchargé par ARCHGEN** depuis l'API Overpass, sur une emprise de 2 × 2 km au plus. Le fichier reçu est enregistré à côté du modèle, et l'import se fait depuis ce fichier. Un `.osm` ou un GeoJSON local reste accepté (mode local), et le terrain `.asc` reste local. | Fichier local seulement (recommandation d'origine). |
| D-39 | Quelle projection ? | **Plan tangent local** (équirectangulaire autour d'une origine), en mètres. L'origine est la géolocalisation du modèle SketchUp si elle existe, sinon le centre de l'emprise du fichier ; dans ce dernier cas, l'origine est enregistrée sur la racine. Sur 2 km, l'écart avec une projection conforme reste sous 0,1 %. | Lambert-93 ou UTM exacts : une bibliothèque de projection à embarquer. |
| D-40 | Que devient une voie OSM ? | Chaque `highway` connu donne une voie ARCHGEN avec un **type tout prêt** selon une table fermée (§2). Les voies reliées forment des **réseaux** de 24 voies au plus, avec leurs carrefours. Une valeur inconnue est ignorée et comptée dans le rapport. | Une coupe calculée tag par tag (`lanes`, `sidewalk`, `width`) : plus fidèle, beaucoup plus de cas. |
| D-41 | Que devient un bâtiment OSM ? | Son contour est remplacé par le **rectangle orienté** qui l'enveloppe au plus juste, si le contour en remplit au moins 85 %. Le nombre de niveaux vient de `building:levels`, sinon de `height` ÷ 3 m, sinon 3. Le style est choisi pour tout l'import. Les autres contours sont écartés et comptés ; ils attendent J22. | Un bâtiment générique en volume extrudé, hors style. |
| D-42 | Quel terrain ? | **ASCII Grid** (`.asc`) importé en maillage régulier, au pas du fichier ramené à 2 m au moins, dans un groupe « ARCHGEN Terrain ». Les commandes de terrain existantes (assise, étagement, voie sur terrain) le relèvent comme n'importe quel terrain. Le terrain de **Fichier → Géolocalisation** de SketchUp reste utilisable tel quel. | GeoTIFF : format binaire et compressé, lecteur lourd. |
| D-43 | Licences et limites ? | La racine d'import enregistre la source, la date du fichier et l'**attribution** : « © les contributeurs d'OpenStreetMap, ODbL » ; « IGN, Licence Ouverte 2.0 » si l'utilisateur la confirme pour un terrain. L'attribution s'affiche dans le rapport et le guide rappelle les obligations. Un import compte au plus 2 × 2 km, 300 bâtiments, 400 tronçons de voie et 1 000 × 1 000 points de terrain. Au-delà, il est refusé avec les nombres. | Aucune attribution enregistrée : contraire à l'ODbL dès qu'une image est diffusée. |

## 1. Lecture et projection — AG-125

- Un lecteur pur, dans le noyau, lit `.osm` XML (`node`, `way`, `tag`) et GeoJSON (`LineString`, `Polygon`, `MultiPolygon`). Il garde seulement les clés de la liste fermée : `highway`, `name`, `building`, `building:levels`, `height`, `lanes`, plus `bridge`, `tunnel` et `layer`, ajoutées à AG-125 pour pouvoir écarter les voies à niveaux en AG-126. Le reste est ignoré.
- Fichiers refusés : plus de 50 Mo, XML avec entités externes ou DTD (XXE), coordonnées hors des bornes WGS 84. Raison `map_file`, avec la ligne.
- Projection D-39 :
  - x = R · Δλ · cos φ₀ ;
  - y = R · Δφ ;
  - R = 6 371 008,8 m ;
  - arrondi au millimètre.
- Ce résultat est déterministe : le même fichier et la même origine donnent les mêmes points.
- Résultat : `{ origin, ways: [...], buildings: [...], skipped: {raison => nombre} }`.

- **Fait (AG-125).** `Core::MapReader` et `Core::MapProjection` sont des modules purs, sans lecture de fichier ni réseau.
  - Le XML est lu par un balayage borné des balises, sans parseur XML externe : REXML n'est pas garanti dans le Ruby de SketchUp. Toute déclaration `<!DOCTYPE` ou `<!ENTITY` est refusée, avec sa ligne.
  - Le GeoJSON passe par `StrictJson` (50 Mo, profondeur 64).
  - Un anneau de bâtiment n'est retenu que s'il est fermé et a au moins quatre références.
  - Comptés dans `skipped` : `missing_nodes`, `relation`, `multipolygon`, `geometry`, `other`.
  - Code `E_MAP`, raisons `map_file` (avec `reason_detail` : `too_large`, `invalid_utf8`, `doctype`, `not_osm`, `json`, `not_geojson`), `map_coordinates` (avec la ligne) et `map_empty`.

### Téléchargement OpenStreetMap (ADR-57), dans l'adaptateur

- **Le noyau ne touche pas le réseau** (AGENTS §2). Seul l'adaptateur SketchUp envoie la requête (`Sketchup::Http::Request`, sans bloquer l'interface), puis remet les octets reçus au lecteur pur.
- **Hôtes fermés**, en HTTPS seulement : `overpass-api.de` en premier, `overpass.kumi.systems` en secours. Aucun hôte ne vient d'un profil, d'un fichier ou d'une réponse.
- **Requête fixe** : voies `highway` et contours `building` dans une emprise sud, ouest, nord, est, sortie `xml`, `timeout:25`. L'emprise est calculée depuis la géolocalisation du modèle ou un point saisi (latitude, longitude), et sa taille (au plus 2 × 2 km).
- **Ce qui part sur le réseau** : l'emprise et l'en-tête `User-Agent: ARCHGEN/<version>`. Rien d'autre : ni nom de document, ni identifiant, ni chemin. Avant l'envoi, le panneau montre l'hôte et l'emprise, et demande une confirmation à chaque téléchargement.
- **Réponse** : statut 200 exigé ; 50 Mo au plus ; contenu lu par le lecteur pur comme un `.osm`. Les erreurs sont localisées (`map_download`) : délai, statut 429 (quota d'Overpass, réessayer plus tard), taille, hors ligne. Aucune nouvelle tentative automatique.
- **Provenance** : la réponse est enregistrée en `<modèle>_osm_<date>.osm` à côté du fichier SKP (dans le dossier choisi si le modèle n'est pas enregistré). La racine d'import garde l'hôte, la date, l'emprise et l'empreinte SHA-256 du fichier. Un nouvel import du même fichier donne le même résultat.

## 2. Voies → réseaux — AG-126

| `highway` | Type ARCHGEN |
|---|---|
| `motorway`, `trunk` | `autoroute` |
| `primary`, `secondary` | `nationale` |
| `tertiary`, `unclassified` | `campagne` |
| `residential`, `living_street` | `ville` |
| `service`, `track` | `rural` |
| `pedestrian`, `footway`, `path`, `steps` | `pieton` |
| `cycleway` | `verte` |

- **Simplification** : Douglas-Peucker à 0,5 m, puis découpe en voies de 64 points au plus.
- **Rayons** : le rayon de chaque sommet est le plus grand de 0, 5 ou 10 m que la voie accepte. Une voie encore refusée est écartée et nommée dans le rapport.
- **Réseaux** : les voies reliées par un nœud OSM commun forment un réseau. Au-delà de 24 voies, le réseau est coupé en morceaux de 24 voies, dans l'ordre d'un parcours en largeur. Les croisements entre deux morceaux deviennent des carrefours sans réseau (0.20.0).
- Les voies à niveaux (`bridge`, `tunnel`, `layer`) sont écartées et comptées : ponts et tunnels ne viennent pas d'OSM dans ce lot.
- **Fait (AG-126).** `Core::MapRoads` rend `{ networks, road_count, skipped }`, avec des réglages de réseau prêts pour `RoadNetworkIntake`. Choix et écarts :
  - **Points partagés** : un point commun à deux voies (nœud OSM partagé) n'est jamais retiré par la simplification, sinon le carrefour disparaîtrait.
  - **Rayon uniforme** : il est le même à tous les sommets d'une voie, le plus grand de 10, 5 ou 0 m qui passe. Ce n'est pas un rayon choisi sommet par sommet : c'est plus simple, au prix de virages parfois plus serrés.
  - **Contrôle du rayon** : il se fait sur le tracé ramené à son premier point, car une voie seule part de son origine.
  - **Écartés comptés** : `highway_unknown`, `level`, `too_short` (moins de 1 m) et `trace_refused`.
  - **Plafond** : au-delà de 400 tronçons, l'import est refusé avec `map_too_large`.
  - **Identifiants** : `w<id OSM>-<n°>`.

## 3. Bâtiments — AG-127

- **Rectangle orienté** : on cherche, sur toutes les directions d'arête du contour, celle qui donne le rectangle d'aire minimale. Il est accepté si contour ÷ rectangle ≥ 0,85, et si sa largeur et sa profondeur sont dans les plages de la configuration.
- Chaque bâtiment est une racine ARCHGEN ordinaire, modifiable au clic droit, placée et tournée selon son rectangle. La façade avant est le côté le plus proche d'une voie importée, sinon le côté le plus long.
- **Graine** : les 32 premiers bits du hachage de l'id OSM. Deux imports donnent les mêmes bâtiments.
- Écartés et comptés : contours non rectangulaires, trop petits ou trop grands, bâtiments qui se chevauchent après simplification.
- **Fait (AG-127).** `Core::MapBuildings` rend, pour chaque bâtiment accepté :
  - un brouillon de création (nom, profil, mode, graine, emprise, niveaux) qui passe `ConfigResolver` ;
  - `origin_m`, le coin gauche de la façade avant ;
  - `x_axis`, le long de la façade, l'intérieur étant à +Y.

  Précisions :
  - Une voie compte pour la façade si le milieu d'un côté est à 30 m au plus.
  - Deux bâtiments mitoyens qui se touchent sont acceptés. Un chevauchement de plus de 1 % du plus petit écarte le second, dans l'ordre des identifiants.
  - Comptés dans `skipped` : `degenerate`, `not_rectangular`, `size`, `levels` (hors 1 à 15) et `overlap`. Au-delà de 300 bâtiments, l'import est refusé avec `map_too_large`.

## 4. Terrain — AG-128

- ASCII Grid : les en-têtes `ncols`, `nrows`, `xllcorner`, `yllcorner`, `cellsize` et `NODATA_value` sont exigés.
- Le repère est **Lambert-93 (EPSG 2154)**, celui du RGE ALTI ; aucun autre repère n'est accepté dans ce lot. ARCHGEN projette la seule origine de la carte en Lambert-93, avec les formules de l'IGN. Il place ensuite chaque point du terrain par son écart à cette origine, divisé par le facteur d'échelle local et tourné de la convergence des méridiens γ = n · (λ − 3°), avec n ≈ 0,7256 : environ 5° en Bretagne, que l'on ne peut pas négliger. Une emprise qui ne recouvre pas la carte est refusée (`terrain_outside_map`).
- Les points `NODATA` sont refusés au-delà de 1 % ; en deçà, ils sont comblés par la moyenne de leurs voisins.
- Le maillage est fait de triangles par cellule, avec les arêtes intérieures adoucies, dans un groupe dédié à son propre calque. C'est une seule opération Undo.

- **Fait (AG-128).** `Core::MapTerrain` (avec `Lambert93`) rend un nœud `terrain` (surface, matière `earth`) et ses mesures : pas, points, faces, altitude d'origine, NODATA comblés, γ et k. Précisions et écarts :
  - **Fenêtre** : le fichier est découpé à l'emprise de la carte plus 20 m.
  - **Pas** : au moins 2 m, et il grandit jusqu'à 250 × 250 points au plus (environ 124 000 faces). Le fichier lui-même peut compter jusqu'à 1 000 × 1 000 points.
  - **Altitudes** : elles sont relatives à celle du terrain à l'origine de la carte, de sorte que voies et bâtiments, posés à z = 0, tombent sur le sol. L'altitude d'origine est rendue pour la racine.
  - **Coordonnées** : `xllcorner` et `xllcenter` sont acceptés tous les deux.
  - **Écriture renvoyée à AG-129** : l'écriture dans le groupe « ARCHGEN Terrain », l'adoucissement des arêtes et l'opération Undo relèvent du service d'import.

## 5. Commande, version — AG-129

- **Extensions → ARCHGEN → Importer une carte…** Le panneau propose :
  - **Télécharger depuis OpenStreetMap** : centre (géolocalisation du modèle ou latitude, longitude), taille, confirmation ; ou un fichier de carte local ;
  - le fichier de terrain, facultatif ;
  - les couches à importer : Voies, Bâtiments, Terrain ;
  - le style des bâtiments ;
  - un **aperçu chiffré** avant écriture : voies, réseaux, bâtiments, objets écartés avec leurs raisons, attribution.
- **Importer** fait une seule opération Undo, sous une racine « ARCHGEN Carte » qui porte l'origine, la source et l'attribution. Un refus laisse le document intact.
- Guide, journal, **RBZ 0.25.0**. Recette **H40** à faire à la main : un extrait OSM réel de 500 m sur 500 m, et un `.asc` IGN.
- **Fait (AG-129).** Ce qui est livré :
  - `Adapters::SketchUp::OverpassClient` : emprise, requête fixe, hôtes fermés, jugement de la réponse, nom du fichier gardé ;
  - `MapImportService` : `preview` sans écriture et `import` en une seule opération ;
  - `UI::MapController` et `MapPanel`, ce dernier envoyant la requête par `Sketchup::Http::Request` après confirmation ;
  - le menu **Importer une carte…** ;
  - le guide, le journal, la version 0.25.0 et le RBZ.

  **Écart au §5 : pas de racine englobante.** Une racine ARCHGEN doit rester au premier niveau du modèle pour être modifiable au clic droit. Réseaux et bâtiments importés sont donc des racines ordinaires, au premier niveau. La racine « ARCHGEN Carte » est un **marqueur** à côté d'eux : un composant avec un point de construction, qui porte l'origine, la source (hôte, emprise, date, SHA-256), l'attribution, les comptes et l'altitude d'origine du terrain. Le terrain est un composant « ARCHGEN Terrain », aux arêtes adoucies.

  **Autres précisions :**
  - Un réseau importé part du premier point de sa première voie et est placé à cet endroit (`origin_m`). Ce point est ajouté à `MapRoads`, car un réseau doit partir de `[0, 0]`.
  - La géolocalisation du modèle n'est pas modifiée ; l'origine est seulement gardée sur le marqueur.
  - **Non vérifié** : aucun envoi réel vers Overpass, aucun essai dans SketchUp.

## 6. Mode simple — AG-130 (ADR-58)

**Constat de l'essai réel (2026-11-11), sur 500 m de centre-ville :**

- téléchargement correct : 314 voies et 742 bâtiments ;
- aperçu refusé : plus de 300 bâtiments ;
- en réseaux ARCHGEN, 10 voies gardées sur environ 300. Les carrefours réels sont dans des virages, trop proches les uns des autres ou trop aigus. En retirant les fautives et en redressant les bouts, on ne dépasse pas la moitié.
- annuler le choix du dossier faisait échouer le téléchargement en silence.

**Ce qui change :**

- **Commande en un clic** : **Extensions → ARCHGEN → Importer rues et bâtiments autour du point géolocalisé…** (`UI::MapQuick`).
  - Il faut que le modèle soit géolocalisé (Fichier → Ajouter un emplacement) ; sinon, le message donne les trois étapes.
  - On choisit la taille de la zone (200 à 1 000 m) et le style, puis on confirme le téléchargement.
  - Un résumé chiffré s'affiche (rues, bâtiments, écartés, attribution) ; **OK** importe en une seule opération et la vue se cadre.
- **Rues à plat** (`Core::MapStreets`) : chaque voie devient une bande de chaussée à sa largeur par type, de 1,5 m pour un sentier à 14 m pour une autoroute.
  - Bords décalés avec onglets bornés ; un segment qui se croiserait reprend ses bords droits ; un triangle comble l'extérieur d'un virage serré.
  - Elle est posée de 3 à 12 cm au-dessus du sol, la plus importante au-dessus aux croisements.
  - Seuls les tunnels et les types inconnus sont écartés ; un pont reste une rue à plat.
  - Le tout forme un composant « ARCHGEN Rues », sous la balise de la chaussée. Plafond : 2 000 rues.
- **Bâtiments** : au-delà de 300, les plus proches du centre sont gardés, et le reste est compté (`too_many`).
- **Recalage sur SketchUp** :
  - l'origine est le point géolocalisé (`point_to_latlong(ORIGIN)` rend [longitude, latitude]) ;
  - la carte est tournée selon le nord de SketchUp, lu par `latlong_to_point`, puis composée avec chaque placement (`frame` du service).
- **Enregistrement sans dialogue** : l'extrait va à côté du SKP, ou dans `Documents\ARCHGEN` si le modèle n'est pas enregistré. Toute erreur du téléchargement revient au panneau ou en message.
- **« Ajouter du contexte » de SketchUp** (image de carte, bâtiments 3D) demande un abonnement : non utilisé.
- **Essai réel**, Montauban, zone de 400 m : 192 rues et 130 bâtiments importés en une opération, à leur place en vue de dessus. Le reste a été écarté : 466 éléments, surtout des bâtiments non rectangulaires.

## Tests

- **U87** : lecture (`.osm`, GeoJSON, clés gardées, XXE refusé, taille), projection (distances connues à 0,1 % près sur 2 km, déterminisme).
- **U88** : table des voies, simplification, rayons, réseaux reliés et découpés à 24, écartés comptés.
- **U89** : rectangle orienté (rectangle tourné, L refusé à 0,85), niveaux, graine stable, façade vers la voie.
- **U90** : ASCII Grid (en-têtes, NODATA, alignement, refus hors emprise), maillage.
- **U92** : rues à plat (largeur, matière, superposition, faces convexes et vers le haut sur virages serrés, tunnels et types inconnus comptés, pont gardé) ; U89 complété (300 plus proches gardés) ; U91 complété (mode simple, repère tourné).
- **U91** : panneau et service d'import avec doubles (aperçu, un Undo, refus sans résidu, attribution sur la racine) ; téléchargement avec un client HTTP factice (requête fixe, hôtes fermés, en-têtes, statut 429, taille, fichier enregistré et empreinte).
