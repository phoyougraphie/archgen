# Journal des versions

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
