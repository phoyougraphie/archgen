# Guide d'utilisation — ARCHGEN 0.3.0

ARCHGEN génère dans SketchUp un bâtiment paramétrique, ou toute une rue ou un îlot à partir d'une ligne tracée, que vous pouvez ensuite déplacer, copier et régénérer à partir de leurs réglages.

**Configuration testée :** Windows 11 avec SketchUp 2026 (26.2.243). Les autres versions et macOS n'ont pas été testés et ne sont pas garantis.

## Installer

1. Ouvrez **Extensions → Extension Manager**, puis **Install Extension**.
2. Choisissez `archgen-0.3.0.rbz` et acceptez l'installation. L'extension n'est pas signée : si vos réglages de chargement n'autorisent que les extensions identifiées, SketchUp refuse de l'activer. Changez ce réglage dans le Gestionnaire d'extensions seulement si vous faites confiance à ce fichier.
3. Le menu **Extensions → ARCHGEN** apparaît.

L'extension fonctionne hors ligne et n'envoie aucune donnée.

**Activer ou désactiver :** sur le poste de test, le bouton Enabled/Disabled du Gestionnaire agit dans la session, mais n'a pas été conservé au redémarrage suivant. Si ARCHGEN reste désactivé, ouvrez **Extensions → Développeur → Console Ruby**, tapez `Sketchup.extensions['ARCHGEN'].check`, puis quittez SketchUp normalement. Pour le désactiver durablement, utilisez `uncheck` de la même façon.

## Créer un bâtiment

1. **Extensions → ARCHGEN → Nouveau bâtiment**.
2. Choisissez un style : le toit, les baies et les matériaux suivent ce style, et vos dimensions déjà saisies sont gardées.
3. Réglez les dimensions, les niveaux et les travées. La section **Avancé** donne accès aux baies, à la toiture, aux matériaux, aux détails et à la graine.
4. Choisissez le mode et le niveau de détail :

| Réglage | Valeur | Résultat |
|---|---|---|
| Mode | Shell | Façades en surface simple : léger, ce n'est pas un volume fermé |
| Mode | Structural | Murs épais, tableaux et dalles : une représentation, pas un calcul de structure |
| Détail | LOD 0 | Volume et ouvertures |
| Détail | LOD 1 | Ajoute les détails du style : cadres, corniche, balcon, encadrements |

L'aperçu à droite est recalculé à chaque changement, sans rien écrire dans le modèle. Un réglage impossible est expliqué sous son champ et dans le résumé « À corriger », et Générer reste désactivé tant qu'il n'est pas corrigé. Un avertissement n'empêche pas de générer.

5. Cliquez sur **Générer**. Le bâtiment est créé à l'origine du modèle et sélectionné : déplacez-le et faites-le pivoter avec les outils de SketchUp. **Annuler** retire la création en une fois.

**Détails (niveau de détail 1) :** la section **Détails** propose **Vitrage** (une vitre dans chaque fenêtre, une porte pleine, une imposte vitrée au-dessus d'une porte haute), **Cheminées** (une ou deux souches, contre les murs de côté ou au bout du faîtage d'une croupe) et **Commerce au rez-de-chaussée** : une vitrine par travée de la façade avant, la porte de l'immeuble gardée, un bandeau d'enseigne au-dessus. Cocher Commerce fait paraître **Hauteur du commerce** : vide, elle vient du style (4,5 m en Haussmannien, 4,0 m ailleurs). Une travée trop étroite pour une vitrine de 1,20 m est refusée et expliquée. **Petits bois** (avec le vitrage) partage chaque fenêtre en deux vantaux et en carreaux ; **Volets** pose deux battants ouverts contre le mur de part et d'autre de chaque fenêtre, dans le matériau choisi (bois peint, vert ou bleu pastel) ; **Lucarnes** pose une lucarne par travée de la façade avant, sur une mansarde, un toit à deux pans ou une croupe (aucune sur un toit plat). Faute de place, un réglage est refusé et expliqué ; une lucarne contre une croupe ou l'angle d'une parcelle, ou des volets contre un passage de porche, sont omis et signalés. Depuis la version 0.13.0, l'Haussmannien coche lucarnes et petits bois, le Toulousain volets bleu pastel et petits bois ; un bâtiment ou une rue créés avant gardent leurs réglages. Décocher le vitrage d'un style à petits bois demande de décocher aussi les petits bois. **Génoise** pose deux rangs de tuiles sous le bord du toit, devant et derrière, sur un toit à deux pans ou une croupe.

**Styles régionaux (0.14.0) :** la liste des styles est groupée par famille. Vernaculaire maçonné : Toulousain, **Provençal — mas**, **Provençal — maison de village**, **Breton — longère**, **Breton — maison de bourg**, **Lyonnais**, **Bordelais — échoppe**, **Parisien faubourien**. Chaque style coche ses détails (génoise et volets en Provence, lucarnes et cheminées en Bretagne, volets gris à Lyon et dans les faubourgs) et propose ses proportions ; tout reste modifiable.

