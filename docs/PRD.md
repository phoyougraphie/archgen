# PRD — bâtiment paramétrique V0.1

**Objectif.** En quelques réglages, produire dans SketchUp un bâtiment lisible, éditable comme composant et régénérable à partir de ses paramètres sauvegardés. Les deux publics sont la maquette architecturale et le décor 3D.

| ID | Fonction | Résultat observable |
|---|---|---|
| P01 | Nouveau bâtiment | Menu Extensions → ARCHGEN ; choisir l'un des trois styles, renseigner dimensions, niveaux, trame et seed. |
| P02 | Aperçu | Élévation et emprise calculées par le même noyau que Générer ; avertissements, dimensions, nombre d'ouvertures ; aucune entité dans le modèle. |
| P03 | Générer Shell | Façades à surface simple et ouvertures traversantes réelles, couverture, matériaux, détails selon LOD. |
| P04 | Générer Structural | Même silhouette de base et mêmes ouvertures ; murs à épaisseur, tableaux et planchers intermédiaires. |
| P05 | Modifier / rouvrir | Sélectionner une racine ARCHGEN ; recharger les paramètres après sauvegarde du SKP ; changer style, mode ou dimensions. |
| P06 | Régénérer / annuler | Conserver la racine et son placement ; isoler les copies ; confirmation de remplacement ; une entrée Undo et Redo vérifié. |
| P07 | Reproduire | Configuration effective, seed et versions identiques ⇒ même plan canonique ; identité et placement indépendants. |
| P08 | Exploiter | Faces visibles orientées, matériaux nommés et pièces organisées ; un aller-retour export hôte sur un outil cible documenté. |
| P09 | Gérer les erreurs | Champ et cause expliqués ; aucune modification du modèle sur rejet ; échec d'écriture restauré. |

**Inclus.** SketchUp Desktop ; une génération à la fois au niveau racine du modèle ; emprise rectangulaire ; niveaux empilés ; ouvertures rectangulaires ; toit plat, deux pans, croupe, mansarde ; matériaux unis embarqués ; LOD 0 et 1 ; haussmannien, toulousain et brutaliste. Les réglages sont une liste fermée, détaillée par [le contrat de configuration](CONFIG_SCHEMA.md). Le nombre de champs affichés vient de l'utilité du parcours, pas d'un quota.

**Signatures V0.1.** Haussmannien : pierre claire, verticalité des baies, mansarde, corniche et balcon filant simplifiés au LOD 1. Toulousain : brique foraine, toit en tuile canal, baies verticales et encadrements au LOD 1. Brutaliste : béton, toit plat, grille répétitive et baies en retrait visuel au LOD 1 Structural. Un profil simplifié peut être crédible sans prétendre restituer toutes ses techniques.

**Frontières.** Structural désigne une représentation volumique ; pas de calcul porteur. Shell ne promet pas un volume étanche. Pas de conformité réglementaire, de vitrages détaillés, d'intérieur, de patrimoine certifié, de terrain, de ville ou de service distant en V0.1 ; rue, îlots et terrassement sont prévus après J5 ([besoin](RUE_ILOT_TERRAIN.md)). Export via SketchUp selon l'édition utilisée ; pas de garantie moteur de jeu, UV ou collisions.

**Recette de sortie.** Créer le fixture de 12 × 9 m, quatre niveaux et quatre travées frontales, dans les deux modes. Vérifier ses dimensions, ses vides et les versions du plan ; déplacer/faire pivoter sa racine, la copier, puis changer le style sur une seule instance. Vérifier copie inchangée, annulation/rétablissement et reprise après sauvegarde/réouverture. Produire les deux autres signatures et le rapport de [recette hôte](TESTING.md).
