# Exemples V1

- [Brouillon de création](creation-draft.json), [sa configuration effective](buildings/haussmann-12x9.json) : mêmes données géométriques ; libellés différents. Quatre niveaux déclenchent l'avertissement historique attendu.
- [Neutre Shell](buildings/rect-neutre-shell.json) et [neutre Structural](buildings/rect-neutre-structural.json) : mêmes dimensions, toit, ouvertures ; réservés aux tests. Le profil interne generic est accepté par le moteur sous banc de tests, jamais dans le panneau.
- [Toulousain](buildings/toulousain.json) et [Brutaliste](buildings/brutalist.json) : signatures de la recette.
- [Registre générique](profiles/generic.json), [haussmann](profiles/haussmann.json), [toulousain](profiles/toulousain.json), [brutalist](profiles/brutalist.json) : données prêtes à reprendre dans le dépôt. Le répertoire profiles contient aussi les sept parents techniques.
- [Matériaux](materials.v1.json) : couleurs sRGB de génération ; textures et nomenclatures d'export sont différées.

Le nom ne participe pas à l'identité du plan. Les tests d'algorithmes, d'Undo et de versions sont décrits dans [TESTING](../docs/TESTING.md).
