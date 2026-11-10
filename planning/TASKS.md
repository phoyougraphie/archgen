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
| **AG-027 — Étagement par parcelle** | AG-026, AG-036 | Une plateforme par parcelle le long d'une rue en pente, raccord par soubassement, section Terrain du panneau d'ensemble, guide, journal, RBZ 0.4.0 ([contrat](../docs/TERRAIN_CONTRACT.md)). | Rue en pente et îlot sur un vrai terrain, une entrée d'Annuler, terrain intact, bâtiments toujours partagés, pannes sans résidu, aller-retour SKP ; H01 à H18 rejouées sur le RBZ. H18. |

## J7 — Rue et îlots au tracé (EXT-07)

Contrat : [ENSEMBLE_CONTRACT](../docs/ENSEMBLE_CONTRACT.md). Décisions : ADR-30 à ADR-32. Une rue ouverte est utilisable dès AG-033 ; l'îlot fermé attend ses accès.

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-028 — Tracé et parcelles** | AG-026 | Schéma `ensemble` V1, tracé, onglets, découpe, parcelles, contrôles d'ensemble, fixtures ; noyau pur. | Carré de référence exact à la main ; segments, angles et recouvrements refusés avec chemin ; 100 tracés pseudo-aléatoires reproductibles. U16. |
| **AG-029 — Bâtiment de rangée** | AG-028 | Plan de rangée rectangulaire : murs latéraux aveugles, travées calculées, toits en section sans débord latéral, croupe refusée. | Toits raccordés entre deux parcelles ; `plan_digest` de toutes les fixtures inchangé. U17. |
| **AG-030 — Parcelle d'angle** | AG-029 | Trapèze en Shell et Structural : joints, dalles, toits, corniche et balcon coupés à l'onglet. | Angles saillants et rentrants : sommets communs sur l'onglet, aucun recouvrement de volume, normales conformes. U18. |
| **AG-031 — Plan d'ensemble** | AG-030 | `EnsemblePlan`, seeds dérivées, définitions partagées, `ensemble_digest`, budgets, progression. | Même entrée, même empreinte ; limites et premier dépassement. Plafonds revus d'après la mesure hôte d'AG-032. U19. |
| **AG-032 — Écrire et persister l'ensemble** | AG-031 | Racine d'ensemble, `archgen.ensemble`, une opération, régénération, copies, refus, version future. | Une entrée d'Annuler, pannes sans résidu, aller-retour SKP, bâtiment seul inchangé ; charge sur 12, 50 et 200 parcelles publiée. H15. |
| **AG-033 — Outil de tracé** | AG-032 | `Sketchup::Tool` au geste YSKE, aperçu dans la vue, réglages et confirmation au panneau. Forme ouverte seulement ; une forme fermée reste refusée tant qu'elle n'a pas d'accès. | Clics, saisie, axes, côté, 90°, fermeture et Échap ; aucune écriture avant confirmation. H16. |
| **AG-034 — Accès par interruption** | AG-033 | Placement déterministe, `gap`, catalogue `ensemble_rules.v1.json` avec Brutaliste, ouverture de la forme fermée pour ce profil. | Carré de référence : 3 accès sur 3 côtés, jamais en angle ; nombre impossible refusé ; aucune cour sans accès. U20. |
| **AG-035 — Accès par porche** | AG-034 | Capacité porche : passage, parois, plafond, étages au-dessus ; entrées Haussmannien et Toulousain. | Shell et Structural, hauteur limite et premier dépassement, baies recouvertes retirées ; fixtures inchangées hors porche. U21. |
| **AG-036 — Panneau d'ensemble et RBZ 0.3.0** | AG-035 | Modifier un ensemble, guide, journal, RBZ. | Parcours rue et îlot complet ; H01 à H17 rejouées sur le RBZ. H17. |

## J8 — Voirie (EXT-11)

