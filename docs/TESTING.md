# Stratégie de tests et recette

Trois niveaux : (1) Ruby pur, tests unitaires et propriétés sur fixtures ; (2) test de contrat des ports avec doubles pour la gestion des erreurs ; (3) script et recette dans SketchUp Desktop, seule preuve des mutations, transactions et conversions réelles. Lancer `bundle exec rake test` en CI après AG-001 ; charger explicitement le script `test/host/run.rb` de développement dans la console d'un modèle de test.

| ID | Vérification Ruby / contrat |
|---|---|
| U01 | Brouillon minimal et effectif complet ; clés dupliquées, nombre non fini, entier mathématique 1.0 accepté et normalisé, types faux, UTF-8 invalide, schema_version inconnu. Parité avec les schémas JSON. |
| U02 | Parents, cycle, révision manquante, feuille planifiée ; distinguer hard/historique ; changement de style garde dimensions et remplace matériaux, façade, toit. |
| U03 | RNG seed 42 : préfixes hex sur `opening/front/0/0` = `cd855d0e3d78c`, `opening/rear/3/3` = `3b73a509759c3`, `feature/cornice` = `8ecd39cb81f48` ; convertir en entier puis /2⁵². Ordre de parcours modifié sans variation du résultat ; canonicaliser −0 et hash de clés réordonnées. |
| U04 | Anneau CCW, normales front (0,−1,0), right (1,0,0), rear (0,1,0), left (−1,0,0) ; bases 0 / 3,2 / 6,4 / 9,6, H=12,8. |
| U05 | P=2,7, centres avant 1,95 / 4,65 / 7,35 / 10,05 m ; 32 ouvertures dont porte front/0/1 ; aucune sur les côtés. Rejeter incompatibilité largeur, niveau, jitter cumulé et marge ≥ demi-longueur d'une façade percée. |
| U06 | Shell : mur front 119,00 m² et rear 119,04 m² pour le fixture neutre ; lancer un segment normal au centre de chaque baie et de la porte, de d=−0,05 à d=t+0,05 m sur le mur testé ; aucune intersection. Le même test dans une cellule pleine sert de témoin. |
| U07 | Structural : chaque pièce murale fermée et volume signé positif ; front 27,82272 m³ ; dalles 3 × 19,63008 m³. Mêmes segments traversants qu'en Shell et test témoin des deux peaux ; onglets sans chevauchement, pas de seuil mural. |
| U08 | Plat à H ; deux pans H+tan(p)·D/2 ; croupe carrée sans sommet dupliqué ; rectangle avec faîtage ; mansarde H+tan(p_bas)·I+tan(p_haut)·(min(W,D)/2−I). Vérifier pente, débord, continuité et normales. |
| U09 | Sérialisation stable ; indices valides, tri et matière ; refuser bord ouvert, éventail scindé, face non plane, orientation incohérente et référence absente. |
| U10 | Le plan neutre sans fusion compte 259 cellules candidates, 218 faces en Shell et 709 en Structural, toit compris. Tester les limites exactes et le premier dépassement en taille, faces, ouvertures et cellules ; au moins 100 configurations pseudo-aléatoires bornées, seed de suite fixée et reproduite dans les erreurs. |
| U11 | Les trois fixtures actives ; centre des baies ouvert malgré les cadres, aucun détail LOD 0 ; absence de géométrie LOD 1 incompatible. |
| U12 | Pont : strings HTML malicieuses, actions inconnues, données trop grandes, requêtes répétées ; faux writer : échec avant/après swap et aucun commit. |

Tolérance des mesures Ruby : 10⁻⁵ sur les cas étalons (unités SI) ; SketchUp ≤1 mm sur cotes attendues. Comparer le plan canonique et les invariants ; captures visuelles seulement en complément. Le hash est exact pour une même version/matrice validée ; une divergence numérique interplateforme doit être caractérisée et corrigée ou documentée avant promesse.

| ID | Procédure hôte | Résultat à conserver |
|---|---|---|
| H01 | Installer/activer le RBZ, fermer/réouvrir le dialogue, désactiver et redémarrer. | Une entrée de menu, rappel fonctionnel, console sans erreur. |
| H02 | Générer les deux neutres ; inspecter coupes et lignes d'arête, mesurer ; répéter dans un document affiché en pouces. | Cotes, orientations, vrais trous, dalles et joints conformes, tags. |
| H03 | Ajouter géométrie, tag et matériau utilisateur ; générer puis Undo/Redo. | Un seul Undo, ressources préexistantes intactes, mêmes métadonnées au Redo. |
| H04 | Sauver et rouvrir le SKP. Essayer config d'une future version dans un modèle de test. | Config restaurée à l'identique ; version future refusée sans mutation. |
| H05 | Déplacer/pivoter A, créer B en copiant A ; vérifier qu'ils partagent la définition, puis sélectionner A et changer ses dimensions sans changer de profil. Undo puis Redo. | PID, transfo et tag de A conservés ; B inchangé, UUID séparé ; forme, données et définition restaurées/rétablies. |
| H06 | Injecter panne après les premières faces, puis après swap et avant écriture finale des métadonnées. | Enregistrements avant/après identiques (définitions, matériaux, sélection, config, racine) ; aucune ligne Undo ajoutée. |
| H07 | Verrouiller, supprimer, imbriquer ou mettre à l'échelle la cible ; changer document/sélection après aperçu ; réutiliser confirmation. | Diagnostic actionnable ; aucune écriture. |
| H08 | Créer les trois profils et comparer LOD 0/1 puis Shell/Structural. | Signatures du PRD visibles ; vraie baie et cotes communes ; partage des cadres. |
| H09 | Taper vite, alterner entrées invalides, modifier l'échelle UI et naviguer au clavier hors ligne. | Aperçu cohérent, focus/labels, pas de mutation ni réponse périmée appliquée. |
| H10 | Doubler Générer ; changer le profil, annuler la confirmation puis confirmer à nouveau sur un aperçu frais. | Une création ; annuler garde l'état ; une régénération. |
| H11 | Exécuter mesures et 20 régénérations de référence. | CSV ou tableau avec p95, compteurs, taille SKP, versions et différences. |
| H12 | Exporter le Shell LOD 0 dans un format effectivement disponible sur l'édition hôte, importer dans un outil de contrôle. | Note des unités et matériaux visibles, normales/baies ; écart dimensionnel ≤1 % sur W, D, H-toit après configuration d'import. |

Gabarit de rapport : commit et moteur ; OS, édition hôte, Ruby et matériel ; identifiant fixture ; mode/LOD ; attendu, observé, résultat, trace minimale ; motif des cas non exécutés. Tester au moins le plancher 2024 et une version récente sur la matrice disponible ; viser Windows et macOS. Les versions non testées sont annoncées comme telles. Faire la recette dans des copies de modèles et noter les opérations reproductibles.