**Pignon sur rue et montagne (0.15.0) :** pour un toit à deux pans, la liste **Faîtage** propose **Perpendiculaire (pignon sur rue)** : le pignon fait face à la rue. Dans une rue, un bâtiment d'angle garde un faîtage parallèle et le panneau le signale. **Pignon à redents** monte le pignon avant en marches au-dessus du toit (débord de toit de 5 cm au plus). **Bardage bois** habille de bois le dernier niveau, les pignons et les balcons. Deux styles de plus : **Flamand** (brique rouge, pignon à redents) et **Savoyard — chalet** (pierre et bois, grand débord, balcon).

**Pan de bois (0.16.0) :** la case **Pan de bois** montre l'ossature des étages (sablières, poteaux, huisseries autour des fenêtres, écharpes en diagonale) sur le mur, le rez-de-chaussée restant maçonné ; le matériau se choisit (bois sombre par défaut). Elle ne se combine pas avec les encadrements, les volets, la corniche ni le bardage, qui occuperaient la même place. Quatre styles : **Maison à colombages**, **Normand**, **Alsacien**, **Basque**. Les étages en encorbellement viendront plus tard.

**Arcs et ornements (0.17.0) :** la liste **Arcs des baies** donne aux fenêtres et à la porte un haut en **plein cintre** ou en **arc brisé** (une baie trop basse pour son arc est refusée). **Ornements classiques** pose des pilastres entre les travées, un soubassement et un fronton au-dessus de l'entrée. Neuf styles : **Maison romane**, **Maison gothique**, **Renaissance**, **Néoclassique**, **Baroque**, **Art déco**, **Art nouveau**, **Méditerranéen — cycladique** et **— andalou**. Roman et Gothique sont des maisons de ville, pas des églises ; avant-corps baroque, reliefs Art déco et courbes Art nouveau sont approchés.

**Volumes modernes (0.18.0) :** la liste **Baies des étages** propose **En bandeau** (une longue fenêtre par étage) ou **Mur-rideau** (vitré du plancher au plafond) ; le rez-de-chaussée garde sa porte. **Pilotis** ouvre le rez-de-chaussée sur des poteaux (bâtiment seul ; dans une rue, ils sont omis et signalés). Le type de toit **Sheds** fait des dents vitrées. **Trame structurelle** montre poteaux et planchers en façade ; **Brise-soleil** pose une casquette au-dessus des fenêtres. Sept styles : **Bauhaus**, **Moderniste**, **Mid-century**, **Contemporain minimaliste**, **Industriel**, **High-tech**, **Bioclimatique**. Les volumes assemblés (deux blocs de hauteurs différentes) viendront plus tard.

**Teintes (0.21.0) :** la liste **Teintes** (Légères, Marquées, Fortes) donne à chaque bâtiment une nuance de ses murs, menuiseries et volets, et une autre pour sa porte d'entrée. Elle est tirée de la graine : changer la graine change les nuances. Dans une rue, chaque maison a la sienne. Le toit et les vitres ne changent pas.

**Garde-corps (0.21.0) :** un balcon reçoit un garde-corps de 1 m, à **Barreaux** (couleur des menuiseries) ou **Plein** (couleur du mur), selon la liste **Garde-corps des balcons**. Un nouveau bâtiment ou une nouvelle rue a des barreaux ; un bâtiment d'avant garde son balcon tel quel.

**Dalle et seuils (0.20.0) :** un nouveau bâtiment ou une nouvelle rue a une dalle au rez-de-chaussée et un seuil sous chaque porte d'entrée, pour qu'aucun vide ne reste entre la rue et la maison ; la case **Dalle de rez-de-chaussée et seuils** les retire. Un bâtiment créé avant garde sa géométrie.

**Ville mixte (0.19.0) :** un **clic droit** sur un bâtiment seul donne **ARCHGEN → Modifier ce bâtiment**, et sur une rue **ARCHGEN → Modifier cette rue**. Dans une rue ouverte, **Personnaliser ce bâtiment** propose maintenant un **Style** : un bâtiment peut être Flamand ou Bauhaus au milieu d'une rue haussmannienne, les autres ne changent pas. Au panneau de rue, **Rez-de-chaussée variés** tire la place de la porte et la largeur des fenêtres de chaque bâtiment, et **Part de commerces** met en commerce une partie des rez-de-chaussée (tirés, toujours les mêmes pour la même graine). **Devanture** pose un **store banne** au-dessus de chaque vitrine ou une **pergola** devant la boutique, interrompue devant la porte de l'immeuble. Les styles Haussmannien, Toulousain et Brutaliste cochent le vitrage par défaut ; un bâtiment créé avant la version 0.11.0 le garde décoché.

**Limites :** emprise de 60 × 60 m, 15 niveaux, 60 m sous toit, 90 m au sommet, 720 ouvertures. Au-delà, ARCHGEN refuse sans modifier le modèle.

## Modifier un bâtiment

1. Sélectionnez un seul bâtiment ARCHGEN, au niveau du modèle.
2. **Extensions → ARCHGEN → Modifier le bâtiment sélectionné**. Ses réglages sont relus.
3. Changez le style, le mode ou les dimensions, puis cliquez sur **Régénérer**.
4. Vérifiez la liste des changements, puis cliquez sur **Remplacer**. La confirmation reste valable 2 minutes.

