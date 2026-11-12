# Contrat des carrefours sans réseau, et de la dalle et des seuils — J19 (AG-100 à AG-103)

**Demande du propriétaire (2026-11-10).** « Je rencontre toujours des difficultés avec les carrefours en T » ; « dommage d'être obligé de passer par les réseaux de voies pour faire des carrefours » ; « les maisons n'ont pas de dalle au rez-de-chaussée ni de seuil aux portes : cela crée des trous entre la rue et les maisons ». Choix de détail selon ADR-48 (options recommandées, révisables) ; changement de comportement par défaut consigné en ADR-50.

## 1. Dalle de rez-de-chaussée et seuils — AG-100

Réglage `structure.ground_slab` (booléen) ; absent, rien ne change (un bâtiment ou une rue d'avant garde son plan).

| Élément | Géométrie |
|---|---|
| **Dalle** | Shell : une face à z = 0 sur toute l'emprise, tournée vers le haut. Structural : une dalle de `structure.slab_m` sous z = 0, entre les faces intérieures des murs. Aucune sur pilotis |
| **Seuils** | Sous chaque porte d'entrée : une marche de 0,03 m de haut, de la largeur de la porte, de 0,20 m devant le nu jusqu'à l'intérieur du mur (Structural) ou 0,05 m derrière le nu (Shell) ; matière du mur |

Au LOD 0 : ils ferment le volume, ce ne sont pas des détails.

**ADR-50 (défaut).** Un **nouveau** bâtiment et une **nouvelle** rue reçoivent `ground_slab: true` à la création (panneau du bâtiment, panneau de rue) ; la valeur est enregistrée, donc une rue garde la sienne quand on la modifie. Une case **Dalle et seuils** au panneau du bâtiment permet de l'enlever.

## 2. Carrefours en T plus tolérants — AG-101

Dans un réseau, un bout de voie raccordé à une autre voie l'était seulement s'il tombait à 1 m de son **axe**. Désormais :

- un bout posé **sur la chaussée** de l'autre voie (à sa demi-largeur + 1 m de son axe) fait un T, le carrefour étant au point de l'axe ;
- une voie qui **dépasse un peu** l'autre (croisement à moins de la demi-largeur de l'autre + 1 m de son bout) fait aussi un T, et non une croix avec un moignon trop court.

## 3. Carrefours depuis « Tracer une voie » — AG-102

Quand une voie tracée avec **Tracer une voie** croise une voie ou un réseau ARCHGEN existants, ou s'arrête dessus (même tolérance qu'en 2), l'aperçu l'annonce : « Cette voie rejoint 2 voies : elles formeront un réseau avec ses carrefours. » À la création, ces voies et réseaux et la nouvelle voie sont **remplacés par un seul réseau** (réglages repris tels quels), en **une** opération d'Annuler. Refus, avec message, si l'une suit le terrain (un réseau reste horizontal, `network_on_terrain`) ou si le réseau dépasse 24 voies.

## 4. Version — AG-103

Guide, journal, **RBZ 0.20.0** ; recette **H35** à la main.

- **Fait (AG-100 à AG-103).** `wall_builder.ground`, `road_network` (portée = demi-chaussée + 1 m, croisement près d'un bout ramené au bout), `core/road_merge` (contacts et réseau, pur) et `RoadService#merge_for` / `NetworkService#create_replacing` ; annonce au panneau de voie. Un défaut des doubles de test (`to_a` des entités) masquait les racines : le service parcourt maintenant les entités par `each`. RBZ 0.20.0. **Recette H35 dans SketchUp non faite.**

## Tests

U66 dalle et seuils ; U67 tolérance des T ; U68 fusion en réseau (contrat de service).
