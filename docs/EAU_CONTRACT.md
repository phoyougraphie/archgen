# Contrat de l'eau et du littoral — EXT-13

Contrat de départ, écrit avant le code. Il prolonge le [contrat de voirie](VOIRIE_CONTRACT.md) sans rien changer à une voie existante : une coupe sans bande d'eau ni de littoral garde son plan et son empreinte. Décision : ADR-39 (D-11). Question encore ouverte : D-12 (ponts). Les valeurs marquées « départ » sont à calibrer à la recette, par une décision écrite.

**Besoin du propriétaire (2026-11-08).** Commencer par l'eau et les ponts. Une rivière peut suivre un terrain ; un canal monte et descend par des écluses ; un fleuve se pose sur un terrain plat. Pour le bord de mer, une astuce : des voies « falaises » puis la mer, « dunes », « plage », avec des murets et les clôtures qui retiennent le sable (ganivelles).

## Principes

- **Un cours d'eau ou une côte est une voie** (ADR-39) : même coupe, même éditeur, même tracé à rayons, mêmes refus et même copie entaillée du terrain (ADR-38). Une rivière, un canal, une falaise ou une plage sont des préréglages de coupe.
- **L'eau est horizontale en travers.** Le long du tracé, son niveau suit l'un de trois régimes, choisis dans le réglage `water` : il descend (rivière), il descend par paliers (canal à écluses), il reste à un seul niveau (fleuve, côte).
- **Pas de réglage caché.** Le placement des écluses, l'enveloppe descendante d'une rivière et le niveau d'un fleuve sont des règles écrites ici et annoncées dans l'aperçu (métriques).
- **Largeur constante** le long d'un tracé, comme une voie. Une largeur qui varie, un méandre qui s'élargit, une confluence sont hors de cette version.
- **Valeurs de conception**, sans vérification hydraulique ni réglementaire ; le panneau le dit.

## Bandes d'eau et de berge (AG-051)

Ajoutées au catalogue `road_bands.v1.json` (révision du catalogue, pas du format `road_profile` V1 : une clé de type nouvelle n'est qu'une valeur de plus du registre fermé).

| Clé | Libellé | Défaut (m) | Plage (m) | Forme |
|---|---|---|---|---|
| `water` | Plan d'eau | 12 | 2 à 400 | Surface d'eau à `−freeboard_m`, lit à `−(freeboard_m + depth_m)` |
| `quay` | Quai | 3 | 1 à 20 | Plane au niveau 0, mur vertical côté eau jusqu'au lit |
| `riverbank` | Berge naturelle | 4 | 1 à 30 | Pente droite du niveau 0 à la surface de l'eau, côté eau |

