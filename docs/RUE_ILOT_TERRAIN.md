# Rue, îlots et terrain — besoin préparatoire

Besoin exprimé par le propriétaire le 05/11/2026. **Hors périmètre V0.1** (voir [PRD](PRD.md)) : à réaliser après J5, sans dépendance inverse. Ce document cadre le besoin ; il ne vaut pas contrat. Chaque capacité recevra un contrat pur, une fixture et une mesure de charge avant son code, comme le demande [FUTURE](FUTURE.md). Les valeurs marquées « départ » sont des propositions à calibrer.

## 1. Générateur de rue et d'îlot au tracé (EXT-07)

**Résultat attendu.** Créer des rues, des pâtés de maisons et des quartiers en traçant une ligne dans la vue, comme on trace des murs avec l'outil Mur connecté de YSKE, au lieu de placer les bâtiments un par un.

**Geste de référence.** Repris de `agen-sketchup/src/yske/tools/mur_tool.rb` :

- clic de départ, puis clic par sommet, ou saisie `longueur` / `longueur;angle` dans la boîte de mesure ;
- chaque segment part de la fin du précédent ;
- flèches pour bloquer un axe, Ctrl pour le côté du tracé, Alt pour verrouiller 90° ;
- cliquer le premier point ferme la forme ; Échap ou double-clic termine sur une forme ouverte.

**Forme ouverte : rue.** Le tracé donne un alignement de façades, d'un seul côté ou des deux côtés d'une largeur de rue. Il est découpé en parcelles, avec un bâtiment par parcelle.

**Forme fermée : îlot.** Le tracé donne le contour de l'îlot. Les façades regardent la rue, les arrières la cour intérieure. **La fermeture génère automatiquement 1 à 3 ouvertures donnant accès à la cour** : une cour sans accès n'est jamais produite.

Règles proposées pour les ouvertures, à valider :

| Point | Proposition |
|---|---|
| Nombre | 1 à 3, réglable ; par défaut selon le périmètre (départ : 1 sous 80 m, 2 sous 160 m, 3 au-delà). |
| Position | Déterministe par seed, jamais dans un angle, réparties sur des côtés différents quand c'est possible. |
| Gabarit | Départ : 3,5 m de large et 3,5 m de haut. Valeur de conception, pas une règle d'accès pompiers ou d'urbanisme. |
| Infaisable | Si aucune ouverture ne tient (îlot trop petit, côtés trop courts), le tracé est refusé avec un diagnostic sur le segment concerné. Pas d'îlot fermé par défaut. |

**Contraintes de conception.**

- Le noyau reste pur : polyligne en mètres → parcelles → configurations → plans. Seul l'outil de tracé (`Sketchup::Tool`, dans l'adaptateur) touche au natif.
- Mêmes tracé, réglages et seed ⇒ même résultat ; la seed de chaque parcelle dérive de celle de l'îlot par une clé stable.
- Une validation réussie du tracé = **une seule opération Undo**, quel que soit le nombre de bâtiments. Un tracé rejeté laisse le document intact.
- Les contraintes restent bloquantes : segments trop courts, auto-intersection, parcelles qui se chevauchent, budgets. Diagnostic localisé par segment ou parcelle.
- Le tracé et ses réglages sont persistés pour pouvoir modifier un îlot sans le refaire. Une parcelle modifiée ne touche pas ses voisines, et la géométrie partagée n'est jamais modifiée sur place.

**Capacités manquantes aujourd'hui.**

| Capacité | Écart avec la V0.1 |
|---|---|
| Racine d'ensemble | ADR-04 fixe une racine par bâtiment ; un îlot demande une racine qui porte le tracé et ses parcelles, avec le contrôle des copies. |
| Angles | L'emprise est rectangulaire ; un angle non droit exige une parcelle d'angle non rectangulaire (D-03). |
| Mitoyenneté | Les façades et toitures sont calculées pour un bâtiment isolé ; un mur mitoyen n'a ni baies ni débord, et ses faces cachées sont à écarter. |
| Passage traversant | Une ouverture sur plusieurs niveaux ou sous un bâtiment n'existe pas au contrat (D-04). |
| Budgets | Les limites actuelles s'appliquent à un bâtiment ; il faut un budget d'ensemble et une génération mesurée (partage des définitions, découpage éventuel en lots). |

## 2. Adaptation au terrain et terrassement (EXT-10)

**Résultat attendu.** L'outil s'adapte aux terrains accidentés : si le sol est incliné ou irrégulier sous une construction, sa base est terrassée.

**Fonctionnement proposé.**

1. L'adaptateur relève les altitudes du terrain sous chaque emprise. Le noyau ne reçoit qu'une grille d'altitudes en mètres et ne connaît jamais d'objet SketchUp.
2. Le noyau calcule une assise par construction : plateforme horizontale, altitude (départ : moyenne des points relevés), déblai, remblai, soubassement visible et talus.
3. Le bâtiment reste calculé sur une base plane puis posé sur son assise : sa géométrie et ses tests actuels ne changent pas.
4. Le long d'une rue en pente, chaque parcelle a sa propre plateforme : les bâtiments s'étagent et le raccord entre deux parcelles est traité par le soubassement.

**Contraintes.**

- L'aperçu indique les hauteurs de déblai et de remblai avant toute écriture.
- Au-delà d'une dénivelée maximale (limite à fixer), la construction est refusée avec un diagnostic localisé, sans adaptation silencieuse.
- Terrain absent, troué ou ambigu : refus localisé, sans altitude inventée. Générer sur un plan horizontal reste un choix explicite.
- Un Annuler ramène le terrain à l'identique, y compris s'il a été modifié (D-05).
- Pas d'étude géotechnique : le terrassement est une représentation, comme Structural n'est pas un calcul porteur.

**Dépendances.** Le terrain concerne d'abord un bâtiment seul, puis EXT-07 l'applique par parcelle. L'import de terrain géospatial reste en EXT-09 et n'est pas nécessaire : un terrain déjà présent dans le modèle suffit.

## 3. Décisions à trancher

Reprises dans [DECISIONS](DECISIONS.md) : D-03 (angles), D-04 (forme des ouvertures), D-05 (terrain modifié ou non), D-06 (ordre de réalisation).

## 4. Découpage prévisionnel

Chaque ticket apporte son contrat, ses tests et sa preuve hôte. Numérotation et ordre à confirmer à l'ouverture de J6.

| Ticket | Dépend de | Livrable |
|---|---|---|
| EXT-07.1 Contrat de tracé | J5, D-03 | Polyligne, fermeture, auto-intersection, découpe en parcelles ; noyau pur et fixtures. |
| EXT-07.2 Racine d'ensemble | EXT-07.1 | Format versionné de l'îlot, persistance, une opération Undo, copies. |
| EXT-07.3 Mitoyenneté et angles | EXT-07.1 | Murs mitoyens, parcelles d'angle, budget d'ensemble. |
| EXT-07.4 Ouvertures de cour | EXT-07.3, D-04 | 1 à 3 accès déterministes, refus si infaisable. |
| EXT-07.5 Outil de tracé | EXT-07.2 | `Sketchup::Tool` au geste YSKE, aperçu dans la vue, recette hôte. |
| EXT-10.1 Relevé et assise | J5, D-05 | Grille d'altitudes, plateforme, déblai/remblai, limites ; noyau pur. |
| EXT-10.2 Écriture du terrassement | EXT-10.1 | Soubassement et talus, Undo, recette sur terrain réel. |
| EXT-10.3 Terrain par parcelle | EXT-07.5, EXT-10.2 | Étagement le long d'une rue en pente. |
