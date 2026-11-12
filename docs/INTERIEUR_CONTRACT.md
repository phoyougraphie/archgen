# Contrat de l'intérieur — J21 (AG-110 à AG-114)

**Demande du propriétaire (2026-11-10).** « On fait tout ce qui est non fait », l'intérieur compris (EXT-05), avant les emprises non rectangulaires (J22) puis EXT-06, 12, 09 et 08. Cadrage validé le même jour (« Oui, cadre J21 »).

**Statut : reporté (2026-11-10).** Le propriétaire a reporté tout l'intérieur : « REPORTE tout ce qui a trait a l'interieur ». Les chantiers prioritaires sont EXT-06 (décor de jeu), EXT-12 (mobilier urbain), EXT-09 (cartographie), EXT-08 (quartier), puis J22 (emprises non rectangulaires), puis J21 (intérieur). Le contrat reste valable pour la reprise ; aucun code n'est écrit.

**Au cas par cas (2026-11-10).** L'intérieur se crée maison par maison, jamais pour toute une rue d'un coup : clic droit sur un bâtiment ARCHGEN → **Créer l'intérieur** (et **Retirer l'intérieur**). Le gabarit de rue ne porte pas de bloc `interior`.

**Périmètre.** Le PRD excluait l'intérieur et l'ADR-01 réservait le nom « Interior » à un mode. ADR-52 ouvre l'intérieur comme une **option des deux modes**, Shell et Structural. C'est un décor pour la maquette et l'image, pas un plan d'aménagement : pas de conformité réglementaire, pas de calcul.

**Choix de détail.** Ils sont pris selon ADR-48, recommandation appliquée, et restent révisables par le propriétaire (D-23 à D-26 ci-dessous).

Chaque réglage est une clé facultative du bloc `interior` : absent, le plan est inchangé, et les empreintes des ensembles types restent identiques. Rien n'est écrit par défaut à la création : l'intérieur coûte des faces, on le demande.

## Décisions de détail appliquées (révisables)

| N° | Question | Choix appliqué | Autre option |
|---|---|---|---|
| D-23 | Mode ou option ? | Option `interior` valable en Shell et en Structural. | Un 3ᵉ mode « Interior » dérivé de Structural. |
| D-24 | Où est l'escalier ? | Cage contre un mur latéral, à l'arrière : le côté sans baie, ou le mur mitoyen dans une rue ; à égalité, la gauche. | Cage au centre, contre le mur arrière. |
| D-25 | Comment sont les pièces ? | Pièces en enfilade : des cloisons transversales posées sur les trumeaux, jamais devant une baie, chacune avec une porte. | Un couloir longitudinal desservant les pièces. |
| D-26 | Quelles dimensions d'escalier ? | Volées de 0,90 m, marches de 0,18 m au plus, giron de 0,27 m, palier de 1,00 m. | Valeurs réglables par le style. |

## 1. Planchers et calque Intérieur — AG-110

- `interior.floors: true` pose un plancher à chaque niveau au-dessus du rez-de-chaussée :
  - en Shell, une face à la base du niveau, tournée vers le haut, sur l'emprise intérieure ;
  - en Structural, les dalles intermédiaires existent déjà, et rien ne s'ajoute.
- Le rez-de-chaussée a déjà son plancher : c'est la dalle d'ADR-50.
- Nouvelles catégories de plan `floor`, `stair` et `partition`, rangées sous un tag **ARCHGEN Intérieur** que l'utilisateur peut masquer.
- Matières du catalogue existant, rôles `interior_floor` (`natural_wood`) et `partition` (`lime_plaster`) ; aucun matériau n'est ajouté.
- « Faux » n'est pas écrit (comme `ground_slab`).

## 2. Cage d'escalier et trémies — AG-111

`interior.stair: 'dogleg'`. Chaque niveau, sauf le dernier, reçoit un escalier à **deux volées** vers le niveau suivant :