Réglages de bande, propres à `water` : `freeboard_m` (revanche, hauteur du niveau 0 au-dessus de l'eau), de 0,3 à 5 m, 1 m par défaut ; `depth_m` (profondeur), de 0,5 à 15 m, 2 m par défaut. Le chemin de halage est un `track` ou un `path` existant, posé sur la berge ou le quai.

- **Bords de l'eau :** chaque côté d'une bande `water` touche un `quay`, une `riverbank`, ou une bande de littoral (ci-dessous) ; sinon `E_ROAD_BAND`, `water_unbounded`, sur la bande d'eau.
- **Lit :** contre un quai, le lit va jusqu'au pied du mur ; contre une berge, il remonte en pente de 1 pour 2 dans la largeur de l'eau. Une eau trop étroite pour ses deux pentes (largeur < 4 × `depth_m` entre deux berges) : `water_too_narrow`.
- **Berge trop raide :** pente `freeboard_m / largeur` au-delà de 100 % : `bank_too_steep`, sur la berge.
- **Éléments :** aucun dans `water` (`band_accepts_no_items`) ; un quai accepte lampadaires, potelets, barrières, garde-corps et murets.
- **Matières :** `water/surface` (bleu, transparence de 40 %, départ), `water/bed`, `water/quay`.
- **Préréglages :** canal à chemin de halage, rivière à berges, fleuve à quais.

## Bandes de littoral (AG-052)

L'astuce du bord de mer : **la mer est la dernière bande de la coupe**, côté extérieur, et certaines bandes changent le niveau de toutes celles qui sont après elles, du côté de la mer. La coupe a donc des niveaux cumulés : la terre en haut, la mer en bas.

| Clé | Libellé | Défaut (m) | Plage (m) | Forme |
|---|---|---|---|---|
| `cliff` | Falaise | 6 | 2 à 40 | Front rocheux de `height_m` (5 à 80, 20 par défaut), incliné vers la mer dans sa largeur ; les bandes suivantes descendent de `height_m` |
| `rocks` | Estran rocheux | 15 | 2 à 200 | Plane, matière rocheuse |
| `dune` | Dune | 30 | 8 à 200 | Bosse de `height_m` (1 à 15, 5 par défaut) à 8 facettes, même niveau des deux côtés |
| `beach` | Plage | 40 | 5 à 300 | Pente douce de `slope_percent` (1 à 10, 4 par défaut) vers la mer ; les bandes suivantes descendent d'autant |
| `sea` | Mer | 200 | 20 à 2 000 | Surface d'eau au niveau du bord de la bande précédente, sans lit |

- **La mer au bout :** `sea` est la première ou la dernière bande, et une seule par coupe ; sinon `sea_not_outer`. La falaise et la plage descendent toujours vers la mer : une coupe à falaise ou à plage sans mer est refusée (`coast_without_sea`).
- **Éléments nouveaux** (`road_items.v1.json`) :
  - `sand_fence`, **ganivelle** : lattes de châtaignier verticales de 0,08 m, jointives à 0,05 m près, sur deux fils, poteaux tous les 2 m ; hauteur de 0,8 à 1,5 m ; continue ; sur une dune ou une plage seulement (`item_band_mismatch`).
  - `low_wall`, **muret** : maçonné, 0,30 m d'épaisseur, hauteur de 0,3 à 1,2 m ; continu ; sur un trottoir, un chemin, un quai, une plage ou en tête de falaise.
- **Pose sur une bande en pente ou en bosse :** la position en travers suit la règle de la voirie ; le pied se pose à la cote de la coupe à cette position.
- **Matières :** `coast/sand`, `coast/dune` (sable et oyats), `coast/rock`, `coast/cliff` ; la mer prend `water/surface`.
- **Préréglages :** côte à falaises (sentier côtier, garde-corps, falaise, estran, mer), côte à dunes (chemin, dune à ganivelles, plage, mer), plage et promenade (trottoir, lampadaires, muret, plage, mer).
- **Rayon :** une mer de 2 000 m de large est un ruban décalé comme les autres. Du côté concave d'un virage, le rayon doit dépasser la largeur, sinon le refus existant de rayon s'applique, sur le segment, avec le conseil de réduire la largeur de la mer.

## Réglage `water`, dans les réglages de voie V1

Clé facultative et fermée, à côté de `ground`. Une coupe qui porte une bande `water` ou `sea` l'exige (`E_ROAD_WATER`, `water_mode_missing`) ; une coupe sans eau la refuse (`water_without_band`).

| Champ | Valeurs | Défaut (départ) | Sens |
|---|---|---|---|
| `mode` | `river`, `canal`, `flat` | — | Régime du niveau d'eau le long du tracé |
| `max_grade_percent` | [0 ; 10] | 3 | Rivière : pente maximale de l'eau |
| `lock_drop_m` | [1 ; 10] | 3 | Canal : chute d'une écluse |
| `lock_length_m` | [20 ; 200] | 40 | Canal : longueur de la chambre |
| `level_m` | nombre | absent | Fleuve ou côte : altitude du niveau 0 de la coupe ; absent, le plus bas des points de pente |

Sans terrain (`ground` absent), les trois régimes donnent une voie horizontale, à un seul niveau : un canal sans terrain n'a pas d'écluse. Une coupe à mer n'accepte que `flat` (`sea_needs_flat`).

## Rivière sur un terrain (AG-053)

Mêmes relevé, points de pente et talus que la [voie sur un terrain](VOIRIE_CONTRACT.md#voie-sur-un-terrain-ag-049-adr-38), avec trois différences :

1. **Le tracé va de l'amont vers l'aval.** Terrain plus haut d'au moins 1 m à la fin qu'au début (moyennes sur l'emprise) : `E_ROAD_WATER`, `river_upstream`, avec le conseil d'inverser le tracé, avant tout autre calcul.
2. **Enveloppe descendante :** l'altitude du niveau 0 à un point de pente est le plus bas entre la moyenne du terrain sur l'emprise en ce point et l'altitude du point précédent. L'eau ne remonte donc jamais ; là où le terrain remonte, la rivière creuse, et le déblai reste borné par `RELIEF_MAX` (`E_ROAD_EARTHWORK`).
3. **Pente :** au-delà de `max_grade_percent`, `E_ROAD_GRADE` comme une voie, borne prise dans `water`.

La copie entaillée du terrain (ADR-38) creuse le lit : l'eau se voit dans l'entaille. Métriques : `water_drop_m` (chute totale), `grade_max_percent`, `cut_max_m`, `fill_max_m`.

## Canal à écluses (AG-054)

Le canal avance par **biefs** horizontaux. Les écluses sont placées par une règle fixe :

1. Le premier bief prend le niveau du profil du terrain au début du tracé.
2. On suit les points de pente du profil du terrain p(s). Dès que p(s) s'écarte du niveau du bief courant de plus de `lock_drop_m`, une écluse est posée **avant** ce point : la chambre finit au point de pente précédent. Le bief suivant est plus bas, ou plus haut, de `lock_drop_m` exactement.
3. Une écluse occupe `lock_length_m` le long de l'axe, plus 10 m (départ) d'approche de chaque côté, sur **un segment droit**. Sinon `E_ROAD_WATER`, `lock_on_curve`, avec l'abscisse ; deux écluses dont les approches se recouvrent : `locks_too_close`. Le conseil est de réduire la chute ou d'allonger la ligne droite.
4. Entre deux écluses, déblai et remblai restent bornés par `RELIEF_MAX`.

**Forme d'une écluse :** chambre à murs verticaux (bajoyers, matière `water/quay`) quelle que soit la berge du bief ; deux paires de portes busquées, solides fermés, avec passerelle à leur tête ; mur de chute au fond, à l'amont ; eau de la chambre au niveau aval. Les bandes de terre (quai, chemin, berge) passent d'un niveau à l'autre en rampe droite le long de la chambre. La largeur de l'eau est celle de la chambre, de 3 à 40 m (`lock_too_wide` au-delà).

**Plan :** un groupe `water/locks` sous la racine, une définition partagée de porte par largeur au millimètre. Métriques : `lock_count`, `water_drop_m`, et pour chaque écluse son abscisse et sa chute.

## Fleuve et côte : un seul niveau (AG-055)

Mode `flat` : tout le tracé à une altitude, `level_m` ou, sans valeur, le plus bas des points de pente du terrain. Le terrain entaillé descend jusqu'au lit ; un terrain trop accidenté le long du tracé est refusé par `RELIEF_MAX`, le terrain doit donc être à peu près plat.

**Côté mer :** pas de talus au bord extérieur de la mer ; la copie du terrain est entaillée jusqu'à ce bord, et le terrain au-delà reste tel qu'il est. Côté terre, le talus raccorde la coupe au terrain comme pour une voie.

## Réseaux et ponts

- Dans un réseau, une voie à eau ou à mer qui croise une autre voie ou finit sur elle est refusée (`E_ROAD_JUNCTION`, `water_crossing`) tant que les ponts n'existent pas. Deux cours d'eau qui se rejoignent : `water_confluence`, hors de cette version.
- Deux racines séparées, une rue et une rivière, ne sont pas comparées entre elles : rien n'empêche de les superposer à la main.
- **Ponts (AG-057) :** comment ils naissent et lesquels, c'est D-12. Le ticket attend la décision, puis son propre contrat.

## Panneau (AG-056)

Dans **Composer une coupe** : les bandes d'eau et de littoral, leurs réglages, la coupe dessinée à niveaux cumulés avec le personnage et la surface de l'eau. Dans **Tracer une voie** : le régime de l'eau, ses réglages, et l'aperçu qui annonce la chute totale, le nombre d'écluses et leurs abscisses. Guide, journal, RBZ 0.8.0 et recette H23.

## Hors périmètre de cette version

Largeur variable, méandres qui s'élargissent, confluences et deltas ; courant, marées, vagues ; ports, digues et épis perpendiculaires au rivage ; berges en enrochement ; écluses à plusieurs chambres et ascenseurs à bateaux ; bateaux.
