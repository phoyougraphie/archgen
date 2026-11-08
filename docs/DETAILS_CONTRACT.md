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
| **Vitre** de fenêtre | Une face plane par baie, dans le jour du cadre (u de 0,04 à W − 0,04, z de 0,04 à H − 0,04), au milieu de la profondeur du cadre (d₀ + 0,02). Recto et verso, matière `materials.glass` |
| **Porte pleine** | Un vantail : panneau de 0,05 m d'épaisseur, dans le jour du cadre, de z = 0 à H − 0,04, en retrait au milieu du cadre ; matière `materials.frames` |
| **Imposte** (porte de plus de 2,40 m) | Traverse de 0,04 m à 2,20 m ; vitre au-dessus, panneau au-dessous |

- **Matière `glass`** : un quatrième rôle de matière, `materials.glass`, à clés d'un catalogue fermé, nouvelle révision du catalogue de matières (verre légèrement teinté, translucide). Un bâtiment sans vitrage n'a pas ce rôle.
- **Définitions partagées** : vitres et vantaux par type, largeur, hauteur et matière, comme les cadres.
- **D-17, options.** **A, retenue (ADR-45)** : vitre et porte pleine seulement (peu de faces, lisible en maquette ; les petits bois et volets restent pour EXT-01). **B** : ajouter dès maintenant des petits bois selon le style (Haussmannien : trois carreaux par vantail), plus de faces et un réglage de plus. **Défaut :** une nouvelle révision de chaque profil publié active le vitrage ; un bâtiment existant garde sa révision, donc rien ne change chez lui tant qu'on ne coche pas la case.
- **Tests U44** : comptes de faces par baie, vitre dans le jour du cadre sans toucher le mur, empreintes d'avant inchangées sans l'option.

## 2. Rez-de-chaussée commerçant — AG-065 (D-18, D-19)

Réglage `ground_floor` du bâtiment : `"dwelling"` (défaut, absent) ou `"shop"`, avec `shop.height_m` (hauteur du rez-de-chaussée, [3,2 ; 6], départ 4,0 m ; Haussmannien 4,5 m).

| Élément | Géométrie (départ) |
|---|---|
| **Hauteur** | Le rez-de-chaussée prend `shop.height_m` ; les étages gardent leur hauteur. Si `levels.heights_m` est saisi, il prime et `shop.height_m` est refusé (`shop_with_heights`) |
| **Vitrines** | Toutes les travées de la façade avant au rez-de-chaussée, sauf `entry_bay`, deviennent des baies `kind = shopfront` : largeur = pas de travée − 2 × 0,30 m (trumeau de 0,30 m au moins de chaque côté), de z = 0,15 m (soubassement) à hauteur du rez-de-chaussée − 0,60 m |
| **Entrée de l'immeuble** | La travée `entry_bay` garde la porte de l'immeuble |
| **Bandeau d'enseigne** | Bande en saillie de 0,10 m, de 0,40 m de haut, entre les vitrines et le plancher du premier étage, d'une marge à l'autre ; sans texte ; matière `materials.frames` |
| **Vitrage** | Avec `features.glazing`, chaque vitrine reçoit une vitre fixe ; une porte vitrée de 0,90 m prend le bord de la vitrine le plus proche de l'entrée de l'immeuble |

