# Contrat de la cartographie — J25 (AG-125 à AG-129)

**Demande du propriétaire (2026-11-10).** « ext 06 12 09 08 sont les chantiers prioritaires », dans cet ordre. EXT-06 et EXT-12 sont faits (0.23.0, 0.24.0). Le cadrage d'EXT-09 a été validé le même jour (« Go »).

**Périmètre.** EXT-09 importe un quartier réel à partir de **fichiers locaux** que l'utilisateur a téléchargés lui-même :

- les voies et les bâtiments d'un extrait OpenStreetMap, au format `.osm` (XML) ou GeoJSON ;
- éventuellement, un modèle numérique de terrain au format ASCII Grid (`.asc`), celui que l'IGN distribue pour le RGE ALTI.

ARCHGEN traduit ces fichiers en objets qu'il sait déjà produire : réseaux de voies, bâtiments et terrain. La provenance et la licence sont gardées et affichées.

**Hors périmètre :**

- le téléchargement : ARCHGEN n'ouvre aucune connexion, comme l'exigent AGENTS et SECURITY_PERFORMANCE ;
- les projections nationales exactes (Lambert-93, UTM) ;
- l'eau, les voies ferrées, la végétation et les points d'intérêt ;
- la mise à jour d'un import déjà fait ;
- les zones de plus de 2 × 2 km.

**Choix de détail.** Ils sont pris selon ADR-48 : la recommandation est appliquée, et le propriétaire peut la réviser (D-38 à D-43 ci-dessous). La décision d'ensemble est ADR-56.

## Décisions de détail appliquées (révisables)

