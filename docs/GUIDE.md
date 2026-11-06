# Guide d'utilisation — ARCHGEN 0.1.0

ARCHGEN génère dans SketchUp un bâtiment paramétrique, que vous pouvez ensuite déplacer, copier et régénérer à partir de ses réglages.

**Configuration testée :** Windows 11 avec SketchUp 2026 (26.2.243). Les autres versions et macOS n'ont pas été testés et ne sont pas garantis.

## Installer

1. Ouvrez **Extensions → Extension Manager**, puis **Install Extension**.
2. Choisissez `archgen-0.1.0.rbz` et acceptez l'installation. L'extension n'est pas signée : si vos réglages de chargement n'autorisent que les extensions identifiées, SketchUp refuse de l'activer. Changez ce réglage dans le Gestionnaire d'extensions seulement si vous faites confiance à ce fichier.
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

## Reproduire

La même configuration, la même graine et les mêmes versions donnent le même plan. Les réglages sont enregistrés dans le fichier SKP et retrouvés à sa réouverture.

## Exporter

SketchUp réalise l'export ; ses formats dépendent de votre édition. Le parcours vérifié est le **Shell LOD 0 en OBJ vers Blender 5.2** :

1. **Fichier → Exporter → Modèle 3D**, format OBJ, unités **mètres**. L'OBJ ne contient aucune unité : avec les unités du modèle, un gabarit en millimètres donne un bâtiment 1 000 fois trop grand dans Blender.
2. Dans Blender : **Fichier → Importer → Wavefront (.obj)**, axe avant Y, axe haut Z, échelle 1.

Dans cet export, les espaces et les accents des noms de matériaux deviennent `_`, par exemple `ARCHGEN_B_ton_brut`, et l'import Blender donne un seul objet. Aucune garantie n'est donnée pour les UV, les moteurs de jeu ou les collisions.

## Limites de cette version

- Emprise rectangulaire et ouvertures rectangulaires. Pas d'intérieur, de vitrage, de garde-corps, de terrain, de rue ni d'îlot.
- Pas de calcul de structure ni de conformité réglementaire. Les styles sont des simplifications, pas des restitutions historiques.
- Le champ « Variation des baies » est le plus souvent refusé dès qu'il n'est pas nul ; le message propose de changer la graine ou la variation.
- Les anciennes définitions restent dans le fichier après une régénération, pour permettre Annuler. **Fenêtre → Infos sur le modèle → Statistiques → Purger les éléments inutilisés** les retire.
- Le plus grand bâtiment accepté bloque SketchUp environ 5 à 6 secondes sur le poste de test.

## Désinstaller

**Extensions → Extension Manager**, puis **Uninstall** sur ARCHGEN. Les bâtiments déjà créés restent dans vos fichiers comme des composants ordinaires.
