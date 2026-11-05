# Contrat géométrique — V1

## Repères et tolérances

Origine P0 = angle avant gauche, au niveau du sol. X vers la droite, Y vers l'arrière, Z vers le haut. L'anneau CCW est (0,0), (W,0), (W,D), (0,D). Les arêtes s'appellent `front,right,rear,left` en cet ordre. Pour A→B : tangente T = (B−A)/L, verticale K, normale extérieure N = T×K. Un point de mur est A + uT + zK − dN. Mètres, radians au calcul ; le writer convertit m en pouces exactement une fois. Le placement du composant ne modifie pas le plan.

Comparaisons géométriques à 10⁻⁶ m ; canonicalisation des coordonnées à 10⁻⁶ m (arrondi demi-éloigné de zéro, −0 ramené à 0). Soumettre le plan quantifié aux vérifications. Pas d'arête émise < 0,002 m ; dégagements de conception ≥ 0,10 m, sauf contact explicitement autorisé. Quantifier les coordonnées puis dédoublonner les coordonnées égales ; refuser une largeur ou hauteur d'ouverture annulée par cette étape. Deux coupes quantifiées distinctes séparées de moins de 0,002 m déclenchent une erreur.

## Placement partagé

1. Niveaux indexés de 0 à n−1 ; `base[i]=sum(h[0...i])`, `top=base+h[i]`. H = somme des hauteurs. Dalles Structural uniquement sur les limites intermédiaires, épaisseur vers le bas. Pas de fondation ni dalle au RDC ; cette convention laisse l'entrée ouverte jusqu'à Z=0.
2. Pas P = (L−2M)/N, centre u = M + (i+0,5)P. N=0 retourne zéro candidat sans appliquer la marge. Pour N>0, exiger L>2M avant le calcul, sinon E_OPENING_CLEARANCE. La porte de la façade avant, au RDC dans `entry_bay`, **remplace** la fenêtre de cette travée. Toutes les autres positions produisent des fenêtres.
3. Si jitter > 0, décaler les centres horizontaux, hors porte, de `jitter_m * (2*unit(seed,key)-1)`. Clé `opening/<side>/<level>/<bay>/u` ASCII. `unit` : SHA-256 de `"archgen-rng-v1:" + seed.to_s + ":" + key`, prendre les 13 premiers caractères hexadécimaux comme entier, diviser par 2⁵². Aucun retentage. Tester la même entrée avec parcours inversé des façades.
4. Ouvrir [u−w/2,u+w/2] × [z,z+h], z = base+sill, sauf porte à z=0. Laisser au moins `wall_m+0,10` jusqu'aux extrémités de chaque façade ; ≥0,10 m entre ouvertures (si les projections fermées se recouvrent sur un axe, dégagement ≥0,10 m sur l'autre ; aucun contact par arête ni sommet) ; haut ≤ top−slab_m−0,10 à un niveau intermédiaire, top−0,10 au dernier. Appliquer les mêmes règles aux deux modes et refuser toute intersection de surfaces ouvertes. Aucun réajustement implicite.
5. Trier ouvertures et pièces par ordre façade/niveau/travée puis identifiant. Les ids comme `opening/front/0/1` sont locaux au plan, stables pour cette position sémantique.

## Murs, dalles, baies

Construire une grille par façade : U = {0,L} + abscisses de tous les bords d'ouvertures ; Z = {0,H} + altitudes d'étage et limites d'ouvertures. Quantifier, trier et dédoublonner les coordonnées égales ; utiliser l'intérieur de cellule pour classer vide ou plein. Les coupes doivent correspondre sur les deux faces d'un mur. Une porte crée une encoche au bord inférieur : aucun seuil muré.

