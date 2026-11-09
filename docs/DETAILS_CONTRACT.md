# Contrat des détails de bâtiment et de la personnalisation d'une parcelle — J11 (AG-064 à AG-069)

Contrat de départ, écrit avant le code. Décisions D-17 à D-22 tranchées par le propriétaire (options A, ADR-45). Il touche EXT-01 (richesse des façades et des toits) et EXT-08 (mixité d'une rue). Les valeurs marquées « départ » sont à calibrer à la recette.

**Besoin du propriétaire (2026-11-08).** Poser des portes et des fenêtres ; personnaliser un bâtiment d'une rue par un clic droit (nombre d'étages, largeur, toiture…) ; transformer des rez-de-chaussée en commerces ; mettre des cheminées sur les toits.

## Ce qui existe

- **Baies.** Chaque bâtiment a déjà ses fenêtres et sa porte d'entrée (façade avant, rez-de-chaussée, travée `entry_bay`), percées dans les murs. Au LOD 1, un **cadre** de barres de 0,04 × 0,04 m borde chaque baie ([contrat géométrique](GEOMETRY_CONTRACT.md)). Il n'y a **ni vitre, ni porte pleine** : la baie reste traversante.
- **Options.** `features` ne connaît que `cornice`, `balcony` et `surrounds`. Trois rôles de matière : `wall`, `roof`, `frames`.
- **Rue.** Toutes les parcelles d'un ensemble partagent les réglages du bâtiment ; seule la variété tire niveaux et toit par parcelle ([rues variées](RUE_VARIEE_CONTRACT.md)). Le contrat d'ensemble **refuse** aujourd'hui toute action sur une parcelle sélectionnée à l'intérieur de l'ensemble ; la modification d'une seule parcelle avait été reportée (EXT-07).

## Règle commune de format

Comme ADR-41 et la variété : **chaque nouveau réglage est une clé facultative, sans changement de version de format.** Absente, elle vaut « désactivé », et la configuration effective canonique ne l'écrit pas. Un bâtiment, une rue ou un îlot existants gardent donc leur plan et leur empreinte, et leur JSON enregistré reste valide tel quel. Chaque ticket le prouve sur les fixtures et les ensembles types d'avant (mêmes empreintes).

## 1. Menuiseries et vitrage — AG-064 (D-17)

Option `features.glazing` (booléen), émise au **LOD 1** seulement, comme les cadres ; ignorée au LOD 0 mais conservée dans les réglages.

| Élément | Géométrie (départ) |
|---|---|
| **Vitre** de fenêtre | Une plaque de 0,01 m, dans le jour du cadre (u de 0,04 à W − 0,04, z de 0,04 à H − 0,04), au milieu de la profondeur du cadre (y de 0,015 à 0,025 dans la définition du cadre) ; matière `materials.glass`. Une plaque plutôt qu'une face seule : solide fermé comme les barres, même validation |
| **Porte pleine** | Un vantail de 0,03 m (y de 0,005 à 0,035), dans le jour du cadre, de z = 0 à H − 0,04 ; matière `materials.frames` |
| **Imposte** (porte de plus de 2,40 m) | Traverse de 0,04 m de 2,20 à 2,24 m ; vitre au-dessus, vantail au-dessous |