La géométrie du bâtiment est **remplacée** : toute modification faite à la main à l'intérieur du composant est perdue. Sa position, son nom, son tag et les attributs d'autres extensions sont conservés. Une copie reste inchangée, même si elle partageait la même définition. **Annuler** rétablit l'état précédent en une fois.

**Cible périmée :** si la sélection change, ou après un Annuler, un Rétablir ou un changement de document, le panneau bloque la régénération. Cliquez sur **Recharger la sélection**. L'enregistrement du fichier, lui, recharge tout seul en gardant vos réglages en cours.

ARCHGEN refuse de régénérer un bâtiment mis à l'échelle ou en miroir, verrouillé, placé dans un groupe, ou créé par une version plus récente, ainsi que depuis un groupe ou un composant ouvert en édition. Le modèle n'est alors pas touché.

## Adapter un bâtiment au terrain

Le terrain doit déjà être dans le modèle, sous forme d'un **groupe ou d'un composant** au niveau du modèle, visible. Groupez-le s'il s'agit de faces libres.

1. Créez le bâtiment et placez-le au-dessus du terrain. Seules sa position en plan et sa rotation comptent : son altitude sera calculée. Il doit rester vertical.
2. Ouvrez **Modifier le bâtiment sélectionné**, puis la section **Terrain**.
3. Sélectionnez le terrain dans le modèle et cliquez sur **Retenir ce terrain**.
4. Resélectionnez le bâtiment et cliquez sur **Recharger la sélection**.
5. Réglez l'assise, puis cliquez sur **Relever**. Le panneau annonce l'altitude de la plateforme, le remblai et le déblai, sans rien écrire.
6. Cliquez sur **Adapter au terrain**, vérifiez les valeurs, puis **Remplacer**. **Annuler** défait tout en une fois.

| Réglage | Valeur | Résultat |
|---|---|---|
| Altitude de plateforme | Au point haut | Rien n'est enterré. Le côté aval reçoit un soubassement ou un talus |
| Altitude de plateforme | À la moyenne | Moins de remblai, mais le terrain traverse le bâtiment côté amont |
| Terrassement | Soubassement | Un mur vertical sous la façade, jusqu'au terrain |
| Terrassement | Talus | Une pente de terre depuis le pied du mur |
| Pas du relevé | 2 m par défaut | Plus fin, il suit mieux le terrain mais prend plus de temps |

**À savoir**

- **Le terrain n'est jamais modifié, ni creusé.** Un déblai est annoncé mais pas montré.
- **Devant la porte (0.21.0) :** si le seuil est au-dessus du terrain, un **Perron** de marches égales (0,17 m au plus) monte jusqu'à lui, ou une **Rampe** à 5 % longe la façade après un palier. Une rampe trop longue pour la façade est refusée. **Rien** garde l'ancien avertissement au-delà de 20 cm. Un terrain adapté avant garde sa géométrie jusqu'à ce qu'on le réadapte. Une porte enterrée est refusée : remontez la plateforme ou changez la travée d'entrée.
- **Limites :** 6 m de variation sous le bâtiment et 3 000 points de relevé. Au-delà, ARCHGEN refuse et dit quoi changer. Un terrain qui manque sous le bâtiment est refusé, sans altitude inventée.
- **Sur un terrain très détaillé, SketchUp se fige pendant le relevé et Windows peut afficher « Ne répond pas ».** Attendez, ne fermez pas la fenêtre, car le travail non enregistré serait perdu. Mesures sur 100 000 faces, pour chaque relevé comme pour chaque adaptation : environ 1 s pour un bâtiment de 12 × 9 m, 8 s avec un talus, 1 min à 1 min 30 pour le plus grand bâtiment. Enregistrez avant, et gardez le pas de 2 m ou plus.
- **Après un déplacement,** l'assise est signalée périmée au rechargement de la sélection. Relevez puis adaptez de nouveau. **Régénérer** relit aussi le terrain à l'emplacement actuel : l'altitude peut donc changer.
- **Si le terrain change,** ARCHGEN ne le voit qu'au relevé suivant, et seulement si la modification touche un point du relevé.
- **Enregistrer le fichier** oublie le terrain retenu mais pas encore utilisé : retenez-le de nouveau. Un bâtiment déjà adapté garde le sien.
- **Si le terrain a été supprimé ou masqué,** la régénération est refusée. Réaffichez-le, ou utilisez **Retirer l'assise**, qui ne change pas l'altitude.
- **Adapter** part des réglages enregistrés du bâtiment : régénérez d'abord si vous en avez changé.

## Tracer une rue ou un îlot

1. **Extensions → ARCHGEN → Tracer une rue**. Le panneau de rue s'ouvre et l'outil de tracé est actif.
2. Réglez le style, le mode, le niveau de détail et les parcelles. Laissez vide ce qui doit suivre le style.
3. Cliquez le départ dans la vue, puis un point par sommet, ou tapez `longueur` ou `longueur;angle` puis Entrée. L'angle se compte en degrés depuis l'axe rouge. Les parcelles se dessinent pendant le tracé, sans rien écrire.
4. **Double-clic ou Échap** termine une rue. **Cliquer le premier point** ferme un îlot.
5. Vérifiez le résultat au panneau, puis cliquez sur **Créer ces N bâtiments**. **Annuler** retire tout en une fois.

