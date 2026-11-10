# Contrat du décor de jeu — J23 (AG-115 à AG-119)

**Demande du propriétaire (2026-11-10).** « ext 06 12 09 08 sont les chantiers prioritaires », dans cet ordre. EXT-06 vient donc avant l'intérieur, qui est reporté (ADR-53). Le cadrage a été validé le même jour (« Oui, cadre EXT-06 »).

**Périmètre.** Il s'agit d'un **exporteur optionnel** qui écrit un fichier lisible par un moteur de jeu à partir d'un bâtiment ou d'une rue ARCHGEN. Il produit :

- des triangles ;
- des UV ;
- des matériaux PBR ;
- les axes et l'unité du moteur ;
- des volumes de collision ;
- trois niveaux de détail.

Ce qui reste hors périmètre :

- les textures peintes : les matières restent unies, comme au PRD ;
- l'éclairage cuit ;
- les routes, le terrain et le mobilier ;
- l'animation ;
- un aller-retour d'édition depuis le moteur.

**Adaptateur séparé (ADR-54).** L'exporteur est écrit en Ruby pur, dans `archgen/adapters/gltf/`. Il lit le **plan déterministe en mètres**, pas le modèle SketchUp. Il est donc testable sans SketchUp, et deux exports du même plan sont identiques à l'octet près. Le noyau n'en dépend pas. Seule la commande d'export (AG-118) touche SketchUp, pour la sélection et la boîte de dialogue « Enregistrer sous ». L'export ne modifie jamais le modèle. Une retouche faite à la main dans SketchUp n'est pas exportée, et le guide le dit.

**Choix de détail.** Ils sont pris selon ADR-48 : la recommandation est appliquée, et le propriétaire peut la réviser (D-27 à D-32 ci-dessous).

**Moteurs visés.** Ceux installés sur ce poste : **Unreal Engine 5.8** comme cible, **Blender 5.2** pour le contrôle. Twinmotion 2026.2, qui lit aussi le glTF, est noté sans être promis. Aucun autre moteur n'est déclaré pris en charge sans une recette.

## Décisions de détail appliquées (révisables)

| N° | Question | Choix appliqué | Autre option |
|---|---|---|---|
| D-27 | Quel format ? | **glTF 2.0 binaire (`.glb`)**, écrit par ARCHGEN. Il porte les mètres, l'axe Y vers le haut et les matériaux PBR ; Unreal, Blender et Godot le lisent sans greffon. | FBX par l'exporteur de SketchUp Pro : format fermé, PBR et UV non maîtrisés. |
| D-28 | Que lit l'exporteur ? | Le **plan** recalculé depuis la configuration enregistrée, après les mêmes contrôles qu'une régénération. | Les faces du modèle SketchUp : retouches comprises, mais non déterministe et intestable sans hôte. |
| D-29 | Quelles UV ? | **Projection cubique** : chaque face est projetée sur le plan de l'axe le plus proche de sa normale, avec 1 m = 1 unité d'UV, en coordonnées locales du bâtiment. | Dépliage par façade : coutures plus propres, mais coûteux à écrire. |
| D-30 | Quels matériaux ? | **Métal-rugosité glTF**. La couleur de base est la sRGB du catalogue, teintes ADR-51 comprises. Deux clés facultatives s'ajoutent au catalogue, `roughness` (0,85 par défaut) et `metallic` (0 par défaut). Le verre a une opacité de 0,35 et une rugosité de 0,05. Une `surface` (face simple, Shell) est double face ; un `solid` ne l'est pas. | Matériaux texturés : hors périmètre tant que les matières sont unies. |
| D-31 | Quels niveaux de détail ? | **Trois fichiers** : `<nom>_LOD0.glb` (le bâtiment tel que réglé), `<nom>_LOD1.glb` (le même plan recalculé au réglage ARCHGEN `lod: 0`, sans détails) et `<nom>_LOD2.glb` (les volumes simples). Dans Unreal, LOD1 et LOD2 s'ajoutent par « Import LOD Level ». | Une seule scène avec l'extension `MSFT_lod`, que les importeurs lisent mal. |
| D-32 | Quelles collisions ? | Des **boîtes convexes** : une par niveau et par volume, et un prisme convexe par toit. Elles sont rangées dans des nœuds `UCX_<nom>_NN`, sans matériau, dans le fichier LOD0. | Collision complexe (« Use Complex as Simple ») : plus lourde à l'exécution. |

## 1. Triangulation et écriture glTF — AG-115

