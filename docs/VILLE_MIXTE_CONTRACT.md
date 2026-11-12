# Contrat de la ville mixte — J18 (AG-095 à AG-099)

**Demande du propriétaire (2026-11-09).** Un clic droit pour modifier un bâtiment seul ; dans une rue, changer le style d'un bâtiment (« avec l'évolution des villes, plusieurs styles se côtoient ») ; moins de répétition dans les portes, fenêtres et vitrines des rez-de-chaussée ; des stores bannes ou des pergolas devant les commerces, pour des étals.

Le style par bâtiment revient sur ADR-44 (« un seul style par ensemble », D-15) **à la demande du propriétaire** : ADR-49. Les choix de détail ci-dessous sont pris par Claude selon ADR-48 (options recommandées, révisables).

## Règle commune de format

Clés facultatives, sans changement de version ; absentes, l'existant garde son plan et son empreinte.

## 1. Clic droit « Modifier » — AG-095

Clic droit sur la racine d'un bâtiment seul : **ARCHGEN → Modifier ce bâtiment** (le panneau du bâtiment s'ouvre sur lui, comme « Modifier le bâtiment sélectionné »). Sur la racine d'une rue ou d'un îlot : **ARCHGEN → Modifier cette rue**. Dans une rue ouverte, « Personnaliser ce bâtiment » reste (AG-069).

## 2. Un style par bâtiment dans une rue — AG-096

Réglage propre `style` d'une parcelle (`parcels.<id>.style`, id d'un style actif). La parcelle prend les défauts de ce style au lieu de ceux de la rue ; les réglages saisis pour la rue (niveaux, hauteur courante, mode, LOD, détails cochés) et ses propres réglages passent ensuite. Sa révision est **figée** à l'écriture (`style_revision`), comme celle de la rue (ADR-46).

- La forme d'accès d'un îlot reste celle du style de la rue.
- Les règles de la variété (fourchette, toits) restent celles de la rue ; un tirage hors du style du bâtiment est averti comme un réglage propre.
- Refus : style inconnu ou inactif (`E_PROFILE_UNAVAILABLE` sur `/parcels/<id>/style`) ; toit en croupe imposé par ce style en rangée (refus existant).
- Panneau de parcelle : liste Style (« Comme la rue » et les styles, groupés par famille).

## 3. Rez-de-chaussée moins répétitifs — AG-097

Nouveau tirage de variété `variety.ground` (rues et îlots) :

| Clé | Effet |
|---|---|
| `entry: true` | La travée de la porte est tirée par parcelle (au lieu du milieu), hors des bouts de façade quand la parcelle a 3 travées ou plus |
| `shop_share` | Part des parcelles en commerce, de 0 à 1 (par exemple 0,6) : chaque parcelle tire son rez-de-chaussée ; un réglage propre `ground_floor` passe devant |
| `widths: true` | La largeur des fenêtres est tirée par parcelle entre 85 % et 115 % de celle du style, au pas de 5 cm. Elle vaut pour tous les niveaux du bâtiment : le format n'a qu'une largeur de fenêtre par bâtiment |

Tirages par `unit(seed, "parcel/<id>/ground/…")` : reproductibles, sans changer les autres tirages. Le résultat du panneau les annonce (« 6 commerces sur 10 »).

## 4. Stores bannes et pergolas — AG-098

Réglage `features.shop_front` : `"awning"` (store banne) ou `"pergola"` ; seulement avec un rez-de-chaussée commerçant (`shop_front_without_shop`). D'abord prévu sous `shop`, il est passé dans `features` : `shop` est reconstruit à la résolution et disparaît avec des hauteurs par niveau, le choix y aurait été perdu sans bruit.

| Élément | Géométrie (départ) |
|---|---|
| **Store banne** | Une toile par vitrine, de la largeur de la vitrine : du dessous du bandeau, inclinée vers la rue sur 1,50 m de saillie et 0,50 m de chute, lambrequin de 0,25 m au bout ; nouvelle matière « Toile rayée » (rôle `materials.awning`, défaut `canvas_red`) |
| **Pergola** | De marge à marge, 2,40 m de saillie : poteaux de 0,10 m tous les 3 m environ, à 2,60 m de haut, deux longerons et des chevrons tous les 0,60 m ; matière des cadres |

Au LOD 1, façade avant. Le store ne passe pas devant la porte de l'immeuble ; la pergola s'interrompt devant elle.

## 5. Panneaux et version — AG-099

Cases et listes aux panneaux (Devanture : rien, store, pergola ; Rez-de-chaussée varié et part de commerces au panneau de rue) ; guide, journal ; **RBZ 0.19.0** ; recette **H34** à la main.

- **Fait (AG-095 à AG-099).** `ui/context_menu` (un seul sous-menu ARCHGEN), `parcels.<id>.style` et `style_revision` figée par le service, `variety.ground` (résumé `shops` écrit seulement avec ce tirage : une rue variée d'avant garde son plan), `features.shop_front` et toiles (rouge, verte, beige). Panneaux : Devanture et toile au bâtiment ; Devanture, Rez-de-chaussée variés et Part de commerces à la rue ; Style et Devanture à la parcelle. RBZ 0.19.0. **Recette H34 dans SketchUp non faite.**

## Tests

U62 clic droit (sélection) ; U63 style par bâtiment ; U64 rez-de-chaussée variés ; U65 stores et pergolas.