Contrat : [VOIRIE_CONTRACT](../docs/VOIRIE_CONTRACT.md), [maquette](../docs/maquettes/voirie-coupe.html). Décision : ADR-34. La coupe vient d'abord, à la demande du propriétaire ; une voie sans carrefour est utilisable dès AG-042.

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-037 — Format de coupe et catalogues** | AG-027 | Schéma `road_profile` V1, catalogues fermés de bandes et d'éléments, onze préréglages en fixtures, diagnostics ; noyau pur. | Limites et premier dépassement pour chaque type ; clé inconnue, élément dans un fossé refusés avec chemin ; préréglages valides ; aucun bâtiment ni ensemble changé. U23. |
| **AG-038 — Éditeur de coupe** | AG-037 | Panneau local : coupe à l'échelle, personnage, gabarits, ajouter, retirer, ordonner, largeur saisie ou glissée, éléments, vue en plan. Aucune écriture dans le modèle. | Valeurs et diagnostics issus du noyau ; échelle mesurée à l'écran ; vrai geste à la souris ; aucune entité ni ligne d'Annuler. H19. |
| **AG-039 — Axe et rubans** | AG-037 | Polyligne à rayons, arcs discrétisés, décalages, rubans, bordures, fossés, talus, `RoadPlan`, validateur, `road_digest` ; noyau pur. | Largeurs exactes en droite et en courbe, sommets communs entre rubans, rayon limite et premier dépassement, 100 tracés pseudo-aléatoires reproductibles. U24. |
| **AG-040 — Arbres, lampadaires, haies, clôtures** | AG-039, D-09 | Répétition au pas, lignes continues, définitions partagées par variante et hauteur, variation par clé, plafonds. | Nombre et positions exacts à la main sur droite et courbe, même empreinte à même seed, définitions partagées, plafond et premier dépassement. U25. |
| **AG-041 — Rails et tram** | AG-039 | Rails à 1,435 m, traverses et ballast, plateforme tram, voie mixte à rails encastrés, poteaux de caténaire. | Écartement exact en droite et en courbe, rails au niveau de la chaussée en voie mixte, faces orientées. U26. |
| **AG-042 — Écrire, tracer, modifier, RBZ 0.5.0** | AG-038, AG-040, AG-041 | Racine `archgen.road`, tags, matériaux, outil de tracé à rayons, modifier au panneau, guide, journal, RBZ. | Une entrée d'Annuler, pannes sans résidu, aller-retour SKP, copie isolée, charge publiée sur 100 m, 1 km et 2 km ; vrai geste à la souris ; H01 à H20 rejouées sur le RBZ. H20. |
| **AG-043 — Réseau et carrefour simple** | AG-042, D-07 | Nœuds et branches, carrefour à 3 à 6 branches, angles de trottoir arrondis, raccord entre deux coupes, refus d'une autoroute à niveau. | T et X à plusieurs angles et coupes différentes, surfaces sans trou ni recouvrement, refus localisés. U27. |
| **AG-044 — Carrefour à feux** | AG-043 | Feux aux angles, lignes d'arrêt, passages piétons déduits de la coupe. | Un feu par sens entrant, passages sur chaque branche à trottoir, refus sans chaussée. U28. |
| **AG-045 — Giratoire** | AG-043 | Anneau, îlot central, îlots séparateurs, rayon et largeur réglables. | Géométrie exacte à la main sur 3 et 4 branches, rayon limite et premier dépassement. U29. |
| **AG-046 — Double giratoire** | AG-045 | Deux nœuds voisins sur une même voie jumelés en deux anneaux, le bout de voie entre eux pour liaison (ADR-37). | Même entrée, même répartition ; liaison trop courte refusée. U30. |
| **AG-047 — Tram au carrefour** | AG-041, AG-045 | Tram à travers un nœud et un îlot central, rails au ras. Le passage à niveau passe en AG-050 : il demande une route en rampe. | Rails continus, branches non opposées refusées, voie ferrée refusée. U31. |
| **AG-048 — Panneau de carrefour, RBZ 0.6.0** | AG-044, AG-046, AG-047 | Choisir et régler un carrefour, aperçu en plan, guide, journal, RBZ. | Quatre types écrits et rouverts, une entrée d'Annuler, charge publiée ; vrai geste à la souris ; recettes rejouées sur le RBZ. H21. |
| **AG-049 — Voie sur un terrain** | AG-042, ADR-38 | Selon ADR-38 : profil en long relevé, pente bornée, talus raccordés au terrain (étape 1, noyau), puis copie entaillée du terrain et écriture (étape 2). | Pentes et talus à la main, refus localisés, plan inchangé sans `ground` (U32) ; copie entaillée, original intact et masqué, une opération, pannes sans résidu (H22). |
| **AG-050 — Passage à niveau** | AG-047, AG-049 | Voie ferrée × route à niveau : la route monte en rampe au dessus des rails, platelage, rails au ras, barrières et feux de passage. Contrat à compléter avant le code. | Rampes de pente bornée, rails continus, voie ferrée hors passage à niveau toujours refusée. U33. |
| **AG-060 — Clous et plots (D-10)** | AG-044, ADR-42 | Plot de chaussée, élément d'une bande roulante sur sa limite gauche ; clous de passage piéton en option d'un carrefour à feux ; panneaux. | Positions à la main, refus localisés, voies et réseaux d'avant inchangés. U41. |

