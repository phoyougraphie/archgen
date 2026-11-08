# Journal des versions

## 0.7.0-dev

En cours, non publiée : voie sur un terrain (AG-049, ADR-38) — profil en long, pente bornée, talus, copie entaillée du terrain d'origine, qui reste masqué ; passage à niveau (AG-050) — la route monte en rampe au ras des rails, feux et barrières, la voie ferrée reste entière.

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