| Touche dans la vue | Effet |
|---|---|
| Ctrl | Côté bâti : à gauche du tracé, à droite, des deux côtés |
| Alt | Verrouille le quart de tour |
| Flèche droite, gauche | Bloque l'axe rouge, l'axe vert ; la même flèche débloque |
| Flèche bas | Perpendiculaire ou prolongement du segment précédent |
| Échap sur un tracé terminé | Efface le tracé |

**Un îlot a toujours un accès à sa cour :** 1 sous 80 m de périmètre, 2 sous 160 m, 3 au-delà, ou le nombre que vous choisissez. Sa forme suit le style : un porche sous un bâtiment en Haussmannien et Toulousain, une interruption entre deux bâtiments en Brutaliste. S'il n'y a pas la place, le tracé est refusé : le nombre n'est jamais réduit en silence.

**Le porche fait 2,7 m de haut par défaut**, car le rez-de-chaussée des styles livrés ne laisse que 2,8 à 2,9 m. Ce n'est pas une règle d'accès pompiers ni d'urbanisme.

**Rue variée :** cochez **Varier les bâtiments** dans la section Variété. Chaque parcelle tire alors son nombre de niveaux dans la fourchette (**Niveaux, au moins** et **au plus**), à un **écart** au plus de sa voisine (2 niveaux par défaut), et son toit parmi les cases cochées : **Toit plat**, **Deux pans**, **Mansarde**. Le panneau propose la fourchette et les toits du style ; un toit marqué « hors style » reste possible, le style le signale alors (et le refuse en fidélité stricte). Sans toit coché, chaque parcelle garde le toit du style. Le résultat annonce le tirage avant d'écrire, par exemple « de 3 à 7 niveaux, 2 toits plats, 4 mansardes ». **Une autre graine donne une autre rue** ; même graine et mêmes réglages, même rue. Les murs mitoyens découverts au-dessus d'un voisin plus bas restent aveugles. Quand la case est cochée, le champ Niveaux de la section Bâtiments est ignoré : le nombre de niveaux vient du tirage ; la Hauteur courante reste celle de chaque étage.

**Détails de toute la rue :** la section **Détails** a les mêmes cases, pour tous les bâtiments de la rue ou de l'îlot (niveau de détail 1). Une case laissée telle quelle suit le style ; une case touchée vaut pour toute la rue. Les commerces respectent le passage d'un îlot à porche. Personnaliser un seul bâtiment viendra par un clic droit.

**Personnaliser un bâtiment de la rue :** double-cliquez la rue pour l'ouvrir, faites un clic droit sur un bâtiment, puis **ARCHGEN → Personnaliser ce bâtiment**. L'édition de la rue se referme et un petit panneau s'ouvre : **niveaux**, **toit**, **rez-de-chaussée** (logement ou commerce) et **hauteur du commerce**, **cheminées**, **vitrage**, **largeur de façade**. Un champ vide prend la valeur de la rue, affichée en grisé ; **Rue** efface le réglage de ce champ, **Tout revenir au réglage de la rue** les efface tous. Une largeur propre se prend sur la voisine du même côté (6 m au moins pour elle) ; un bâtiment d'angle garde la sienne. **Appliquer** régénère la rue ; **Annuler** la rétablit en une fois. Les autres bâtiments ne bougent pas, et un tirage de rue variée reste le même. Le panneau de rue affiche le nombre de bâtiments personnalisés et peut retirer tous leurs réglages propres.

**Modifier :** sélectionnez l'ensemble, puis **Extensions → ARCHGEN → Modifier l'ensemble sélectionné**. Changez les réglages (la variété et sa graine comprises ; décocher Varier rend un seul gabarit), puis cliquez sur **Remplacer cet ensemble**. Toute sa géométrie est remplacée, ses bâtiments compris. Le tracé ne change pas : pour le changer, tracez-en un autre. Une copie garde sa géométrie jusqu'à sa propre modification.

**À savoir**

- **Refus :** un angle trop fermé pour la profondeur, un segment de moins de 6 m, un tracé qui se coupe ou une cour de moins de 3 m sont refusés, avec la cause au panneau et les parcelles en rouge.
- **Toit en croupe :** refusé dans une rangée, aucun autre toit ne lui est substitué.
- **Limites :** 64 points, 200 bâtiments, 120 000 faces distinctes et 600 000 faces au total.
- **Temps :** une rue droite partage presque tout : 200 bâtiments s'écrivent en 2 à 3 s. Un tracé dont tous les segments diffèrent partage peu : 76 bâtiments en Structural LOD 1 prennent 14 à 17 s, et SketchUp se fige pendant ce temps. Attendez, ne fermez pas la fenêtre.
- **Après coup :** on déplace ou on copie l'ensemble entier. Pour agir sur un bâtiment, il faudrait éclater l'ensemble : ses bâtiments restent, mais ne sont plus modifiables par ARCHGEN.
- **Hors de portée :** pas encore de chaussée, de trottoir ni de carrefour (en préparation, tickets AG-037 à AG-049). Le tracé est horizontal, sans adaptation au terrain, et rien ne vérifie qu'il ne traverse pas d'autres objets du modèle.