## J9 — Eau et littoral (EXT-13)

Contrat : [EAU_CONTRACT](../docs/EAU_CONTRACT.md). Décision : ADR-39. Les cours d'eau et les côtes sont des voies : chaque ticket prolonge la voirie sans changer une voie existante. Les ponts suivent ADR-40 et leur [contrat](../docs/PONT_CONTRACT.md).

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-051 — Bandes d'eau et de berge** | AG-042, ADR-39 | Bandes `water`, `quay`, `riverbank`, revanche et profondeur, lit, réglage `water`, préréglages canal, rivière et fleuve ; voie horizontale. | Lit et murs exacts à la main, eau sans bord, eau trop étroite, berge trop raide et mode manquant refusés avec chemin ; voies existantes inchangées (mêmes empreintes). U34. |
| **AG-052 — Littoral : falaise, dune, plage, mer** | AG-051 | Bandes `cliff`, `rocks`, `dune`, `beach`, `sea` à niveaux cumulés, ganivelles et murets, trois préréglages côtiers. | Niveaux à la main sur les trois préréglages, mer ailleurs qu'au bout refusée, ganivelle hors dune ou plage refusée, rayon côté mer refusé. U35. |
| **AG-053 — Rivière sur un terrain** | AG-049, AG-051 | Mode `river` : enveloppe descendante, pente bornée, tracé de l'amont vers l'aval, lit creusé dans la copie entaillée. | Eau jamais remontante sur une vallée à bosse, tracé inversé refusé, déblai borné ; copie entaillée et une opération (H23). U36. |
| **AG-054 — Canal à écluses** | AG-053 | Mode `canal` : biefs horizontaux, écluses placées par règle, chambre, portes busquées, rampes des berges. | Nombre, abscisses et chutes à la main sur un plan incliné, écluse en courbe et écluses trop proches refusées, portes partagées. U37. |
| **AG-055 — Fleuve et côte à un seul niveau** | AG-052, AG-053 | Mode `flat` : niveau saisi ou plus bas du profil ; côté mer sans talus, terrain entaillé jusqu'au bord de la mer. | Niveau unique, terrain accidenté refusé, mer sans talus, terrain au-delà intact. U38. |
| **AG-056 — Panneau de l'eau, RBZ 0.8.0** | AG-054, AG-055 | Bandes et réglages au panneau, coupe à niveaux cumulés, aperçu des écluses, guide, journal, RBZ. | Rivière, canal, fleuve et trois côtes écrits et rouverts, une entrée d'Annuler, vrai geste à la souris ; recettes rejouées sur le RBZ. H23. |
| **AG-057 — Pont à poutre** | AG-056, ADR-40 | Selon le [contrat des ponts](../docs/PONT_CONTRACT.md) : type de nœud `bridge` (poutre), voie portée en rampes, tablier, culées, murs, garde-corps ; pont né tout seul sur l'eau, cours d'eau admis dans un réseau par leurs ponts ; noyau. | Cotes, portée et rampes à la main sur l'eau, une voie ferrée et une route, en biais ; voie franchie inchangée ; objets coupés ; refus localisés ; réseaux sans pont inchangés (mêmes empreintes). U39. |
| **AG-058 — Arc et voûte** | AG-057 | Arc parabolique à montants, voûte maçonnée à arches de 20 m et piles ; gabarit et piles contrôlés. | Flèche, montants, nombre d'arches à la main ; arc dans le gabarit et pile sur une chaussée refusés. U40. |
| **AG-059 — Panneau de pont, RBZ 0.9.0** | AG-058 | Type Pont et ses réglages au panneau de réseau, eau et littoral dans le réseau, guide, journal, RBZ. | Trois genres écrits et rouverts, une entrée d'Annuler, vrai geste à la souris ; recettes rejouées sur le RBZ. H24. |

