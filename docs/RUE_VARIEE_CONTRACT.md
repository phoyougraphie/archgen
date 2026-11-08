# Contrat des rues variées — EXT-08, première partie (AG-061 à AG-063)

Contrat de départ, écrit avant le code, **à valider par le propriétaire** : les choix marqués « proposé » dépendent des décisions ouvertes D-13 à D-16. Il prolonge le [contrat d'ensemble](ENSEMBLE_CONTRACT.md) sans rien changer à un ensemble existant : un ensemble sans réglage `variety` garde son plan et son empreinte. Les valeurs marquées « départ » sont à calibrer à la recette.

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
| `levels.max_step` | [1 ; 14] | 2 | Écart maximal entre deux voisines (proposé, D-13) |
| `roofs` | liste de 1 à 4 types parmi `flat`, `gable`, `mansard` | le toit du bâtiment | Toits tirés par parcelle (proposé, D-14) ; `hip` reste refusé en rangée (`E_STREET_ROOF`) |

**Tirage, proposé (D-13, D-14) :** pour chaque parcelle, dans l'ordre des rangées puis des parcelles, `levels = min + ⌊unit(seed, "parcel/<id>/levels") × (max − min + 1)⌋`, puis ramené dans `[voisine − max_step ; voisine + max_step]` par **un nouveau tirage dans la fenêtre permise**, jamais par une coupe silencieuse : la fenêtre permise est l'intersection de la fourchette et de ± `max_step` autour de la parcelle précédente de la rangée. Le toit est `roofs[⌊unit(seed, "parcel/<id>/roof") × n⌋]`. Mêmes réglages et même seed : même rue.

**Contrôles, refus `E_STREET_VARIETY` :**

| Raison | Quand |
|---|---|
| `variety_levels_order` | `min` > `max` |
| `variety_style_levels` | La fourchette sort de la règle de niveaux du style en fidélité historique (par exemple 5 à 7 pour Haussmannien) ; le message donne la fourchette permise |
| `variety_style_roof` | Un toit de la liste n'est pas permis par le style en fidélité historique (Haussmannien : mansarde seulement) |
| `variety_hip_roof` | `hip` dans la liste |
| `variety_with_levels` | `building.levels.heights_m` saisi : une liste de hauteurs par niveau ne se tire pas |

En fidélité libre, les règles du style deviennent des avertissements, comme pour un bâtiment seul.

**Budget :** des parcelles différentes partagent moins de définitions ; le plafond de faces de l'ensemble s'applique tel quel (`E_STREET_BUDGET`), estimé avant l'écriture.

## Jointures à hauteurs différentes (AG-062)

| Situation | Règle proposée |
|---|---|
| **Mur mitoyen découvert** (D-16) | Reste aveugle, enduit de la matière des murs : proposé (option A). Option B : le percer de baies au-dessus du toit du voisin, ticket à part |
| **Corniche** | S'arrête au mur latéral de sa parcelle, comme aujourd'hui ; sur la plus haute, elle ne retourne pas sur le mur mitoyen découvert |
| **Toit contre un mur plus haut** | Le toit bas bute contre le mur du voisin, déjà émis ; aucune face de toit n'entre dans le volume du voisin (contrôle de recouvrement par parcelle) |
| **Deux pans contre mansarde ou toit plat** | Chaque toit garde son pignon aveugle ; les deux pignons se touchent sans se recouvrir |
| **Étagement sur un terrain** | Inchangé : une plateforme par parcelle ; la hauteur de chaque bâtiment s'ajoute à sa propre plateforme |
| **Accès à la cour (porche)** | La hauteur du porche se mesure sous le rez-de-chaussée, qui ne varie pas avec le nombre de niveaux : inchangé |
| **Angle d'îlot** | Une parcelle d'angle tire comme les autres ; ses deux voisines sont celles des deux segments |

## Styles mêlés (D-15)

Proposé : **un seul style par ensemble** dans ce lot (option A) ; mêler les styles d'une parcelle à l'autre (option B) demande d'accorder les hauteurs de rez-de-chaussée, les corniches et les matières entre styles, et ferait l'objet d'un ticket suivant.

## Panneau (AG-063)

Dans **Tracer une rue ou un îlot** et **Modifier l'ensemble sélectionné** : une case **Varier les bâtiments**, la fourchette de niveaux, l'écart entre voisines, les toits à tirer (cases parmi ceux du style) ; l'aperçu annonce la répartition (« 4 à 7 niveaux, 3 toits à deux pans, 2 mansardes… »). Une nouvelle graine redonne une autre rue. Guide, journal, RBZ 0.10.0, recette H25 et recettes rejouées.

## Hors de ce lot

Styles mêlés (si D-15 = B) ; baies sur les murs mitoyens découverts (si D-16 = B) ; profondeur et largeur variées par parcelle ; réglage d'une parcelle à la main ; retraits d'attique ; densité et mixité à l'échelle d'un quartier (suite d'EXT-08).
