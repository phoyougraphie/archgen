# Décisions d'architecture

| ID | Décision | Motif / conséquence |
|---|---|---|
| ADR-01 | Génération hybride C : plan indépendant + writer SketchUp | Le fil a retenu cette séparation. Shell et Structural partagent les solveurs de placement. Interior est réservé. |
| ADR-02 | Trois profils actifs ; 24 fiches ; sept familles techniques | Le fil retient Haussmannien, Toulousain et Brutaliste. Les autres restent désactivés tant que leurs capacités et tests n'existent pas. |
| ADR-03 | Configuration V1 fermée, valeurs effectives figées et conservées ; saisie séparée | La réouverture ne recalcule pas de valeurs implicites. Changement de style = transition explicite. |
| ADR-04 | Une racine top-level par bâtiment, définition de remplacement fraîche | L'identité de l'instance, sa transformation et les copies restent stables. Pas d'édition imbriquée en V0.1. |
| ADR-05 | Subdivision explicite et jonctions à onglet, quatre pièces murales fermées | Évite les booléens SketchUp et les chevauchements volumétriques. La racine n'est pas un solide unique. |
| ADR-06 | Unités m/rad au calcul, degrés en saisie/JSON de config | Les champs portent leurs unités ; une seule conversion à chaque frontière. |
| ADR-07 | Aperçu 2D en dialogue, sans écriture | Même vérité géométrique, rapide, aucune trace dans l'Undo. |
| ADR-08 | Cible initiale Desktop 2024–2026, Ruby compatible 3.2, Windows et macOS | Minimum fondé sur Ruby embarqué documenté. Matrice à vérifier dans les versions réellement disponibles ; aucune compatibilité annoncée avant la recette. |
| ADR-09 | API minimale et géométrie locale ; pas de purge globale | Réduit les conflits avec les autres extensions et protège les ressources utilisateur. |
| ADR-10 | Migrations de format distinctes des changements de règles | Une migration adapte les données ; une mise à niveau d'un profil peut changer la géométrie et requiert une régénération choisie. |
| ADR-11 | Code `E_PLAN` pour tout invariant de plan violé, en plus de la liste initiale | Le contrat exige de refuser un plan invalide sans lui attribuer de code. `E_PLAN` signale une anomalie interne : `path:"/plan"`, identifiant de pièce en `params.id`. Aucune écriture. Liste mise à jour dans CONFIG_SCHEMA. |
| ADR-12 | `E_PROFILE_UNAVAILABLE` sur `/lod` tant que les détails n'existent pas | LOD 1 est refusé par le moteur jusqu'à AG-015 plutôt que d'émettre un plan sans détails : pas de réglage silencieux. Les fixtures LOD 1 ne sont générables qu'à partir de cette porte. |
| ADR-13 | Copie embarquée de `schemas/`, `examples/profiles/` et `materials.v1.json` dans `archgen/`, identité vérifiée par test | Le RBZ ne contient que `archgen.rb` et `archgen/`. `composition.rb` est le seul lecteur de fichiers du noyau. |

**Décisions ouvertes** (à trancher par le propriétaire du projet, sans changement de comportement avant cela) :

| ID | Question | Constat et options |
|---|---|---|
| D-01 | Le jitter est-il utilisable tel que spécifié ? | Le contrat tire un jitter par ouverture et refuse deux coupes distantes de moins de 2 mm, sans retentage. Sur la fixture neutre (500 graines), part de graines acceptées : 0 % à 1 cm, 1 % à 2 cm, 16 % à 5 cm, 39 % à 10 cm, 73 % à 30 cm. Tous les profils livrés ont `jitter_m = 0`, donc la V0.1 n'est pas bloquée. **Option A** : arrondir le centre tiré à une grille de 5 mm, les coupes étant alors confondues ou espacées d'au moins 5 mm (recommandée, change le plan des configurations avec jitter). **Option B** : tirer le jitter par travée et non par ouverture, les colonnes restant alignées (moins de variété). **Option C** : conserver le contrat et masquer le jitter du panneau en V0.1. |

ADR-03 à 10 précisent les points laissés ouverts dans le fil, avec des choix de départ révisables par décision écrite. Au démarrage, AG-001 consigne les versions hôtes réellement accessibles. Les seuils de performance sont des cibles de livraison à mesurer, et les plages historiques des réglages de conception à calibrer.