## J10 — Rues variées (EXT-08, première partie)

Contrat : [RUE_VARIEE_CONTRACT](../docs/RUE_VARIEE_CONTRACT.md). Décisions : D-13 à D-16, tranchées (ADR-44). Un ensemble sans réglage `variety` ne change pas.

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-061 — Tirage par parcelle** | AG-036, ADR-44 | Réglage `variety` du format ensemble V1 ; niveaux et toit tirés par parcelle, écart entre voisines, contrôles contre les règles du style ; noyau. | Tirage reproductible à la main sur une rue de 6 parcelles, fenêtre entre voisines, refus localisés, ensembles d'avant inchangés (mêmes empreintes). U42. |
| **AG-062 — Jointures à hauteurs différentes** | AG-061, ADR-44 | Toits contre un mur plus haut, pignons de types différents, corniches, étagement et porches inchangés. | Aucune face d'un toit dans le volume du voisin, murs mitoyens découverts aveugles, étagement sur un terrain ; vu dans SketchUp. U43. |
| **AG-063 — Panneau de rue variée, RBZ 0.10.0** | AG-062 | Case Varier les bâtiments, fourchette, écart, toits, répartition annoncée ; guide, journal, RBZ. | Rue variée créée et modifiée au vrai geste, une entrée d'Annuler ; recettes rejouées sur le RBZ. H25. |

## J11 — Détails et personnalisation (EXT-01, EXT-08)

Contrat : [DETAILS_CONTRACT](../docs/DETAILS_CONTRACT.md). Décisions : D-17 à D-22, tranchées (ADR-45). Chaque réglage est une clé facultative : un bâtiment ou un ensemble existant ne change pas.

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-064 — Menuiseries et vitrage** | AG-063, ADR-45 | `features.glazing` : vitre par fenêtre, vantail plein par porte, imposte, au LOD 1 ; rôle de matière `glass` ; révision des profils. | Comptes par baie, vitre dans le jour du cadre, empreintes d'avant inchangées. U44. |
| **AG-065 — Rez-de-chaussée commerçant** | AG-064, ADR-45 | `ground_floor: shop`, `shop.height_m` ; vitrines `shopfront` entre trumeaux, bandeau, entrée gardée, porte vitrée ; porche et balcons compatibles. | Vitrines sur la trame, trumeau trop étroit refusé, rue entière en commerce. U45. |
| **AG-066 — Cheminées** | AG-064, ADR-45 | `features.chimneys` : 1 ou 2 souches contre les murs latéraux, couronnement, sur chaque type de toit, jamais chez le voisin. | Hauteur au-dessus du faîtage, tirage reproductible, aucune face hors parcelle. U46. |
| **AG-067 — Section Détails aux panneaux, RBZ 0.11.0** | AG-065, AG-066, ADR-45 | Cases Vitrage, Commerce et sa hauteur, Cheminées au panneau du bâtiment et de la rue ; guide, journal, RBZ. | Bâtiment et rue créés et modifiés au vrai geste, une entrée d'Annuler ; recettes rejouées. H26. |
| **AG-068 — Réglages propres d'une parcelle** | AG-067, ADR-45 | Clé `parcels` du format ensemble : niveaux, toit, commerce, cheminées, vitrage, largeur ; priorité sur la variété ; ids inconnus refusés. | Priorité vérifiée à la main, voisine qui absorbe la largeur, refus localisés, ensembles d'avant inchangés. U47. |
| **AG-069 — Clic droit « Personnaliser ce bâtiment », RBZ 0.12.0** | AG-068, ADR-45 | Menu contextuel sur une parcelle dans l'ensemble ouvert, panneau de parcelle, retour au réglage de la rue, régénération en une opération. | Vrai geste au clic droit, une entrée d'Annuler, refus sans résidu, réouverture. H27. |

