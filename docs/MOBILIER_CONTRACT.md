# Contrat du mobilier urbain — J24 (AG-120 à AG-124)

**Demande du propriétaire (2026-11-10).** « ext 06 12 09 08 sont les chantiers prioritaires », dans cet ordre. EXT-06 est fait (0.23.0). Cadrage d'EXT-12 validé le même jour (« Oui, cadre EXT-12 »).

**Périmètre.** EXT-12 ajoute des arrêts de bus, des attaches vélos et des panneaux de signalisation, plus deux petits mobiliers courants : banc et corbeille. Ils sont posés **dans la coupe d'une voie**, comme les arbres et les lampadaires. Ce sont des éléments du catalogue fermé `road_items` (ADR-34, ADR-35) : volumes simples à facettes, couleurs unies, une définition partagée par variante et hauteur.

Hors périmètre :

- les panneaux avec du texte ou un pictogramme fin : une plaque est une forme et des couleurs ;
- les panneaux posés automatiquement aux carrefours ;
- le mobilier posé hors d'une voie, par exemple au pied d'une maison isolée ;
- les composants de l'utilisateur.

**Choix de détail.** Ils sont pris selon ADR-48 : la recommandation est appliquée, et le propriétaire peut la réviser (D-33 à D-37 ci-dessous). La décision d'ensemble est ADR-55.

## Décisions de détail appliquées (révisables)

| N° | Question | Choix appliqué | Autre option |
|---|---|---|---|
| D-33 | Module séparé ou coupe ? | **Dans la coupe** : nouveaux types du catalogue `road_items`, réglés bande par bande dans l'éditeur de voie. | Un outil séparé qui pose un objet d'un clic sur une voie : deuxième racine, deuxième format. |
| D-34 | Comment poser un objet à un endroit précis ? | Nouveau mode de pose **`positions_m`** : une liste de distances depuis le début du tronçon, sur la ligne de pose. Il vaut pour tout élément ponctuel, lampadaire compris. Le pas régulier reste le mode par défaut. | Pose à la souris sur la voie tracée. |
| D-35 | Quel arrêt de bus ? | **Abri** de 3,0 m × 1,4 m × 2,5 m, ouvert du côté de la chaussée la plus proche : fond et deux joues vitrés, toit, banc, mât de 2,6 m avec plaque. Il demande une bande de 1,6 m au moins. | Mât et plaque seuls, sans abri. |
| D-36 | Quels panneaux ? | **Huit plaques sans texte**, sur mât de 2,3 m, face à ceux qui arrivent dans le sens choisi : stop (octogone rouge), cédez le passage (triangle pointe en bas), interdiction (disque rouge), limitation (disque blanc cerclé de rouge), obligation (disque bleu), indication (carré bleu), danger (triangle pointe en haut), passage piéton (carré bleu, triangle blanc). | Plaques texturées avec pictogrammes : hors des matières unies. |
| D-37 | Quels petits mobiliers ? | **Banc** de 1,8 m (assise et dossier en bois, pieds en métal), **corbeille** cylindrique de 0,6 m, **attache vélos** en U renversé de 0,80 × 0,75 m, par groupes de `count` arceaux espacés de 0,80 m. | Bancs et racks en plusieurs variantes de style. |

## 1. Catalogue et formes — AG-120

Nouveaux types dans `road_items.v1.json`, avec leur copie embarquée identique (ADR-13) :

| Clé | Variantes | Hauteur (m) | Répétition | Bandes |
|---|---|---|---|---|
| `bench` | `bench` | 0,8 à 1,0 (0,85) | pas de 5 m au moins, 20 m par défaut | trottoir, chemin, accotement, plantation, terre-plein |
| `bin` | `bin` | 0,6 à 1,1 (0,9) | pas de 5 m au moins, 40 m par défaut | idem |
| `bike_rack` | `hoop` | 0,7 à 0,9 (0,75) | pas de 5 m au moins, 30 m par défaut ; `count` de 1 à 10 arceaux (3) | idem |
| `bus_stop` | `shelter`, `pole` | 2,3 à 3,0 (2,5) | positions seulement (`positions_m`) | trottoir, accotement |
| `sign` | `stop`, `give_way`, `prohibition`, `limit`, `mandatory`, `information`, `danger`, `crossing` | 2,0 à 3,0 (2,3) | positions seulement | trottoir, accotement, terre-plein, plantation |

