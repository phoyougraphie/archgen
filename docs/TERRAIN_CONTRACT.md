# Contrat terrain et assise — EXT-10

Contrat de la version 0.2. Il complète [le contrat géométrique](GEOMETRY_CONTRACT.md) et [la régénération](REGENERATION.md) sans modifier le plan d'un bâtiment : **à configuration égale, `plan_digest` reste identique**, et un bâtiment sans assise se comporte comme en V0.1. Décisions : ADR-27 et ADR-28. Les valeurs marquées « départ » sont à calibrer à la recette, par une décision écrite. Le besoin d'origine est dans [RUE_ILOT_TERRAIN](RUE_ILOT_TERRAIN.md).

## Principes

- **Le terrain n'est jamais modifié.** ARCHGEN ajoute un soubassement, un plancher et éventuellement un talus dans la définition du bâtiment. Un Annuler ne concerne donc que le bâtiment.
- **Conséquence :** un déblai ne peut pas être montré, car le terrain ne se creuse pas. Il est calculé et annoncé, et le terrain traverse le bâtiment s'il dépasse la plateforme. D'où la politique par défaut : plateforme au point haut.
- **Un geste en deux temps :** le bâtiment est créé puis déplacé comme en V0.1, et l'assise s'applique ensuite à la racine sélectionnée. Aucun outil de placement n'est ajouté.
- **Noyau pur :** il reçoit une grille d'altitudes en mètres et ne connaît pas SketchUp. Seul l'adaptateur lance les rayons et écrit.
- **Pas d'étude géotechnique :** l'assise est une représentation.

## Réglages `site` V1

Format séparé de la configuration du bâtiment, qui reste en V1 fermée. Clés inconnues refusées, comme pour tout JSON d'entrée.

| Champ | Valeurs | Défaut (départ) | Sens |
|---|---|---|---|
| `site_version` | 1 | 1 | Version du format |
| `platform.policy` | `high`, `mean` | `high` | Altitude de référence sous l'emprise |
| `platform.offset_m` | [−2, 2] | 0 | Décalage explicite ajouté à la référence |
| `earthwork` | `plinth`, `embankment` | `plinth` | Soubassement seul, ou soubassement remplacé par un talus là où il y a remblai |
| `embankment_ratio` | [1, 3] | 1,5 | Horizontal pour 1 vertical ; 0 interdit |
| `plinth_material` | Identifiant du catalogue | `concrete` | Soubassement et plancher |
| `survey.step_m` | [0,5 ; 5] | 2 | Pas de la grille de relevé |

Le talus utilise `earth`, d'un catalogue séparé `site_materials.v1.json` : `materials.v1.json` et sa révision ne changent pas, et les matériaux existants d'un modèle restent réutilisés.

## Grille de relevé

```json
{ "schema_version": 1, "xs_m": [0.0, 6.0, 12.0], "ys_m": [0.0, 4.5, 9.0], "z_m": [[7.25, null, 7.3], [7.3, 7.31, 7.4], [7.4, 7.5, 7.6]] }
```

- Coordonnées dans le repère du bâtiment ; `z_m[j][i]` est l'altitude du point (`xs_m[i]`, `ys_m[j]`) dans le repère du modèle ; `null` = pas de terrain.
- **Axes imposés :** sur [0, L], `n = ⌈L / step_m⌉` intervalles égaux, donc un pas au plus égal à `step_m`, 0 et L étant toujours relevés, sans petit intervalle au bout. Hors de l'emprise, des points au pas `step_m` jusqu'à couvrir la marge. Le noyau calcule ces axes (`SurveyGrid.plan`) ; l'adaptateur les reçoit, et une grille aux axes différents est refusée. Quantification à 10⁻⁶ m.
- **Marge :** 0 pour `plinth` ; `(RELIEF_MAX + |offset_m|) × embankment_ratio + step_m` pour `embankment`, le décalage pouvant ajouter du remblai.
- **Budget :** au plus 3 000 points (départ), au-delà `E_SITE_BUDGET` avec le conseil d'augmenter le pas, avant tout relevé. Aucun pas n'est changé en silence.

## Assise

Soit E l'ensemble des points de la grille dans l'emprise, angles compris.