- Chaque face du plan est un polygone plan à une seule boucle, comme l'écrit le writer SketchUp. Elle est triangulée par **oreilles** dans l'ordre de ses indices, donc la normale est conservée. Une face concave est prise en charge. Une face dégénérée est refusée avec un diagnostic localisé (`export_face`, id du nœud).
- Les normales sont plates, avec des sommets dupliqués par face. Le nombre de triangles d'une face vaut n − 2.
- Changement d'axes : un point SketchUp (x, y, z) devient (x, z, −y) dans le glTF. L'unité est le mètre, et l'origine est celle de l'objet ARCHGEN.
- Une définition partagée (primitive `instance`) devient **un seul maillage glTF**, référencé par plusieurs nœuds avec leur matrice. Le partage de SketchUp se retrouve ainsi dans le moteur.
- La hiérarchie des nœuds suit celle du plan, avec les mêmes noms : façades, toit, détails, maisons d'une rue.
- Le fichier contient un en-tête GLB, un bloc JSON trié et un bloc binaire aligné sur 4 octets. Les flottants sont arrondis au dix-millième de mètre, et le résultat est déterministe à l'octet près.
- Le service rend le nombre de triangles, de sommets, de maillages et de matériaux pour chaque fichier.

## 2. UV et matériaux PBR — AG-116

- Les UV suivent D-29 : u et v sont des mètres le long des deux axes du plan de projection. Une texture répétée de 1 m tombe donc à l'échelle.
- Les matériaux suivent D-30, avec un matériau glTF par matière utilisée, nommé par son id ARCHGEN (`id~L.n` pour une teinte). Les clés `roughness` et `metallic` du catalogue sont facultatives et versionnées : le schéma du catalogue les accepte, et elles sont absentes partout au départ, sauf le verre et les métaux du catalogue s'il y en a.
- Le verre est en mode alpha `BLEND`.

## 3. Niveaux de détail et collisions — AG-117

- **LOD0** : le plan du bâtiment.
- **LOD1** : le plan recalculé au réglage `lod: 0`, sans changer ni la graine ni le reste. Si le bâtiment est déjà au réglage `lod: 0`, LOD1 n'est pas écrit et le rapport le dit.
- **LOD2** : une boîte par volume, de l'emprise jusqu'au haut du dernier niveau, plus un prisme de toit. Le toit plat n'a pas de prisme. Les mansardes et croupes sont simplifiées à un prisme à deux pans de même faîtage.
- **Collisions** : les mêmes formes que LOD2, en nœuds `UCX_` sans matériau, ajoutées au fichier LOD0. Un balcon ou un détail n'a pas de collision.
- **Contrôle** : le nombre de triangles décroît de LOD0 à LOD1 puis à LOD2. Sinon, un avertissement est émis (`W_EXPORT_LOD`).

## 4. Commande d'export — AG-118

- Clic droit sur un bâtiment ou une rue ARCHGEN → **Exporter pour un moteur de jeu…** La boîte « Enregistrer sous » propose le nom de l'objet. Les trois fichiers sont écrits à côté les uns des autres.
- Pour une rue, chaque maison est un nœud, avec ses soubassements, plateformes et murs de soutènement. Le terrain et les routes ne sont pas exportés, et le rapport le dit.
- Un réseau de routes ou un terrain sélectionné seul est refusé (`export_unsupported`).
- L'export n'est pas une opération du modèle : pas d'Undo, et le document est intact. Un fichier existant n'est remplacé qu'après la confirmation de la boîte de dialogue.
- Le rapport affiche les triangles par fichier et le chemin.

## 5. Guide, version — AG-119

- Section **Décor de jeu** du guide, qui décrit :
  - l'import dans Unreal 5.8 : glTF, mètres, LOD par « Import LOD Level », collisions `UCX_` ;
  - le contrôle dans Blender 5.2 ;
  - la limite : les retouches faites à la main ne sont pas exportées.
- Journal, puis **RBZ 0.23.0**.
- Recette **H38** à faire à la main :
  - importer un bâtiment et une rue dans Unreal 5.8 ;
  - vérifier l'échelle, les axes, les matériaux, les LOD et les collisions.

  Tant que H38 n'est pas faite, la reconnaissance des `UCX_` par l'importeur glTF d'Unreal n'est pas affirmée. Si elle échoue, le repli est écrit dans le guide : collision complexe.

## Tests

- **U78** : triangulation (faces concaves, n − 2, normale conservée, face dégénérée refusée), axes, en-tête GLB valide, octets identiques sur deux exports, partage des maillages.
- **U79** : UV à 1 m sur une façade et sur un pan de toit, matériaux PBR (défauts, verre, teinte), double face des surfaces.
- **U80** : LOD1 sans détails, LOD2 et collisions convexes, triangles décroissants, LOD1 absent au réglage `lod: 0`.
- **U81** : service d'export avec un hôte factice (bâtiment, rue, refus d'un réseau), modèle intact.
