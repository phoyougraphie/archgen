# Roadmap à dépendances — V0.1 puis extensions

Un jalon se ferme sur une preuve (test, rapport ou démonstration). Développer sur le profil interne neutre ; les données de style ne masquent jamais un défaut du noyau.

| Jalon | Entrée | Tickets | Porte de sortie |
|---|---|---|---|
| J0 — Base | Dépôt prêt | AG-001–002 | Projet Ruby testable et panneau local installable sur un hôte de référence. |
| J1 — Données | J0 | AG-003–005 | Brouillons et effectifs vérifiés, héritage générique, seed stable ; fixtures sans SketchUp. |
| J2 — Enveloppe neutre | J1 | AG-006–010 | Shell et Structural ; découpes, dalles et quatre toits éprouvés en Ruby ; plans quantifiés et bornés. |
| J3 — Adaptateur et persistance | J2 | AG-011–014 | Une racine native, aller-retour SKP, Undo/Redo, copie isolée et échecs restaurés. |
| J4 — Styles et panneau | J3 | AG-015–017 | Trois signatures, réglages et aperçu réels, confirmation et diagnostics lisibles. |
| J5 — Livraison | J4 | AG-018–020 | Recette sur Windows et SketchUp 2026 (ADR-26), sécurité, budgets, export repère et RBZ installé. |
| J6 — Terrain d'un bâtiment | J5, ADR-27 | AG-021–026 | Assise sur un terrain réel, terrain intact, une entrée d'Annuler ; RBZ 0.2.0. |
| J7 — Rue et îlots au tracé | J6, ADR-30 à 32 | AG-028–036, puis AG-027 | Tracer une rue ou un îlot, une entrée d'Annuler ; RBZ 0.3.0 ; puis l'étager sur un terrain, RBZ 0.4.0. |
| J8 — Voirie | J7, ADR-34, D-07 à D-10 | AG-037–049 | Composer une voie en coupe à l'échelle humaine, la tracer, RBZ 0.5.0 ; carrefours, RBZ 0.6.0 ; puis sur un terrain. |
| J9 — Eau et littoral | J8, ADR-39, ADR-40 | AG-051–059 | Rivière, canal à écluses, fleuve et côtes (falaise, dune, plage) tracés comme des voies, RBZ 0.8.0 ; puis les ponts. |
| J10 — Rues variées | J7, ADR-44 | AG-061–063 | Hauteurs et toits tirés par parcelle dans une rue ou un îlot, RBZ 0.10.0. |
| J11 — Détails et personnalisation | J10, ADR-45 | AG-064–069 | Vitrage, commerces au rez-de-chaussée et cheminées, RBZ 0.11.0 ; personnaliser un bâtiment d'une rue au clic droit, RBZ 0.12.0. |
| J12 — Volets, lucarnes et petits bois | J11, ADR-47 | AG-070–073 | Petits bois, volets ouverts, lucarnes sur les pans avant ; révision 3 des styles ; RBZ 0.13.0. |
| J13 — Styles régionaux maçonnés | J12, ADR-48 | AG-074–078 | Génoises ; Provençal, Breton, Lyonnais, Bordelais, Parisien faubourien ; RBZ 0.14.0. |
| J14 — Pignon sur rue et montagne | J13, ADR-48 | AG-079–082 | Faîtage perpendiculaire, pignon à redents, bardage ; Flamand, Savoyard ; RBZ 0.15.0. |
| J15 — Pan de bois | J14, ADR-48 | AG-083–085 | Pan de bois apparent ; colombages, Normand, Alsacien, Basque ; RBZ 0.16.0. |
| J16 — Arcs et ornements | J15, ADR-48 | AG-086–089 | Arcs, ornements classiques ; neuf styles historiques et méditerranéens ; RBZ 0.17.0. |
| J17 — Volumes modernes | J16, ADR-48 | AG-090–094 | Bandeaux, murs-rideaux, pilotis, sheds, trame, brise-soleil ; sept styles modernes ; RBZ 0.18.0. | Pignon sur rue et montagne ; pan de bois ; arcs et ornements ; volumes modernes ([plan](../docs/STYLES_REGIONAUX_CONTRACT.md)). |
| J18 — Ville mixte | J17, ADR-49 | AG-095–099 | Clic droit Modifier, style par bâtiment, rez-de-chaussée variés, stores et pergolas ; RBZ 0.19.0. |
| J19 — Carrefours sans réseau, dalle et seuils | J18, ADR-50 | AG-100–103 | Dalle et seuils, T tolérants, carrefours depuis Tracer une voie ; RBZ 0.20.0. |
| J20 — Teintes et abords | J19, ADR-51 | AG-104–109 | Teintes par bâtiment, perrons et rampes, garde-corps, tour d'îlot ; RBZ 0.21.0 ; talus en rue droite, RBZ 0.22.0. |
| J23 — Décor de jeu (EXT-06) | J20, ADR-53, ADR-54 | AG-115–119, fait | Export glTF : triangles, UV, PBR, axes, collisions, trois LOD ; clic droit ; RBZ 0.23.0 ; H38 à faire. |
| J24 — Mobilier urbain (EXT-12) | J23, ADR-55 | AG-120–124, fait | Bancs, corbeilles, attaches vélos, arrêts de bus, panneaux ; pose à des positions ; RBZ 0.24.0. |
| J25 — Cartographie (EXT-09) | J24, ADR-56, ADR-57 | AG-125–129, fait | Téléchargement OpenStreetMap ou fichier local, terrain ASCII Grid : voies en réseaux, bâtiments rectangles, terrain, attribution ; RBZ 0.25.0. |
| Priorité, suite — EXT-08 | J25 | à cadrer | Quartier. |
| J22 — Emprises non rectangulaires | priorité ci-dessus | à cadrer | Emprises en L, en T et polygonales. |
| J21 — Intérieur (EXT-05), **reporté** | J22, ADR-52, ADR-53 | AG-110–114 | Planchers, escalier à deux volées et trémies, pièces en enfilade ; au cas par cas, au clic droit ; RBZ à la reprise. |
| J20+ — Bibliothèque, intérieur, ville, mobilier | J5 + contrats par capacité | EXT-01–06, EXT-08, EXT-09, EXT-12 | Voir [extensions](../docs/FUTURE.md) ; aucune dépendance de livraison inverse. |

Les branches AG-004/005, AG-007/009 et AG-018/019 sont indépendantes une fois leurs prérequis satisfaits. Les dépendances dans [TASKS](TASKS.md) priment sur les numéros et permettent de commencer du Ruby pur avant de fermer J0 ; la table fixe l'ordre de validation des jalons. Attacher les éléments de preuve au ticket et garder une démo neutre de référence. Sans hôte disponible, continuer sur les tests purs ; ne pas franchir un jalon qui requiert la recette native.

**Chemin critique produit :** charger et valider → plan neutre → géométrie SketchUp → sauvegarder et régénérer une cible → styles et UI → recette. Une idée nouvelle entre dans la liste des extensions ; modifier la V0.1 seulement avec une décision écrite, un test et les impacts sur les tickets.
