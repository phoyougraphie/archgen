# ARCHGEN — dossier de développement V0.1

ARCHGEN est une extension SketchUp Desktop, ciblant Windows et SketchUp 2026 en V0.1, qui génère des bâtiments paramétriques pour la maquette architecturale et la création de décors. Ce dépôt contient la spécification et le code en cours de développement. La version 0.19.0 ajoute le clic droit Modifier, plusieurs styles dans une même rue, des rez-de-chaussée variés, les stores et pergolas ; la 0.18.0, les volumes modernes et sept styles (32 styles en tout) ; la 0.17.0, les arcs, les ornements classiques et neuf styles historiques et méditerranéens ; la 0.16.0, le pan de bois et quatre styles (colombages, Normand, Alsacien, Basque) ; la 0.15.0, le pignon sur rue, le pignon à redents, le bardage bois et les styles Flamand et Savoyard ; la 0.14.0, sept styles régionaux (Provençal, Breton, Lyonnais, Bordelais, Parisien faubourien) et les génoises, après le vitrage, les commerces, les cheminées, les petits bois, les volets, les lucarnes et la personnalisation d'un bâtiment d'une rue au clic droit ; ses recettes H26 à H34 dans SketchUp restent à faire. La 0.10.0, qui permet de varier les hauteurs et les toits d'une rue ou d'un îlot, est recettée sur Windows 11 et SketchUp 26.2.243 ([rapport](docs/recette/V0.10.md)). Pour l'utiliser : [guide](docs/GUIDE.md) et [journal des versions](CHANGELOG.md). Le paquet se construit avec `bundle exec rake package`.

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
