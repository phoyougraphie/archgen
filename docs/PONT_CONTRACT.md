# Contrat des ponts — EXT-13, AG-057 à AG-059

Contrat de départ, écrit avant le code. Il prolonge les [carrefours](VOIRIE_CONTRACT.md#carrefours) et le [contrat de l'eau](EAU_CONTRACT.md) sans rien changer à un réseau existant : un réseau sans nœud de type `bridge` garde son plan et son empreinte. Décision : ADR-40 (D-12). Les valeurs marquées « départ » sont à calibrer à la recette, par une décision écrite.

**Besoin du propriétaire.** Commencer par l'eau et les ponts (2026-11-08) ; D-12 tranchée : un pont naît tout seul au croisement, avec un type au choix (poutre, arc, voûte), et la voie monte et descend par des rampes de pente bornée.

## Principes

- **Un pont est un type de nœud** d'un réseau (`"type": "bridge"`), comme le passage à niveau (AG-050) : pas de cœur de carrefour, les deux voies traversent le nœud. L'une passe dessus (**voie portée**), l'autre dessous (**voie franchie**).
- **La voie franchie ne change pas** : sa surface, son eau, ses rails restent entiers. Seuls ses objets hauts sous le tablier s'interrompent.
- **La voie portée monte** par une rampe droite, franchit sur un tablier, redescend : même mécanisme de profil en long que le passage à niveau.
- **Le réseau reste horizontal** (ADR-38 n'est pas étendu ici) : le sol est le niveau 0 du réseau. Un pont sur un terrain est hors de ce lot.
- **Formes simples (ADR-35)** : volumes fermés à facettes, couleurs unies ; ni ferraillage, ni calcul de structure. **Valeurs de conception, sans vérification de structure ni réglementaire**, et le panneau le dit.

## Quand naît un pont

- **Sur l'eau, tout seul** : un nœud où une voie à eau ou à mer croise une autre voie est un pont, sans réglage ; un réglage `simple`, valeur par défaut d'un nœud réglé, y vaut aussi pont. C'est le seul type permis à ce nœud ; un autre type choisi y est refusé (`water_crossing`, qui propose le pont). La voie à eau passe toujours dessous ; `over` qui la nomme : `bridge_over_unknown`.
- **Sur une voie ferrée ou une route, au choix** : `"type": "bridge"` sur le nœud, à la place d'un carrefour ou d'un passage à niveau. Sur une voie ferrée, la route passe dessus. Entre deux routes, le réglage `over` nomme la voie portée ; sans lui, refus `bridge_over_missing` (aucun choix implicite).
- **Les cours d'eau entrent dans un réseau** à cette condition : chacun de leurs nœuds est un pont. Ils y restent à un seul niveau, quel que soit leur régime (pas de terrain dans un réseau). Une voie à eau qui finit sur une autre voie, ou deux voies à eau qui se croisent : `water_confluence`, hors de ce lot. Le refus `water_in_network` d'AG-051 disparaît.
- **Deux voies, qui traversent** : exactement deux voies au nœud (`bridge_roads`), qui le traversent toutes deux (`bridge_through`), à 45° au moins l'une de l'autre (`bridge_angle`).

## Réglages du nœud, `road-network` V1

Champs facultatifs d'un réglage de nœud, refusés sur un autre type.

| Champ | Valeurs | Défaut (départ) | Sens |
|---|---|---|---|
| `bridge_kind` | `beam`, `arch`, `vault` | `beam` | Poutre, arc, voûte |
| `over` | nom d'une des deux voies | — | Voie portée, exigé entre deux routes |
| `clearance_m` | [2 ; 30] | 4,75 au-dessus d'une route, 5,5 d'une voie ferrée, 4 de l'eau | Hauteur libre sous le tablier, au-dessus du point le plus haut de la voie franchie (dessus des rails, surface de l'eau) |
| `ramp_grade_percent` | [2 ; 8] | 5 | Pente des rampes de la voie portée |

## Géométrie commune

Notations : `U` = point le plus haut de la voie franchie sous le tablier (niveau de ses bandes, dessus des rails, ou surface de l'eau) ; `e` = épaisseur du tablier ; `H` = cote du dessus du tablier = `U + clearance_m + e`.

- **Portée** : l'emprise de la voie franchie mesurée le long de la voie portée (largeur ÷ sinus de l'angle), plus 1 m de chaque côté (départ). Le tablier couvre la portée ; le reste de la coupe de la voie portée y est porté à la cote `H`.
- **Rampes** : de 0 à `H`, droites, de pente `ramp_grade_percent`, de chaque côté du tablier ; longueur `H / pente`. Leurs bords sont fermés par des **murs** verticaux jusqu'au sol, comme les murets du passage à niveau, en matière `road/bridge`.
- **Culées** : à chaque bout de la portée, sous le haut de la rampe, un bloc plein de la largeur de la voie portée, 1,5 m le long de la voie (départ), du sol (0) jusqu'à 2 cm sous la rampe à son bout extérieur, matière `road/bridge` (`road/bridge_stone` pour la voûte).
- **Tablier** : dalle fermée sous la coupe portée, de `H − e` à `H − 0,02` (2 cm sous la chaussée, pour qu'aucune face ne double la surface), sur la portée et 0,2 m dans chaque culée.
- **Garde-corps** : de chaque côté de la voie portée, à l'extérieur de la coupe : sur la portée, une paroi de la sous-face du tablier à 1,1 m au-dessus du bord (elle sert aussi de rive) ; sur chaque rampe, du bord à 1,1 m au-dessus. Paroi métallique de 5 cm pour la poutre et l'arc (le barreaudage est simplifié ainsi, ADR-35), parapet maçonné de 0,3 m pour la voûte. Ils vont avec les autres ouvrages dans `road/bridges`.
- **Objets** : sur la portée, les objets de la voie portée s'interrompent (pas d'arbre sur un tablier ; lampadaires gardés sur les rampes). Sous le tablier, tous les objets de la voie franchie, hors rails et traverses, s'interrompent sur la largeur de la voie portée plus 1 m de chaque côté, comme sous un passage à niveau (le tri par hauteur prévu au départ n'est pas fait : un objet bas sous un pont reste rare).
- **Zones** : la zone de la voie portée va du pied d'une rampe au pied de l'autre ; celle de la voie franchie couvre la largeur de la voie portée, plus 1 m de chaque côté. Chacune tient dans un segment droit de sa voie (`junction_on_curve`), dans sa longueur (`arm_too_short`), et ne touche aucune autre zone de nœud (`junctions_too_close`).