- **Shell :** émettre le quad extérieur de chaque cellule pleine, normal N. Aucun quad dans le vide. Les quatre murs sont des surfaces ; ni dalles ni faces de retour.
- **Structural :** même grille, extrudée à d=t. À l'intérieur, u=0 devient t et u=L devient L−t ; les autres coupes gardent u. Les extrémités produisent des onglets partagés avec le mur voisin. Pour chaque cellule pleine, émettre quad extérieur et intérieur avec sens opposés, puis un quad latéral seulement si le voisin U/Z est absent ou vide. Cela ferme la pièce et produit jambages, linteau et appui (pas de seuil pour la porte). Chaque mur est écrit dans ses propres entités ; deux onglets partagent une interface sans chevauchement de volume.
- Dalles intermédiaires : boîte intérieure [t,W−t]×[t,D−t]×[base[i]−s,base[i]], i=1…n−1 ; une pièce par dalle. Interfaces de contact autorisées entre pièces, aucun chevauchement volumique avec les murs. La racine assemblée et le toit n'ont pas de garantie manifold.
- LOD 1 : cadre par barres simples de section 0,04 × 0,04 m, aux bords intérieurs de la baie ; pas de barre de seuil sur la porte, pas de vitrage. Utiliser une définition locale partagée par type, largeur, hauteur et matériau. Laisser le centre traversant et garder l'empreinte du percement inchangée. Recul du cadre : d₀=0 en Shell, `min(0,16, wall_m−0,04)` en Structural ; chaque barre occupe d∈[d₀,d₀+0,04]. Les montants occupent les 0,04 m à chaque extrémité de U sur toute la hauteur ; la traverse haute (et basse pour les fenêtres) occupe les 0,04 m à l'extrémité de Z, entre les montants. Les cadres ne percent ni ne modifient les murs.

## Toitures, en coordonnées locales

Soit H la tête du mur, E le débord horizontal. Rive rectangulaire élargie par E. Les pans sont des polygones plans, normales vers le haut. Pour chaque pente calculer r = tan(angle). Les angles sont convertis de degrés vers radians une seule fois par normalisation métier. Une rive qui descend sous Z=0 ou dépasse le budget est rejetée.

| Type | Construction |
|---|---|
| Plat | Quad à H, avec débord éventuel. |
| Deux pans | Faîtage parallèle à X à y=D/2, z=H+rD/2 ; prolonger aux x=−E et W+E. Rives latérales y=−E,D+E à H−rE. Ajouter deux pignons triangulaires dans les plans x=0 et W, à partir de H, normaux vers l'extérieur. |
| Croupe | Pente constante ; altitude au point de projection = H + r·distance signée au bord le plus proche du rectangle non élargi. Intersections par égalité des distances : faîtage dans l'axe du côté long, à H+r·min(W,D)/2. Carré quantifié : un sommet, quatre triangles ; sinon deux trapèzes et deux triangles. |
| Mansarde | Pans inférieurs entre rive à H−r_basE et anneau intérieur, inset I, à H+r_basI. Couronner l'anneau par une croupe à pente haute, débord nul. Vérifier que l'anneau existe et que les jonctions ont les mêmes sommets. |

Le toit est une peau dans les deux modes. Normales pignons et toiture testées séparément. Pas de comble habitable ni de rive épaissie. Altitude totale = max Z de la couverture ; calcul analytique et géométrie doivent concorder.

## Détails LOD 1 de façade

Corniche : bande avant, même longueur que le mur, profondeur 0,15 m, hauteur 0,08 m entre H−0,08 et H ; vérifier la tête des fenêtres (marge 0,10 m). Balcon : dalle décorative de 0,90 m de saillie, 0,12 m d'épaisseur, du premier au dernier axe de travée avec un demi-pas supplémentaire à chaque extrémité. Dessus à base du niveau ; niveaux d'index 2 et 5 s'ils existent. Pas de balcon si aucun de ces niveaux (avertissement). Les tests le traitent comme représentation sans garde-corps. Encadrement des fenêtres sur toutes façades percées : montants de 0,04 m juste hors de l'intervalle U, sur toute la hauteur de baie ; linteau de 0,04 m juste au-dessus, sur la largeur des deux montants compris. Toutes les barres occupent d∈[−0,03,0]. Corniche et balcon s'étendent depuis d=0 vers l'extérieur. Contacts de bord et appuis sur le mur permis ; la peau de toit peut traverser la corniche à leur raccord sans face coplanaire superposée. Interdire un détail dans un vide (sauf barres de cadre), ou deux détails à volumes recouvrants ; rendre un diagnostic LOD 1. Vérifier ce raccord sur la mansarde repère. Le LOD change les accessoires et leurs saillies, tout en gardant le volume de référence, les baies et le toit.