## J12 — Volets, lucarnes et petits bois (EXT-01)

Contrat : [VOLETS_LUCARNES_CONTRACT](../docs/VOLETS_LUCARNES_CONTRACT.md). Décisions : D-23 à D-27, tranchées (ADR-47). Chaque réglage est une clé facultative : un bâtiment ou un ensemble existant ne change pas.

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-070 — Petits bois** | AG-069, ADR-47 | `features.muntins` avec le vitrage : montant central et traverses selon `facade.muntin_rows` du style, dans la définition du cadre. | Comptes de barres, rien sans vitrage, empreintes d'avant inchangées. U48. |
| **AG-071 — Volets** | AG-070, ADR-47 | `features.shutters`, rôle `materials.shutters` : deux battants ouverts par fenêtre ; refus `shutters_no_room` ; nouvelles teintes au catalogue. | Battants placés, rien sur portes et vitrines, refus localisé. U49. |
| **AG-072 — Lucarnes** | AG-071, ADR-47 | `features.dormers` : une lucarne par travée avant, sur mansarde, deux pans et croupe ; avertissement sur toit plat ; refus faute de place ; rangées et cheminées compatibles. | Une par travée, sur chaque toit, aucune face hors parcelle. U50. |
| **AG-073 — Styles et panneaux, RBZ 0.13.0** | AG-072, ADR-47 | Révision 3 des styles selon D-27 ; cases Petits bois, Volets, Lucarnes aux panneaux du bâtiment, de la rue et de la parcelle ; guide, journal, RBZ. | Panneaux essayés, version installée ; recette H28 à la main. |

## J13 — Styles régionaux maçonnés (EXT-01)

Contrat : [STYLES_REGIONAUX_CONTRACT](../docs/STYLES_REGIONAUX_CONTRACT.md). Décisions : ADR-48 (choix de détail délégués, options recommandées). Plan des lots J13 à J17 dans le contrat.

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-074 — Génoises** | AG-073, ADR-48 | `features.genoise` : deux rangs en encorbellement sous l'égout, avant et arrière, deux pans et croupe ; refus avec corniche ou baie trop haute. | Rangs et saillies, avertissement sur toit plat ou mansarde, rangée d'angle. U51. |
| **AG-075 — Provençal, matières régionales** | AG-074 | Profils Provençal — mas et — maison de village ; nouvelles matières du catalogue. | Profils valides, défauts en bâtiment, rue et îlot. U52. |
| **AG-076 — Breton** | AG-075 | Profils Breton — longère et — maison de bourg. | Idem. U52. |
| **AG-077 — Lyonnais, Bordelais, Parisien faubourien** | AG-076 | Trois profils, formes d'accès d'îlot. | Idem. U52. |
| **AG-078 — Panneaux, RBZ 0.14.0** | AG-077 | Styles groupés par famille, case Génoise aux trois panneaux ; guide, journal, RBZ. | Panneaux essayés, version installée ; recette H29 à la main. |

## J14 — Pignon sur rue et montagne (EXT-01)

Contrat : [PIGNON_MONTAGNE_CONTRACT](../docs/PIGNON_MONTAGNE_CONTRACT.md). Décisions : ADR-48 (choix de détail délégués).

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-079 — Faîtage perpendiculaire** | AG-078, ADR-48 | `roof.ridge: perpendicular` pour deux pans : bâtiment seul et rangée ; angle averti ; cheminées, lucarnes, génoise adaptées. | Pans et pignons, rangée sans débord latéral, refus hors deux pans. U53. |
| **AG-080 — Pignon à redents** | AG-079 | `features.stepped_gable` : marches au-dessus du toit sur le pignon avant. | Marches au-dessus de la pente, refus sans faîtage perpendiculaire. U54. |
| **AG-081 — Bardage bois** | AG-080 | `features.cladding`, `materials.cladding` : dernier niveau, pignons et balcons en bois. | Matières par niveau, empreintes d'avant inchangées. U54. |
| **AG-082 — Flamand, Savoyard, RBZ 0.15.0** | AG-081 | Deux profils ; liste Faîtage et cases aux trois panneaux ; guide, journal, RBZ. | Profils en bâtiment, rue et îlot ; panneaux essayés ; recette H30 à la main. |