1. Tout point de E à `null` : `E_SITE_SURVEY` sur `/site/survey`, avec le nombre de points manquants et les coordonnées des dix premiers. Aucune altitude n'est interpolée au-dessus d'un trou. Un trou rencontré par un rayon de talus relève du même code, avec les coordonnées du point ; un trou au-delà du pied n'est pas utile et n'est pas refusé.
2. **Relief :** `max(E) − min(E) ≤ 6,0 m` (départ), sinon `E_SITE_RELIEF` sur `/site/platform`.
3. **Plateforme :** `P = référence + offset_m`, quantifiée. `high` prend `max(E)` ; `mean` prend la moyenne arithmétique de E. Le niveau z=0 du bâtiment est à P.
4. **Indicateurs :** `platform_z_m`, `terrain_min_z_m`, `terrain_max_z_m`, `relief_m`, `cut_max_m = max(0, max(E) − P)`, `fill_max_m = max(0, P − min(E))`, et les volumes `cut_volume_m3` et `fill_volume_m3` : pour chaque cellule de l'emprise, aire × moyenne des hauteurs positives aux quatre angles. C'est exact sur un plan entièrement d'un côté de P, approché sinon.
5. L'altitude entre les points est interpolée de façon bilinéaire dans la cellule. Elle est donc approchée à l'échelle du pas : c'est une limite assumée, pas un réglage caché.

| Situation | Code | Effet |
|---|---|---|
| Terrain au-dessus du seuil de la porte de plus de 0,02 m, relevé aux deux bords et au milieu de la porte | `E_SITE_DOOR_BURIED` sur `/site/platform` | Refus : la porte serait inutilisable |
| Seuil de la porte à plus de 0,20 m au-dessus du terrain, au milieu de la porte (départ) | `W_SITE_DOOR_GAP` | Avertissement avec la hauteur : aucun escalier n'est généré |
| `cut_max_m` > 0 | `W_SITE_BURIED` | Avertissement avec la hauteur et le nombre de baies dont le bas est sous le terrain, relevé aux deux bords et au milieu de chaque baie, dans le plan de sa façade |
| Pied de talus introuvable dans la marge | `E_SITE_TOE` sur `/site/embankment_ratio` | Refus localisé par façade, sans altitude extrapolée |
| Plus de 20 000 faces d'assise, ou total hors plafonds | `E_SITE_BUDGET` | Refus avant écriture |

## Plan d'assise

`SitePlan = {schema_version:1, units:"m", nodes:[Node], metrics:{...}}`, calculé à part du `GeometryPlan` et sans y toucher, avec sa propre empreinte `site_digest`. Primitives `surface` uniquement. Catégories ajoutées : `site`, `plinth`, `platform`, `embankment`. Les métriques reprennent les indicateurs d'assise et ajoutent `site_face_count`, `door_gap_m` (null sans porte) et `buried_opening_count`. Coordonnées locales au bâtiment, z=0 à la plateforme. Mêmes tolérances et mêmes refus de plan que le contrat géométrique.

- **`platform` :** quad à z=0, normale vers le haut. Emprise pleine en Shell, retrait de `wall_m` en Structural, pour ne pas superposer des faces au bas des murs.
- **`plinth` :** une bande par façade, dans le plan extérieur du mur, normale N, de z=0 jusqu'à `terrain − 0,05 m`. Le bord bas suit les abscisses de la grille. Aucune bande là où `terrain − 0,05 m` atteint z=0 : la bande s'arrête par un triangle au point de passage. Un bord bas à moins de 2 mm de z=0 compte pour z=0, et un triangle réduit à moins de 2 mm est omis, car ces arêtes seraient refusées par le validateur. Les bandes de deux façades partagent les sommets de l'angle.
- **`embankment` :** remplace entièrement les bandes de soubassement. Là où il y a remblai, le talus part du bas du mur à z=0 avec la pente `1 / embankment_ratio` et descend jusqu'à son premier point sous le terrain, puis encore 0,05 m en altitude. Rayons perpendiculaires à la façade aux abscisses de la grille ; à chaque angle, trois rayons en éventail à 22,5°, 45° et 67,5°. Le pied est cherché par pas de `step_m / 4`, puis affiné. Un rayon dont l'origine est au niveau du terrain ou dessous n'a pas de longueur. Faces triangulées, car le terrain est quelconque ; normales vers le haut et vers l'extérieur. La métrique `embankment_reach_m` donne la plus grande emprise du talus au sol.

