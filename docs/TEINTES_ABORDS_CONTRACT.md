# Contrat des teintes et des abords — J20 (AG-104 à AG-108)

**Demande du propriétaire (2026-11-10).** « On fait tout ce qui est non fait » (limites du guide : escaliers et rampes, talus entre voisins, garde-corps, tour d'îlot, existant sans dalle) ; « un truc super facile pour varier la couleur des murs, portes… car dans une ville rien n'est si lisse ». L'intérieur (EXT-05) et les emprises non rectangulaires sont des chantiers à part : J21 et J22, puis EXT-06, 12, 09 et 08 dans cet ordre. Détails selon ADR-48 ; teintes en ADR-51.

Chaque réglage est une clé facultative : absente, le plan est inchangé (empreintes des ensembles types identiques).

## 1. Teintes — AG-104

Réglage `facade.tint` : entier de 1 à 3 (légères, marquées, fortes) ; « Toutes pareilles » (0) n'est pas écrit. Il est rangé sous `facade` et non sous `materials`, dont toutes les valeurs sont des identifiants du catalogue.

- Une seule liste **Teintes** au panneau du bâtiment et à celui de la rue. Une parcelle suit la rue.
- Chaque bâtiment tire, avec sa seed, une variante de chacun de ses matériaux de **mur**, de **menuiserie** et de **volets**, et une pour sa **porte d'entrée**, distincte des fenêtres. Dans une rue, chaque parcelle a sa seed : les maisons voisines diffèrent.
- Variante : `id~n` avec n de 1 à 8 et le niveau dans la clé (`id~2.5`), soit au plus 8 variantes par matériau et par niveau. La couleur se calcule à partir du sRGB du catalogue (`Core::Tint`, pur) : clarté ± 4 % par niveau, saturation et teinte légèrement décalées. Toit, vitre et sol ne varient pas.
- Le validateur de plan accepte `id~L.n` si `id` est au catalogue ; les ressources SketchUp créent le matériau « ARCHGEN Pierre (teinte 2.5) », marqué et réutilisé comme les autres.

- **Fait (AG-104).** `core/tint` (variantes, couleur), `GeometryEngine` (entrée teintée), porte à part dans `DetailSolver.frames`, seed gardée par `ParcelBuilding.share_key`, catalogue étendu dans `PlanValidator` et `Resources`. Empreintes des quatre ensembles types identiques.

## 2. Escaliers et rampes — AG-105

Aujourd'hui un seuil à plus de 20 cm du sol est signalé, pas résolu. Désormais, devant une porte d'entrée dont le seuil dépasse le sol fini :

- jusqu'à 0,05 m : rien (le seuil de 0,03 m suffit) ;
- au-delà, selon le réglage du terrain `site.entrance` :
  - `steps` : un **perron** de marches égales de 0,17 m au plus (giron 0,28 m), la dernière au niveau du seuil, de la largeur de la porte + 0,15 m de chaque côté ;
  - `ramp` : un palier de 1,20 m devant la porte, puis une rampe de 5 % le long de la façade, du côté le plus long ; refus `ramp_too_long` si la façade n'offre pas la longueur ;
  - `none` : rien, l'avertissement du seuil haut reste.
- Matière du soubassement, dans le plan d'assise (catégorie `plinth`). Le perron et la rampe ne connaissent pas les voies : dans une rue sans recul, ils sont sur le trottoir.
- `entrance` est écrit à `steps` quand on adapte au terrain (valeur de départ de l'assise) ; absent d'un terrain enregistré, il n'est pas exigé et rien ne change.

- **Fait (AG-105).** `SitePlanner.entrance_nodes` (marches, palier, rampe), `SiteIntake` (défaut, clé facultative à la relecture), listes **Devant la porte** aux panneaux du bâtiment et de la rue.

## 3. Garde-corps — AG-106

Selon `features.balcony_rail`, un balcon reçoit sur ses trois côtés libres un garde-corps de 1,00 m :

- `bars` : main courante de 0,05 m et barreaux carrés de 0,02 m tous les 0,12 m environ, une seule définition partagée, matière des menuiseries ;
- `solid` : muret de 0,10 m, matière du mur.

« Aucun » n'est pas écrit. Absente, le balcon reste tel quel. Comme la dalle (ADR-50), `bars` est écrit à la création d'un bâtiment ou d'une rue ; il ne compte que s'il y a des balcons. Le toit-terrasse accessible n'existe pas encore : rien n'y est ajouté.

- **Fait (AG-106).** `DetailSolver.balcony_rails` (bande intérieure au contour, onglets compris), liste **Garde-corps des balcons** au panneau du bâtiment.

## 4. Tour d'îlot — AG-107 ; talus entre voisins — AG-109

- Sur un terrain, deux parcelles voisines dont les plateformes diffèrent sont raccordées par un **talus** (pente 1 / 1,5 au plus) ou, faute de place, par un **mur de soutènement** de la matière du soubassement, entre leurs limites.
- Dans un îlot à hauteurs variées, le contrôle d'écart avec la voisine porte aussi sur la dernière et la première parcelle du tour : chaque tirage reste à `restant × écart` au plus de la première parcelle.

- **Fait (AG-107, tour d'îlot).** `EnsembleVariety.closing`. Correction de comportement : un îlot varié d'avant peut changer de hauteurs à sa prochaine régénération.
- **Talus, renvoyé à AG-109.** Il demande un relevé devant et derrière chaque parcelle (aujourd'hui limité à la parcelle) et un mur de soutènement au droit de chaque limite mitoyenne entre deux talus, simple seulement sur une rue droite. Il reste refusé (`embankment_in_row`).

## 5. Existant, version — AG-108

Case **Dalle de rez-de-chaussée et seuils** au panneau de rue : une rue d'avant peut la recevoir ; décochée, rien ne s'écrit. Guide (dont la ligne « pas de vitrage », périmée depuis J11), journal, **RBZ 0.21.0** ; recette **H36** à la main.

- **Fait (AG-108).** Case au panneau de rue, gabarit de départ avec la dalle ; RBZ 0.21.0. **Recette H36 dans SketchUp non faite.**

## Tests

U69 teintes ; U70 perron et rampe ; U71 garde-corps ; U72 tour d'îlot.
