# Tickets de développement

Chaque bloc est un ticket importable. Dépendances = prérequis à valider. Les identifiants de recette renvoient à [TESTING](../docs/TESTING.md).

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-001 — Initialiser dépôt et CI Ruby** | — | Arborescence, version, Gemfile de dev, Rakefile, test smoke et matrice de poste. | `bundle exec rake test` fonctionne sans SketchUp ; CI Ruby 3.2 ; renseigner OS, versions hôtes accessibles et conventions. |
| **AG-002 — Enregistrer l'extension** | AG-001 | Chargeur minimal, menu et HtmlDialog local de diagnostic, packaging de développement. | Installer le RBZ de développement ; activation/réouverture ne dédoublent pas le menu ; pas d'appel réseau ni erreur console. H01. |
| **AG-003 — Validation des entrées** | AG-001 | Parseur JSON borné, diagnostic, BuildingConfig immuable, brouillon vs effectif. | Fixtures conformes ; clé inconnue, doublon, version future et type faux rejetés avec chemin ; empreinte indépendante du nom. U01. |
| **AG-004 — Résoudre les profils** | AG-003 | Registre, héritage, choix actif/exact, règles de fidélité, fusion et transition de style ; tester avec capacités injectées. | Révision exacte, union capacités et fusion feuilles ; révision absente/cycle refusés ; les modes changent la sévérité, jamais une contrainte hard. U02. |
| **AG-005 — Quantifier et dériver le hasard** | AG-003 | RNG par clé SHA-256, canonicalisation, valeurs sémantiques, tests de compatibilité. | Golden indépendant du parcours ; même hash pour clés réordonnées ; changement de clé/seed produit un autre tirage ; NaN/−0 traités. U03. |
| **AG-006 — Emprise et niveaux** | AG-004, AG-005 | Rectangle CCW, repères, hauteurs uniformes/variables, bandes de dalles. | Fixture 12 × 9 : normales correctes, sommet 12,80 m, trois bandes ; rejeter dépassements. U04. |
| **AG-007 — Travées et percements** | AG-006 | Centres, jitter borné, porte de substitution, distances et diagnostics. | Quatre centres attendus, 31 fenêtres + 1 porte ; dimensions trop grandes et collisions refusées avant plan. U05. |
| **AG-008 — Murs et dalles** | AG-007 | Grille Shell, onglets Structural, tableaux et trois dalles. | Aires, volumes et bords orientés conformes ; aucune face dans l'axe d'un percement ; pas de seuil de mur. U06–U07. |
| **AG-009 — Toitures** | AG-006 | Plat → deux pans → croupe → mansarde, pignons, débords et erreurs. | Tester carré et rectangle, plans et raccords ; rejeter inset invalide et rive sous Z=0. U08. |
| **AG-010 — Contrat du plan et budgets** | AG-008, AG-009 | Engine, plan sérialisable, PlanValidator, projection aperçu et budgets. | Fixtures neutres déterministes ; solid invalide et budget rejetés ; modes partagent baies et silhouette. U09–U10. |
| **AG-011 — Écrire le plan dans SketchUp** | AG-002, AG-010 | Writer isolé, unités, regroupements et matériaux ; sonde native dédiée. | Fixture neutre en pouces et en mètres UI donne mêmes cotes ; normales, trous et tags conformes. H02. |
| **AG-012 — Créer et relire une racine** | AG-011 | Service de création, transaction, métadonnées, réouverture. | Une action Undo ; SKP rouvert retrouve effectif exact et métadonnées ; ressource utilisateur homonyme intacte. H03–H04. |
| **AG-013 — Régénérer une instance** | AG-012 | Cible par jeton, sélection, copie, remplacement de définition, révision. | Cible pivotée et déplacée conserve PID/transfo lors d'une modification de dimensions ; copie intacte ; Undo/Redo restaure géométrie et config. H05. |
| **AG-014 — Rejeter et restaurer** | AG-013 | Garde de transaction, vérifications de contexte, injection de fautes et version incompatible. | Faute au milieu d'écriture et après swap restaurée sans nouvelle opération ; cible supprimée, verrouillée, imbriquée ou autre document sans effet. H06–H07. |
| **AG-015 — Détails et profils V0.1** | AG-014 | Cadres, corniche, balcon et encadrements ; activer les trois profils versionnés et fixtures LOD 1. | Signatures distinctes, vides traversants, cadre répété mutualisé, silhouette de base stable. U11, H08. |
| **AG-016 — Relier formulaire et aperçu** | AG-015 | UI locale, validation, messages et protocoles init/lecture/aperçu. | Cotes et nombre de baies issus du plan ; réponse ancienne ignorée ; aperçu n'ajoute ni entité ni Undo. H09. |
| **AG-017 — Relier création et édition** | AG-016 | Génération, transition, confirmation, requête unique et état périmé. | Double clic ne crée qu'une racine ; annulation sans effet ; confirmation expirée ou autre document refusé ; profil change selon la politique documentée. H10. |
| **AG-018 — Recette de sécurité et charge** | AG-017 | Cas adverses, budgets, profils de charge, mesure de croissance. | U10/U12, H06–H07, H11 et seuils du contrat ; fournir mesures et corriger les écarts ou amender la cible par ADR justifiée avant sortie. |
| **AG-019 — Recette export et compatibilité** | AG-017 | Cible Windows et SketchUp 2026 (ADR-26), versions réellement testées ; export d'un Shell LOD 0 vers un outil choisi. | H01–H10 et H12 sur cette cible ; rapport cotes, orientations, matériaux, format/édition ; ne pas annoncer une plateforme non vérifiée. |
| **AG-020 — Produire le RBZ V0.1** | AG-018, AG-019 | Paquet reproductible, journal de version, guide utilisateur, rapport de recette. | RBZ installé depuis un profil propre, fonctionnalités P01–P09 démontrées, recettes H01–H12 rejouées sur ce RBZ, limitations documentées ; contrôle final J5. |

