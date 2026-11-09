# Journal des versions

## Non publié

**Ajouts**

- **Génoises** : option `features.genoise`, deux rangs de tuiles en encorbellement sous l'égout, avant et arrière, sur deux pans et croupe ; pas encore de case au panneau (AG-074).

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