## Étager une rue ou un îlot sur un terrain

Le terrain doit déjà être dans le modèle, en un seul groupe ou composant, visible, au niveau du modèle. Le tracé reste horizontal : on trace d'abord l'ensemble, on le place au-dessus du terrain, puis on l'adapte.

1. Sélectionnez le terrain, ouvrez **Modifier l'ensemble sélectionné** s'il ne l'est pas, et cliquez sur **Retenir ce terrain**.
2. Sélectionnez l'ensemble, puis cliquez sur **Recharger la sélection**.
3. Choisissez l'altitude de plateforme, le décalage, le matériau et le pas, puis cliquez sur **Relever**. Rien n'est écrit : le panneau annonce plateformes, ressaut, remblai et déblai.
4. Cliquez sur **Adapter au terrain**. Le relevé est refait d'abord. Un Annuler retire tout en une fois.

Chaque parcelle a sa plateforme, et le soubassement ferme la marche entre deux voisins. **Le terrain n'est pas modifié.** Si le terrain dépasse une plateforme, il traverse le bâtiment. Un refus sur une seule parcelle refuse tout l'ensemble, et le message la désigne.

Remplacer un ensemble adapté garde son assise et relève de nouveau le terrain, ce qui prend le temps d'un relevé. **Retirer l'assise** ramène tous les bâtiments au niveau de l'ensemble.

**Durée.** Le relevé traverse tout ce qui est au-dessus du terrain, et SketchUp ne répond plus pendant ce temps : ne fermez pas la fenêtre. Sur une longue rue, augmentez le pas.

**Talus (0.22.0).** Sur une rangée droite, la liste **Terrassement** propose **Talus** : chaque maison a un talus devant et derrière, et sur son côté libre en bout de rangée. Entre deux voisines à des hauteurs différentes, un **mur de soutènement** ferme la limite mitoyenne, devant et derrière ; le côté mitoyen garde son soubassement. Le relevé s'étend devant et derrière les parcelles : le terrain doit les déborder. Une rue à angle ou un îlot sont refusés : choisissez Soubassement.

**Limites.** La liste **Devant les portes** pose un perron ou une rampe devant chaque porte au-dessus du terrain ; ils ne connaissent pas les voies et peuvent empiéter sur un trottoir sans recul. Un terrain modifié n'est vu qu'au relevé suivant.

## Tracer une voie

**Extensions → ARCHGEN → Tracer une voie.** Le panneau s'ouvre et l'outil de tracé est actif.

1. **Composez la coupe.** Partez d'un type de voie : autoroute, route de campagne à fossés, boulevard planté, rue tram et voitures, voie ferrée double, chemin piéton… Les bandes se lisent de gauche à droite dans le sens du tracé. Ajoutez-en une après la bande choisie, retirez-la, déplacez-la avec les flèches, ou inversez tout avec **Miroir**. Tapez une largeur, ou glissez la poignée bleue sous la limite de deux bandes. Sur la bande choisie, ajoutez arbres, lampadaires, haies, barrières, glissières, potelets ou poteaux de caténaire, avec leur hauteur et leur pas.
2. **Tracez dans la vue.** Cliquez le départ, puis un point par sommet, ou tapez « longueur » ou « longueur;angle » dans la boîte de mesure. Les flèches bloquent un axe, Alt l'angle droit. Double-clic ou Échap pour finir ; Échap sur un tracé terminé l'efface.
3. **Réglez le tracé.** Le rayon des virages vaut pour chaque sommet, 0 pour un angle vif. Le tracé peut suivre le milieu de la coupe ou l'un de ses bords. Le panneau annonce la longueur, les objets et les faces ; un rayon trop serré pour la largeur est refusé avec le minimum à respecter.
4. **Cliquez sur Créer la voie.** Une seule entrée d'Annuler retire tout. L'outil reste actif pour une autre voie.

Glissez le personnage le long de la coupe pour juger l'échelle ; décochez **Gabarits de véhicules** pour masquer voitures, bus, tram et train.

**Sur un terrain :** cochez **Suivre le terrain**, sélectionnez le terrain (un groupe ou un composant) et cliquez sur **Retenir le terrain sélectionné**, puis **Relever le terrain** une fois le tracé fini. La voie suit le terrain avec une pente bornée (8 %, 6 % pour un tram, 2,5 % pour une voie ferrée), et des talus la raccordent au terrain. À la création, le terrain d'origine est masqué, jamais modifié : ARCHGEN pose à sa place une copie entaillée le long de la voie. Annuler rend l'original. Pour le revoir après avoir effacé la voie à la main : **Édition → Afficher**.

