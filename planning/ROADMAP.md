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
| J12 — Volets, lucarnes et petits bois | J11, D-23 à D-27 | AG-070–073 | Petits bois, volets ouverts, lucarnes sur les pans avant ; révision 3 des styles ; RBZ 0.13.0. |
| J13+ — Bibliothèque, intérieur, ville, mobilier | J5 + contrats par capacité | EXT-01–06, EXT-08, EXT-09, EXT-12 | Voir [extensions](../docs/FUTURE.md) ; aucune dépendance de livraison inverse. |

Les branches AG-004/005, AG-007/009 et AG-018/019 sont indépendantes une fois leurs prérequis satisfaits. Les dépendances dans [TASKS](TASKS.md) priment sur les numéros et permettent de commencer du Ruby pur avant de fermer J0 ; la table fixe l'ordre de validation des jalons. Attacher les éléments de preuve au ticket et garder une démo neutre de référence. Sans hôte disponible, continuer sur les tests purs ; ne pas franchir un jalon qui requiert la recette native.

**Chemin critique produit :** charger et valider → plan neutre → géométrie SketchUp → sauvegarder et régénérer une cible → styles et UI → recette. Une idée nouvelle entre dans la liste des extensions ; modifier la V0.1 seulement avec une décision écrite, un test et les impacts sur les tickets.
