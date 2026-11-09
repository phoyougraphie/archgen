# Contrat des volets, lucarnes et petits bois — J12 (AG-070 à AG-073)

Contrat de départ, écrit avant le code. Décisions D-23 à D-27 **à trancher** par le propriétaire ; les options A sont recommandées. Il poursuit EXT-01 (richesse des façades et des toits) après J11 ([détails](DETAILS_CONTRACT.md)). Les valeurs marquées « départ » sont à calibrer à la recette.

**Besoin du propriétaire (2026-11-09).** Après le vitrage, les commerces et les cheminées : des volets et des lucarnes. Les petits bois, écartés de J11 (D-17), viennent avec eux.

## Ce qui existe

- **Baies.** Chaque fenêtre a un cadre de barres de 0,04 m au LOD 1 et, avec `features.glazing`, une vitre de 0,01 m dans le jour du cadre ([détails](DETAILS_CONTRACT.md)). Les encadrements (`features.surrounds`) bordent la fenêtre de 0,04 m à l'extérieur.
- **Toits.** Plat, deux pans, croupe, mansarde (brisis à forte pente de la rive à l'anneau, terrasson au-dessus). En rangée : pignons aux murs latéraux, croupe refusée. La peau du toit est faite de faces simples ; une souche de cheminée la traverse sans la percer (AG-066).
- **Rues.** Toutes les options d'un bâtiment valent pour une rue entière (case du panneau de rue) ou pour un seul bâtiment (réglages propres, clic droit, AG-068 et AG-069).

## Règle commune de format

Comme J11 : **chaque nouveau réglage est une clé facultative, sans changement de version de format** ; absente, elle vaut « désactivé », et la configuration canonique ne l'écrit pas. Un bâtiment, une rue ou un îlot existants gardent leur plan et leur empreinte. Une nouvelle révision de profil ne change pas un bâtiment ou un ensemble existant, qui garde la sienne (ADR-46).

## 1. Petits bois — AG-070 (D-26)

Option `features.muntins` (booléen), LOD 1, **seulement avec `features.glazing`** (refus `muntins_without_glazing` sinon).

| Élément | Géométrie (départ) |
|---|---|
| **Montant central** | Une barre verticale de 0,03 m au milieu du jour de la fenêtre : deux vantaux. Une fenêtre de moins de 0,80 m de large n'en a pas (un seul vantail) |
| **Traverses** | `facade.muntin_rows − 1` barres horizontales de 0,02 m par vantail, réparties également ; `muntin_rows` vient du style ([1 ; 6], départ 3 ; 1 = pas de traverse) |
| **Profondeur** | Dans la définition du cadre, devant la vitre (y de 0,005 à 0,015) ; matière `materials.frames` |

- La définition du cadre prend `/muntins/<rangs>` dans son identifiant ; sans l'option, identifiant et contenu sont ceux d'avant.
- Portes et vitrines : pas de petits bois.
- **D-26, options.** **A, recommandée** : montant central et traverses, nombre de rangs donné par le style. **B** : nombre de rangs et de colonnes libre au panneau.

## 2. Volets — AG-071 (D-25)

Option `features.shutters` (booléen), LOD 1, et quatrième rôle de matière facultatif `materials.shutters` (écrit seulement avec l'option ; par défaut `painted_wood`).

| Élément | Géométrie (départ) |
|---|---|
| **Battants** | Deux battants ouverts par fenêtre, plaqués au mur de part et d'autre : chacun fait la moitié de la largeur de la fenêtre et sa hauteur, 0,03 m d'épaisseur, posé à 0,01 m devant le mur ; à l'extérieur de l'encadrement s'il y en a un |
| **Où** | Toutes les fenêtres, sur toutes les façades ; ni porte, ni vitrine, ni lucarne |
| **Place** | Entre deux fenêtres voisines, les deux battants doivent tenir : écart ≥ largeur de fenêtre (+ 2 × 0,04 m avec encadrements). Sinon refus `E_OPENING_CLEARANCE`, `shutters_no_room`, sur `/features/shutters`, avec l'id de la baie ; jamais un volet rétréci ou omis en silence. Même règle aux bouts de façade, contre l'angle du bâtiment |

- Catalogue de matières : nouvelles entrées « Bois peint vert » et « Bois peint bleu pastel » (Toulousain), révision du catalogue.
- Définitions partagées : un battant par largeur, hauteur et matière.
- **D-25, options.** **A, recommandée** : battants ouverts plaqués au mur, refus localisé faute de place. **B** : persiennes repliées dans l'embrasure, invisibles de face (pas de conflit de place, mais peu lisibles en maquette).

## 3. Lucarnes — AG-072 (D-23, D-24)

Option `features.dormers` (booléen), LOD 1.

| Élément | Géométrie (départ) |
|---|---|
| **Où** | Une lucarne par travée de la façade avant, à l'aplomb des fenêtres du dernier niveau ; mansarde : dans le brisis ; deux pans et croupe : sur le pan avant. Toit plat : aucune, avertissement `W_DETAIL` (`dormer_flat_roof`) |
| **Fenêtre** | Largeur `facade.window_width_m`, hauteur min(1,40 ; place disponible) ; cadre, vitre et petits bois comme une fenêtre (même définition partagée) ; allège à 0,30 m au-dessus du haut des murs |
| **Volume** | Façade verticale en recul de 0,15 m sur le nu du mur ; jouées (côtés) de 0,10 m ; petit toit à deux pans de même pente que le pan principal (pente du terrasson pour une mansarde), faîtage perpendiculaire à la façade ; matières `wall` (façade, jouées) et `roof` (toit) |
| **Assise** | Le volume part du haut des murs et traverse la peau du toit sans la percer, comme une souche (D-23, A) ; il s'arrête avant le faîtage principal |
| **Place** | Les lucarnes restent entre les marges de façade, à 0,30 m au moins l'une de l'autre et d'une croupe ; sinon refus `E_OPENING_CLEARANCE`, `dormer_no_room`, sur `/features/dormers`. Un pan trop bas pour une fenêtre de 0,60 m de haut : même refus, `dormer_too_low` |

- En rangée : même règle ; une lucarne ne passe jamais le plan latéral d'une parcelle.
- Avec des cheminées : une souche et une lucarne ne se recouvrent pas ; sinon refus `dormer_on_chimney`.
- **D-23, options.** **A, recommandée** : volume posé qui traverse la peau du toit sans la percer (peu de faces, aucune face de toit découpée, même validation que les souches). **B** : vraie trémie dans le pan, faces du toit découpées autour de la lucarne (plus juste vue de l'intérieur du comble, beaucoup plus de cas).
- **D-24, options.** **A, recommandée** : façade avant seulement, une par travée. **B** : avant et arrière.

## 4. Styles et panneaux — AG-073 (D-27)

- **D-27, options.** **A, recommandée** : révision 3 des styles, chacune activant ce qui lui ressemble : Haussmannien lucarnes et petits bois (`muntin_rows` 3) ; Toulousain volets (bleu pastel) et petits bois ; Brutaliste inchangé (pas de révision). Un bâtiment ou un ensemble existant garde sa révision (ADR-46). **B** : aucune révision, tout est décoché par défaut ; on coche au panneau.
- **Panneaux** : cases Petits bois, Volets, Lucarnes dans la section Détails du bâtiment et de la rue, et au panneau de parcelle (Comme la rue / Oui / Non). Guide, journal ; **RBZ 0.13.0** ; recette **H28**.

## Tests

- **U48** petits bois : comptes de barres, rien sans vitrage, vantail unique sous 0,80 m, empreintes inchangées sans l'option.
- **U49** volets : battants de part et d'autre, rien sur portes et vitrines, refus faute de place, matière.
- **U50** lucarnes : une par travée, sur chaque type de toit, refus et avertissement, rangée sans débordement, cheminée.
- Ensembles types d'avant : mêmes empreintes à chaque ticket.

## Hors périmètre

Volets fermés ou entrebâillés ; lucarnes sur les façades latérales, lucarnes rampantes ou en œil-de-bœuf ; débords de toit et génoises ; profils Provençal, Breton (EXT-01, plus tard) ; intérieur des combles (EXT-05).