## J15 — Pan de bois (EXT-02)

Contrat : [PAN_DE_BOIS_CONTRACT](../docs/PAN_DE_BOIS_CONTRACT.md). Décisions : ADR-48 (choix de détail délégués) ; encorbellement reporté, consigné au contrat.

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-083 — Pan de bois apparent** | AG-082, ADR-48 | `features.timber_frame`, `materials.timber` : sablières, poteaux, huisseries, décharges aux étages ; refus des détails concurrents. | Pièces placées, solides valides, deux modes. U55. |
| **AG-084 — Colombages, Normand, Alsacien, Basque** | AG-083 | Quatre profils. | Profils en bâtiment, rue et îlot. U52. |
| **AG-085 — Panneaux, RBZ 0.16.0** | AG-084 | Case Pan de bois aux trois panneaux ; guide, journal, RBZ. | Panneaux essayés, version installée ; recette H31 à la main. |

## J16 — Arcs et ornements (EXT-03)

Contrat : [ARCS_ORNEMENTS_CONTRACT](../docs/ARCS_ORNEMENTS_CONTRACT.md). Décisions : ADR-48 (choix de détail délégués) ; portée et approximations consignées au contrat.

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-086 — Arcs** | AG-085, ADR-48 | `facade.arch` plein cintre ou brisé : écoinçons devant les baies ; refus d'une baie trop basse. | Tracés, refus, deux modes. U56. |
| **AG-087 — Ornements classiques** | AG-086 | `features.classical` : pilastres, soubassement, fronton d'entrée ; refus localisés. | Pièces placées, refus. U57. |
| **AG-088 — Neuf profils** | AG-087 | Maison romane, maison gothique, Renaissance, Néoclassique, Baroque, Art déco, Art nouveau, Méditerranéen cycladique et andalou. | Profils en bâtiment, rue et îlot. U52. |
| **AG-089 — Panneaux, RBZ 0.17.0** | AG-088 | Liste Arcs et case Ornements ; guide, journal, RBZ. | Panneaux essayés, version installée ; recette H32 à la main. |

## J17 — Volumes modernes (EXT-04)

Contrat : [VOLUMES_MODERNES_CONTRACT](../docs/VOLUMES_MODERNES_CONTRACT.md). Décisions : ADR-48 ; volumes assemblés et scénario climatique reportés.

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-090 — Bandeaux et murs-rideaux** | AG-089, ADR-48 | `facade.ribbon` : une baie par étage de marge à marge, montants. | Baies, montants, refus. U58. |
| **AG-091 — Pilotis** | AG-090 | `features.pilotis` : rez-de-chaussée ouvert, poteaux, sous-face. | Murs et baies absents au RDC, poteaux, refus. U59. |
| **AG-092 — Toit en sheds** | AG-091 | Type de toit `sawtooth`, bâtiment seul et rangée. | Dents, faces vitrées, rangée. U60. |
| **AG-093 — Trame structurelle et brise-soleil** | AG-092 | `features.structural_grid`, `features.sun_shades`. | Pièces placées. U61. |
| **AG-094 — Sept profils, RBZ 0.18.0** | AG-093 | Bauhaus, Moderniste, Mid-century, Minimaliste, Industriel, High-tech, Bioclimatique ; panneaux ; guide, journal, RBZ. | Profils en bâtiment, rue et îlot ; recette H33 à la main. |

## J18 — Ville mixte (EXT-08)

