# Journal des versions

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