- **Matière `glass`** : un quatrième rôle de matière, `materials.glass`, à clés d'un catalogue fermé, nouvelle révision du catalogue de matières (verre légèrement teinté, translucide). Un bâtiment sans vitrage n'a pas ce rôle.
- **Définitions partagées** : vitre, vantail et imposte vivent dans la définition du cadre, dont l'identifiant prend `/glazed/<verre>` ; sans vitrage, identifiant et contenu sont ceux d'avant. Catégorie `frame` (calque Menuiseries).
- **Résolution** : coché, `features.glazing` prend la matière `glass` du catalogue si le style n'en donne pas ; décoché, ni `glazing` ni `materials.glass` ne sont écrits. Une configuration enregistrée qui les dépareille est refusée (`glass_required`, `glass_without_glazing`, `glazing_false_written`).
- **Révisions (fait, AG-064)** : Haussmannien, Toulousain et Brutaliste ont une révision 2, vitrée, qui requiert la capacité `glazing`. Le panneau ne propose que la dernière révision de chaque style ; la révision 1 reste lisible. **Une rue ou un îlot fige la révision de son style à la création** ; un ensemble enregistré sans révision (d'avant AG-064) est relu en révision 1, et garde la sienne quand on le modifie sans changer de style (ADR-46).
- **D-17, options.** **A, retenue (ADR-45)** : vitre et porte pleine seulement (peu de faces, lisible en maquette ; les petits bois et volets restent pour EXT-01). **B** : ajouter dès maintenant des petits bois selon le style (Haussmannien : trois carreaux par vantail), plus de faces et un réglage de plus. **Défaut :** une nouvelle révision de chaque profil publié active le vitrage ; un bâtiment existant garde sa révision, donc rien ne change chez lui tant qu'on ne coche pas la case.
- **Tests U44** (`test/unit/glazing_test.rb`) : vitre dans le jour, vantail, imposte, comptes de faces, refus, LOD 0, trois styles dans les deux modes, rue vitrée et rue en révision 1 ; révision figée au contrôleur de rue. Empreintes des profils en révision 1 et de quatre ensembles types identiques avant et après. **Fait (AG-064)** : vu dans SketchUp ([image](recette/img/ag064-vitrage.jpg)), sonde `test/host/ag064.rb` 13/13.

## 2. Rez-de-chaussée commerçant — AG-065 (D-18, D-19)

Réglage `ground_floor` du bâtiment : `"dwelling"` (défaut, absent) ou `"shop"`, avec `shop.height_m` (hauteur du rez-de-chaussée, [3,2 ; 6], départ 4,0 m ; Haussmannien 4,5 m).

| Élément | Géométrie (départ) |
|---|---|
| **Hauteur** | Le rez-de-chaussée prend `shop.height_m` ; les étages gardent leur hauteur. Si `levels.heights_m` est saisi, il prime et `shop.height_m` est refusé (`shop_with_heights`) |
| **Vitrines** | Toutes les travées de la façade avant au rez-de-chaussée, sauf `entry_bay`, deviennent des baies `kind = shopfront` : centrées sur la trame, sans variation des baies ; largeur = pas de travée − 2 × 0,30 m (trumeau de 0,30 m de chaque côté), 1,20 m au moins ; de z = 0,15 m (soubassement) à hauteur du rez-de-chaussée − 0,60 m. Cadre de barres comme une fenêtre, traverse basse comprise |
| **Entrée de l'immeuble** | La travée `entry_bay` garde la porte de l'immeuble |
| **Bandeau d'enseigne** | Bande en saillie de 0,10 m, de 0,40 m de haut (de rez-de-chaussée − 0,50 à − 0,10 m), d'une marge à l'autre, coupée à l'onglet sur une parcelle d'angle comme les balcons ; sans texte ; matière `materials.frames` ; LOD 1, catégorie `fascia`. S'il passait devant la porte de l'immeuble ou le passage du porche, refus `fascia_over_entrance` sur `/shop/height_m` |
| **Vitrage** | Avec `features.glazing`, chaque vitrine reçoit une vitre fixe ; une porte vitrée de 0,90 m prend le bord de la vitrine le plus proche de l'entrée de l'immeuble (porte ou passage), séparée par un montant de 0,04 m. L'identifiant de définition prend `/door-left` ou `/door-right` |

- Dégagements du contrat géométrique appliqués aux vitrines ; une travée trop étroite pour une vitrine de 1,20 m est refusée (`E_OPENING_CLEARANCE`, `shopfront_too_narrow`, sur `/facade/front_bays`, dans une rue `/parcels/<id>/facade/front_bays`), jamais rétrécie en silence.
- Porche d'îlot : une parcelle à porche garde son passage ; une vitrine qu'il recouvre s'arrête à 0,10 m du passage, du côté de son milieu, si elle garde 1,20 m ; sinon elle est retirée, comme une baie d'aujourd'hui.
- **Résolution** : `"dwelling"` n'est pas écrit, ni `shop`. En commerce, la hauteur vient du brouillon, sinon de `defaults.shop.height_m` du style (Haussmannien révision 2 : 4,5 m ; la révision 2 n'était pas encore publiée), sinon 4,0 m. Des `levels.heights_m` saisis priment : `shop` n'est pas écrit, le premier niveau doit faire 3,2 m au moins (`shop_ground_too_low`), et une hauteur de commerce donnée avec eux est refusée (`shop_with_heights`). Refus d'une configuration enregistrée dépareillée : `shop_without_ground_floor`, `shop_height_required`. Un changement de style garde `ground_floor` ; la hauteur repart du nouveau style.
- Corniche et balcons inchangés ; le premier balcon (niveau d'index 2) monte avec le rez-de-chaussée plus haut.
- **D-18, options.** **A, retenue (ADR-45)** : une vitrine par travée, entre trumeaux maçonnés (suit la trame, se combine avec la variation des baies). **B** : une devanture continue en applique (bois), d'une marge à l'autre, plus parisienne mais hors trame.
- **D-19, dans une rue.** **A, retenue (ADR-45)** : commerces sur toute la rue (case du panneau de rue), puis bâtiment par bâtiment au clic droit. **B** : en plus, une proportion tirée par parcelle (par exemple 60 %), comme la variété.
- **Tests U45** (`test/unit/shop_test.rb`) : résolution et refus, hauteur du rez-de-chaussée, vitrines sur la trame sans variation, travée trop étroite refusée, bandeau et son refus, vitrine vitrée et porte côté entrée, balcon relevé, trois styles dans les deux modes, rue entière en commerce, vitrines arrêtées au porche. Empreintes de quatre ensembles types identiques avant et après. **Fait (AG-065)** : vu dans SketchUp ([image](recette/img/ag065-commerce.jpg)), sonde `test/host/ag065.rb` 9/9.

## 3. Cheminées — AG-066 (D-20)

Option `features.chimneys` (booléen), LOD 1.

- **Souche** : parallélépipède de 0,60 × 0,45 m (départ), adossé à l'intérieur d'un mur latéral (à 0,10 m de sa face intérieure), centré sur le faîtage pour un toit à deux pans ou une mansarde. Le haut dépasse le faîtage de 0,60 m ; sur un toit plat, il dépasse la toiture de 1,00 m. Un **couronnement** de 0,05 m déborde de 0,05 m. Matière `materials.wall`.
- **Nombre** : 1 ou 2 souches par bâtiment (une contre chaque mur latéral), tiré par `unit(seed, "chimneys")` (< 0,5 : une) ; une souche seule prend le côté gauche ou droit tiré par `unit(seed, "chimneys/side")`. Une parcelle d'angle ou un bâtiment seul suit la même règle ; sur une parcelle d'angle, la souche reste à 0,10 m du mur biais sur toute sa profondeur. La seed devient géométrique : deux parcelles ne partagent plus leur plan quand les cheminées sont cochées.
- **Assise** : la souche part du haut des murs (z = H) et traverse la peau du toit sans la percer, comme la peau du toit traverse déjà la corniche. Elle ne déborde jamais chez le voisin.
- **Croupe** : il n'y a pas de faîtage sur toute la longueur ; souche centrée sur le bout du faîtage. Même règle pour la mansarde d'un bâtiment seul, dont le haut est une croupe ; une mansarde de rangée a des pignons et suit la règle des murs latéraux. Un toit carré n'a qu'un sommet : une seule souche.
- **Résolution** : décochée, l'option n'est pas écrite ; `chimneys: false` enregistré est refusé (`chimneys_false_written`). Couronnement de z = haut − 0,05 au haut ; catégorie `chimney`. Sur un toit plat, la face basse de la souche est confondue avec le toit et cachée.
- **D-20, options.** **A, retenue (ADR-45)** : souches contre les murs latéraux, sur tous les types de toit (réaliste en rangée, où les souches mitoyennes se groupent par deux, et simple). **B** : souches seulement sur les toits en pente ; un toit plat n'en a pas, avec un avertissement `W_DETAIL`.
- **Tests U46** (`test/unit/chimney_test.rb`) : option non écrite, refus ; deux pans (position, faîtage + 0,60, couronnement, matière) ; tirage stable ; toit plat + 1,00 ; croupe, carré, mansarde ; LOD 0, deux modes ; rue : souches dans chaque parcelle, une ou deux selon la seed. Empreintes de quatre ensembles types identiques. **Fait (AG-066)** ; contrôle dans SketchUp laissé au propriétaire.

## 4. Personnaliser une parcelle — AG-068 et AG-069 (D-21, D-22)

### Format, AG-068

Clé facultative `parcels` du format `ensemble` V1 : une table `id de parcelle → réglages propres`.

```json
{ "parcels": { "front/0/2": { "levels": 7, "roof": "mansard", "ground_floor": "shop",
                              "chimneys": true, "width_m": 15 } } }
```

| Champ | Sens |
|---|---|
| `levels` | Nombre de niveaux de cette parcelle, [1 ; 15] |
| `roof` | `flat`, `gable` ou `mansard` (`hip` refusé en rangée) |
| `ground_floor`, `shop.height_m` | Commerce ou logement, comme au bâtiment |
| `chimneys`, `glazing` | Les options du bâtiment, pour cette parcelle |
| `width_m` | Largeur de façade de cette parcelle (D-21) |

- **Priorité** : réglages de l'ensemble, puis tirage de variété, puis réglages propres de la parcelle. Le tirage des parcelles suivantes ne change pas : une parcelle personnalisée ne déplace pas le reste de la rue. Son écart avec ses voisines n'est pas contrôlé par `max_step` ; il est permis, et le panneau l'affiche.
- **Clés d'identité** : les `id` restent `<rangée>/<segment>/<rang>`. Une clé qui ne désigne plus aucune parcelle (le tracé a changé) est refusée (`E_STREET_PARCEL`, `unknown_parcel`) avec son id ; le panneau propose de la retirer, rien n'est oublié en silence.
- **Règles du style** : en fidélité historique, un réglage propre hors style est refusé, sinon averti, sur `/parcels/<id>/…`, comme pour la variété.
- **D-21, largeur.** **A, retenue (ADR-45)** : la limite mitoyenne se déplace. La parcelle s'élargit ou rétrécit aux dépens de sa voisine suivante sur le même segment (la précédente si elle est la dernière). Le nombre de parcelles et leurs ids ne changent pas. Refus si la voisine passe sous 6 m, si elle a elle-même une largeur propre, ou si la parcelle est d'angle (`width_locked`) (prévisible, et les réglages des autres parcelles restent attachés aux mêmes bâtiments). **B** : la largeur est fixée, et le reste du segment est redécoupé ; le nombre de parcelles peut changer, et les réglages propres des parcelles suivantes peuvent ne plus désigner le même bâtiment.
- **Fait (AG-068).** `core/ensemble_parcels` : clés de la forme `<rangée>/<segment>/<rang>` (512 au plus), champs vérifiés à la lecture (refus `E_SCHEMA` sur `/parcels/<id>/…`, entrée vide `empty_parcel`) ; le schéma JSON déclare `parcels` comme objet, le détail des champs est tenu par `EnsembleParcels::ENTRY_SCHEMA`, le validateur de schéma ne lisant pas un `additionalProperties` à sous-schéma. Ids inconnus et largeurs jugés sur les parcelles définitives, accès de cour compris, dans `EnsembleEngine.layout_for` : la mise sur terrain voit donc les mêmes limites. Voisine : la suivante contiguë du même segment, sinon la précédente ; un accès de cour entre les deux les sépare. Refus `width_locked` (paramètre `why` : `corner`, `no_neighbour`, `neighbour_width`) et `neighbour_too_narrow`.
- **Tests U47** (`test/unit/ensemble_parcels_test.rb`) : refus à la lecture, ensemble sans réglage propre inchangé, id inconnu, priorité sur la rue (les autres parcelles gardent plan et place), priorité sur la variété (tirage inchangé), avertissement hors style, voisine suivante ou précédente qui absorbe la largeur, refus localisés. Empreintes de quatre ensembles types identiques.

### Clic droit, AG-069

- **D-22, geste.** **A, retenue (ADR-45)** : on entre dans la rue (double-clic sur la racine), on fait un clic droit sur un bâtiment, puis **ARCHGEN → Personnaliser ce bâtiment**. Un petit panneau de parcelle s'ouvre, avec les champs ci-dessus, la valeur de la rue en grisé, et **Revenir au réglage de la rue** pour chaque champ (c'est le geste demandé). **B** : clic droit sur la rue entière, puis choix du bâtiment dans une liste.
- **Écriture** : l'action relit la racine d'ensemble (cible revalidée), ajoute ou retire le réglage propre dans `parcels`, et régénère tout l'ensemble en **une seule opération d'Annuler** (« ARCHGEN : personnaliser un bâtiment »). Un refus laisse le document intact.
- **Exception au refus actuel** : seule cette action accepte une parcelle sélectionnée à l'intérieur d'un ensemble. Les autres (Modifier le bâtiment sélectionné, Terrain) la refusent toujours.
- Le panneau de rue (Modifier l'ensemble sélectionné) affiche le nombre de bâtiments personnalisés ; changer la fourchette ou les toits de la rue ne touche pas leurs réglages propres.
- **Recette H27** : vrai geste au clic droit, une entrée d'Annuler, réouverture du fichier.
- **Fait (AG-069).** `ui/parcel_controller` (testable sans SketchUp : init avec les valeurs de la rue calculées par `EnsembleParcels.street_values`, aperçu, écriture rejouée une seule fois, jeton d'aperçu) et `ui/parcel_panel` (menu contextuel, choix de la parcelle : édition ouverte sur une racine d'ensemble, une instance de parcelle sélectionnée dont le nom est un id). Avant d'écrire, l'édition de la rue est refermée et la racine sélectionnée : la définition n'est jamais remplacée pendant qu'on est dedans. Un champ vide vaut la rue ; plus aucun champ retire l'entrée, plus aucune entrée retire `parcels`. Panneau de rue : nombre de bâtiments personnalisés et case « retirer les réglages propres » (`parcels: null`, seule écriture permise de cette clé depuis le panneau de rue). RBZ 0.12.0. Vérifié : tests de contrat (`test/contract/parcel_controller_test.rb`), panneau chargé et champs essayés dans un navigateur ; **recette H27 dans SketchUp non faite** (laissée au propriétaire).

## Panneaux, AG-067

Section **Détails** dans le panneau du bâtiment et dans celui de la rue : cases Vitrage, Commerce au rez-de-chaussée (et sa hauteur), Cheminées. Pour une rue, elles valent pour toute la rue (D-19, A). Guide, journal ; **RBZ 0.11.0** ; recette **H26**.

- **Fait (AG-067).** Panneau du bâtiment : section « Détails (LOD 1) », cases liées à `/features/glazing`, `/features/chimneys`, `/ground_floor` (cochée : `shop`, décochée : `dwelling`) ; le champ Hauteur du commerce (`/shop/height_m`) ne paraît qu'avec la case, et un changement de style l'efface comme les autres blocs de style. Panneau de rue : mêmes cases ; une case n'est envoyée que si on l'a touchée, sinon la rue suit son style (le noyau donne, par style, ce qu'il coche et sa hauteur de commerce) ; à la modification, une case non envoyée garde la valeur enregistrée. Une rue d'une autre révision que celle proposée montre ses cases décochées. Vérifié : tests de contrat, panneaux chargés et cases essayées dans un navigateur ; **recette H26 dans SketchUp non faite** (laissée au propriétaire). Le clic droit d'AG-069 donne le **RBZ 0.12.0**.

## Hors périmètre

Petits bois, volets, lucarnes (cadrés en J12, [contrat](VOLETS_LUCARNES_CONTRACT.md)) ; enseignes à texte ; intérieur des commerces (EXT-05) ; vitrage au LOD 0 ; mélange de styles entre parcelles (D-15) ; personnaliser un bâtiment d'un îlot à porche autrement que par les champs ci-dessus.