Le chevauchement de 0,05 m évite une fente visible au raccord. Le terrain restant visible aux raccords est la limite connue de ce choix.

## Relevé dans SketchUp

Faits mesurés par `test/host/terrain_spike.rb` sur 26.2.243 :

| Fait mesuré | Règle de l'adaptateur |
|---|---|
| `raytest` donne l'altitude exacte sur un terrain imbriqué et pivoté (écart 0,0 m aux sommets) | Le rayon vertical part 1 m au-dessus de la boîte du terrain : ce qui est plus haut ne compte pas |
| Le dernier élément du chemin est une `Face` ou une `Edge` | Les deux sont acceptés : seul `chemin[0]` désigne le terrain |
| Un obstacle arrête le rayon ; relancer depuis le point d'impact le fait traverser sans blocage | Si `chemin[0]` n'est pas le terrain, relancer, au plus 64 fois, puis `E_SITE_SURVEY` avec `too_many_obstacles` : un bâtiment Structural de 15 niveaux compte déjà une trentaine de faces sur un rayon |
| Un trou renvoie `nil` | `null` dans la grille |
| Terrain ou tag masqué : `nil` avec `wysiwyg` vrai | `wysiwyg` reste vrai ; terrain invisible = refus, jamais de géométrie masquée |
| Une face inversée reste touchée | L'orientation du terrain est sans effet |
| Sur un soubassement déjà écrit, un nœud situé sur une arête verticale de bande ne renvoyait plus d'altitude (H13). Le décalage fait disparaître le défaut ; l'explication, un rayon filant le long de l'arête, est déduite et n'a pas été isolée | Chaque rayon est décalé de 0,2 mm en X et en Y dans le repère de la racine ; l'altitude lue reste juste à moins de 1 mm tant que le terrain ne dépasse pas une pente de 100 % |
| Une face du bâtiment à l'altitude exacte du terrain arrête le rayon, qui repart sous le terrain et ne le voit plus (H18 : une dalle sur une pente, en un seul nœud). À 1 mm de là, le terrain est retrouvé | Un rayon sans terrain, après un obstacle traversé, est relancé à 1 mm puis à 5 mm du nœud. Sans obstacle, c'est un vrai trou et il n'y a pas de relance. L'altitude lue reste juste à moins de 5 mm tant que le terrain ne dépasse pas une pente de 100 % |
| 0,84 ms par rayon sur 7 200 faces | Relevé sur demande seulement, jamais à chaque frappe |

**Le terrain est désigné par l'utilisateur :** un seul `Group` ou `ComponentInstance` de niveau racine, sélectionné puis retenu dans le panneau. Pas de déduction : avec des arbres ou un autre bâtiment, deviner reviendrait à inventer une altitude. Des faces libres sont refusées, avec le conseil de les grouper. Un bâtiment ARCHGEN, une entité imbriquée ou masquée sont refusés aussi. Terrain absent ou d'un autre document : `E_SITE_TERRAIN` sur `/site/terrain`. Terrain trop petit : ses nœuds sont à `null`, donc `E_SITE_SURVEY`. Rien n'est écrit sur le terrain : la référence retenue vit dans la session, et sa persistance relève de l'écriture de l'assise.

## Écriture et persistance

