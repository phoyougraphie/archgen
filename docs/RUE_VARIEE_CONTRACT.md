# Contrat des rues variées — EXT-08, première partie (AG-061 à AG-063)

Contrat de départ, écrit avant le code. Décisions D-13 à D-16 tranchées par le propriétaire (options A, ADR-44). Il prolonge le [contrat d'ensemble](ENSEMBLE_CONTRACT.md) sans rien changer à un ensemble existant : un ensemble sans réglage `variety` garde son plan et son empreinte. Les valeurs marquées « départ » sont à calibrer à la recette.

**Besoin du propriétaire (2026-11-08).** Choisir, à la génération d'une rue, d'avoir des hauteurs de bâtiment et des toitures variées. (Les fenêtres et les portes existent déjà sur chaque bâtiment ; la « Variation des baies », utilisable depuis D-01, varie déjà leur position d'une parcelle à l'autre.)

## Ce qui existe et ce qui change

Aujourd'hui, le contrat d'ensemble impose **le même gabarit partout** : mêmes niveaux, même profondeur, même toit. Mais la géométrie s'y prête déjà en grande partie :

- chaque parcelle est un bâtiment complet, avec ses deux **murs latéraux toujours émis en entier et aveugles** (ADR-32) : quand un voisin est plus bas, le haut du mur du plus haut existe déjà ; il apparaît comme un **mur mitoyen nu**, ce qui est l'aspect courant d'une rue réelle ;
- chaque toit est **coupé par les deux plans latéraux** de sa parcelle et ne déborde jamais chez le voisin : un toit bas vient buter contre le mur aveugle du voisin plus haut, et deux toits de types différents se jouxtent sans se recouvrir ;
- la seed de chaque parcelle dérive déjà de celle de l'ensemble par une clé stable.

Ce lot ajoute donc surtout **un tirage par parcelle** (niveaux, toit), ses contrôles, et les cas de jointure que les hauteurs différentes rendent visibles.

## Réglage `variety`, dans le format `ensemble` V1

Clé facultative et fermée, ajoutée sans changer la version du format (comme ADR-41) ; absente, rien ne change.

| Champ | Valeurs | Défaut (départ) | Sens |
|---|---|---|---|
| `levels.min`, `levels.max` | entiers [1 ; 15], min ≤ max | les niveaux du bâtiment | Fourchette du nombre de niveaux, tiré par parcelle |
| `levels.max_step` | [1 ; 14] | 2 | Écart maximal entre deux voisines (D-13) |
| `roofs` | liste de 1 à 3 types parmi `flat`, `gable`, `mansard` | le toit du bâtiment | Toits tirés par parcelle (D-14) ; `hip` reste refusé en rangée (`E_STREET_ROOF`) |

**Tirage (D-13, D-14 ; AG-061) :** les parcelles sont prises dans l'ordre du plan (rangée par rangée, le long du tracé). Pour chacune, la **fenêtre permise** est la fourchette, réduite à ± `max_step` autour du nombre de niveaux de la parcelle précédente de la même rangée ; elle n'est jamais vide. Le nombre de niveaux est `bas + ⌊unit(seed, "parcel/<id>/levels") × (haut − bas + 1)⌋` dans cette fenêtre : le tirage se fait directement dans la fenêtre, aucune valeur n'est coupée après coup. Le toit est `roofs[⌊unit(seed, "parcel/<id>/roof") × n⌋]`. `seed` est celle de l'ensemble. Mêmes réglages et même seed : même rue. **Limite :** dans un îlot, la dernière parcelle du tour n'est comparée qu'à sa précédente, pas à la première : l'écart entre ces deux-là peut dépasser `max_step`.

**Contrôles, refus `E_STREET_VARIETY` :**

| Raison | Quand |
|---|---|
| `variety_levels_order` | `min` > `max` |
| `variety_style_levels` | La fourchette sort de la règle de niveaux du style en fidélité historique (par exemple 5 à 7 pour Haussmannien) ; le message donne la fourchette permise |
| `variety_style_roof` | Un toit de la liste n'est pas permis par le style en fidélité historique (Haussmannien : mansarde seulement) |
| `variety_hip_roof` | `hip` dans la liste, sur `/variety/roofs` |
| `variety_with_levels` | `building.levels.heights_m` saisi : une liste de hauteurs par niveau ne se tire pas |

En fidélité libre, les règles du style deviennent des avertissements, comme pour un bâtiment seul.

Les règles du style se jugent sur une parcelle témoin, la première du plan, avec chaque bout de la fourchette puis chaque toit de la liste, par la même résolution qu'un bâtiment : `variety_style_levels` sur `/variety/levels`, avec la fourchette permise ; `variety_style_roof` sur `/variety/roofs/<i>`, avec les toits permis. Les autres refus portent sur `/variety/levels/min` (`variety_levels_order`) et `/building/levels/heights_m` (`variety_with_levels`).

**Plan :** chaque parcelle porte son tirage (`variety` : `levels`, `roof`), et le plan d'ensemble la répartition (`variety` : niveaux et toits comptés). Deux parcelles de même tirage et de même forme partagent toujours leur définition.

**Budget :** des parcelles différentes partagent moins de définitions ; le plafond de faces de l'ensemble s'applique tel quel (`E_STREET_BUDGET`), estimé avant l'écriture.

## Jointures à hauteurs différentes (AG-062)

Vérifié (U43) : sur une rue en coude et un îlot, trois graines, chaque sommet de toit reste entre les deux plans latéraux de sa parcelle, onglets compris ; chaque mur monte à sa propre hauteur ; l'étagement donne les mêmes plateformes avec ou sans variété. Vu dans SketchUp sur une rue en coude bâtie des deux côtés (22 parcelles, 20 définitions) : aucun recouvrement, pignons et murs découverts aveugles ([image](recette/img/ag062-rue-variee.jpg)). Aucune géométrie nouvelle n'a été nécessaire : ADR-32 et la coupe des toits aux plans latéraux suffisent.

| Situation | Règle |
|---|---|
| **Mur mitoyen découvert** (D-16) | Reste aveugle, de la matière des murs (option A). Le percer de baies au-dessus du toit du voisin serait un ticket à part |
| **Corniche** | S'arrête au mur latéral de sa parcelle, comme aujourd'hui ; sur la plus haute, elle ne retourne pas sur le mur mitoyen découvert |
| **Toit contre un mur plus haut** | Le toit bas bute contre le mur du voisin, déjà émis ; aucune face de toit n'entre dans le volume du voisin (contrôle de recouvrement par parcelle) |
| **Deux pans contre mansarde ou toit plat** | Chaque toit garde son pignon aveugle ; les deux pignons se touchent sans se recouvrir |
| **Étagement sur un terrain** | Inchangé : une plateforme par parcelle ; la hauteur de chaque bâtiment s'ajoute à sa propre plateforme |
| **Accès à la cour (porche)** | La hauteur du porche se mesure sous le rez-de-chaussée, qui ne varie pas avec le nombre de niveaux : inchangé |
| **Angle d'îlot** | Une parcelle d'angle tire comme les autres ; ses deux voisines sont celles des deux segments |

## Styles mêlés (D-15)

**Un seul style par ensemble** dans ce lot (option A) ; mêler les styles d'une parcelle à l'autre demanderait d'accorder les hauteurs de rez-de-chaussée, les corniches et les matières entre styles, et ferait l'objet d'un ticket suivant.

## Panneau (AG-063)

Dans **Tracer une rue ou un îlot** et **Modifier l'ensemble sélectionné** : une case **Varier les bâtiments**, la fourchette de niveaux, l'écart entre voisines, les toits à tirer et la **graine** de l'ensemble ; l'aperçu annonce la répartition (« de 4 à 7 niveaux, 3 toits à deux pans, 2 mansardes »). Une nouvelle graine redonne une autre rue. Guide, journal, RBZ 0.10.0, recette H25 et recettes rejouées.

**Fait (AG-063).** `init` donne pour chaque style ses toits de rangée (règle `roof_type` ∩ plat, deux pans, mansarde ; les trois sans règle) et sa fourchette (règle `level_count`, sinon 3 à 6 proposés). Les toits du style sont cochés par défaut ; les autres restent proposés, marqués « hors style » : en fidélité plausible le style les signale, en stricte il les refuse (`variety_style_roof`). Ce choix précise « cases parmi ceux du style » : un style d'un seul toit n'aurait sinon aucune variété de toits. Case décochée, le panneau envoie `variety: null` : en création rien n'est ajouté, en modification la variété enregistrée est retirée ; une variété envoyée remplace l'enregistrée en entier. La graine n'est envoyée que saisie. Les corps `preview`, `load_selection`, `edit_preview` et `regenerate` portent `variety`, la répartition du plan. Contrat vérifié par quatre tests du contrôleur (C : test/contract/street_controller_test.rb).

## Hors de ce lot

Styles mêlés ; baies sur les murs mitoyens découverts ; profondeur et largeur variées par parcelle ; réglage d'une parcelle à la main ; retraits d'attique ; densité et mixité à l'échelle d'un quartier (suite d'EXT-08).