**Eau et bord de mer :** choisissez un type tout prêt (canal, rivière, fleuve, côte à falaises, côte à dunes, plage et promenade) ou ajoutez des bandes **Plan d'eau**, **Quai**, **Berge naturelle**, **Falaise**, **Estran rocheux**, **Dune**, **Plage** et **Mer**. Sous la bande, réglez la revanche (hauteur du quai au-dessus de l'eau) et la profondeur d'un plan d'eau, la hauteur d'une falaise ou d'une dune, la pente d'une plage. La mer est toujours la première ou la dernière bande ; son fond descend à 3 m en 10 m. Une ganivelle se pose sur une dune ou une plage, un muret sur un trottoir, un chemin, un quai ou une plage. Dès qu'une bande d'eau ou de mer est là, le panneau demande le **régime de l'eau** :

| Régime | Sur un terrain | Réglages |
|---|---|---|
| Un seul niveau : fleuve, côte | Tout le tracé à une altitude : celle saisie, ou le point le plus bas du terrain. Pas de talus côté mer : le terrain au-delà de la mer reste tel quel. | Altitude du haut de la coupe |
| Rivière | Tracez de l'amont vers l'aval : l'eau descend avec le terrain sans jamais remonter, et creuse là où le terrain remonte. | Pente maximale (3 % par défaut) |
| Canal | Biefs plats ; une écluse est posée dès que le terrain s'écarte de plus d'une chute. L'aperçu donne le nombre d'écluses et leur position. Le canal doit être bordé de quais. | Chute (3 m), longueur d'une chambre (40 m) |

Sans terrain, l'eau reste à un seul niveau quel que soit le régime. Une écluse demande une ligne droite de sa chambre plus 10 m de chaque côté. Un cours d'eau ne s'ajoute pas à un réseau de voies tant que les ponts n'existent pas.

**Modifier :** sélectionnez la voie, puis **Extensions → ARCHGEN → Modifier la voie sélectionnée**, et cliquez sur **Recharger la sélection**. Changez la coupe, le rayon (vide : chaque sommet garde le sien) ou l'axe, puis cliquez sur **Remplacer cette voie**. Le tracé ne change pas. Une copie garde sa géométrie.

**À savoir**