## J6 — Terrain d'un bâtiment (EXT-10)

Contrat : [TERRAIN_CONTRACT](../docs/TERRAIN_CONTRACT.md). Ordre fixé par ADR-27.

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-021 — Réglages, grille et assise** | AG-020 | Schéma `site` V1, grille de relevé, fixtures (pente, creux, trou), plateforme, indicateurs et refus ; noyau pur. | Réglages et grilles adverses refusés avec chemin ; `high` et `mean` exacts ; relief limite et premier dépassement. U13. |
| **AG-022 — Soubassement et plancher** | AG-021 | SitePlan, bandes, plancher, validateur, budgets, porte enterrée ou haute. | Géométrie et normales conformes ; empreinte déterministe ; `plan_digest` inchangé pour toutes les fixtures. U14. |
| **AG-023 — Talus** | AG-022 | Rayons, pied de talus, angles en éventail, catalogue `site_materials.v1.json`. | Pente exacte, pied introuvable refusé, 100 terrains pseudo-aléatoires reproductibles. U15. |
| **AG-024 — Relevé dans SketchUp** | AG-021 | Port de relevé, terrain retenu, obstacles, trous, repère de la racine ; aucune écriture. | Fait mesuré par le contrat rejoué sur le produit ; temps publié ; aucune trace d'Annuler. H13, partie relevé. |
| **AG-025 — Écrire et persister l'assise** | AG-023, AG-024 | Définition avec assise, Z de la racine, `archgen.site`, garde de transaction, retrait, version future. | Une entrée d'Annuler, terrain intact, pannes sans résidu, terrain changé refusé, aller-retour SKP, bâtiment V0.1 inchangé. H13. |
| **AG-026 — Panneau terrain et RBZ 0.2.0** | AG-025 | Section Terrain, aperçu, confirmation, assise périmée, guide, journal, RBZ. | Valeurs issues du plan, parcours complet, charge sur 100 000 faces ; H01 à H14 rejouées sur le RBZ. H14. |
| **AG-027 — Étagement par parcelle** | AG-026, AG-036 | Une assise par parcelle le long d'une rue en pente, raccord par soubassement. | À détailler à l'ouverture, après le contrat d'EXT-07. |

