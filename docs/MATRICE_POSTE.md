# Matrice de poste

Consigne les versions réellement accessibles (ADR-08). Une ligne n'annonce aucune compatibilité : seule la recette hôte ([TESTING](TESTING.md)) en apporte la preuve.

| Poste | OS | SketchUp | Ruby embarqué | Ruby de dev | Relevé |
|---|---|---|---|---|---|
| Poste principal | Windows 11 Home 10.0.26200 | SketchUp 2026 — `SketchUp.exe` 26.2.243 | 3.2.2p53 (`x64-ucrt-ruby320.dll`) | 3.2.11 x64-mingw-ucrt, Bundler 2.4.19, Minitest 5.25, Rake 13.0 | 2026-11-05, propriétés des fichiers ; [H01](recette/H01.md) réussi |

**Non accessibles à ce jour :** macOS ; SketchUp 2024 et 2025. Le plancher 2024 de la recette reste donc à trouver avant AG-019.

**Écart à surveiller :** la version 26.2 embarque déjà `ComponentDefinition#manifold?` (ajoutée en 2026.2), interdite comme dépendance V0.1 car absente du plancher 2024. Tester sur ce poste ne suffit pas à prouver son absence d'usage : le test de contrat du noyau et la revue la couvrent.

**Conventions retenues par AG-001.** Branche d'intégration `main` ; développement sur `dev/v0.1`. Fichiers UTF-8/LF imposés par `.gitattributes`. Lecture de fichiers en binaire + UTF-8 explicite pour rester stable entre Windows et macOS. Noyau chargé par le manifeste `archgen/loader.rb`, sans `require` interne ni modification de `$LOAD_PATH`. Commande unique : `bundle exec rake test`.
