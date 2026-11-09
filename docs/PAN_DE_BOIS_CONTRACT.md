# Contrat du pan de bois — J15 (AG-083 à AG-085)

Lot J15 du plan des styles ([régionaux](STYLES_REGIONAUX_CONTRACT.md), ADR-48 : choix de détail délégués, options recommandées retenues et consignées ici). Valeurs « départ » à calibrer à la recette.

## Règle commune de format

Chaque réglage est une clé facultative, non écrite quand il est désactivé ; l'existant garde son plan.

## 1. Pan de bois apparent — AG-083

Option `features.timber_frame` (booléen), LOD 1, avec un rôle de matière `materials.timber` (écrit seulement avec l'option ; par défaut `dark_wood`). Le **rez-de-chaussée reste maçonné** ; les étages montrent leur ossature, posée sur le mur (de 0,04 m devant le nu jusqu'au nu), le remplissage gardant la matière du mur.

| Pièce | Géométrie (départ) |
|---|---|
| **Sablières** | Une poutre de 0,20 m de haut au pied de chaque étage et une sous le haut des murs, d'un bout de la façade à l'autre |
| **Poteaux** | 0,16 m de large aux deux bouts de la façade et à mi-distance entre deux baies voisines d'un même étage, d'une sablière à l'autre ; omis là où un poteau d'huisserie prend sa place |
| **Huisseries** | Poteaux de 0,12 m de chaque côté de chaque fenêtre ; appui et linteau de 0,12 m de part et d'autre de la fenêtre |
| **Décharges** | Une écharpe en diagonale de 0,12 m dans chaque panneau plein de 0,50 m de large au moins, alternant de sens |
| **Façades** | Avant et arrière ; côtés aussi pour un bâtiment seul (en rangée, les côtés sont mitoyens) |

- **Incompatibles** (refus `E_SCHEMA` sur `/features/timber_frame`) : encadrements (`timber_with_surrounds`), volets (`timber_with_shutters`), corniche (`timber_with_cornice`), bardage (`timber_with_cladding`) — ils occuperaient la même épaisseur devant le mur.
- **Écart au catalogue, consigné.** Le catalogue associe l'encorbellement (`jetties`) aux colombages et à l'Alsacien. Il demande de décaler les murs étage par étage (murs, baies, planchers, toit) : c'est un lot à lui seul. Il est **reporté** ; les profils de J15 sont publiés sans lui, et ne le requièrent pas.

- **Fait (AG-083).** `geometry/timber_solver` ; écharpes en solides parallélogrammes dans le plan de façade. Tests U55 (`test/unit/timber_frame_test.rb`) : aucune pièce devant une baie, rez-de-chaussée nu, côtés seulement pour un bâtiment seul.

## 2. Profils — AG-084

| Profil | Volume et toit | Matières | Détails |
|---|---|---|---|
| **Maison à colombages** | 3 niveaux de 2,8 m, deux pans à 45° | Enduit clair, bois sombre, tuile mécanique | Pan de bois, petits bois, vitrage |
| **Normand** | 2 niveaux de 2,7 m, deux pans à 50° | Enduit clair, bois sombre, ardoise | Pan de bois, lucarnes, cheminées, petits bois, vitrage |
| **Alsacien** | 3 niveaux de 2,7 m, deux pans à 55° | Enduit ocre, bois sombre, tuile mécanique | Pan de bois, lucarnes, petits bois, vitrage |
| **Basque** | 3 niveaux de 2,8 m, deux pans à 30°, faîtage perpendiculaire, débord 0,60 m | Enduit clair, bois peint rouge, tuile canal | Pan de bois, petits bois, vitrage |

- **Fait (AG-084).** Profils `colombages`, `normand`, `alsacien`, `basque`, famille `timber_vernacular` ; U52 étendu.

## 3. Panneaux — AG-085

Case Pan de bois (avec sa matière) aux trois panneaux ; guide, journal ; **RBZ 0.16.0** ; recette **H31** à la main.

- **Fait (AG-085).** Case Pan de bois (et matériau) aux trois panneaux ; RBZ 0.16.0. **Recette H31 dans SketchUp non faite** (laissée au propriétaire).

## Tests

- **U55** pan de bois : pièces et positions, rez-de-chaussée nu, côtés selon bâtiment seul ou rangée, refus, deux modes, solides valides.
- **U52** étendu aux quatre profils.
