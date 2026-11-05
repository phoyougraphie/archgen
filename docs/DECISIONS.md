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

ADR-03 à 10 précisent les points laissés ouverts dans le fil, avec des choix de départ révisables par décision écrite. Au démarrage, AG-001 consigne les versions hôtes réellement accessibles. Les seuils de performance sont des cibles de livraison à mesurer, et les plages historiques des réglages de conception à calibrer.
