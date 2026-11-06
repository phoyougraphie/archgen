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
{ "schema_version": 1, "xs_m": [-11.0, -9.0, 0.0, 12.0], "ys_m": [-11.0, 0.0, 9.0], "z_m": [[7.25, null, 7.3, 7.4], [7.3, 7.31, 7.4, 7.5], [7.4, 7.5, 7.6, 7.7]] }
```

- Coordonnées dans le repère du bâtiment ; `z_m[j][i]` est l'altitude du point (`xs_m[i]`, `ys_m[j]`) dans le repère du modèle ; `null` = pas de terrain.
- `xs_m` et `ys_m` croissent strictement, au pas `step_m`, et contiennent 0, W et D pour que les angles de l'emprise soient relevés. Quantification à 10⁻⁶ m.
- **Marge :** 0 pour `plinth` ; `RELIEF_MAX × embankment_ratio + step_m` pour `embankment`.
- **Budget :** au plus 3 000 points (départ), au-delà `E_SITE_BUDGET` avec le conseil d'augmenter le pas. Aucun pas n'est changé en silence.

## Assise

Soit E l'ensemble des points de la grille dans l'emprise, angles compris.

1. Tout point de E à `null`, ou tout point nécessaire au talus : `E_SITE_SURVEY` sur `/site/survey`, avec les coordonnées des premiers points manquants. Aucune altitude n'est interpolée au-dessus d'un trou.
2. **Relief :** `max(E) − min(E) ≤ 6,0 m` (départ), sinon `E_SITE_RELIEF` sur `/site/platform`.
3. **Plateforme :** `P = référence + offset_m`, quantifiée. `high` prend `max(E)` ; `mean` prend la moyenne arithmétique de E. Le niveau z=0 du bâtiment est à P.
4. **Indicateurs :** `platform_z_m`, `terrain_min_z_m`, `terrain_max_z_m`, `cut_max_m = max(0, max(E) − P)`, `fill_max_m = max(0, P − min(E))`, et les volumes `cut_volume_m3` et `fill_volume_m3` par quadrature sur les cellules.
5. L'altitude entre les points est interpolée de façon bilinéaire dans la cellule. Elle est donc approchée à l'échelle du pas : c'est une limite assumée, pas un réglage caché.

| Situation | Code | Effet |
|---|---|---|
| Terrain au-dessus du seuil de la porte de plus de 0,02 m | `E_SITE_DOOR_BURIED` sur `/site/platform` | Refus : la porte serait inutilisable |
| Seuil de la porte à plus de 0,20 m au-dessus du terrain (départ) | `W_SITE_DOOR_GAP` | Avertissement avec la hauteur : aucun escalier n'est généré |
| `cut_max_m` > 0 | `W_SITE_BURIED` | Avertissement avec la hauteur et le nombre de baies touchées |
| Pied de talus introuvable dans la marge | `E_SITE_TOE` sur `/site/embankment_ratio` | Refus localisé par façade |
| Plus de 20 000 faces d'assise, ou total hors plafonds | `E_SITE_BUDGET` | Refus avant écriture |

## Plan d'assise

`SitePlan = {schema_version:1, units:"m", nodes:[Node], metrics:{...}}`, calculé à part du `GeometryPlan` et sans y toucher, avec sa propre empreinte `site_digest`. Primitives `surface` uniquement. Catégories ajoutées : `site`, `plinth`, `platform`, `embankment`. Coordonnées locales au bâtiment, z=0 à la plateforme. Mêmes tolérances et mêmes refus de plan que le contrat géométrique.

- **`platform` :** quad à z=0, normale vers le haut. Emprise pleine en Shell, retrait de `wall_m` en Structural, pour ne pas superposer des faces au bas des murs.
- **`plinth` :** une bande par façade, dans le plan extérieur du mur, normale N, de z=0 jusqu'à `terrain − 0,05 m`. Le bord bas suit les abscisses de la grille. Aucune bande là où le terrain dépasse z=0. Les bandes de deux façades partagent les sommets de l'angle.
- **`embankment` :** là où il y a remblai, le talus part du bas du mur à z=0 avec la pente `1 / embankment_ratio` et descend jusqu'à son premier point sous le terrain, puis 0,05 m au-delà. Rayons perpendiculaires à la façade aux abscisses de la grille ; à chaque angle, trois rayons en éventail. Normales vers le haut et vers l'extérieur.

Le chevauchement de 0,05 m évite une fente visible au raccord. Le terrain restant visible aux raccords est la limite connue de ce choix.

## Relevé dans SketchUp

Faits mesurés par `test/host/terrain_spike.rb` sur 26.2.243 :

| Fait mesuré | Règle de l'adaptateur |
|---|---|
| `raytest` donne l'altitude exacte sur un terrain imbriqué et pivoté (écart 0,0 m aux sommets) | Le rayon vertical part au-dessus de la boîte du terrain |
| Le dernier élément du chemin est une `Face` ou une `Edge` | Les deux sont acceptés : seul `chemin[0]` désigne le terrain |
| Un obstacle arrête le rayon ; relancer depuis le point d'impact le fait traverser sans blocage | Si `chemin[0]` n'est pas le terrain, relancer, au plus 16 fois, puis `E_SITE_SURVEY` |
| Un trou renvoie `nil` | `null` dans la grille |
| Terrain ou tag masqué : `nil` avec `wysiwyg` vrai | `wysiwyg` reste vrai ; terrain invisible = refus, jamais de géométrie masquée |
| Une face inversée reste touchée | L'orientation du terrain est sans effet |
| 0,84 ms par rayon sur 7 200 faces | Relevé sur demande seulement, jamais à chaque frappe |

**Le terrain est désigné par l'utilisateur :** un seul `Group` ou `ComponentInstance` de niveau racine, sélectionné puis retenu dans le panneau. Pas de déduction : avec des arbres ou un autre bâtiment, deviner reviendrait à inventer une altitude. Des faces libres sont refusées, avec le conseil de les grouper. Terrain absent ou trop petit : `E_SITE_TERRAIN`.

## Écriture et persistance

- **Transaction :** une action = une opération « ARCHGEN : adapter au terrain ». Le relevé est refait avant d'écrire ; si son empreinte diffère de celle de l'aperçu, `E_TARGET_STALE` avec `terrain_changed`.
- **Définition :** fraîche comme toute régénération, avec le plan du bâtiment et le plan d'assise. Nouveau tag « ARCHGEN Terrassement » sur les conteneurs d'assise.
- **Placement :** seul le Z de la racine change, pour valoir P ; X, Y et la rotation restent. C'est la seule exception à « la transformation est conservée ». Refus `E_SITE_TRANSFORM` si la racine n'est pas horizontale : une rotation hors de l'axe Z rendrait la grille fausse.
- **Attributs :** dictionnaire séparé `archgen.site` sur la racine : `site_version`, `site_json`, `survey_digest`, `site_digest`, `terrain_pid`, `placement_xy_m`. La grille n'est pas conservée : elle dépasserait 64 Kio. Ces attributs entrent dans le relevé d'intégrité de `TransactionGuard` et dans la relecture finale.
- **Assise périmée :** ni observateur de terrain ni relevé automatique. Le panneau compare le placement enregistré à l'actuel et propose « Relever de nouveau ». Un terrain modifié n'est vu qu'au relevé suivant, et cette limite est écrite dans le guide.
- **Retirer l'assise :** action explicite, nouvelle définition sans assise, dictionnaire retiré, Z inchangé.
- **Copies :** la copie garde sa définition et son assise jusqu'à sa propre adaptation, comme toute régénération.

Un bâtiment écrit par un moteur antérieur reste valable sans `archgen.site`. Un `site_version` plus récent : consultable, non régénérable, `E_VERSION`.

## Panneau

Section « Terrain » en mode édition seulement. Elle contient : « Retenir ce terrain », politique de plateforme, décalage, type de terrassement, pente, matériau, pas, puis « Relever ». L'aperçu s'ajoute à celui du bâtiment : altitude de plateforme, déblai et remblai maximaux, volumes, avertissements. La confirmation liste ces valeurs avant Remplacer. Un relevé ne laisse aucune trace dans le modèle ni dans l'Annuler.

## Hors périmètre

Découpe ou remodelage du terrain (option B de D-05), escaliers et rampes, murs de soutènement, plateforme débordant de l'emprise, étagement par parcelle (AG-027, avec EXT-07), import de terrain (EXT-09), calcul géotechnique.
