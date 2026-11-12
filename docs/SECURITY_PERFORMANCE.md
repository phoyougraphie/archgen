# Sécurité et performances

Le plugin V0.1 fonctionne hors ligne. Entrées non fiables : pont JS, JSON, anciens SKP, attributs d'instance, futures bibliothèques externes. Protéger le modèle autant contre un formulaire invalide que contre un fichier modifié.

| Surface | Règle |
|---|---|
| JSON | UTF-8 ; ≤64 Kio par requête et config, profondeur ≤12, clés dupliquées rejetées, nombres finis, bornes contrôlées avant allocation. Pas de YAML objet, Marshal, eval, accès fichier ou exécution de règle arbitraire. |
| Dialogue | HTML/CSS/JS locaux, politique CSP restrictive sans script inline, pas de CDN. Écrire le texte avec `textContent`. Ruby appelle un nom JS fixe via `execute_script` avec une chaîne de JSON encodée à nouveau comme littéral JS sûr (échapper U+2028/U+2029) ; JS parse cette chaîne. |
| Accès hôte | Allowlist actions/champs, jetons opaques limités à la session, à la cible et au modèle. Rejeter les ids ou actions forgés, le rejeu d'une mutation et les destinations imbriquées. Un marqueur d'attribut ne suffit pas à garantir l'intégrité des données. |
| Données | Aucun envoi ni télémétrie. Exceptions (ADR-57, ADR-59) : le téléchargement OpenStreetMap et celui des tuiles du fond de plan (tile.openstreetmap.org, data.geopf.fr), confirmé à chaque fois, n'envoie qu'une emprise et `User-Agent: ARCHGEN/<version>` à un hôte Overpass de la liste fermée, depuis l'adaptateur. Logs locaux bornés en mémoire (100 entrées), sans chemins personnels, JSON complet ni nom du document ; détail technique seulement en mode développement. |
| Fichiers | Un seul module écrit des fichiers (`Adapters::SketchUp::LocalFiles`, ADR-71), dans des dossiers fixés par ARCHGEN : export à côté du SKP, cache du fond de plan, `%APPDATA%\ARCHGEN\recettes`. Écriture atomique ; aucun chemin choisi par une page ou un profil. |
| Assets | Catalogue embarqué par ID. Une future importation doit vérifier provenance, licence, taille et chemins canoniques. Aucune URL distante ni écriture choisie par profil. |

**Limites bloquantes V0.1** (rejet avant écriture) : 60 × 60 m au plan, ≤15 niveaux, ≤60 m sous toit et ≤90 m au sommet ; ≤720 ouvertures ; ≤30 000 faces uniques, ≤60 000 faces après expansion des instances, ≤100 000 cellules candidates de murs au total, ≤128 définitions de détail distinctes par plan. Pré-estimer les cellules via les coupes U/Z uniques après calcul des ouvertures ; contrôler les compteurs réels avant écriture, puis dans l'hôte. Un plan ne doit pas s'approcher des plafonds à cause d'un détail caché ; proposer « Réduire les travées, les niveaux ou le niveau de détail ».

**Cibles de sortie**, sur poste de référence documenté (CPU, RAM, OS, SketchUp, version moteur) :

| Mesure | Fixture | Cible |
|---|---|---|
| Calcul d'aperçu / plan | Haussmannien 12 × 9, deux modes | p95 ≤150 ms hors temporisation et rendu |
| Écriture native | Même cas LOD 1 | p95 ≤2 s depuis start_operation jusqu'au commit |
| Écriture native soutenue | 24 × 18, 10 niveaux, 8 travées frontales et 4 latérales, plat, Structural LOD 1 | p95 ≤5 s |
| Croissance | 20 régénérations avec la même géométrie, même SKP et session | Définitions de cadres stables, aucune ressource orpheline d'échec ; SKP final ≤10 Mo au-dessus du SKP initial. |

Mesurer avec une horloge monotone, 3 échauffements puis 20 passages par scénario (p95 rang 19 sur 20), sur modèles réinitialisés pour les trois premiers tests. Enregistrer faces, définitions, SKP et diagnostics. Profilage par phase (calcul, validation, adaptation, ressources, commit). Ne pas garder une transaction ouverte entre des rappels UI. Partager les détails réellement répétés et privilégier l'émission par lots ; optimisation au-delà des cibles seulement après profilage. L'interface montre l'activité et empêche les écritures concurrentes, sans promettre une annulation pendant l'appel natif.