## Types (AG-057, AG-058)

| Type | Épaisseur `e` | Portée permise | Forme sous le tablier |
|---|---|---|---|
| `beam` — poutre | 1,2 m | 40 m au plus d'un seul tenant, sinon `bridge_span_too_long` (le message propose l'arc) | Rien entre les culées |
| `arch` — arc | 0,6 m | 120 m au plus | Arc parabolique de flèche portée ÷ 5, anneau de 1 m, des culées au tablier ; montants verticaux tous les 5 m entre l'arc et le tablier |
| `vault` — voûte | 0,8 m au-dessus de la clé | Arches de 20 m au plus : `⌈portée / 20⌉` arches égales | Maçonnerie pleine percée d'arches en plein cintre ; piles entre les arches, matière `road/bridge_stone` |

- **Gabarit** : aucun point de l'arc, d'une voûte ou d'une pile n'entre dans la hauteur libre au-dessus d'une bande de circulation, de rails ou d'eau de la voie franchie (`bridge_clearance`, avec la bande en cause). Une pile ne se pose pas sur une chaussée, une voie ferrée ou un tram (`pier_on_traffic`) ; dans l'eau, elle est permise.
- Un arc ou une voûte sur une route plate demande souvent de relever `clearance_m` : le refus donne la hauteur qui manque.

## Plan

Sous la racine du réseau, un groupe `road/bridges` (balise de la chaussée) porte tablier, culées, garde-corps, arcs, voûtes et piles, en solides fermés, nommés `bridge/<nœud>/<pièce>`. Les murs des rampes sont des faces de la surface, comme les murets du passage à niveau. Les cours d'eau du réseau ont leur surface d'eau dans un groupe `road/water`. Par nœud : `type`, `bridge_kind`, `over`, `deck_m` (`H`), `span_m`, `ramp_m`. Métrique `bridge_count`, présente seulement s'il y a un pont : un réseau sans pont garde son plan et son empreinte (six réseaux types vérifiés identiques). `crossing_count` ne compte que les passages à niveau. Matières `road/bridge` (béton clair) et `road/bridge_stone` (pierre).

## Refus, `E_ROAD_JUNCTION`, sur `/junctions/<id du nœud>`

| Raison | Quand |
|---|---|
| `water_crossing` | Un nœud touché par une voie à eau ou à mer n'est pas un pont |
| `water_confluence` | Une voie à eau finit sur une autre voie, ou deux voies à eau se croisent |
| `bridge_roads` | Pas exactement deux voies au nœud |
| `bridge_through` | Une des deux voies finit au nœud |
| `bridge_angle` | Moins de 45° entre les deux voies |
| `bridge_over_missing` | Deux routes, sans `over` |
| `bridge_over_unknown` | `over` ne nomme pas une des deux voies, ou nomme la voie à eau |
| `bridge_span_too_long` | Poutre de plus de 40 m, arc de plus de 120 m |
| `bridge_clearance` | Arc, voûte ou pile dans la hauteur libre d'une bande |
| `pier_on_traffic` | Pile sur une chaussée, une voie ferrée ou un tram |
| `bridge_setting_unavailable` | Un réglage de pont sur un autre type de nœud |

Plus les refus de zone existants (`junction_on_curve`, `arm_too_short`, `junctions_too_close`).

## Panneau (AG-059)

Dans **Tracer un réseau** : le type **Pont** et ses réglages (genre, voie portée, hauteur libre, pente des rampes) ; un nœud sur l'eau s'affiche d'office en pont ; les préréglages d'eau et de littoral s'ajoutent au réseau. Guide, journal, RBZ 0.9.0, recette H24, recettes rejouées.

## Hors de ce lot

Pont sur un terrain ; échangeurs à bretelles ; pont tournant ou levant ; pont à haubans ou suspendu ; pont-canal ; tunnel ; ponts de plus de deux voies ; calcul de structure.