## GeometryPlan et writer

Contrat sérialisable : `{schema_version:1, engine_version, units:"m", nodes:[Node], definitions:{id:[Node]}, openings:[Opening], metrics:{...}}`. `Node={id, category, children, primitive?}` ; un groupe sans primitive peut contenir d'autres nœuds. Les ids de nœuds sont uniques par arbre. Un seul nœud building en tête de `nodes`. Chaque primitive porte son discriminant `type` ; les définitions de détail partagées contiennent seulement des surfaces ou des solides. Primitives :

| Type | Champs et obligations |
|---|---|
| surface | `vertices:[[x,y,z],...], faces:[{indices:[...],material:id}]` ; triangles/quads plans, ordre visible antihoraire vu de l'extérieur. |
| solid | Même structure, sommets indexés par position locale quantifiée, bord fermé : chaque arête non orientée a exactement deux incidences orientées en sens opposé ; une seule coque connexe, éventail de faces connexe à chaque sommet, volume signé positif. Vérifier absence d'auto-intersection par construction + cas adverses. |
| instance | `definition_id, matrix` ; 16 nombres en ordre colonne, transformation affine rigide directe, translation en m. Définitions immuables, sans références imbriquées en V1. |

Affectation : murs, tableaux, dalles, pignons, balcons, corniches et encadrements → `materials.wall` ; pans de toit → `materials.roof` ; cadres → `materials.frames`. Les trous sont compilés dans le noyau en faces à contour simple. Les éventuelles diagonales générées par le writer sont traitées de manière cohérente avec les matériaux. Un ajout natif qui échoue ou change le nombre d'éléments attendu déclenche l'abandon de l'opération. Le plan est indépendant de la visibilité, des tags ou de la sélection hôte.

Ordre de validation : configuration → faisabilité/compte estimé → plan → budget exact (instances comprises) → écriture → contrôles natifs. Empreinte de plan calculée sur les données canoniques triées, hors identifiants hôte. Le même plan ne dépend ni des noms ni du placement des instances.

Structure minimale pour implémenter les ports :

- `Level={index, base_z_m, top_z_m, slab_bottom_z_m}` ; `slab_bottom_z_m` vaut null au RDC, et `base_z_m−slab_m` ailleurs.
- `Candidate={facade_id, level_index, bay_index, center_u_m}`. `Opening={id, facade_id, level_index, bay_index, kind, u_min_m, u_max_m, z_min_m, z_max_m}` ; `kind=window|door`. Ces rectangles sont indépendants des cadres.
- `category` appartient à `building|walls|wall|slabs|slab|roof|roof_face|gable_end|details|frame|cornice|balcony|surround`. Racine logique `building` et groupes sans primitive ; un nœud avec primitive n’a pas d’enfant. Géométrie locale au bâtiment sauf contenu des définitions de cadres, dont l’origine est le coin bas gauche reculé de la baie. La matrice du cadre a les colonnes (T,−N,K) et la translation A+u_min·T+z_min·K−d₀·N ; la définition utilise x=u relatif, y=d relatif, z=hauteur relative.
- `metrics={width_m,depth_m,wall_top_z_m,roof_top_z_m,opening_count,unique_face_count,expanded_face_count,wall_cell_count,detail_definition_count}`. Les dimensions sont celles du rectangle de référence, hors débords. `unique_face_count` compte le plan et chaque définition une fois ; `expanded_face_count` compte le plan et chaque instanciation.
- Projection 2D : produire les bords de l’emprise, le contour de façade avant et la silhouette projetée de la couverture, puis les rectangles des ouvertures frontales (coordonnées X/Z). Fournir au panneau des coordonnées numériques, pas du SVG ou HTML injecté.