| N° | Question | Choix appliqué | Autre option |
|---|---|---|---|
| D-38 | D'où viennent les données ? | **D'un fichier local** choisi par l'utilisateur : `.osm` exporté depuis openstreetmap.org, GeoJSON (Overpass, QGIS), `.asc` pour le terrain. Le **mode local** est le seul mode. | Un téléchargement direct par l'API Overpass : réseau, disponibilité et quotas. |
| D-39 | Quelle projection ? | **Plan tangent local** (équirectangulaire autour d'une origine), en mètres. L'origine est la géolocalisation du modèle SketchUp si elle existe, sinon le centre de l'emprise du fichier ; dans ce dernier cas, l'origine est enregistrée sur la racine. Sur 2 km, l'écart avec une projection conforme reste sous 0,1 %. | Lambert-93 ou UTM exacts : une bibliothèque de projection à embarquer. |
| D-40 | Que devient une voie OSM ? | Chaque `highway` connu donne une voie ARCHGEN avec un **type tout prêt** selon une table fermée (§2). Les voies reliées forment des **réseaux** de 24 voies au plus, avec leurs carrefours. Une valeur inconnue est ignorée et comptée dans le rapport. | Une coupe calculée tag par tag (`lanes`, `sidewalk`, `width`) : plus fidèle, beaucoup plus de cas. |
| D-41 | Que devient un bâtiment OSM ? | Son contour est remplacé par le **rectangle orienté** qui l'enveloppe au plus juste, si le contour en remplit au moins 85 %. Le nombre de niveaux vient de `building:levels`, sinon de `height` ÷ 3 m, sinon 3. Le style est choisi pour tout l'import. Les autres contours sont écartés et comptés ; ils attendent J22. | Un bâtiment générique en volume extrudé, hors style. |
| D-42 | Quel terrain ? | **ASCII Grid** (`.asc`) importé en maillage régulier, au pas du fichier ramené à 2 m au moins, dans un groupe « ARCHGEN Terrain ». Les commandes de terrain existantes (assise, étagement, voie sur terrain) le relèvent comme n'importe quel terrain. Le terrain de **Fichier → Géolocalisation** de SketchUp reste utilisable tel quel. | GeoTIFF : format binaire et compressé, lecteur lourd. |
| D-43 | Licences et limites ? | La racine d'import enregistre la source, la date du fichier et l'**attribution** : « © les contributeurs d'OpenStreetMap, ODbL » ; « IGN, Licence Ouverte 2.0 » si l'utilisateur la confirme pour un terrain. L'attribution s'affiche dans le rapport et le guide rappelle les obligations. Un import compte au plus 2 × 2 km, 300 bâtiments, 400 tronçons de voie et 1 000 × 1 000 points de terrain. Au-delà, il est refusé avec les nombres. | Aucune attribution enregistrée : contraire à l'ODbL dès qu'une image est diffusée. |

## 1. Lecture et projection — AG-125

- Un lecteur pur, dans le noyau, lit `.osm` XML (`node`, `way`, `tag`) et GeoJSON (`LineString`, `Polygon`, `MultiPolygon`). Il garde seulement les clés de la liste fermée : `highway`, `name`, `building`, `building:levels`, `height`, `lanes`. Le reste est ignoré.
- Fichiers refusés : plus de 50 Mo, XML avec entités externes ou DTD (XXE), coordonnées hors des bornes WGS 84. Raison `map_file`, avec la ligne.
- Projection D-39 :
  - x = R · Δλ · cos φ₀ ;
  - y = R · Δφ ;
  - R = 6 371 008,8 m ;
  - arrondi au millimètre.
- Ce résultat est déterministe : le même fichier et la même origine donnent les mêmes points.
- Résultat : `{ origin, ways: [...], buildings: [...], skipped: {raison => nombre} }`.

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

## 3. Bâtiments — AG-127

- **Rectangle orienté** : on cherche, sur toutes les directions d'arête du contour, celle qui donne le rectangle d'aire minimale. Il est accepté si contour ÷ rectangle ≥ 0,85, et si sa largeur et sa profondeur sont dans les plages de la configuration.
- Chaque bâtiment est une racine ARCHGEN ordinaire, modifiable au clic droit, placée et tournée selon son rectangle. La façade avant est le côté le plus proche d'une voie importée, sinon le côté le plus long.
- **Graine** : les 32 premiers bits du hachage de l'id OSM. Deux imports donnent les mêmes bâtiments.
- Écartés et comptés : contours non rectangulaires, trop petits ou trop grands, bâtiments qui se chevauchent après simplification.

## 4. Terrain — AG-128

- ASCII Grid : les en-têtes `ncols`, `nrows`, `xllcorner`, `yllcorner`, `cellsize` et `NODATA_value` sont exigés.
- Le repère est **Lambert-93 (EPSG 2154)**, celui du RGE ALTI ; aucun autre repère n'est accepté dans ce lot. ARCHGEN projette la seule origine de la carte en Lambert-93, avec les formules de l'IGN. Il place ensuite chaque point du terrain par son écart à cette origine, divisé par le facteur d'échelle local et tourné de la convergence des méridiens γ = n · (λ − 3°), avec n ≈ 0,7256 : environ 5° en Bretagne, que l'on ne peut pas négliger. Une emprise qui ne recouvre pas la carte est refusée (`terrain_outside_map`).
- Les points `NODATA` sont refusés au-delà de 1 % ; en deçà, ils sont comblés par la moyenne de leurs voisins.
- Le maillage est fait de triangles par cellule, avec les arêtes intérieures adoucies, dans un groupe dédié à son propre calque. C'est une seule opération Undo.

## 5. Commande, version — AG-129

- **Extensions → ARCHGEN → Importer une carte…** Le panneau propose :
  - le fichier de carte et, facultatif, le fichier de terrain ;
  - les couches à importer : Voies, Bâtiments, Terrain ;
  - le style des bâtiments ;
  - un **aperçu chiffré** avant écriture : voies, réseaux, bâtiments, objets écartés avec leurs raisons, attribution.
- **Importer** fait une seule opération Undo, sous une racine « ARCHGEN Carte » qui porte l'origine, la source et l'attribution. Un refus laisse le document intact.
- Guide, journal, **RBZ 0.25.0**. Recette **H40** à faire à la main : un extrait OSM réel de 500 m sur 500 m, et un `.asc` IGN.

## Tests

- **U87** : lecture (`.osm`, GeoJSON, clés gardées, XXE refusé, taille), projection (distances connues à 0,1 % près sur 2 km, déterminisme).
- **U88** : table des voies, simplification, rayons, réseaux reliés et découpés à 24, écartés comptés.
- **U89** : rectangle orienté (rectangle tourné, L refusé à 0,85), niveaux, graine stable, façade vers la voie.
- **U90** : ASCII Grid (en-têtes, NODATA, alignement, refus hors emprise), maillage.
- **U91** : panneau et service d'import avec doubles (aperçu, un Undo, refus sans résidu, attribution sur la racine).