- **Balises :** ARCHGEN Voirie chaussée et trottoirs, végétation, éclairage, mobilier et clôtures, rails : masquez une famille d'un clic.
- **Refus :** rayon trop petit pour la largeur, virages plus longs que leur segment, demi-tour, angle vif où le bord intérieur se replierait, voie qui se recouvre elle-même.
- **Limites :** 64 points, 5 000 objets, 20 000 traverses, 60 000 faces distinctes et 600 000 faces au total.
- **Temps :** 2 km de boulevard planté s'écrivent en moins d'une demi-seconde, 2 km de voie ferrée double en moins de 3 s.
- **Plots de chaussée :** ajoutez l'élément « Plot de chaussée » à une voie, une bande d'arrêt ou une bande dérasée : il se pose sur la **limite gauche** de cette bande, blanc ou rétroréfléchissant, tous les 12 m par défaut. Pour marquer la ligne entre deux voies, posez-le sur la voie de droite.
- **Balise de l'eau :** la surface de l'eau est sous la balise de la chaussée ; les portes d'écluse sous celle du mobilier.
- **Mobilier urbain (0.24.0).** Sur un trottoir, un chemin, un accotement, une bande plantée ou un terre-plein, ajoutez un **Banc**, une **Corbeille**, une **Attache vélos** (réglez le nombre d'**Arceaux**, de 1 à 10), un **Arrêt de bus** ou un **Panneau**.
  - **Pose :** au pas, comme un lampadaire, ou à des **Positions** précises. Tapez les distances en mètres depuis le début de la voie, séparées par des points-virgules : « 12 ; 48,5 ». La liste **Pose** passe d'un mode à l'autre. Un arrêt de bus et un panneau se posent toujours à des positions.
  - **Arrêt de bus :** l'abri vitré s'appuie au fond du trottoir et s'ouvre vers la chaussée. Il demande un trottoir de 1,6 m ; sinon, choisissez **Mât seul**. Un zigzag jaune de 12 m marque la voie de circulation voisine, s'il y en a une. Un arbre ou un lampadaire à moins de 2 m de l'abri est signalé.
  - **Panneau :** stop, cédez le passage, sens interdit, limitation, obligation, indication, danger ou passage piéton. Ce sont des formes et des couleurs, sans texte ni chiffre. **Sens** : vu par ceux qui suivent le tracé, ou par ceux qui viennent en face.
  - Le type **Rue avec arrêt de bus** montre tout cela d'un coup.
  - Dans un réseau, les positions se comptent sur chaque voie entière ; un objet qui tomberait dans un carrefour n'est pas posé.
- **Hors de portée :** pas de fil de caténaire ; un réseau de voies reste horizontal ; pas de pont ni de confluence ; largeur d'un cours d'eau constante. **Carrefours sans réseau (0.20.0) :** une voie tracée qui croise une voie ou un réseau ARCHGEN, ou s'arrête dessus, forme avec eux un réseau et ses carrefours ; l'aperçu l'annonce, et Annuler défait tout en une fois. Une voie qui suit le terrain ne peut pas y entrer (un réseau reste horizontal). Les largeurs sont des valeurs de conception, pas une vérification du code de la route ni des normes.
## Tracer un réseau de voies et ses carrefours

**Extensions → ARCHGEN → Tracer un réseau de voies.** Le panneau s'ouvre et l'outil de tracé est actif.

1. **Tracez une voie** dans la vue, comme une voie seule : clics ou longueurs tapées, double-clic ou Échap pour finir.
2. **Choisissez son type** (rue de ville, boulevard, route nationale, voie mixte tram et voitures…), son axe et le rayon de ses virages, puis cliquez sur **Ajouter la voie tracée**. Recommencez pour chaque voie ; la première porte l'origine du réseau.
3. **Les carrefours naissent tout seuls** là où deux voies se croisent, où l'une finit sur l'autre (n'importe où sur sa chaussée, ou en la dépassant un peu) ou où deux bouts se rejoignent. Chacun apparaît dans la liste et sur la vue en plan.
4. **Choisissez le type de chaque carrefour** : simple (bordures arrondies), à feux (passages piétons, lignes d'arrêt et un feu par branche à chaussée ; cochez **Clous aux passages piétons** pour border chaque passage de deux rangées de clous), giratoire (rayon extérieur de 13 à 60 m, anneau de 6 à 12 m), double giratoire (deux carrefours voisins sur une même voie, reliés par la voie entre eux) ou passage à niveau (une route qui traverse une voie ferrée : la route monte par deux rampes, de 4 % par défaut, jusqu'au ras des rails, avec feux et barrières). Le rayon des bordures se règle pour chacun.
5. **Cliquez sur Créer le réseau.** Toutes les voies et tous les carrefours s'écrivent en une fois ; une seule entrée d'Annuler retire tout.

**Ponts.** Ajoutez une rivière, un canal, un fleuve ou une côte comme une autre voie : là où une voie la croise, **un pont naît tout seul**, la voie passant dessus. Sur une voie ferrée ou entre deux routes, choisissez le type **Pont** pour le carrefour ; entre deux routes, indiquez la **voie portée**. Réglez le **genre** (poutre jusqu'à 40 m de portée, arc jusqu'à 120 m, voûte de pierre à arches de 20 m au plus), la **hauteur libre** sous le tablier (4,75 m au-dessus d'une route, 5,5 m d'une voie ferrée, 4 m de l'eau par défaut) et la **pente des rampes** (5 %). La voie portée monte par deux rampes jusqu'au tablier, avec culées, murs et garde-corps ; la voie franchie reste entière. Si un arc ou une voûte entre dans le gabarit d'une voie ou de l'eau, le message donne la hauteur libre qui suffit. Sous le tablier, les arbres et lampadaires de la voie franchie sont retirés. Dans un réseau, l'eau reste à un seul niveau ; deux cours d'eau ne se rejoignent pas encore.

**Modifier :** sélectionnez le réseau, puis **Extensions → ARCHGEN → Modifier le réseau sélectionné**. Changez le type ou les rayons des carrefours, ou retirez une voie (sauf la première), puis cliquez sur **Remplacer ce réseau**. Une copie garde sa géométrie. Pour ajouter une voie, tracez un nouveau réseau.

**À savoir**

- **Tram :** une voie mixte ou à plateforme traverse un carrefour ou un giratoire tout droit, rails au ras ; une voie à rails qui tourne ou finit au carrefour, ou deux voies à rails au même carrefour, sont refusées.
- **Refus :** autoroute à niveau (un échangeur viendra plus tard), voie ferrée sur ballast hors passage à niveau, passage à niveau à moins de 45°, branches à moins de 30°, carrefour dans un virage, carrefours qui se touchent, voie trop courte ; chaque refus nomme son carrefour.
- **Limites :** 24 voies par réseau, 6 branches par carrefour ; mêmes plafonds de faces et d'objets qu'une voie.
- **Hors de portée :** le réseau est horizontal (pas de pont sur un terrain) ; pas d'échangeur à bretelles, de courbe de rails ni de marquage de priorité ; pas de calcul de structure : un pont est une maquette.

## Importer une carte (0.26.0)

**Le plus simple : trois gestes.**

1. **Fichier → Ajouter un emplacement…** : cherchez l'adresse, puis cliquez sur **Définir la géolocalisation**. La carte de SketchUp montre le lieu.
2. **Extensions → ARCHGEN → Importer rues et bâtiments autour du point géolocalisé…** : choisissez la taille de la zone (400 m par défaut) et le style, puis acceptez le téléchargement. Seule la zone est envoyée à OpenStreetMap.
3. Lisez le résumé (rues, bâtiments, éléments écartés) et cliquez sur **OK**. Tout arrive d'un coup, et un seul Annuler retire tout.

**Ce que vous obtenez :**

- **Les rues** : des bandes de chaussée à plat, chacune à la largeur de son type (trottoir, rue, avenue…). La plus importante passe au-dessus aux croisements. Elles forment le composant **ARCHGEN Rues** ; pour une rue précise, tracez par-dessus une vraie voie ARCHGEN avec trottoirs et mobilier.
- **Les bâtiments** : des bâtiments ARCHGEN rectangulaires, tournés vers la rue la plus proche et modifiables au clic droit. Au-delà de 300, ce sont les plus proches du centre qui sont gardés. Les contours non rectangulaires sont écartés : ils attendent les emprises non rectangulaires.
- **Le fichier téléchargé** est gardé à côté du modèle, ou dans **Documents\ARCHGEN** si le modèle n'est pas encore enregistré.
- **Le composant ARCHGEN Carte** garde la source et l'attribution.

**Depuis un fichier :** **Extensions → ARCHGEN → Importer une carte depuis un fichier…** ouvre le panneau complet : fichier `.osm` ou GeoJSON, terrain IGN `.asc` en Lambert-93, couches.

**Licences.** Les données OpenStreetMap sont sous licence ODbL : toute image diffusée doit porter « © les contributeurs d'OpenStreetMap ». Le RGE ALTI de l'IGN est sous Licence Ouverte 2.0.

**Limites.**

- Zone de 1 000 m au plus en un clic, 2 000 m depuis le panneau.
- Les tunnels ne sont pas importés.
- La fonction « Ajouter du contexte » de SketchUp (image aérienne, bâtiments 3D) demande un abonnement SketchUp ; ARCHGEN ne s'en sert pas.

## Reproduire

La même configuration, la même graine et les mêmes versions donnent le même plan. Les réglages sont enregistrés dans le fichier SKP et retrouvés à sa réouverture.

## Exporter

SketchUp réalise l'export ; ses formats dépendent de votre édition. Le parcours vérifié est le **Shell LOD 0 en OBJ vers Blender 5.2** :

1. **Fichier → Exporter → Modèle 3D**, format OBJ, unités **mètres**. L'OBJ ne contient aucune unité : avec les unités du modèle, un gabarit en millimètres donne un bâtiment 1 000 fois trop grand dans Blender.
2. Dans Blender : **Fichier → Importer → Wavefront (.obj)**, axe avant Y, axe haut Z, échelle 1.

Dans cet export, les espaces et les accents des noms de matériaux deviennent `_`, par exemple `ARCHGEN_B_ton_brut`, et l'import Blender donne un seul objet.

### Pour un moteur de jeu (0.23.0)

1. Sélectionnez un bâtiment ou une rue ARCHGEN.
2. Faites un clic droit → **ARCHGEN → Exporter pour un moteur de jeu…**
3. Choisissez le dossier. Le nom proposé est `<nom>_LOD0.glb`.

Trois fichiers glTF binaires sont écrits côte à côte, en mètres, avec l'axe Y vers le haut :

- **`_LOD0`** : le bâtiment tel que réglé, avec sa collision, un nœud `UCX_<nom>_00` sans matériau ;
- **`_LOD1`** : le même bâtiment sans détails. Ce fichier n'est pas écrit s'il est déjà sans détails ;
- **`_LOD2`** : un volume simple, murs et toit.

**Ce que contiennent les fichiers.** Les matériaux sont de type PBR, avec la couleur du catalogue, teintes comprises. Le verre est transparent, le zinc et le métal foncé sont métalliques. Les UV sont à l'échelle 1 m : une texture répétée tous les mètres tombe à la bonne taille. Une maison répétée dans une rue n'est stockée qu'une fois.

**Pour une rue**, chaque maison est un objet, avec son assise et sa propre collision. Le terrain et les routes ne sont pas exportés. Une route ou un réseau seuls sont refusés.

**Le modèle n'est pas modifié**, et rien n'apparaît dans Annuler. L'export recalcule le bâtiment depuis ses réglages : **une retouche faite à la main dans SketchUp n'est pas exportée**.

**Dans Unreal Engine 5.8.** Importez `_LOD0.glb` en glTF, à l'échelle 1. Ouvrez le Static Mesh, puis **LOD Settings → Import LOD Level** pour ajouter `_LOD1` et `_LOD2`. Si la collision `UCX_` n'est pas reconnue, réglez **Collision Complexity** sur **Use Complex Collision As Simple**. Ces étapes n'ont pas encore été vérifiées dans Unreal (recette H38).

**Dans Blender 5.2.** **Fichier → Importer → glTF 2.0** ; l'échelle et les axes sont justes sans réglage.

## Limites de cette version

- Emprise rectangulaire et ouvertures rectangulaires. Pas d'intérieur ; des garde-corps seulement aux balcons.
- Export pour moteur de jeu : matières unies, sans textures peintes ; le terrain, les routes et les retouches manuelles ne sont pas exportés.
- Pas de calcul de structure ni de conformité réglementaire. Les styles sont des simplifications, pas des restitutions historiques.
- Le champ « Variation des baies » décale chaque fenêtre au hasard, par pas de 5 mm, d'au plus la valeur saisie ; la graine change le tirage. Une variation de moins de 5 mm ne décale rien.
- Les anciennes définitions restent dans le fichier après une régénération, pour permettre Annuler. **Fenêtre → Infos sur le modèle → Statistiques → Purger les éléments inutilisés** les retire.
- Le plus grand bâtiment accepté bloque SketchUp environ 5 à 6 secondes sur le poste de test.

## Désinstaller

**Extensions → Extension Manager**, puis **Uninstall** sur ARCHGEN. Les bâtiments déjà créés restent dans vos fichiers comme des composants ordinaires.