Contrat : [VILLE_MIXTE_CONTRACT](../docs/VILLE_MIXTE_CONTRACT.md). Décisions : ADR-49 (plusieurs styles par rue) ; détails selon ADR-48.

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-095 — Clic droit Modifier** | AG-094 | Menu contextuel sur une racine de bâtiment ou de rue. | Sélection reconnue. U62. |
| **AG-096 — Style par bâtiment** | AG-095, ADR-49 | `parcels.<id>.style`, révision figée ; panneau de parcelle. | Style appliqué, voisins inchangés, refus. U63. |
| **AG-097 — Rez-de-chaussée variés** | AG-096 | `variety.ground` : entrée, part de commerces, largeurs. | Tirages reproductibles, réglage propre prioritaire. U64. |
| **AG-098 — Stores bannes et pergolas** | AG-097 | `shop.front`, matière de toile. | Pièces placées, refus. U65. |
| **AG-099 — Panneaux, RBZ 0.19.0** | AG-098 | Listes et cases ; guide, journal, RBZ. | Panneaux essayés ; recette H34 à la main. |

## J19 — Carrefours sans réseau, dalle et seuils

Contrat : [CARREFOURS_DALLE_CONTRACT](../docs/CARREFOURS_DALLE_CONTRACT.md). Décisions : ADR-50 (dalle par défaut à la création) ; détails selon ADR-48.

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-100 — Dalle de rez-de-chaussée et seuils** | AG-099, ADR-50 | `structure.ground_slab` ; dalle et seuils au LOD 0 ; écrit à la création. | Dalle, seuils, existant inchangé. U66. |
| **AG-101 — T plus tolérants** | AG-100 | Bout sur la chaussée ou léger dépassement : un T. | Cas de T. U67. |
| **AG-102 — Carrefours depuis Tracer une voie** | AG-101 | Voies touchées fusionnées en un réseau, une opération. | Fusion, refus. U68. |
| **AG-103 — RBZ 0.20.0** | AG-102 | Guide, journal, RBZ. | Version installée ; recette H35 à la main. |

## J20 — Teintes et abords

Contrat : [TEINTES_ABORDS_CONTRACT](../docs/TEINTES_ABORDS_CONTRACT.md). Décisions : ADR-51 (teintes tirées par bâtiment) ; détails selon ADR-48.

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-104 — Teintes** | AG-103, ADR-51 | `materials.tint` ; variantes de mur, menuiserie, volets et porte, tirées par bâtiment. | Variantes bornées, existant inchangé. U69. |
| **AG-105 — Escaliers et rampes** | AG-104 | Perron ou rampe devant une porte au-dessus du sol. | Marches, rampe, refus. U70. |
| **AG-106 — Garde-corps** | AG-105 | Garde-corps des balcons, barreaux ou plein. | Garde-corps. U71. |
| **AG-107 — Tour d'îlot** | AG-106 | Écart de hauteur contrôlé sur tout le tour d'un îlot varié. | Tour sans saut. U72. |
| **AG-108 — Dalle pour l'existant, RBZ 0.21.0** | AG-107 | Case au panneau de rue ; guide, journal, RBZ. | Version installée ; recette H36 à la main. |
| **AG-109 — Talus entre voisins dans une rue** | AG-108 | Relevé devant et derrière chaque parcelle ; talus avant et arrière ; soutènement aux limites mitoyennes ; RBZ 0.22.0. | Talus, soutènement, refus hors rue droite. U73. |

## J23 — Décor de jeu

Contrat : [DECOR_JEU_CONTRACT](../docs/DECOR_JEU_CONTRACT.md). Décisions : ADR-54 (adaptateur glTF séparé) ; D-27 à D-32 selon ADR-48, révisables. Passe avant J21 et J22 (ADR-53).

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-115 — Triangulation et écriture glTF** | AG-109, ADR-54 | `adapters/gltf` : oreilles, normales plates, axes Y, maillages partagés, GLB déterministe. | Octets identiques, n − 2 triangles, refus localisé. U78 vert ; sonde Blender. |
| **AG-116 — UV et matériaux PBR** | AG-115 | Projection cubique 1 m ; métal-rugosité, `roughness`/`metallic` facultatifs au catalogue ; verre ; double face. | UV, matériaux, teintes. U79 vert ; sonde Blender. |
| **AG-117 — LOD et collisions** | AG-116 | LOD0, LOD1 (`lod: 0`), LOD2 enveloppe convexe ; collision `UCX_`. | Triangles décroissants, collisions convexes. U80 vert ; sonde Blender. |
| **AG-118 — Commande d'export** | AG-117 | Clic droit → Exporter pour un moteur de jeu… ; bâtiment ou rue ; refus réseau et terrain ; rapport. | Modèle intact, hôte factice. U81 vert ; H38 à faire. |
| **AG-119 — Guide, RBZ 0.23.0** | AG-118 | Section Décor de jeu ; journal ; RBZ. | Version installée ; recette H38 à la main (à faire). |

