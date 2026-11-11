# Journal des versions

## 0.32.0

Balcons d'angle, bow-windows, bâtiments en L, T et U (AG-137 à AG-139 ; ADR-65, ADR-66).

**Ajouts**

- **Balcons qui tournent l'angle** sur un bâtiment seul ou isolé.
- **Bow-windows** sur la travée centrale ou les travées des bouts.
- **Forme** du bâtiment : rectangle, L, T ou U (ailes vers le jardin).
- **Import de carte** : les bâtiments en L, T et U ne sont plus ignorés.

## 0.31.0

Attique, garde-corps vitré, bâtiments isolés (AG-135, AG-136 ; ADR-63, ADR-64).

**Ajouts**

- **Retrait de l'attique** : le dernier niveau recule sur une terrasse bordée d'un garde-corps.
- **Garde-corps vitré** pour les balcons.
- **Bâtiments isolés sur leur terrain** dans une rue ou un îlot : écart aux limites, retrait sur rue, jardin autour.
- Le style **Côtier — front de mer** prend un attique de 2,5 m et des garde-corps vitrés.

## 0.30.0

Front de mer recadré sur photos (AG-134, ADR-62).

**Changements**

- **Côtier — front de mer** : balcons de 1,8 m à barreaux blancs, baies de 2,0 m, rez-de-chaussée commerçant de 3,6 m quand on le coche.
- Option **Profondeur des balcons** (0,6 à 2,5 m) au panneau du bâtiment.

## 0.29.0

Styles côtiers et maison moderne (AG-133, ADR-61).

**Ajouts**

- **Côtier — front de mer (La Baule)** : immeuble blanc de huit niveaux, balcons filants à chaque étage, toit plat.
- **Maison individuelle moderne** : enduit blanc, bardage bois à l'étage, grandes baies, toit plat.
- **Côtier — villa balnéaire (La Baule, Pornichet)** : pignon pentu sur rue, pan de bois à l'étage, ardoise, cheminées.
- Option **Étages des balcons** : 2e et 5e niveaux (comme avant) ou tous les étages.

## 0.28.0

Carrefour sur un virage (AG-132, ADR-60).

**Changements**

- **Un carrefour peut toucher un virage** : la branche est redressée jusqu'au bout du carrefour, puis la voie rejoint sa courbe. Seul un virage très serré juste après le carrefour (plus de 45°) reste refusé. Les rues d'une carte importées en réseau sont donc moins souvent refusées.

## 0.27.0

Fond de plan à l'échelle (AG-131, ADR-59), essayé dans SketchUp.

**Ajouts**

- **Fond de plan (carte et photo) autour du point géolocalisé** : tuiles OpenStreetMap (emprises des bâtiments) et photo aérienne IGN, à plat, à l'échelle, au nord du modèle, sur deux balises à allumer ou éteindre. Images gardées en cache, une entrée d'Annuler.

## 0.26.0

Import de carte en mode simple (AG-130, ADR-58), essayé dans SketchUp sur 400 m de centre-ville.

**Ajouts**

- **Importer rues et bâtiments autour du point géolocalisé** : un clic après Fichier → Ajouter un emplacement ; taille et style ; résumé ; un Annuler.
- **Toutes les rues** posées à plat à leur largeur, sans carrefour calculé : 301 sur 314 voies dans l'extrait d'essai, contre 10 en réseaux.

**Corrections**

- Au-delà de 300 bâtiments, les plus proches du centre sont gardés au lieu de tout refuser.
- L'extrait est enregistré sans dialogue (Documents\ARCHGEN pour un modèle non enregistré) ; une erreur de téléchargement s'affiche au lieu d'aller en silence dans la console.
- L'import suit le nord du modèle géolocalisé.

## 0.25.0

Cartographie (AG-125 à AG-129, ADR-56, ADR-57). Recette H40 dans SketchUp à faire.

**Ajouts**