- Dégagements du contrat géométrique appliqués aux vitrines ; un trumeau trop étroit est refusé (`E_OPENING_CLEARANCE`, sur `/facade/bay_width_m` ou `/parcels/<id>/…`), jamais rétréci en silence.
- Porche d'îlot : une parcelle à porche garde son passage ; ses vitrines s'arrêtent à 0,10 m du passage, comme les baies d'aujourd'hui.
- Corniche et balcons inchangés ; le premier balcon (niveau d'index 2) monte avec le rez-de-chaussée plus haut.
- **D-18, options.** **A, retenue (ADR-45)** : une vitrine par travée, entre trumeaux maçonnés (suit la trame, se combine avec la variation des baies). **B** : une devanture continue en applique (bois), d'une marge à l'autre, plus parisienne mais hors trame.
- **D-19, dans une rue.** **A, retenue (ADR-45)** : commerces sur toute la rue (case du panneau de rue), puis bâtiment par bâtiment au clic droit. **B** : en plus, une proportion tirée par parcelle (par exemple 60 %), comme la variété.
- **Tests U45.**

## 3. Cheminées — AG-066 (D-20)

Option `features.chimneys` (booléen), LOD 1.

- **Souche** : parallélépipède de 0,60 × 0,45 m (départ), adossé à l'intérieur d'un mur latéral (à 0,10 m de sa face intérieure), centré sur le faîtage pour un toit à deux pans ou une mansarde. Le haut dépasse le faîtage de 0,60 m ; sur un toit plat, il dépasse la toiture de 1,00 m. Un **couronnement** de 0,05 m déborde de 0,05 m. Matière `materials.wall`.
- **Nombre** : 1 ou 2 souches par bâtiment (une contre chaque mur latéral), tiré par `unit(seed, "chimneys")`. Une parcelle d'angle ou un bâtiment seul suit la même règle.
- **Assise** : la souche part du haut des murs (z = H) et traverse la peau du toit sans la percer, comme la peau du toit traverse déjà la corniche. Elle ne déborde jamais chez le voisin.
- **Croupe** : il n'y a pas de faîtage sur toute la longueur ; souche centrée sur le bout du faîtage.
- **D-20, options.** **A, retenue (ADR-45)** : souches contre les murs latéraux, sur tous les types de toit (réaliste en rangée, où les souches mitoyennes se groupent par deux, et simple). **B** : souches seulement sur les toits en pente ; un toit plat n'en a pas, avec un avertissement `W_DETAIL`.
- **Tests U46.**

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
- **Tests U47** : priorité, voisine qui absorbe la largeur, refus localisés, ensembles d'avant inchangés.

### Clic droit, AG-069

- **D-22, geste.** **A, retenue (ADR-45)** : on entre dans la rue (double-clic sur la racine), on fait un clic droit sur un bâtiment, puis **ARCHGEN → Personnaliser ce bâtiment**. Un petit panneau de parcelle s'ouvre, avec les champs ci-dessus, la valeur de la rue en grisé, et **Revenir au réglage de la rue** pour chaque champ (c'est le geste demandé). **B** : clic droit sur la rue entière, puis choix du bâtiment dans une liste.
- **Écriture** : l'action relit la racine d'ensemble (cible revalidée), ajoute ou retire le réglage propre dans `parcels`, et régénère tout l'ensemble en **une seule opération d'Annuler** (« ARCHGEN : personnaliser un bâtiment »). Un refus laisse le document intact.
- **Exception au refus actuel** : seule cette action accepte une parcelle sélectionnée à l'intérieur d'un ensemble. Les autres (Modifier le bâtiment sélectionné, Terrain) la refusent toujours.
- Le panneau de rue (Modifier l'ensemble sélectionné) affiche le nombre de bâtiments personnalisés ; changer la fourchette ou les toits de la rue ne touche pas leurs réglages propres.
- **Recette H27** : vrai geste au clic droit, une entrée d'Annuler, réouverture du fichier.

## Panneaux, AG-067

Section **Détails** dans le panneau du bâtiment et dans celui de la rue : cases Vitrage, Commerce au rez-de-chaussée (et sa hauteur), Cheminées. Pour une rue, elles valent pour toute la rue (D-19, A). Guide, journal ; **RBZ 0.11.0** ; recette **H26**. Le clic droit d'AG-069 donne le **RBZ 0.12.0**.

## Hors périmètre

Petits bois, volets, lucarnes (EXT-01) ; enseignes à texte ; intérieur des commerces (EXT-05) ; vitrage au LOD 0 ; mélange de styles entre parcelles (D-15) ; personnaliser un bâtiment d'un îlot à porche autrement que par les champs ci-dessus.
