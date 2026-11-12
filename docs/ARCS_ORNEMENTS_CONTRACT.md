# Contrat des arcs et ornements — J16 (AG-086 à AG-089)

Lot J16 du plan des styles ([régionaux](STYLES_REGIONAUX_CONTRACT.md), ADR-48 : choix de détail délégués, options recommandées retenues et consignées ici). Valeurs « départ » à calibrer à la recette.

## Portée retenue, et ce qui est approché

Le générateur fait des bâtiments d'habitation en rangée ou isolés, pas des églises : Roman et Gothique deviennent « maison romane » et « maison gothique » (baies en arc sur une maison de ville). Deux capacités portent tout le lot : **les arcs** et **les ornements classiques**. Sont **approchés** et consignés comme tels : l'avant-corps baroque (fronton et pilastres, sans saillie de volume), les reliefs Art déco (pilastres en bandes verticales), l'Art nouveau (baies en plein cintre, sans courbes libres ni oriels), le patio andalou (l'îlot fermé fait déjà cour). **Reportés** : retraits en gradins (Art déco), oriels, abside, voûtes, colonnes en ronde-bosse.

## 1. Arcs — AG-086

Réglage `facade.arch` : `"round"` (plein cintre) ou `"pointed"` (arc brisé) ; absent, baies droites. Il vaut pour les fenêtres et la porte d'entrée, au LOD 1.

| Élément | Géométrie (départ) |
|---|---|
| **Tracé** | Plein cintre : demi-cercle de rayon L/2 sous le haut de la baie. Brisé : deux arcs de rayon L, sommet au haut de la baie, naissances à 0,866 L sous lui |
| **Écoinçons** | Les deux coins du haut de la baie, hors de l'arc, sont remplis par des plaques de 0,02 m devant le nu, matière du mur, en bandes verticales (8 par côté) : la baie se lit en arc, cadre et vitre restant derrière |
| **Refus** | Une baie moins haute que la flèche de l'arc plus 0,30 m : `arch_too_low` sur `/facade/window_height_m` ou `/facade/door_height_m` |

## 2. Ornements classiques — AG-087

Option `features.classical` (booléen), LOD 1, façade avant :

| Élément | Géométrie (départ) |
|---|---|
| **Pilastres** | Bandes de 0,30 m de large, 0,06 m de saillie, à chaque bout de façade et entre deux travées, du soubassement au haut des murs |
| **Soubassement** | Bande de 0,80 m de haut, 0,06 m de saillie, d'un bout à l'autre |
| **Fronton** | Triangle de 0,10 m d'épaisseur au-dessus de la porte d'entrée : base = largeur de porte + 0,60 m, hauteur 0,50 m, à 0,15 m au-dessus de la porte |

Matière `materials.wall`. Refus : avec le pan de bois (`classical_with_timber`) ; un pilastre qui toucherait une baie, son encadrement ou ses volets (`pilaster_no_room`, avec l'id) ; un fronton qui sortirait du rez-de-chaussée (`pediment_no_room`).

## 3. Profils — AG-088

| Profil | Traits |
|---|---|
| **Maison romane** | Pierre, 2 niveaux, petites baies en plein cintre, murs épais, deux pans à 30° |
| **Maison gothique** | Pierre, 3 niveaux, baies en arc brisé, pignon sur rue à 55° |
| **Renaissance** | Pierre blonde, 3 niveaux, croisées (petits bois à 2 rangs), lucarnes, encadrements |
| **Néoclassique** | Pierre claire, 4 niveaux, ornements classiques, corniche, toit à deux pans bas (la croupe est refusée en rangée) |
| **Baroque** | Pierre dorée, 4 niveaux, ornements classiques, baies en plein cintre au rez-de-chaussée et aux étages, mansarde |
| **Art déco** | Béton clair, 6 niveaux, ornements classiques (bandes verticales), toit plat, corniche |
| **Art nouveau** | Pierre blonde, 5 niveaux, baies en plein cintre, balcons, mansarde |
| **Méditerranéen — cycladique** | Enduit blanc, 2 niveaux, toit plat, baies en plein cintre, volets bleus |
| **Méditerranéen — andalou** | Enduit blanc, 2 niveaux, tuile canal à deux pans bas, portes en plein cintre, volets verts |

- **Fait (AG-086 à AG-088).** `geometry/ornament_solver` (écoinçons en bandes solides, pilastres, soubassement coupé au droit des baies basses, fronton triangulaire). Un pilastre devant un passage de porche est omis et dit (`pilaster_porch`). Profils : `facade.muntin_rows` seulement avec les petits bois ; Néoclassique et Andalou à deux pans (la croupe est refusée en rangée). Tests U56-U57 (`test/unit/ornaments_test.rb`), U52 étendu.

## 4. Panneaux — AG-089

Liste « Arcs » (droites, plein cintre, brisés) et case Ornements classiques aux panneaux ; **RBZ 0.17.0** ; recette **H32** à la main.

- **Fait (AG-089).** Liste Arcs au panneau du bâtiment ; case Ornements aux trois panneaux (dans une rue, l'arc suit le style). RBZ 0.17.0. **Recette H32 dans SketchUp non faite.**

## Tests

- **U56** arcs : écoinçons, flèches, refus, deux modes.
- **U57** ornements : pilastres, soubassement, fronton, refus.
- **U52** étendu aux neuf profils.
