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
- **Aucun escalier n'est généré.** Si le seuil est à plus de 20 cm du sol, un avertissement le signale. Une porte enterrée est refusée : remontez la plateforme ou changez la travée d'entrée.
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

**Modifier :** sélectionnez l'ensemble, puis **Extensions → ARCHGEN → Modifier l'ensemble sélectionné**. Changez les réglages, puis cliquez sur **Remplacer cet ensemble**. Toute sa géométrie est remplacée, ses bâtiments compris. Le tracé ne change pas : pour le changer, tracez-en un autre. Une copie garde sa géométrie jusqu'à sa propre modification.

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

**Limites.** Soubassement seulement, pas de talus entre voisins. Pas d'escalier ni de rampe : un seuil haut est signalé, pas résolu. Un terrain modifié n'est vu qu'au relevé suivant.

## Tracer une voie

**Extensions → ARCHGEN → Tracer une voie.** Le panneau s'ouvre et l'outil de tracé est actif.

1. **Composez la coupe.** Partez d'un type de voie : autoroute, route de campagne à fossés, boulevard planté, rue tram et voitures, voie ferrée double, chemin piéton… Les bandes se lisent de gauche à droite dans le sens du tracé. Ajoutez-en une après la bande choisie, retirez-la, déplacez-la avec les flèches, ou inversez tout avec **Miroir**. Tapez une largeur, ou glissez la poignée bleue sous la limite de deux bandes. Sur la bande choisie, ajoutez arbres, lampadaires, haies, barrières, glissières, potelets ou poteaux de caténaire, avec leur hauteur et leur pas.
2. **Tracez dans la vue.** Cliquez le départ, puis un point par sommet, ou tapez « longueur » ou « longueur;angle » dans la boîte de mesure. Les flèches bloquent un axe, Alt l'angle droit. Double-clic ou Échap pour finir ; Échap sur un tracé terminé l'efface.
3. **Réglez le tracé.** Le rayon des virages vaut pour chaque sommet, 0 pour un angle vif. Le tracé peut suivre le milieu de la coupe ou l'un de ses bords. Le panneau annonce la longueur, les objets et les faces ; un rayon trop serré pour la largeur est refusé avec le minimum à respecter.
4. **Cliquez sur Créer la voie.** Une seule entrée d'Annuler retire tout. L'outil reste actif pour une autre voie.

Glissez le personnage le long de la coupe pour juger l'échelle ; décochez **Gabarits de véhicules** pour masquer voitures, bus, tram et train.

**Modifier :** sélectionnez la voie, puis **Extensions → ARCHGEN → Modifier la voie sélectionnée**, et cliquez sur **Recharger la sélection**. Changez la coupe, le rayon (vide : chaque sommet garde le sien) ou l'axe, puis cliquez sur **Remplacer cette voie**. Le tracé ne change pas. Une copie garde sa géométrie.

**À savoir**

- **Balises :** ARCHGEN Voirie chaussée et trottoirs, végétation, éclairage, mobilier et clôtures, rails : masquez une famille d'un clic.
- **Refus :** rayon trop petit pour la largeur, virages plus longs que leur segment, demi-tour, angle vif où le bord intérieur se replierait, voie qui se recouvre elle-même.
- **Limites :** 64 points, 5 000 objets, 20 000 traverses, 60 000 faces distinctes et 600 000 faces au total.
- **Temps :** 2 km de boulevard planté s'écrivent en moins d'une demi-seconde, 2 km de voie ferrée double en moins de 3 s.
- **Hors de portée :** la voie est horizontale et ne suit pas un terrain ; pas de carrefour, de marquage, de passage piéton ni de fil de caténaire. Les largeurs sont des valeurs de conception, pas une vérification du code de la route ni des normes.
## Reproduire

La même configuration, la même graine et les mêmes versions donnent le même plan. Les réglages sont enregistrés dans le fichier SKP et retrouvés à sa réouverture.

## Exporter

SketchUp réalise l'export ; ses formats dépendent de votre édition. Le parcours vérifié est le **Shell LOD 0 en OBJ vers Blender 5.2** :

1. **Fichier → Exporter → Modèle 3D**, format OBJ, unités **mètres**. L'OBJ ne contient aucune unité : avec les unités du modèle, un gabarit en millimètres donne un bâtiment 1 000 fois trop grand dans Blender.
2. Dans Blender : **Fichier → Importer → Wavefront (.obj)**, axe avant Y, axe haut Z, échelle 1.

Dans cet export, les espaces et les accents des noms de matériaux deviennent `_`, par exemple `ARCHGEN_B_ton_brut`, et l'import Blender donne un seul objet. Aucune garantie n'est donnée pour les UV, les moteurs de jeu ou les collisions.

## Limites de cette version

- Emprise rectangulaire et ouvertures rectangulaires. Pas d'intérieur, de vitrage ni de garde-corps.
- Pas de calcul de structure ni de conformité réglementaire. Les styles sont des simplifications, pas des restitutions historiques.
- Le champ « Variation des baies » est le plus souvent refusé dès qu'il n'est pas nul ; le message propose de changer la graine ou la variation.
- Les anciennes définitions restent dans le fichier après une régénération, pour permettre Annuler. **Fenêtre → Infos sur le modèle → Statistiques → Purger les éléments inutilisés** les retire.
- Le plus grand bâtiment accepté bloque SketchUp environ 5 à 6 secondes sur le poste de test.

## Désinstaller

**Extensions → Extension Manager**, puis **Uninstall** sur ARCHGEN. Les bâtiments déjà créés restent dans vos fichiers comme des composants ordinaires.
