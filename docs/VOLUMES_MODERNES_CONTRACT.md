# Contrat des volumes modernes — J17 (AG-090 à AG-094)

Dernier lot du plan des styles ([régionaux](STYLES_REGIONAUX_CONTRACT.md), ADR-48 : choix de détail délégués, options recommandées retenues et consignées ici). Valeurs « départ » à calibrer à la recette.

## Portée retenue

Quatre capacités portent le lot. **Reportés et consignés** : volumes assemblés (deux blocs de hauteurs différentes, Bauhaus et minimaliste s'en passent pour l'instant), orientation solaire et scénario climatique (le Bioclimatique garde des brise-soleil fixes, sans calcul).

## 1. Bandeaux et murs-rideaux — AG-090

Réglage `facade.ribbon` : `"band"` ou `"curtain"` ; absent, baies par travée. Aux **étages** (le rez-de-chaussée garde sa porte et ses baies), chaque façade avant et arrière reçoit **une seule baie par niveau**, de la marge à la marge (`kind = ribbon`) :

| Réglage | Hauteur |
|---|---|
| `band` | La hauteur et l'allège des fenêtres du style |
| `curtain` | De 0,15 m au-dessus du plancher à 0,15 m sous le plafond (dalle déduite) |

Montants verticaux de 0,05 m tous les `facade.window_width_m` (au moins 0,8 m) dans le cadre ; avec le vitrage, une vitre par module. Volets, encadrements, petits bois et arcs ne s'appliquent qu'aux baies par travée, donc au rez-de-chaussée ; une baie en bandeau en reste nue. Une corniche ou une génoise refusent un mur-rideau qui monte trop haut (refus existants).

## 2. Pilotis — AG-091

Option `features.pilotis` (booléen) : le **rez-de-chaussée est ouvert**, sans murs ni baies ; le bâtiment repose sur des poteaux de 0,30 × 0,30 m aux angles et à chaque limite de travée, avant et arrière ; une sous-face ferme le dessous du premier étage. Il faut deux niveaux au moins (`pilotis_levels`). L'entrée se fait par-dessous : pas de porte. Incompatible avec un commerce (`pilotis_with_shop`). En rangée, les voisins s'appuient sur le rez-de-chaussée : les pilotis y sont **omis et dits** (`W_DETAIL`, `pilotis_in_row`) — d'abord prévus comme un refus, changé en AG-094 pour qu'un style à pilotis puisse faire une rue.

## 3. Toit en sheds — AG-092

Type de toit `"sawtooth"` : des dents successives de l'avant vers l'arrière, chacune avec une face verticale vitrée (si le vitrage est coché, sinon matière des cadres) tournée vers l'arrière et un pan incliné à `pitch_deg` ; largeur de dent 4 m (départ), le nombre arrondi à l'entier pour couvrir la profondeur. Bâtiment seul et rangée.

## 4. Trame structurelle et brise-soleil — AG-093

- `features.structural_grid` : bandeaux de plancher de 0,30 m et poteaux de 0,30 m aux limites de travée, en saillie de 0,10 m, façade avant et arrière, matière du mur ; les poteaux sautent les baies en bandeau.
- `features.sun_shades` : une casquette de 0,60 m de saillie et 0,08 m d'épaisseur au-dessus de chaque fenêtre et de chaque bandeau, façade avant ; matière des cadres.

## 5. Profils et panneaux — AG-094

| Profil | Traits |
|---|---|
| **Bauhaus** | Enduit blanc, 3 niveaux, toit plat, bandeaux |
| **Moderniste** | Béton clair, 4 niveaux, pilotis, bandeaux, toit plat |
| **Mid-century** | Brique, 2 niveaux, grands vitrages en bandeau, toit plat à débord 1,00 m |
| **Contemporain minimaliste** | Enduit blanc, 3 niveaux, murs-rideaux aux étages, toit plat |
| **Industriel** | Brique rouge, 2 niveaux hauts, toit en sheds, porte de 2,40 m (3,50 m ne tenait pas dans une travée de rue) |
| **High-tech** | Métal sombre, 5 niveaux, murs-rideaux, trame structurelle, toit plat |
| **Bioclimatique** | Bois naturel en bardage, 3 niveaux, brise-soleil, deux pans |

Liste « Baies » (par travée, bandeau, mur-rideau) et cases Pilotis, Trame structurelle, Brise-soleil aux panneaux ; type de toit Sheds. **RBZ 0.18.0** ; recette **H33** à la main.

- **Fait (AG-090 à AG-094).** `opening_solver` (bandeaux bornés aux dégagements d'about, pour les angles biais), `wall_builder` (pilotis : cellules sous le premier plancher omises, face basse en Structural, poteaux, sous-face en Shell), `roof_solver.sawtooth` (bords sur les murs latéraux, onglets compris), `geometry/modern_solver`. Le test commun U52 a fait corriger avant publication : mur-rideau minimaliste trop haut au rez-de-chaussée, plafond de niveaux du High-tech, porte industrielle trop large pour une travée de rue. RBZ 0.18.0. **Recette H33 dans SketchUp non faite.**

## Tests

- **U58** bandeaux et murs-rideaux ; **U59** pilotis ; **U60** sheds ; **U61** trame et brise-soleil ; **U52** étendu aux sept profils.
