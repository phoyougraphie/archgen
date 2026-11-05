# ARCHGEN — dossier de développement V0.1

ARCHGEN est une extension SketchUp Desktop qui génère des bâtiments paramétriques pour la maquette architecturale et la création de décors. Ce dépôt contient la spécification et le code en cours de développement. Il ne contient pas encore d'extension utilisable : le noyau Ruby calcule les plans, l'écriture dans SketchUp reste à faire.

**Pour commencer :** lire [la carte mentale](docs/CARTE.md) (résumé à jour, version graphique dans [docs/carte/index.html](docs/carte/index.html)), [AGENTS.md](AGENTS.md), puis prendre le prochain ticket indiqué sur la carte. Tests : `bundle exec rake test`. Le premier démonstrateur est un rectangle neutre. Les styles arrivent après le noyau.

| Besoin | Document |
|---|---|
| Parcours, périmètre et critères produit | [PRD](docs/PRD.md) |
| Modules Ruby, flux et versions | [Architecture](docs/ARCHITECTURE.md), [décisions](docs/DECISIONS.md) |
| Algorithmes, unités, primitives et invariants | [Contrat géométrique](docs/GEOMETRY_CONTRACT.md) |
| Saisie, fusion, persistance et exemples | [Configuration](docs/CONFIG_SCHEMA.md), [schémas JSON](schemas/README.md), [exemples](examples/README.md) |
| Hiérarchie, 24 styles et capacités | [Schéma des styles](docs/STYLE_SCHEMA.md), [catalogue](docs/styles/CATALOGUE.md) |
| Panneau, requêtes et messages | [Interface](docs/UI_SPEC.md) |
| Modification ciblée, copies, annulation | [Régénération](docs/REGENERATION.md) |
| Livraison et validation | [Roadmap](planning/ROADMAP.md), [tickets](planning/TASKS.md), [tests](docs/TESTING.md) |
| Ruby, SketchUp, garde-fous et budgets | [Conventions](docs/RUBY_SKETCHUP.md), [sécurité et performances](docs/SECURITY_PERFORMANCE.md) |
| Capacités après V0.1 | [Extensions](docs/FUTURE.md), [rue, îlots et terrain](docs/RUE_ILOT_TERRAIN.md) |

**V0.1 :** une emprise rectangulaire, deux modes géométriques (Shell et Structural), deux niveaux de détail indépendants, quatre types de toit, trois profils jouables. Les 24 styles sont spécifiés ; seuls les trois profils V0.1 sont sélectionnables à la livraison.

Références : [fil de conception ARCHGEN](chatgpt-conversation://6aebb8f0-acb8-83e9-bb44-e6099aa7a827) et [documentation technique officielle](docs/RUBY_SKETCHUP.md#références). Les calibrations et décisions ajoutées pour permettre le codage sont explicitées dans [DECISIONS](docs/DECISIONS.md).