- **Transaction :** une action = une opération « ARCHGEN : adapter au terrain ». Le relevé est refait avant d'écrire ; si son empreinte diffère de celle de l'aperçu, `E_TARGET_STALE` avec `terrain_changed`.
- **Définition :** fraîche comme toute régénération, avec le plan du bâtiment et le plan d'assise. Nouveau tag « ARCHGEN Terrassement » sur les conteneurs d'assise.
- **Placement :** seul le Z de la racine change, pour valoir P ; X, Y et la rotation restent. C'est la seule exception à « la transformation est conservée ». Refus `E_SITE_TRANSFORM` sur `/site/placement`, dès le relevé, si la racine n'est pas horizontale : une rotation hors de l'axe Z rendrait la grille fausse.
- **Attributs :** dictionnaire séparé `archgen.site` sur la racine : `site_version`, `site_json`, `survey_digest`, `site_digest`, `terrain_pid`, `placement_json` (X et Y en mètres, puis l'axe X de la racine en plan, pour repérer aussi une rotation). La grille n'est pas conservée : elle dépasserait 64 Kio. Ces attributs entrent dans le relevé d'intégrité de `TransactionGuard` et dans la relecture finale.
- **Assise périmée :** ni observateur de terrain ni relevé automatique. Le panneau compare le placement enregistré à l'actuel et propose « Relever de nouveau ». Un terrain modifié n'est vu qu'au relevé suivant, et cette limite est écrite dans le guide.
- **Régénérer une racine qui a une assise :** elle la garde (ADR-29). Le terrain enregistré est relevé de nouveau à l'emplacement actuel, pour la nouvelle emprise, et le Z suit la nouvelle plateforme, le tout dans la même opération. Terrain disparu, masqué ou relief devenu trop fort : refus localisé. L'assise n'est jamais retirée en silence.
- **Retirer l'assise :** action explicite, nouvelle définition sans assise, dictionnaire retiré, Z inchangé.
- **Copies :** la copie garde sa définition et son assise jusqu'à sa propre écriture. Elle est alors relevée à son propre emplacement, sans toucher à l'original.

Un bâtiment écrit par un moteur antérieur reste valable sans `archgen.site`. Un `site_version` plus récent : consultable, non régénérable, `E_VERSION`.

## Panneau

Section « Terrain » en mode édition seulement. Elle contient : « Retenir ce terrain », politique de plateforme, décalage, type de terrassement, pente, matériau, pas, puis « Relever », « Adapter au terrain » et « Retirer l'assise ». Sélectionner le terrain périme la cible : il faut ensuite resélectionner le bâtiment et recharger, le jeton de terrain restant valable. Enregistrer périme ce jeton, mais une racine déjà adaptée garde son terrain. L'adaptation part de la configuration enregistrée : un brouillon non régénéré ne s'y applique pas. L'aperçu s'ajoute à celui du bâtiment : altitude de plateforme, déblai et remblai maximaux, volumes, avertissements. La confirmation liste ces valeurs avant Remplacer. Un relevé ne laisse aucune trace dans le modèle ni dans l'Annuler.

## Étagement d'un ensemble (AG-027)

Chaque parcelle d'un ensemble a sa propre plateforme : le long d'une rue en pente, les bâtiments s'étagent, et le soubassement traite le raccord. Décision : ADR-33. **Le plan d'ensemble et `ensemble_digest` ne changent pas :** l'étagement est calculé à part, comme l'assise d'un bâtiment.

**Geste.** En deux temps, comme pour un bâtiment : l'ensemble est créé, puis adapté. Dans le panneau « Modifier l'ensemble sélectionné », une section Terrain donne « Retenir ce terrain », politique, décalage, matériau et pas, puis « Relever », « Adapter au terrain » et « Retirer l'assise ». Retenir un terrain ne perd pas ce jeton quand on resélectionne l'ensemble.

**Réglages.** Le format `site` V1, inchangé. `earthwork: "embankment"` est refusé, `E_STREET_SITE` sur `/site/earthwork` : un talus déborderait chez le voisin, et aucun autre terrassement ne lui est substitué.

**Relevé.** Une grille par parcelle, dans le repère de la parcelle, sur la boîte `x ∈ [min(0, δg), max(W, W − δd)]`, `y ∈ [0, D]`, avec les axes de `SurveyGrid`. Plafond de 12 000 points pour tout l'ensemble (départ) : `E_SITE_BUDGET` sur `/site/survey/step_m`, avant tout rayon. Le trapèze ne remplit pas toujours sa boîte : E vaut alors les nœuds dans le trapèze, plus l'altitude interpolée aux stations de ses quatre bords, au pas au plus égal à `step_m`.

- Un nœud manquant sur une cellule qui touche le trapèze : `E_SITE_SURVEY`. Un nœud manquant hors de ces cellules ne sert pas et n'est pas refusé.
- Les volumes prennent l'aire de la cellule à l'intérieur du trapèze.
- **Rectangle et trapèze suivent la même règle.** Sur un rectangle, le résultat est celui d'un bâtiment seul de mêmes dimensions.

**Plateforme et limites.** Assise, relief, porte et baies enterrées : mêmes règles et mêmes codes qu'un bâtiment seul, par parcelle, sur `/parcels/<id>/site/…`. Un refus sur une parcelle refuse tout l'ensemble, sans rien écrire.

| Situation | Code | Effet |
|---|---|---|
| Terrain au-dessus du sol du passage de plus de 0,02 m, relevé aux deux bords et au milieu, en façade et à l'arrière | `E_SITE_DOOR_BURIED`, raison `passage_buried` | Refus : le porche serait inutilisable |
| Sol du passage à plus de 0,20 m au-dessus du terrain, en façade ou à l'arrière | `W_SITE_DOOR_GAP` | Avertissement avec la hauteur : aucune rampe n'est générée |
| Écart de plateforme entre deux voisines | Aucun | Métrique `max_step_m` : le mur mitoyen, toujours émis (ADR-32), ferme le ressaut |

**Raccord.** Les bandes de soubassement des quatre côtés de chaque parcelle suivent le terrain. Le côté de la parcelle haute descend donc jusqu'au terrain le long de sa voisine, ce qui ferme la marche. Deux bandes mitoyennes se touchent dans le même plan, comme deux murs mitoyens. Un bord en biais a ses stations à intervalles égaux, au plus `step_m`. En Structural, le plancher suit le trapèze intérieur des murs ; un passage de porche reçoit en plus un plancher entre le trapèze intérieur et ses deux bords.

**Plan.** `EnsembleSitePlan = {schema_version:1, units:"m", definitions:{id:{schema_version, units, nodes, metrics:{site_face_count}}}, parcels:[{id, site_definition_id, level_m, platform_z_m, terrain_min_z_m, terrain_max_z_m, cut_max_m, fill_max_m, door_gap_m, buried_opening_count}], metrics}`, d'empreinte `ensemble_site_digest`.

- `level_m = platform_z_m − Z de la racine`, quantifié. Le Z de la racine appartient à l'entrée du calcul.
- **Partage :** deux parcelles de mêmes nœuds partagent leur définition d'assise, sinon non. Les bâtiments gardent leur partage : **la pente ne multiplie pas la géométrie des bâtiments.**
- **Métriques :** `parcel_count`, `site_definition_count`, `unique_site_face_count`, `expanded_site_face_count`, `survey_point_count`, `platform_min_z_m`, `platform_max_z_m`, `max_step_m` (entre voisines d'une même rangée), `cut_max_m`, `fill_max_m`, `cut_volume_m3`, `fill_volume_m3`, `buried_opening_count`.
- **Plafonds :** plus de 20 000 faces pour une parcelle, ou faces uniques et étendues au-delà des plafonds d'ensemble, bâtiments compris : `E_SITE_BUDGET` sur `/site/survey/step_m`.

**Écriture.** Une opération « ARCHGEN : adapter au terrain », dans une définition d'ensemble fraîche, relevé refait avant d'écrire : si `ensemble_site_digest` diffère de celui de l'aperçu, `E_TARGET_STALE` avec `terrain_changed`.

- **Racine :** elle ne bouge pas, en Z non plus. Les parcelles portent l'étagement : chaque instance reçoit `level_m` dans sa translation.
- **Assise :** une seconde instance par parcelle, nommée `<id>/assise`, de même matrice, tag « ARCHGEN Terrassement ». Un bâtiment partagé reste donc partagé.
- **Attributs :** `archgen.site` sur la racine, mêmes clés. `site_digest` y porte `ensemble_site_digest` et `survey_digest` l'empreinte des grilles ; `placement_json` ajoute le Z de la racine, qui décide de l'étagement.
- **Remplacer :** une racine avec assise la garde (ADR-29) ; son terrain est relevé de nouveau dans la même opération, ou refus localisé.
- **Retirer l'assise :** action explicite, parcelles ramenées à z = 0, dictionnaire retiré, racine immobile.
- **Copie :** elle garde sa définition jusqu'à sa propre écriture, puis est relevée à son emplacement.
- **Périmée :** le panneau compare le placement enregistré à l'actuel et propose de relever. Pas d'observateur de terrain.

**Charge.** Un rayon traverse tout ce qui est au-dessus du terrain. Le panneau annonce le nombre de points relevés et la barre d'état suit les parcelles. Les temps sont mesurés en H18.

**Hors périmètre.** Talus et murs de soutènement entre parcelles, escaliers et rampes d'accès, plateforme commune à plusieurs parcelles, marches de hauteur imposée, suivi de la pente par le faîtage d'un même bâtiment.

## Hors périmètre

Découpe ou remodelage du terrain (option B de D-05), escaliers et rampes, murs de soutènement, plateforme débordant de l'emprise, import de terrain (EXT-09), calcul géotechnique.