- **Importer une carte** : extrait OpenStreetMap téléchargé par ARCHGEN (Overpass, après confirmation, seule l'emprise est envoyée, fichier gardé à côté du modèle) ou fichier `.osm` / GeoJSON local.
- **Voies** en réseaux ARCHGEN par type de voie ; **bâtiments** en rectangles orientés vers la voie ; **terrain IGN** ASCII Grid en Lambert-93, recalé (échelle, convergence).
- Aperçu chiffré avant écriture, une seule entrée d'Annuler, attribution gardée sur le composant « ARCHGEN Carte ».

## 0.24.0

Mobilier urbain (AG-120 à AG-124, ADR-55). Recette H39 dans SketchUp à faire.

**Ajouts**

- **Bancs, corbeilles et attaches vélos** dans la coupe des voies ; nombre d'arceaux réglable.
- **Pose à des positions** : distances depuis le début de la voie, pour tout objet posé à l'unité, lampadaires compris ; voies seules et réseaux.
- **Arrêt de bus** : abri vitré au fond du trottoir, ouvert vers la chaussée, ou mât seul ; zigzag jaune sur la voie voisine ; trottoir de 1,6 m exigé ; proximité d'un arbre ou d'un lampadaire signalée.
- **Huit panneaux** sans texte, tournés dans le sens choisi.
- **Éditeur de voie** : champs Positions, Pose, Sens et Arceaux ; dessins dans la coupe ; type « Rue avec arrêt de bus ».

## 0.23.0

Décor de jeu (AG-115 à AG-119, ADR-54). Recette H38 dans SketchUp et Unreal à faire.

**Ajouts**

- **Exporter pour un moteur de jeu** au clic droit d'un bâtiment ou d'une rue : trois fichiers glTF binaires (`_LOD0`, `_LOD1`, `_LOD2`), en mètres, axe Y en haut.
- **Matériaux PBR** : couleur du catalogue et teintes, verre transparent, zinc et métal foncé métalliques ; UV à 1 m.
- **Collision** convexe `UCX_` par bâtiment dans le LOD0 ; volume simple au LOD2.
- **Rue** : une maison par objet, avec son assise ; plans répétés stockés une fois ; terrain et routes non exportés.
- Le catalogue des matières accepte `roughness` et `metallic`, facultatifs.

## 0.22.0

Talus dans une rue (AG-109). Recette H36 dans SketchUp à faire.

**Ajouts**

- **Talus en rangée droite** : talus devant et derrière chaque maison, et sur le côté libre des bouts ; mur de soutènement sur chaque limite mitoyenne entre deux plateformes ; relevé élargi devant et derrière. Rue à angle et îlot refusés (`embankment_bend`).

## 0.21.0

Teintes et abords (AG-104 à AG-108). Recette H36 dans SketchUp à faire.

**Ajouts**

- **Teintes** : chaque bâtiment tire une nuance de ses murs, menuiseries, volets et de sa porte ; voisines différentes dans une rue (AG-104, ADR-51).
- **Perron ou rampe** devant une porte au-dessus du terrain (AG-105).
- **Garde-corps des balcons**, à barreaux ou plein (AG-106).
- **Dalle et seuils** possibles sur une rue d'avant, par une case du panneau de rue (AG-108).

**Corrections**

- **Tour d'îlot** : la dernière parcelle d'un contour fermé respecte aussi l'écart de hauteur avec la première (AG-107). Un îlot varié d'avant peut changer de hauteurs à sa prochaine régénération.

## 0.20.0

Carrefours sans réseau, dalle et seuils (AG-100 à AG-103). Recette H35 dans SketchUp à faire.

**Ajouts**

- **Carrefours depuis Tracer une voie** : une voie qui en touche d'autres forme avec elles un réseau et ses carrefours, en une opération (AG-102).
- **Dalle de rez-de-chaussée et seuils** pour ce qui est créé ; l'existant garde son plan (AG-100, ADR-50).

**Corrections**

- **Carrefours en T** : un bout posé sur la chaussée de l'autre voie, ou qui la dépasse un peu, fait un T ; il fallait le poser à 1 m de son axe (AG-101).

## 0.19.0

Ville mixte (AG-095 à AG-099). Moteur de géométrie 1 inchangé ; l'existant garde son plan. Recette H34 dans SketchUp à faire.

**Ajouts**

- **Clic droit Modifier** : sur un bâtiment seul et sur une rue (AG-095).
- **Plusieurs styles dans une rue** : style propre d'un bâtiment, révision figée (AG-096, ADR-49).
- **Rez-de-chaussée variés** : porte, largeur des fenêtres et part de commerces tirées par bâtiment (AG-097).
- **Stores bannes et pergolas** devant les commerces ; toiles rouge, verte, beige (AG-098).
- **Panneaux** : Devanture, Rez-de-chaussée variés, Part de commerces, Style du bâtiment (AG-099).

## 0.18.0

Volumes modernes (AG-090 à AG-094). Moteur de géométrie 1 inchangé ; l'existant garde son style et son plan. Recettes H26 à H33 dans SketchUp à faire.

**Ajouts**

- **Bandeaux et murs-rideaux** : `facade.ribbon`, une baie par étage de marge à marge, montants et vitres par module (AG-090).
- **Pilotis** : `features.pilotis`, rez-de-chaussée ouvert sur poteaux, sous-face ; omis et dits en rangée (AG-091).
- **Toit en sheds** : type de toit `sawtooth`, jours vitrés tournés vers l'arrière, bâtiment seul et rangée (AG-092).
- **Trame structurelle et brise-soleil** : `features.structural_grid`, `features.sun_shades` (AG-093).
- **Sept styles** : Bauhaus, Moderniste, Mid-century, Contemporain minimaliste, Industriel, High-tech, Bioclimatique ; liste Baies et cases aux panneaux (AG-094).

**Limites connues**

- Volumes assemblés et scénario climatique reportés.

## 0.17.0

Arcs et ornements (AG-086 à AG-089). Moteur de géométrie 1 inchangé ; l'existant garde son style et son plan. Recettes H26 à H32 dans SketchUp à faire.

**Ajouts**

- **Arcs** : `facade.arch` plein cintre ou brisé, écoinçons devant le haut des baies (AG-086).
- **Ornements classiques** : `features.classical`, pilastres, soubassement, fronton d'entrée (AG-087).
- **Neuf styles** : maison romane, maison gothique, Renaissance, Néoclassique, Baroque, Art déco, Art nouveau, Méditerranéen cycladique et andalou (AG-088).
- **Panneaux** : liste Arcs, case Ornements classiques (AG-089).

**Limites connues**

- Approchés : avant-corps baroque, reliefs Art déco, courbes Art nouveau, patio andalou. Reportés : gradins, oriels, voûtes.

## 0.16.0

Pan de bois (AG-083 à AG-085). Moteur de géométrie 1 inchangé ; un bâtiment ou un ensemble existant garde son style et son plan. Recettes H26 à H31 dans SketchUp à faire.

**Ajouts**

- **Pan de bois apparent** : option `features.timber_frame`, sablières, poteaux, huisseries et écharpes aux étages, matière `materials.timber` (AG-083).
- **Maison à colombages, Normand, Alsacien, Basque** : quatre styles de la famille « Ossature bois traditionnelle » (AG-084).
- **Panneaux** : case Pan de bois et son matériau aux trois panneaux (AG-085).

**Limites connues**

- Pas encore d'encorbellement (étages en saillie), reporté.

## 0.15.0

Pignon sur rue et montagne (AG-079 à AG-082). Moteur de géométrie 1 inchangé ; un bâtiment ou un ensemble existant garde son style et son plan. Recettes H26 à H30 dans SketchUp à faire.

**Ajouts**

- **Flamand, Savoyard — chalet** : deux styles ; liste Faîtage et cases Pignon à redents et Bardage aux panneaux (AG-082).
- **Faîtage perpendiculaire** : `roof.ridge: perpendicular`, pignon sur rue pour un toit à deux pans, en bâtiment seul et en rangée ; une parcelle d'angle garde un faîtage parallèle et le dit (AG-079).
- **Pignon à redents** : option `features.stepped_gable`, marches au-dessus du toit sur le pignon avant (AG-080).
- **Bardage bois** : option `features.cladding`, dernier niveau, pignons et balcons en bois ; matières bois naturel, bois sombre, brique rouge (AG-081).

## 0.14.0

Styles régionaux maçonnés (AG-074 à AG-078). Moteur de géométrie 1 inchangé ; un bâtiment ou un ensemble existant garde son style et son plan. Recettes H26 à H29 dans SketchUp à faire.

**Ajouts**

- **Panneaux** : styles groupés par famille ; case Génoise aux panneaux du bâtiment, de la rue et de la parcelle (AG-078).
- **Génoises** : option `features.genoise`, deux rangs de tuiles en encorbellement sous l'égout, avant et arrière, sur deux pans et croupe ; pas encore de case au panneau (AG-074).
- **Provençal** : styles « Provençal — mas » et « Provençal — maison de village » ; dix matières régionales (enduits ocre et clair, pierres blonde et dorée, granit, schiste, ardoise, tuile mécanique, bois peints gris et rouge) (AG-075).
- **Breton** : styles « Breton — longère » et « Breton — maison de bourg », granit ou schiste et ardoise, lucarnes et cheminées (AG-076).
- **Lyonnais, Bordelais — échoppe, Parisien faubourien** : trois styles de plus ; formes d'accès d'îlot par porche (Lyonnais, faubourien) ou par interruption (échoppe) (AG-077).

## 0.13.0

Volets, lucarnes et petits bois (AG-070 à AG-073). Moteur de géométrie 1 inchangé ; un bâtiment ou un ensemble existant garde sa révision de style et son plan. Recettes H26 à H28 dans SketchUp à faire.

**Ajouts**

- **Révision 3 des styles** : Haussmannien avec lucarnes et petits bois ; Toulousain avec volets bleu pastel et petits bois ; cases Petits bois, Volets, Lucarnes aux panneaux du bâtiment, de la rue et de la parcelle (AG-073).
- **Petits bois** : option `features.muntins` avec le vitrage, montant central et traverses, rangs donnés par le style ; pas encore de case au panneau (AG-070).
- **Volets** : option `features.shutters`, deux battants ouverts par fenêtre, plaqués au mur ; matière `materials.shutters`, avec deux teintes nouvelles (vert, bleu pastel) ; refus quand la place manque ; pas encore de case au panneau (AG-071).
- **Lucarnes** : option `features.dormers`, une par travée de la façade avant, sur mansarde, deux pans et croupe, posée sans percer le toit ; aucune sur un toit plat ; pas encore de case au panneau (AG-072).

## 0.12.0

Personnaliser un bâtiment d'une rue (AG-068, AG-069). Moteur de géométrie 1 inchangé ; un ensemble sans réglage propre garde son plan. Recettes H26 et H27 dans SketchUp à faire.

**Ajouts**

- **Personnaliser ce bâtiment** : dans une rue ou un îlot ouvert, clic droit sur un bâtiment, puis ARCHGEN → Personnaliser ce bâtiment ; niveaux, toit, commerce et sa hauteur, cheminées, vitrage, largeur ; valeur de la rue en grisé et retour à la rue par champ ; une entrée d'Annuler « ARCHGEN : personnaliser un bâtiment » (AG-069).
- **Réglages propres d'une parcelle** (format) : clé `parcels` d'une rue ou d'un îlot ; la largeur se prend sur la voisine du même côté (AG-068).
- **Panneau de rue** : nombre de bâtiments personnalisés, case pour retirer tous leurs réglages propres (AG-069).

## 0.11.0

Détails de bâtiment (AG-064 à AG-067) : vitrage, rez-de-chaussée commerçant, cheminées. Moteur de géométrie 1 inchangé ; un bâtiment, une rue ou un îlot existants gardent leur plan. Recette H26 dans SketchUp à faire.

**Ajouts**

- **Vitrage** : vitre dans chaque fenêtre, porte pleine, imposte vitrée au-dessus d'une porte haute, au niveau de détail 1. Nouvelle révision des styles Haussmannien, Toulousain et Brutaliste, vitrée ; un bâtiment, une rue ou un îlot existants gardent leur révision et ne changent pas (AG-064).
- **Rez-de-chaussée commerçant** : réglage `ground_floor: shop`, une vitrine par travée entre trumeaux, entrée de l'immeuble gardée, bandeau d'enseigne, porte vitrée avec le vitrage ; rue entière en commerce, porche respecté. (AG-065).
- **Section Détails aux panneaux** : cases Vitrage, Cheminées, Commerce au rez-de-chaussée et sa hauteur, dans le panneau du bâtiment et dans celui de la rue (pour toute la rue) (AG-067).
- **Cheminées** : option `features.chimneys`, une ou deux souches par bâtiment, contre les murs latéraux ou au bout du faîtage d'une croupe, au niveau de détail 1 (AG-066).

## 0.10.0

Rues variées (AG-061 à AG-063), clous et plots (AG-060), variation des baies (D-01). Testée sur Windows 11 avec SketchUp 2026 (26.2.243) seulement. Moteur de voirie 1 inchangé ; un ensemble sans réglage `variety` garde son plan. Le rapport de recette est dans [docs/recette/V0.10.md](docs/recette/V0.10.md).

**Ajouts**

- **Panneau de rue variée** : dans Tracer une rue et Modifier l'ensemble sélectionné, case Varier les bâtiments, fourchette de niveaux, écart entre voisines, toits à tirer (ceux du style proposés, les autres marqués hors style) et graine ; le résultat annonce le tirage avant d'écrire (AG-063).
- **Rues variées, tirage** : réglage `variety` d'une rue ou d'un îlot ; nombre de niveaux tiré par parcelle dans une fourchette, à 2 niveaux au plus de sa voisine, toit tiré dans une liste ; règles du style respectées (AG-061 ; panneau en AG-063). Toits contre un voisin plus haut, pignons de toits différents et murs mitoyens découverts vérifiés (AG-062).
- **Plots de chaussée** : nouvel élément d'une voie, d'une bande d'arrêt ou dérasée, posé sur la limite gauche de sa bande, blanc ou rétroréfléchissant, tous les 12 m par défaut (D-10).
- **Variation des baies utilisable** : le décalage des fenêtres est arrondi à 5 mm, et n'est plus refusé (avant, 1 % des graines passaient à 2 cm) ; seules les configurations qui s'en servent changent (D-01).
- **Clous de passage piéton** : case d'un carrefour à feux ; deux rangées de clous de part et d'autre de chaque passage (D-10).

**Corrections**

- Les avertissements de style d'une rue ou d'un îlot (toit ou nombre de niveaux qui s'écartent du style, en fidélité plausible) n'étaient jamais affichés ; ils le sont, une fois par message.

**Limites connues**

- Un style par rue. Dans un îlot, la dernière parcelle du tour n'est comparée qu'à sa précédente : l'écart avec la première peut dépasser l'écart choisi. Pas de baie sur un mur mitoyen découvert.

## 0.9.0

Ponts (AG-057 à AG-059). Testée sur Windows 11 avec SketchUp 2026 (26.2.243) seulement. Moteur de géométrie 1 et moteur de voirie 1 inchangés : bâtiments, ensembles, voies et réseaux sans pont identiques. Le rapport de recette est dans [docs/recette/V0.9.md](docs/recette/V0.9.md).

**Ajouts**

- **Pont à poutre** dans un réseau de voies : né tout seul sur un cours d'eau, au choix sur une voie ferrée ou une route ; la voie portée monte en rampes jusqu'au tablier, avec culées et garde-corps ; les cours d'eau entrent dans un réseau (AG-057).
- **Arc et voûte** : arc parabolique à montants, voûte de pierre à arches de 20 m au plus et piles ; le gabarit sous l'ouvrage est contrôlé, et un refus donne la hauteur libre qui suffit (AG-058).
- **Panneau de réseau** : type Pont, genre, voie portée, hauteur libre et pente des rampes ; rivières, canaux et côtes s'ajoutent au réseau, l'eau se voit en plan ; un réseau refusé garde sa liste de carrefours pour corriger (AG-059).

**Limites connues**

- Réseau horizontal : pas de pont sur un terrain. Deux cours d'eau ne se rejoignent pas. Sous le tablier, tous les objets de la voie franchie sont retirés. Garde-corps en parois pleines, portes et montants simplifiés.

## 0.8.0

Eau et littoral (EXT-13). Testée sur Windows 11 avec SketchUp 2026 (26.2.243) seulement. Moteur de géométrie 1 et moteur de voirie 1 inchangés : bâtiments, ensembles, voies et réseaux sans eau identiques. Le rapport de recette est dans [docs/recette/V0.8.md](docs/recette/V0.8.md).

**Ajouts**

- **Bandes d'eau** : plan d'eau (revanche et profondeur réglables), quai, berge naturelle ; surface de l'eau transparente au-dessus du lit. Préréglages canal, rivière et fleuve (AG-051).
- **Littoral** : falaise, estran rocheux, dune, plage et mer (fond à 3 m, atteint sur 10 m depuis le rivage), à niveaux cumulés de la terre vers la mer ; ganivelles et murets. Préréglages côte à falaises, côte à dunes, plage et promenade (AG-052).
- **Canal à écluses sur un terrain** : biefs plats, écluse posée par règle dès que le terrain s'écarte de plus de la chute (3 m par défaut) ; chambre au niveau bas, mur de chute, portes, chemin de halage en rampe (AG-054).
- **Fleuve et côte sur un terrain** : à un seul niveau, saisi ou au plus bas du terrain ; pas de talus côté mer (AG-055).
- **Rivière sur un terrain** : tracée de l'amont vers l'aval, l'eau ne remonte jamais ; là où le terrain remonte, la rivière creuse, dans la limite de 6 m (AG-053).
- **Panneau** : réglages de bande (revanche, profondeur, hauteur, pente) sous chaque bande, régime de l'eau et ses réglages dans Tracer une voie ; l'aperçu annonce la chute et les écluses (AG-056).

**Limites connues**

- Un canal sur un terrain est bordé de quais, et ses portes sont des battants droits ; au-delà de la mer, un terrain plus haut reste en place et forme un mur ; un cours d'eau n'entre pas dans un réseau (ponts : AG-057).

## 0.7.0

Voies sur un terrain et passages à niveau. Testée sur Windows 11 avec SketchUp 2026 (26.2.243) seulement. Moteur de géométrie 1 et moteur de voirie 1 inchangés : bâtiments, ensembles, voies horizontales et réseaux sans passage à niveau identiques. Le rapport de recette est dans [docs/recette/V0.7.md](docs/recette/V0.7.md).

**Ajouts**

- **Tracer une voie → Suivre le terrain** : retenir un terrain, le relever, poser la voie dessus. Profil en long à pente bornée (8 % ; 6 % pour un tram, 2,5 % pour une voie ferrée), talus jusqu'au terrain, objets à la cote de la voie ; pente, déblai et remblai annoncés avant de créer.
- **Le terrain d'origine n'est jamais modifié** : il est masqué, et une copie entaillée le long de la voie le remplace à l'écran (ADR-38). Annuler rend l'original ; modifier la voie refait la copie depuis l'original.
- **Passage à niveau** dans le panneau de réseau : la route monte par deux rampes (4 % par défaut, 2 à 8 %) jusqu'au ras des rails, avec murets, feux de passage et barrières ; la voie ferrée reste entière.

**Limites connues**

- Un réseau de voies reste horizontal ; seule une voie seule suit un terrain.
- Le bord de l'entaille suit le terrain au pas du relevé (4 m) : quelques centimètres d'écart possibles ; aux deux bouts de la voie, l'entaille est coupée droit.
- Une voie posée sur un terrain garde ce terrain : la case ne change rien en modification ; une telle voie ne doit pas être tournée.
- Effacer la voie à la main ne réaffiche pas le terrain d'origine : **Édition → Afficher**.
- Au passage à niveau, le bord du platelage reste ouvert au-dessus de la voie ferrée.

## 0.6.0

Réseaux de voies et carrefours : on trace plusieurs voies, les carrefours naissent là où elles se croisent ou se touchent, et chacun se règle en simple, à feux, giratoire ou double giratoire ; le tram les traverse. Testée sur Windows 11 avec SketchUp 2026 (26.2.243) seulement. Moteur de géométrie 1 et moteur de voirie 1 inchangés : bâtiments, ensembles et voies seules identiques. Le rapport de recette est dans [docs/recette/V0.6.md](docs/recette/V0.6.md).

**Ajouts**

- **Extensions → ARCHGEN → Tracer un réseau de voies** : voies tracées une à une avec leur type, carrefours détectés tout seuls, vue en plan avant de créer.
- Carrefour simple : bordures arrondies, onglet du côté extérieur d'un virage, trottoirs qui tournent l'angle, murets aux changements de niveau, surface sans trou ni recouvrement.
- Carrefour à feux : passages piétons, lignes d'arrêt sur les voies qui entrent, un feu tricolore par branche à chaussée.
- Giratoire : anneau, îlot central planté, îlots séparateurs, entrées arrondies ; double giratoire sur deux carrefours voisins.
- Tram au carrefour : rails continus au ras à travers le carrefour, l'anneau et l'îlot central.
- **Modifier le réseau sélectionné** : changer le type et les rayons des carrefours, retirer une voie. Une création ou un remplacement = une entrée d'Annuler.

**Limites connues**

- Pas d'échangeur : une autoroute ne se croise pas à niveau. Pas de passage à niveau tant que la voie ne suit pas un relief (AG-049, AG-050).
- Une voie s'ajoute en traçant un nouveau réseau ; la modification règle les carrefours et retire des voies.
- Pas de courbe de rails ni de marquage de priorité ; une plateforme tram s'abaisse au carrefour avec un muret de 5 cm.
- Les largeurs et rayons sont des valeurs de conception, pas une vérification réglementaire.

## 0.5.0

Voirie : composer une coupe à l'échelle humaine et tracer une voie, de l'autoroute au chemin piéton, rails compris. Testée sur Windows 11 avec SketchUp 2026 (26.2.243) seulement. Moteur de géométrie 1 inchangé : bâtiments et ensembles identiques. Moteur de voirie 1. Le rapport de recette est dans [docs/recette/V0.5.md](docs/recette/V0.5.md).

**Ajouts**

- **Extensions → ARCHGEN → Tracer une voie** : coupe à composer (onze types de départ, bandes, largeurs, ordre, éléments), à l'échelle d'un personnage de 1,75 m ; tracé dans la vue au clic ou au clavier, rayon des virages, axe au milieu ou sur un bord ; aperçu de la longueur, des objets et des faces avant de créer.
- Chaussée, trottoirs et bordures, pistes, stationnement, terre-pleins, accotements, fossés et talus, suivis exactement en droite, en courbe et à l'angle vif.
- Arbres, lampadaires, potelets et poteaux de caténaire au pas choisi, en volumes simples partagés ; haies, barrières et glissières continues avec leurs poteaux ; arbres de trois hauteurs au choix.
- Rails de tram au ras de la chaussée ou de la plateforme, voie ferrée sur traverses et ballast, écartement de 1,435 m.
- Une balise par famille : chaussée et trottoirs, végétation, éclairage, mobilier et clôtures, rails.
- **Modifier la voie sélectionnée** : changer la coupe, le rayon ou l'axe ; le tracé est gardé. Une création ou un remplacement = une entrée d'Annuler.

**Limites connues**

- Voie horizontale : elle ne suit pas encore un terrain. Pas de carrefour : une voie qui se recouvre est refusée.
- Pas de marquage au sol, de passage piéton, de gorge de rail, ni de fil de caténaire.
- Un seul rayon pour tous les sommets d'une nouvelle voie.
- Les largeurs sont des valeurs de conception, pas une vérification réglementaire.
## 0.4.0

Étagement d'une rue ou d'un îlot sur un terrain déjà présent dans le modèle. Testée sur Windows 11 avec SketchUp 2026 (26.2.243) seulement. Moteur de géométrie 1, inchangé : les plans des bâtiments et des ensembles restent identiques. Le rapport de recette est dans [docs/recette/V0.4.md](docs/recette/V0.4.md).

**Ajouts**

- Section Terrain dans **Modifier l'ensemble sélectionné** : retenir un terrain, relever, adapter, retirer l'assise.
- Une plateforme par parcelle, au point haut ou à la moyenne de la parcelle, avec décalage. Les bâtiments s'étagent, et le soubassement ferme la marche entre deux voisins.
- Altitudes, ressaut, remblai et déblai annoncés avant d'écrire ; porte ou passage enterrés refusés, seuils hauts signalés.
- Les bâtiments identiques restent partagés dans le fichier : la pente ne multiplie que les assises.
- Une action = une entrée d'Annuler ; le terrain n'est jamais modifié. Remplacer un ensemble adapté garde son assise et relit le terrain.

**Limites connues**

- Soubassement seulement : un talus déborderait chez le voisin, il est refusé.
- Pas d'escalier ni de rampe : sur une pente, un seuil ou un passage peut rester au-dessus du sol, et c'est signalé.
- Le relevé traverse tout ce qui est au-dessus du terrain : compter le temps mesuré dans le rapport sur une grande rue.
- Une modification du terrain n'est vue qu'au relevé suivant, et seulement si elle touche un point du relevé.
- Autres versions de SketchUp et macOS non testés ; extension non signée.

## 0.3.0

Rues et îlots au tracé. Testée sur Windows 11 avec SketchUp 2026 (26.2.243) seulement. Moteur de géométrie 1, inchangé : les plans des bâtiments seuls restent identiques. Le rapport de recette est dans [docs/recette/V0.3.md](docs/recette/V0.3.md).

**Ajouts**

- Menu **Tracer une rue** : une ligne tracée dans la vue au geste du Mur connecté de YSKE, à la souris ou au clavier, parcelles visibles pendant le tracé.
- Forme ouverte : une rue, d'un côté ou des deux. Forme fermée : un îlot, avec 1 à 3 accès à la cour.
- Angles libres : parcelles d'angle en onglet, toits et corniches raccordés.
- Accès à la cour selon le style : porche pour Haussmannien et Toulousain, interruption pour Brutaliste.
- Une validation = une entrée d'Annuler, quel que soit le nombre de bâtiments. Bâtiments identiques partagés dans le fichier.
- Menu **Modifier l'ensemble sélectionné** : changer les réglages et remplacer tout l'ensemble.

**Limites connues**

- Pas de chaussée, de trottoir, de carrefour ni de réseau de rues ; pas de collision testée avec le reste du modèle.
- Tous les bâtiments d'un ensemble ont le même gabarit. Une parcelle seule ne se modifie pas, et le tracé ne se modifie pas : on en trace un autre.
- Pas d'assise sur terrain pour un ensemble : le tracé est horizontal. Levé en 0.4.0.
- Murs mitoyens doublés en Structural. Pas de fenêtre sur les murs de fin de rangée.
- Porche de 2,7 m de haut par défaut : c'est ce que permet le rez-de-chaussée des styles livrés.
- Un tracé dont tous les segments ont des longueurs différentes partage peu : 14 à 17 s pour 76 bâtiments en Structural LOD 1.
- Autres versions de SketchUp et macOS non testés ; extension non signée.

## 0.2.0

Adaptation d'un bâtiment à un terrain déjà présent dans le modèle. Testée sur Windows 11 avec SketchUp 2026 (26.2.243) seulement. Moteur de géométrie 1, inchangé : les plans des bâtiments restent identiques. Le rapport de recette est dans [docs/recette/V0.2.md](docs/recette/V0.2.md).

**Ajouts**

- Section Terrain dans le panneau, en édition : retenir un terrain, relever, adapter, retirer l'assise.
- Plateforme au point haut ou à la moyenne, avec décalage ; soubassement ou talus ; plancher.
- Déblai et remblai annoncés avant d'écrire ; porte enterrée refusée, porte haute signalée.
- Une action = une entrée d'Annuler ; le terrain n'est jamais modifié.
- Régénérer un bâtiment adapté garde son assise et relit le terrain à son emplacement actuel.

**Corrections**

- Après plusieurs fermetures et réouvertures du panneau, Générer pouvait annoncer un bâtiment créé sans rien écrire : une ancienne réponse était rejouée. Défaut présent depuis la 0.1.0, trouvé par la recette H14.

**Limites connues**

- Le terrain n'est pas creusé : un déblai est annoncé mais pas montré, et le terrain traverse alors le bâtiment.
- Pas d'escalier, de rampe ni de mur de soutènement. Sur une pente, la plateforme au point haut laisse souvent la porte au-dessus du sol.
- Une modification du terrain n'est vue qu'au relevé suivant, et seulement si elle touche un point du relevé.
- Autres versions de SketchUp et macOS non testés ; extension non signée ; bouton du Gestionnaire d'extensions non conservé au redémarrage sur le poste de test.

## 0.1.0

Première version, testée sur Windows 11 avec SketchUp 2026 (26.2.243) seulement. Moteur de géométrie 1, catalogue de matériaux 1. Le rapport de recette est dans [docs/recette/V0.1.md](docs/recette/V0.1.md).

**Ajouts**

- Menu Extensions → ARCHGEN : « Nouveau bâtiment » et « Modifier le bâtiment sélectionné ».
- Trois styles : haussmannien, toulousain et brutaliste.
- Deux modes : Shell (surfaces) et Structural (murs épais, dalles).
- Deux niveaux de détail : LOD 0 (volume) et LOD 1 (cadres, corniche, balcon, encadrements selon le style).
- Toits plat, à deux pans, à croupe et mansarde ; matériaux unis embarqués.
- Aperçu 2D calculé par le moteur, sans écriture dans le modèle.
- Régénération d'un bâtiment après confirmation, en conservant sa place, son nom et ses tags ; une copie n'est pas affectée.
- Une action réussie donne une seule entrée d'Annuler ; un refus ou une panne laisse le document intact.

**Limites connues**

- Autres versions de SketchUp et macOS non testés.
- Extension non signée.
- Le bouton Enabled/Disabled du Gestionnaire d'extensions n'a pas été conservé au redémarrage sur le poste de test (voir le guide).
- Le champ « Variation des baies » est le plus souvent refusé dès qu'il n'est pas nul (décision D-01 ouverte).
- Pas de terrain, de rue, d'îlot, d'intérieur ni de vitrage.
