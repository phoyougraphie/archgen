# Contrat des styles régionaux maçonnés — J13 (AG-074 à AG-078)

**Demande du propriétaire (2026-11-09).** « On les fait tous, en créant les éléments nécessaires au fur et à mesure » : tous les styles du [catalogue](../examples/style-catalogue.v1.json), plus des régionaux faisables avec l'existant. Le propriétaire délègue les choix de détail (ADR-48) : chaque contrat de lot retient les options recommandées, les consigne, et reste révisable par lui.

## Plan d'ensemble des lots

Un style n'est publié qu'avec les capacités qu'il requiert, chacune livrée et testée avant lui (AGENTS, règle 5). Les lots vont du moins au plus de géométrie nouvelle ; chacun a son contrat écrit au moment de le commencer.

| Lot | Capacités nouvelles | Styles |
|---|---|---|
| **J13 — Régionaux maçonnés** (ce contrat) | Génoises ; matières régionales | Provençal (mas, maison de village), Breton (longère, maison de bourg), Lyonnais, Bordelais (échoppe), Parisien faubourien |
| J14 — Pignon sur rue et montagne | Axe de faîtage perpendiculaire à la rue, pignon à redents, grands débords, bardage bois | Flamand, Savoyard |
| J15 — Pan de bois (EXT-02) | Ossature apparente, encorbellement | Maison à colombages, Normand, Alsacien, Basque |
| J16 — Arcs et ornements (EXT-03) | Arc plein cintre et brisé, meneaux, ordres, fronton, avant-corps, reliefs, baies courbes, patio | Roman, Gothique, Renaissance, Néoclassique, Baroque, Art déco, Art nouveau, Méditerranéen (variantes cycladique, andalouse) |
| J17 — Volumes modernes (EXT-04) | Volumes assemblés, mur-rideau, fenêtres en bandeau, pilotis, sheds, trame structurelle, protections solaires | Bauhaus, Moderniste, Mid-century, Contemporain minimaliste, Industriel, High-tech, Bioclimatique |

**Variantes régionales.** Le catalogue demande de distinguer, par exemple, longère et maison de bourg bretonnes. Une variante est un **profil à part** de la même famille, nommé « Breton — longère » : aucune capacité `regional_variant` n'est nécessaire, et chaque variante garde ses calibrages et règles.

## 1. Génoises — AG-074

Option `features.genoise` (booléen), LOD 1 ; décochée, non écrite (refus `genoise_false_written`).

| Élément | Géométrie (départ) |
|---|---|
| **Rangs** | Deux rangs de tuiles en encorbellement sous l'égout, façades avant et arrière : rang du haut de z = H − 0,10 à H, en saillie de 0,16 m ; rang du bas de H − 0,20 à H − 0,10, en saillie de 0,08 m. Matière `materials.roof` (terre cuite) |
| **Étendue** | D'un bout de la façade à l'autre ; en rangée d'angle, coupée à l'onglet en façade avant comme la corniche, raccourcie de sa saillie à chaque bout en façade arrière |
| **Toits** | Deux pans et croupe seulement ; sur un toit plat ou une mansarde, rien et un avertissement `W_DETAIL` (`genoise_roof`) |
| **Refus** | Avec une corniche : `genoise_with_cornice` sur `/features/genoise`. Une fenêtre dont la tête passe au-dessus de H − 0,30 : `genoise_head_margin`, avec son id |

- **Fait (AG-074).** Le rang du haut s'arrête sous la peau du toit prolongée au droit de sa saillie (H − pente × 0,16) : rien ne traverse le toit. Catégorie `genoise`. Tests U51 (`test/unit/genoise_test.rb`) ; empreintes des ensembles types identiques. Pas de case au panneau avant AG-078.

## 2. Matières régionales — avec AG-075

Nouvelles entrées du catalogue : enduit ocre, enduit clair, pierre blonde, pierre dorée (Lyon), granit, schiste, ardoise, tuile mécanique, bois peint gris, bois peint rouge basque (pour J15). Couleurs moyennes, sans texture.

## 3. Profils — AG-075 à AG-077

Calibrages du catalogue (niveaux ; hauteur d'étage ; pente) et règles historiques (`level_count`, `roof_type`, `window_ratio`, `material_allowed`) pour chaque profil.

| Profil | Volume et toit | Matières | Détails cochés |
|---|---|---|---|
| **Provençal — mas** (AG-075) | 2 niveaux de 2,8 m, deux pans à 22°, débord 0,10 | Enduit ocre, tuile canal, bois peint | Génoise, volets (vert), petits bois, vitrage, cheminées |
| **Provençal — maison de village** | 3 niveaux de 2,9 m, deux pans à 22° | Enduit clair, tuile canal | Génoise, volets (bleu pastel), petits bois, vitrage |
| **Breton — longère** (AG-076) | 1 niveau de 2,6 m, deux pans à 45°, façade large et peu profonde | Granit, ardoise | Lucarnes, cheminées, petits bois, vitrage |
| **Breton — maison de bourg** | 2 niveaux de 2,8 m, deux pans à 45° | Schiste ou granit enduit, ardoise | Lucarnes, cheminées, encadrements, petits bois, vitrage |
| **Lyonnais** (AG-077) | 5 niveaux de 3,0 m, deux pans à 20°, fenêtres hautes | Pierre dorée, tuile canal | Encadrements, petits bois, vitrage, volets (gris) |
| **Bordelais — échoppe** | 1 niveau de 3,6 m, toit plat caché, corniche | Pierre blonde | Corniche, encadrements, petits bois, vitrage |
| **Parisien faubourien** | 4 niveaux de 2,9 m, deux pans à 30° | Enduit clair, tuile mécanique | Encadrements, volets (gris), petits bois, vitrage |

- Formes d'accès d'îlot : porche pour Lyonnais et Parisien faubourien ; accès par interruption pour les autres.
- Chaque profil est vérifié par défaut en bâtiment seul (deux modes, LOD 0 et 1), en rue droite, en rue à angle et en îlot, avant d'être publié.

## 4. Panneaux et version — AG-078

Le panneau propose déjà tous les styles actifs ; la liste devient longue : groupement par famille (« Vernaculaire maçonné », « Façade ordonnancée », « Moderne modulaire »). Case Génoise dans les trois panneaux. Guide, journal ; **RBZ 0.14.0** ; recette **H29** à la main.

## Tests

- **U51** génoises : rangs et saillies, toits pris en charge, refus et avertissement, rangée d'angle.
- **U52** profils régionaux : chaque profil valide, ses règles, ses défauts en bâtiment, rue et îlot sous le budget.
- Ensembles types d'avant : mêmes empreintes.

## Hors périmètre

Les lots J14 à J17 (contrats à écrire au moment de les commencer) ; textures photographiques ; génoise sur pignon.
