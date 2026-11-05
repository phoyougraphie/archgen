# Extensions après V0.1

Chaque capacité débute par un contrat pur, une fixture et une mesure de charge. L'API runtime reste versionnée ; les vieux bâtiments sont relus avec leurs données et versions. L'absence d'un module bloque la publication d'un profil qui en dépend.

| Lot | Dépendances | Livrable et porte |
|---|---|---|
| EXT-01 — Richesse régionale | J5 | Axes de faîtage, volets, encadrements, lucarnes, débords et variantes versionnées ; premiers profils Provençal, Breton et variantes maçonnées quand les règles et ressources sont prêtes. Tester défauts, attaches et dégradations LOD. |
| EXT-02 — Bois traditionnel | J5, EXT-01 | TimberFrameSolver, nœuds, poteaux, traverses, diagonales et encorbellement ; Basque, Colombages, Normand, Alsacien par sous-profil. Baies et contreventement ne se coupent pas. |
| EXT-03 — Courbes et décor | J5 | Arcs plein cintre/brisés puis courbes, reliefs, corniches profilées, ordres et portiques ; Art déco, Art nouveau, Baroque, Néoclassique, Renaissance et sous-profils méditerranéens selon les capacités. Roman/Gothique suivent après volumes composés, voûtes et contreforts. Erreur de discrétisation et budget documentés. |
| EXT-04 — Volumes et technique | J5 | Retraits, volumes joints, trame structurelle, sheds, façade rideau, protections ; styles modernes et Industriel, High-tech. Bioclimatique dépend du nord, du scénario climatique et des hypothèses explicites. Ne pas confondre représentation et simulation. |
| EXT-05 — Interior | J5 + volumes multi-pièces | Cloisons, pièces, circulations et escaliers, trémies coordonnées aux dalles ; conserver Shell/Structural et leurs migrations. Ne pas produire d'escalier sans résolution de la hauteur et de la trémie. |
| EXT-06 — Décor de jeu | J5 | Exporteur optionnel, triangulation, UV, matériaux PBR, axes, collisions et LOD 2. Mesurer triangles et importer dans les moteurs choisis ; conserver un adaptateur séparé. |
| EXT-07 — Rue et parcelles | J5 + contrat placement et empreintes | Graphe de rues, trottoirs, intersections, parcelles ; placement bâtiment déterministe, aucune collision entre parcelles. Undo borné et lots mesurés. |
| EXT-08 — Quartier | EXT-07 | Densité, mixité, catalogue local, seeds par parcelle et mises à jour ciblées. Limiter calcul, mémoire et affichage à grande échelle. |
| EXT-09 — Cartographie et terrain | EXT-07 + ADR données et licences | Import géospatial (dont OpenStreetMap en option), projection, unités, terrain et attribution. Valider précision et disponibilité des sources ; garder un mode local. |

Le [catalogue](styles/CATALOGUE.md) donne pour chaque style les prérequis fins et un oracle de recette. Regrouper les ajouts par capacité ; une dépendance de profil peut nécessiter plusieurs lots. Les profils à grande emprise, aux plafonds élevés ou à typologies nouvelles demandent une extension explicite du schéma et des budgets. Un futur moteur de variation gère l'époque, les transformations, l'usure et les textures avec des clés déterministes. Un autre adaptateur, par exemple Blender, ne change pas le noyau et doit démontrer la parité du plan.