- h est la hauteur d'étage, de base à base. On prend n = ⌈h / 0,18⌉ marches égales, réparties en deux volées de ⌈n/2⌉ et ⌊n/2⌋ marches, avec un palier entre les deux.
- La cage mesure 1,90 m de large (deux volées et 0,10 m de jour). Sa longueur est ⌈n/2⌉ × 0,27 + 1,00 m.
- Elle est placée selon D-24, à 0,10 m au moins des faces intérieures, de la porte d'entrée et du passage d'un porche.
- **Trémie** : la dalle du niveau supérieur (Structural) ou son plancher (Shell) est découpé autour de la cage, en au plus quatre rectangles. Le dernier niveau n'a pas de trémie, et le toit n'est jamais percé.
- Les marches sont des solides en Structural et en Shell, car elles sont vues des deux côtés. Une volée est une définition partagée entre les niveaux de même hauteur.
- **Refus localisés** :
  - `stair_no_room` : la cage ne tient pas dans l'emprise intérieure ;
  - `stair_blocks_door` : la cage coupe la porte d'entrée ou le passage ;
  - `stair_single_level` : le bâtiment n'a qu'un niveau, donc pas d'escalier.
- **Pilotis** : le rez-de-chaussée n'a pas d'intérieur ; l'escalier commence au premier étage, avec un avertissement.
- **Emprise d'angle (trapèze)** : la cage doit tenir dans la partie rectangulaire, sinon `stair_no_room`.
- « Escalier » n'existe que si `floors` est vrai : sans planchers, `stair_without_floors`.

## 3. Cloisons et pièces — AG-112

`interior.rooms: true`, selon D-25 :

- À chaque niveau, des cloisons transversales, perpendiculaires à la façade avant, sont posées au milieu de trumeaux. Elles visent des pièces de 3,0 à 5,0 m de large et vont de la façade avant à la façade arrière, en s'arrêtant à la cage.
- La cage est fermée par une cloison longitudinale, avec une porte.
- Chaque cloison a une porte de 0,90 × 2,10 m, à 1,00 m de la façade avant, ou au milieu si la pièce est moins profonde que 3,00 m.
- Cloison : en Structural, un solide de 0,10 m ; en Shell, une face verticale. La porte est une ouverture sans menuiserie.
- Un rez-de-chaussée commercial reste un seul volume, sans cloison (vitrines).
- Une cloison ne passe jamais devant une baie ni dans la cage. Une pièce de moins de 2,0 m de large est fondue avec sa voisine.
- `rooms` exige `floors`, sinon `rooms_without_floors`.

## 4. Intérieur au cas par cas, au clic droit — AG-113

- Jamais à l'ensemble d'une rue : le gabarit de rue n'a pas de bloc `interior`, et le panneau de rue n'a pas de section Intérieur.
- Clic droit sur un bâtiment ARCHGEN, isolé ou maison d'une rue → **Créer l'intérieur** : une seule opération Undo, sur ce seul bâtiment ; **Retirer l'intérieur** l'enlève. Dans une rue, la réponse est stockée comme personnalisation de cette parcelle.
- Dans une rangée, la cage s'appuie sur un mur mitoyen (D-24) et évite le passage d'un porche.
- Les budgets de faces de l'ensemble s'appliquent tels quels. Au-delà, le refus est localisé et dit de retirer les pièces ou l'escalier.

## 5. Panneaux, version — AG-114

- Section **Intérieur** au panneau du bâtiment seulement, avec trois cases : Planchers, Escalier, Pièces. Escalier et Pièces cochent Planchers.
- Guide, journal, RBZ à la reprise ; recette **H37** à la main.

## Tests

- U74 : planchers et tag.
- U75 : escalier, trémie et refus.
- U76 : cloisons, portes, baies évitées, rez-de-chaussée commercial.
- U77 : clic droit sur une maison de rue, les voisines inchangées, budget.
