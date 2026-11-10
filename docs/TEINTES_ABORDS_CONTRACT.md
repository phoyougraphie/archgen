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

- jusqu'à 0,02 m : rien ;
- au-delà : un **perron** de marches de 0,17 m au plus (giron 0,28 m), de la largeur de la porte + 0,30 m, posé sur le sol devant la porte ;
- réglage `features.entrance` : `steps` (défaut quand la clé manque et qu'un seuil dépasse) ou `ramp` (rampe de pente 5 % au plus, palier de 1,20 m ; refus localisé si elle ne tient pas dans le recul devant la façade). Dans une rue, le recul est la marge avant de la parcelle.
- Les marches ne débordent jamais sur une voie ARCHGEN : sinon avertissement et marches omises.

## 3. Garde-corps — AG-106

Chaque balcon reçoit un garde-corps de 1,00 m : main courante et barreaux (matière des menuiseries), ou plein (matière du mur) selon `features.balcony_rail` : `bars` (défaut) ou `solid`. Le toit-terrasse accessible n'existe pas encore : rien n'y est ajouté.

## 4. Talus entre voisins, tour d'îlot — AG-107

- Sur un terrain, deux parcelles voisines dont les plateformes diffèrent sont raccordées par un **talus** (pente 1 / 1,5 au plus) ou, faute de place, par un **mur de soutènement** de la matière du soubassement, entre leurs limites.
- Dans un îlot à hauteurs variées, le contrôle d'écart avec la voisine porte aussi sur la dernière et la première parcelle du tour.

## 5. Existant, version — AG-108

Case **Dalle et seuils** au panneau de rue : une rue d'avant peut la recevoir. Guide (dont la ligne « pas de vitrage », périmée depuis J11), journal, **RBZ 0.21.0** ; recette **H36** à la main.

## Tests

U69 teintes ; U70 perron et rampe ; U71 garde-corps ; U72 talus et tour d'îlot.
