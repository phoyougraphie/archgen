# Contrat de l'eau et du littoral — EXT-13

Contrat de départ, écrit avant le code. Il prolonge le [contrat de voirie](VOIRIE_CONTRACT.md) sans rien changer à une voie existante : une coupe sans bande d'eau ni de littoral garde son plan et son empreinte. Décisions : ADR-39 (D-11), ADR-40 (D-12, ponts), ADR-41 (réglages de bande). Les valeurs marquées « départ » sont à calibrer à la recette, par une décision écrite.

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

Réglages de bande, propres à `water` : `freeboard_m` (revanche, hauteur du niveau 0 au-dessus de l'eau), de 0,3 à 5 m, 1 m par défaut ; `depth_m` (profondeur), de 0,5 à 15 m, 2 m par défaut. Ce sont deux champs facultatifs de la bande dans `road_profile` V1 (ADR-41) : le catalogue dit quelle bande les accepte (`settings`), une autre bande les refuse (`band_setting_unavailable`), une valeur hors plage aussi (`setting_range`). Le profil effectif d'un plan d'eau porte toujours les deux ; celui d'une autre bande n'en porte aucun, si bien qu'une coupe d'avant garde son empreinte. Le chemin de halage est un `track` ou un `path` existant, posé sur la berge ou le quai.

- **Bords de l'eau :** chaque côté d'une bande `water` touche un `quay` ou une `riverbank` ; sinon `E_ROAD_BAND`, `water_unbounded`, sur la bande d'eau.
- **Lit :** contre un quai, le lit va jusqu'au pied du mur ; contre une berge, il part de la ligne d'eau et descend en pente de 1 pour 2 (2 × `depth_m` en largeur). Une eau trop étroite pour ses pentes (largeur < 2 × `depth_m` par berge) : `water_too_narrow`, sur `/bands/<i>/width_m`, avec le minimum.
- **Berge :** elle touche un seul plan d'eau, juste à côté (`bank_without_water` sinon) ; pente `freeboard_m / largeur` au-delà de 100 % : `bank_too_steep`, sur sa largeur.
- **Ligne de coupe :** le lit fait partie de la ligne de coupe ; le mur d'un quai est la contremarche entre le quai et le lit, en matière `road/quay`. La surface de l'eau est un ruban à part, à la ligne d'eau, de bord à bord du plan d'eau, dans un nœud `road/water` (balise de la chaussée) : séparée, elle ne coupe pas les murs de quai dans SketchUp. Métrique `water_face_count`.
- **Éléments :** aucun dans `water` (`band_accepts_no_items`) ; un quai et une berge les acceptent comme un trottoir, posés à la cote de leur surface (sur la pente pour une berge).
- **Matières :** `road/water` (lit), `road/quay`, `road/riverbank`, `road/water_surface` (bleu, opacité de 0,6, départ ; le writer règle l'opacité de la matière).
- **Réseau :** une voie à eau n'entre pas encore dans un réseau (`E_ROAD_WATER`, `water_in_network`, sur le profil de la voie).
- **Terrain :** jusqu'à AG-053 et AG-055, une voie à eau sur un terrain est refusée (`water_ground_unavailable`, sur `/ground`) plutôt que posée à plat en silence.
- **Préréglages :** canal à chemin de halage, rivière à berges, fleuve à quais.

## Bandes de littoral (AG-052)

L'astuce du bord de mer : **la mer est la dernière (ou la première) bande de la coupe**, et certaines bandes changent le niveau de toutes celles qui sont après elles, du côté de la mer. La coupe a donc des niveaux cumulés : la terre en haut, la mer en bas. De la terre vers la mer, chaque bande part du niveau où s'arrête la précédente (`base_m` dans la coupe dessinée) ; sa propre forme et son niveau de catalogue s'y ajoutent. Une coupe sans mer garde tous ses niveaux.

| Clé | Libellé | Défaut (m) | Plage (m) | Forme |
|---|---|---|---|---|
| `cliff` | Falaise | 6 | 2 à 40 | Front rocheux de `height_m` (5 à 80, 20 par défaut), incliné vers la mer dans sa largeur ; les bandes suivantes descendent de `height_m` |
| `rocks` | Estran rocheux | 15 | 2 à 200 | Plane, matière rocheuse |
| `dune` | Dune | 30 | 8 à 200 | Bosse de `height_m` (1 à 15, 5 par défaut) à 8 facettes, même niveau des deux côtés |
| `beach` | Plage | 40 | 5 à 300 | Pente douce de `slope_percent` (1 à 10, 4 par défaut) vers la mer ; les bandes suivantes descendent d'autant |
| `sea` | Mer | 200 | 20 à 2 000 | Surface d'eau au niveau du bord de la bande précédente, sur un fond plat 1 m plus bas (départ) |

- **La mer au bout :** `sea` est la première ou la dernière bande, et une seule par coupe ; sinon `sea_not_outer`, sur la mer en trop (`/bands/<i>`). La falaise et la plage descendent toujours vers la mer : une coupe à falaise ou à plage sans mer est refusée (`coast_without_sea`, sur la bande). Une dune va sans mer.
- **Réglages de bande** (ADR-41) : `height_m` sur une falaise ou une dune, `slope_percent` sur une plage ; ailleurs `band_setting_unavailable`, hors plage `setting_range`.
- **Ligne de coupe :** la falaise est un front incliné dans sa largeur ; entre la plage (ou l'estran) et le fond marin, la contremarche de 1 m prend la matière de la bande haute. La surface de la mer rejoint le nœud `road/water`.
- **Éléments nouveaux** (`road_items.v1.json`) :
  - `sand_fence`, **ganivelle** : hauteur de 0,8 à 1,5 m (1,2 par défaut) ; continue ; sur une dune ou une plage seulement. Forme simple (ADR-35) : les lattes jointives sont une paroi de bois de 2 cm, de 0,05 m au-dessus du sol jusqu'en haut, avec des poteaux de 0,08 m tous les 2 m qui la dépassent de 5 cm.
  - `low_wall`, **muret** : maçonné (`road/item/stone`), 0,30 m d'épaisseur, hauteur de 0,3 à 1,2 m (0,6 par défaut) ; continu ; sur un trottoir, un chemin, un chemin empierré, un accotement, un quai ou une plage.
  - Ailleurs : `E_ROAD_ITEM`, `item_band_mismatch`, sur `/bands/<i>/items/<j>/kind`, avec les bandes permises. La liste est une clé `bands` de l'élément dans le catalogue. Falaise, estran et mer n'acceptent aucun élément (`band_accepts_no_items`).
- **Pose sur une bande en pente ou en bosse :** la position en travers suit la règle de la voirie ; le pied se pose à la cote de la coupe à cette position.
- **Matières :** `road/cliff`, `road/rocks`, `road/dune`, `road/beach`, `road/sea` (fond marin) ; la surface de la mer prend `road/water_surface`.
- **Préréglages :** côte à falaises (bande plantée, sentier à barrière, accotement, falaise de 25 m, estran de 20 m, mer de 200 m), côte à dunes (chemin, dune de 6 m à deux ganivelles, plage à 3 % et sa ganivelle, mer), plage et promenade (trottoir, promenade à lampadaires et muret, plage à 4 %, mer).
- **Rayon :** une mer de 2 000 m de large est un ruban décalé comme les autres. Du côté intérieur d'un virage, le rayon doit dépasser la largeur de ce côté de l'axe (plus 1 m), sinon le refus existant `radius_too_small` s'applique, sur le rayon. Placer l'axe côté terre (`axis` à gauche ou à droite) laisse virer librement du côté de la terre.

## Réglage `water`, dans les réglages de voie V1

Clé facultative et fermée, à côté de `ground` (`mode` obligatoire ; réglages effectifs complets : `max_grade_percent`, `lock_drop_m`, `lock_length_m` toujours, `level_m` s'il est saisi, entre −10 000 et 10 000 m). Une coupe qui porte une bande `water` ou `sea` l'exige (`E_ROAD_WATER`, `water_mode_missing`) ; une coupe sans eau la refuse (`water_without_band`).

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

Les moyennes du terrain sont prises sous la largeur de l'eau (bandes `water`), et non sous toute l'emprise : le lit se règle sur le fond de la vallée.

1. **Le tracé va de l'amont vers l'aval.** Terrain plus haut d'au moins 1 m au dernier point de pente qu'au premier : `E_ROAD_WATER`, `river_upstream`, sur `/trace`, avec la montée et le conseil d'inverser le tracé ; contrôlé dès le relevé, avant la pente et les terrassements.
2. **Enveloppe descendante :** l'altitude du niveau 0 à un point de pente est le plus bas entre la moyenne du terrain sous l'eau en ce point et l'altitude du point précédent. L'eau ne remonte donc jamais ; là où le terrain remonte, la rivière creuse, et le déblai reste borné par `RELIEF_MAX` (`E_ROAD_EARTHWORK`).
3. **Pente :** au-delà de `max_grade_percent`, `E_ROAD_GRADE` comme une voie, borne prise dans `water`, sur `/water/max_grade_percent`.

Seule la rivière suit un terrain dans cette étape : un canal ou un régime à un seul niveau sur un terrain reste refusé (`water_ground_unavailable`, avec le régime) jusqu'à AG-054 et AG-055. Comme pour une voie, une seconde voie ne se pose pas sur un terrain déjà masqué par une première (`terrain_hidden`) : limite existante d'ADR-38, vue en recette H23.

La copie entaillée du terrain (ADR-38) creuse le lit : l'eau se voit dans l'entaille ([recette H23](recette/H23.md)). Métriques : `water_drop_m` (chute totale, du premier au dernier point de pente), `grade_max_percent`, `cut_max_m`, `fill_max_m`.

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

- Une voie à eau ou à mer n'entre pas dans un réseau (`water_in_network`) tant que les ponts n'existent pas. Deux cours d'eau qui se rejoignent : hors de cette version.
- Deux racines séparées, une rue et une rivière, ne sont pas comparées entre elles : rien n'empêche de les superposer à la main.
- **Ponts (AG-057, ADR-40) :** un pont naît tout seul là où une voie d'un réseau franchit un cours d'eau, une voie ferrée ou une autre voie, comme un carrefour (ADR-36), avec un type au choix (poutre, voûte, arc) ; la voie monte et redescend par des rampes de pente bornée. Le détail viendra dans le contrat du ticket, écrit avant son code.

## Panneau (AG-056)

Dans **Composer une coupe** : les bandes d'eau et de littoral, leurs réglages, la coupe dessinée à niveaux cumulés avec le personnage et la surface de l'eau. Dans **Tracer une voie** : le régime de l'eau, ses réglages, et l'aperçu qui annonce la chute totale, le nombre d'écluses et leurs abscisses. Guide, journal, RBZ 0.8.0 et recette H23.

## Hors périmètre de cette version

Largeur variable, méandres qui s'élargissent, confluences et deltas ; courant, marées, vagues ; ports, digues et épis perpendiculaires au rivage ; berges en enrochement ; écluses à plusieurs chambres et ascenseurs à bateaux ; bateaux.