- Un élément posé sur une autre bande est refusé (`item_band_mismatch`).
- Chaque forme est faite de solides fermés et orientés, définis dans `RoadItemShapes`. La définition partagée a pour identifiant `<type>/<variante>/<hauteur en mm>`, plus `/<count>` pour l'attache vélos.
- Matières : `road/item/wood`, `steel`, `metal`, `red` et `white` existent déjà. On ajoute `road/item/blue`, `road/item/glass` (verre, opacité 0,35) et `road/item/yellow` (marquage de l'abri). Ce sont des données versionnées du catalogue `road_materials`.
- Repère de l'instance : le même que celui des éléments existants. Y pointe vers la chaussée la plus proche. Le banc tourne le dos à la chaussée ; l'abri s'ouvre vers elle.
- Les objets comptent dans les plafonds `road_items` et `road_faces` existants.
- **Fait (AG-120).** Ce qui est livré :
  - `Geometry::RoadFurnitureShapes` donne les formes des cinq types ;
  - `bench`, `bin` et `bike_rack` sont au catalogue (copies identiques) et posés au pas régulier, avec la clé facultative `count` (schéma de coupe, refus `count_unavailable` et `count_range`) ;
  - les matières `road/item/blue`, `glass` (opacité 0,35) et `yellow` sont ajoutées ;
  - l'éditeur dessine le banc, la corbeille et l'arceau dans la coupe.
  - Écart d'ordre : les formes de `bus_stop` et `sign` sont faites, mais leurs entrées de catalogue viennent avec AG-121, car elles exigent `positions_m`. Sans ce mode, le moteur les aurait traitées comme des éléments continus.

## 2. Pose à des positions — AG-121

- `positions_m: [s1, s2, …]`, de 1 à 50 valeurs en ordre strictement croissant (`positions_order`), mesurées **sur l'axe de la voie tracée** depuis son début, puis reportées sur la ligne de pose au même endroit. Une valeur au-delà de la voie est refusée (`position_out_of_road`). Revu à AG-121 : le contrat disait « sur la ligne de pose », mais l'axe est la longueur que l'on lit au tracé, la même pour toutes les bandes.
- On donne `positions_m` ou `spacing_m`, jamais les deux (`positions_with_spacing`). `bus_stop` et `sign` exigent `positions_m` (`positions_required`).
- Un élément continu n'accepte pas `positions_m` (`continuous_item`).
- Un réseau découpe ses voies en tronçons : les positions se mesurent sur la voie entière telle que tracée, et chacune n'est posée qu'une fois. Comme un élément répété, une position qui tombe dans l'emprise d'un carrefour ou d'un passage à niveau n'est pas posée.
- **Fait (AG-121).** Ce qui est livré :
  - `RoadItems.place_at` (paramètres `from_m` et `to_end` pour les tronçons), `RoadEngine.position_problems` (voie seule et réseau), contrôles d'intake, clé `positions_m` au schéma de coupe ;
  - `bus_stop` et `sign` au catalogue, en mode `positions` ;
  - le budget d'objets compte les positions.
  - Les plaques de panneau sont découpées en éventail, car le plan n'accepte que des faces de 3 ou 4 sommets.
  - L'éditeur n'a pas encore de champ Positions (AG-124) : y ajouter un arrêt de bus donne pour l'instant le refus `positions_required`.

## 3. Arrêt de bus — AG-122

- `shelter` : abri D-35, centré sur la position, sa longueur le long de la ligne. L'arrière est à 0,3 m du bord de bande opposé à la chaussée. Une bande de moins de 1,6 m est refusée (`bus_stop_band_too_narrow`).
- `pole` : mât de 2,6 m et plaque carrée bleue de 0,4 m, sans abri.
- Un marquage jaune « zigzag » simplifié est posé sur la voie de circulation voisine. Cette bande est extrudée sur 12 m à 0,01 m au-dessus de la surface, centrée sur l'arrêt. Il est absent s'il n'y a pas de voie de circulation contiguë.
- Avertissement `W_ROAD_CLEARANCE` si un arbre ou un lampadaire de la même bande est à moins de 2 m de l'abri.
- **Fait (AG-122).** Ce qui est livré :
  - `RoadSection` pose l'abri en travers, fond à 0,30 m du bord opposé à la chaussée, et ajoute un élément dérivé `bus_marking` sur la voie contiguë, à 0,60 m de son bord. Le marquage partage les positions de l'arrêt.
  - Une bande voisine qui n'est pas une voie de circulation (stationnement, piste cyclable) ne reçoit pas de marquage.
  - L'intake refuse un abri sur une bande trop étroite (`bus_stop_band_too_narrow`) ; le mât seul passe.
  - L'avertissement `bus_stop_clearance` mesure l'écart le long de la voie comme sur une droite : moins de 1,5 + 2 m du centre de l'abri.
  - Un refus de position hors voie n'est émis que sur l'arrêt, pas sur son marquage.

## 4. Panneaux — AG-123

- `sign` porte une clé `facing` : `forward` (vu par ceux qui circulent dans le sens du tracé, par défaut) ou `backward`.
- La plaque fait 0,7 m. Elle est en haut du mât, son bas à `height_m − 0,7`. Elle est épaisse de 0,02 m, avec un liseré de couleur à 0,05 m du bord.
- Formes : octogone, triangle, disque à 16 pans, carré, selon D-36.
- Couleurs uniquement. Le chiffre d'une limitation n'est pas écrit (limite rappelée au guide).
- **Fait (AG-123).** Ce qui est livré :
  - la clé `facing` au schéma de coupe ; l'intake la réserve aux panneaux (`facing_unavailable`) et écrit `forward` par défaut ;
  - `RoadItems.side` oriente l'instance d'un panneau selon son sens et non selon la chaussée la plus proche ;
  - la plaque est découpée en éventail ; son haut est exactement à `height_m`.

## 5. Éditeur et version — AG-124

- Dans l'éditeur de voie :
  - les cinq types apparaissent dans la liste d'éléments de chaque bande compatible ;
  - un champ **Positions (m)** prend des distances séparées par des points-virgules ;
  - un choix **Sens** est proposé pour un panneau.
- L'aperçu de coupe montre les objets à l'échelle, à côté du personnage de repère.
- Un préréglage « Rue avec arrêt de bus » s'ajoute à ceux de l'éditeur.
- Guide, journal, **RBZ 0.24.0**. Recette **H39** à faire à la main.

## Tests

- **U82** : formes du catalogue (solides fermés, hauteur respectée, une définition par variante et hauteur, attache vélos par `count`), refus `item_band_mismatch`, copies embarquées identiques.
- **U83** : `positions_m` (pose exacte sur droite et sur arc, refus hors tronçon, refus avec un pas, positions exigées), lampadaire à des positions.
- **U84** : abri ouvert vers la chaussée, bande trop étroite refusée, marquage sur la voie voisine seulement, avertissement de proximité.
- **U85** : huit plaques, sens `forward` et `backward`, hauteur.
- **U86** : panneau de voie (types, champ Positions, sens), préréglage.