## J7 — Rue et îlots au tracé (EXT-07)

Contrat : [ENSEMBLE_CONTRACT](../docs/ENSEMBLE_CONTRACT.md). Décisions : ADR-30 à ADR-32. Une rue ouverte est utilisable dès AG-033 ; l'îlot fermé attend ses accès.

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-028 — Tracé et parcelles** | AG-026 | Schéma `ensemble` V1, tracé, onglets, découpe, parcelles, contrôles d'ensemble, fixtures ; noyau pur. | Carré de référence exact à la main ; segments, angles et recouvrements refusés avec chemin ; 100 tracés pseudo-aléatoires reproductibles. U16. |
| **AG-029 — Bâtiment de rangée** | AG-028 | Plan de rangée rectangulaire : murs latéraux aveugles, travées calculées, toits en section sans débord latéral, croupe refusée. | Toits raccordés entre deux parcelles ; `plan_digest` de toutes les fixtures inchangé. U17. |
| **AG-030 — Parcelle d'angle** | AG-029 | Trapèze en Shell et Structural : joints, dalles, toits, corniche et balcon coupés à l'onglet. | Angles saillants et rentrants : sommets communs sur l'onglet, aucun recouvrement de volume, normales conformes. U18. |
| **AG-031 — Plan d'ensemble** | AG-030 | `EnsemblePlan`, seeds dérivées, définitions partagées, `ensemble_digest`, budgets, progression. | Même entrée, même empreinte ; limites et premier dépassement. Plafonds revus après la mesure hôte d'AG-032. U19. |
| **AG-032 — Écrire et persister l'ensemble** | AG-031 | Racine d'ensemble, `archgen.ensemble`, une opération, régénération, copies, refus, version future. | Une entrée d'Annuler, pannes sans résidu, aller-retour SKP, bâtiment seul inchangé ; charge sur 12, 50 et 200 parcelles publiée. H15. |
| **AG-033 — Outil de tracé** | AG-032 | `Sketchup::Tool` au geste YSKE, aperçu dans la vue, réglages et confirmation au panneau. Forme ouverte seulement ; une forme fermée reste refusée tant qu'elle n'a pas d'accès. | Clics, saisie, axes, côté, 90°, fermeture et Échap ; aucune écriture avant confirmation. H16. |
| **AG-034 — Accès par interruption** | AG-033 | Placement déterministe, `gap`, catalogue `ensemble_rules.v1.json` avec Brutaliste, ouverture de la forme fermée pour ce profil. | Carré de référence : 3 accès sur 3 côtés, jamais en angle ; nombre impossible refusé ; aucune cour sans accès. U20. |
| **AG-035 — Accès par porche** | AG-034 | Capacité porche : passage, parois, plafond, étages au-dessus ; entrées Haussmannien et Toulousain. | Shell et Structural, hauteur limite et premier dépassement, baies recouvertes retirées ; fixtures inchangées hors porche. U21. |
| **AG-036 — Panneau d'ensemble et RBZ 0.3.0** | AG-035 | Modifier un ensemble, guide, journal, RBZ. | Parcours rue et îlot complet ; H01 à H17 rejouées sur le RBZ. H17. |

**Définition de terminé.** Livrable revu et intégré, preuve liée au ticket, test de non-régression pertinent, contrats à jour et aucune régression connue bloquante. Si un prérequis échoue, consigner cause, preuve et prochaine étape. Le simple affichage d'un rendu ne valide pas les ouvertures, le rollback ou les unités.