## J24 — Mobilier urbain

Contrat : [MOBILIER_CONTRACT](../docs/MOBILIER_CONTRACT.md). Décisions : ADR-55 (dans la coupe) ; D-33 à D-37 selon ADR-48, révisables.

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-120 — Catalogue et formes** | AG-119, ADR-55 | `bench`, `bin`, `bike_rack`, `bus_stop`, `sign` au catalogue ; formes ; matières bleu, verre, jaune ; bandes admises. | Solides fermés, définitions partagées, copies identiques. U82. |
| **AG-121 — Pose à des positions** | AG-120 | `positions_m` pour tout élément ponctuel ; refus hors tronçon, avec un pas, positions exigées. | Pose exacte sur droite et arc. U83. |
| **AG-122 — Arrêt de bus** | AG-121 | Abri ouvert vers la chaussée, mât seul ; bande de 1,6 m ; marquage jaune ; proximité. | U84. |
| **AG-123 — Panneaux** | AG-121 | Huit plaques, sens `forward`/`backward`, mât. | U85. |
| **AG-124 — Éditeur, RBZ 0.24.0** | AG-122, AG-123 | Types, Positions et Sens dans l'éditeur ; préréglage arrêt de bus ; guide, journal, RBZ. | U86 ; recette H39 à la main. |

## J21 — Intérieur

**Reporté le 2026-11-10 (ADR-53)** : aucun ticket J21 ne démarre avant EXT-06, EXT-12, EXT-09, EXT-08 et J22. À la reprise, l'intérieur se crée au cas par cas, au clic droit, jamais pour une rue entière.

Contrat : [INTERIEUR_CONTRACT](../docs/INTERIEUR_CONTRACT.md). Décisions : ADR-52 (option des deux modes), ADR-53 (report, cas par cas) ; D-23 à D-26 selon ADR-48, révisables.

| Ticket | Dépendances | Périmètre / résultat attendu | Acceptation et preuve |
|---|---|---|---|
| **AG-110 — Planchers et calque Intérieur** | J22, ADR-52, ADR-53 | `interior.floors` ; catégories `floor`, `stair`, `partition` ; tag ARCHGEN Intérieur. | Planchers Shell, Structural inchangé, existant inchangé. U74. |
| **AG-111 — Escalier et trémies** | AG-110 | `interior.stair` : deux volées par étage, trémie découpée, placement D-24. | Marches égales, trémie, refus localisés. U75. |
| **AG-112 — Cloisons et pièces** | AG-111 | `interior.rooms` : enfilade sur les trumeaux, portes, cage fermée. | Baies évitées, commerce ouvert. U76. |
| **AG-113 — Créer l'intérieur au clic droit** | AG-112 | Clic droit ARCHGEN → Créer / Retirer l'intérieur, sur un seul bâtiment ; dans une rue, personnalisation de la parcelle ; mur mitoyen, porche, budgets. Pas de bloc au gabarit de rue. | Une maison, voisines inchangées, un Undo, budget. U77. |
| **AG-114 — Panneau, RBZ** | AG-113 | Section Intérieur au panneau du bâtiment seulement ; guide, journal, RBZ. | Version installée ; recette H37 à la main. |

**Définition de terminé.** Livrable revu et intégré, preuve liée au ticket, test de non-régression pertinent, contrats à jour et aucune régression connue bloquante. Si un prérequis échoue, consigner cause, preuve et prochaine étape. Le simple affichage d'un rendu ne valide pas les ouvertures, le rollback ou les unités.
