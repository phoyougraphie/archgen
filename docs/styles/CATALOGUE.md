# Catalogue des 24 styles

Trois profils sont actifs en V0.1 (données dans [examples/profiles](../../examples/README.md)). Les autres fiches sont des contrats d'intention : les capacités listées s'ajoutent au noyau, et les variantes régionales déterminent la portée réelle du profil. [Index JSON](../../examples/style-catalogue.v1.json) pour inventaire et suivi, distinct du registre runtime.

Calibrage : **niveaux incluant le RDC ; hauteur d'étage en m ; pente de toit**. Plages proposées pour le générateur, non normatives et non exhaustives. Pour Roman et Gothique, le nombre désigne des volumes de référence, pas des étages répétitifs. Les matériaux de ces fiches sont des rôles candidats ; seuls les matériaux V0.1 existent au runtime. Les dates signalent des contextes et des variantes, pas des seuils légaux ou des preuves d'authenticité.

Repères : [typologie haussmannienne, Ville de Paris](https://www.paris.fr/pages/haussmann-l-homme-qui-a-transforme-paris-23091) ; [chronologie Bauhaus, Fondation Bauhaus Dessau](https://bauhaus-dessau.de/en/institution/chronology/). Les autres fiches reprennent le fil de conception comme point de départ ; chaque activation future requiert des références de variantes et des cas de recette.

## Façade ordonnancée

### Haussmannien — `haussmann`

**V0.1 · Paris, second XIXe siècle et prolongements.** Calibrage : 5–7 ; 2,7–4,0 ; mansarde.

- **Géométrie :** Baies verticales, trame régulière, hiérarchie RDC/étages, corniche et balcon filant selon niveau. V0.1 : mansarde simple et balcons 2/5 si présents.
- **Matériaux :** Pierre claire, zinc ou ardoise, ferronnerie, bois peint.
- **Cohérence historique :** Ne pas traiter les baies panoramiques comme d'origine ; variantes immeuble courant, angle (ultérieur), post-haussmannien.
- **Capacités à vérifier :** `mansard`, `cornice`, `balcony`. **Recette :** À 5 niveaux : balcon au niveau 2 ; mansarde, pierre claire, pas de balcon 5.

### Baroque — `baroque`

**Planifié · Europe, XVIIe–XVIIIe siècles selon région.** Calibrage : 2–5 ; 3,2–5,5 ; selon variante.

- **Géométrie :** Axe principal, avant-corps, ordres superposés ; frontons courbes ou brisés facultatifs.
- **Matériaux :** Pierre, stuc, marbre de prestige, ardoise ou tuile.
- **Cohérence historique :** Adapter aux variantes française, italienne et germanique ; courbure non obligatoire.
- **Capacités à vérifier :** `avant_corps`, `classical_orders`, `curved_pediment`. **Recette :** Le fronton est rattaché à l'axe de son avant-corps ; pas d'ornements flottants.

### Néoclassique — `neoclassical`

**Planifié · Europe et international, XVIIIe–XIXe siècles.** Calibrage : 2–5 ; 3,0–4,5 ; 15–45°.

- **Géométrie :** Façade symétrique et régulière ; fronton triangulaire, portique ou pilastres selon typologie.
- **Matériaux :** Pierre claire, enduit minéral, bois peint, couverture régionale.
- **Cohérence historique :** Ordre cohérent par portique ; colonnes optionnelles pour la maison ordinaire.
- **Capacités à vérifier :** `classical_orders`, `portico`. **Recette :** Centres des travées symétriques ; un portique ne bloque ni la porte ni ses dégagements.

### Renaissance — `renaissance`

**Planifié · Europe, XVe–XVIIe siècles selon région.** Calibrage : 2–5 ; 2,8–4,5 ; 25–60° pour variantes pentues.

- **Géométrie :** Travées, meneaux, corniches ; château français à forte pente/lucarnes ; palais italien à composition distincte.
- **Matériaux :** Pierre taillée, brique régionale, ardoise, bois.
- **Cohérence historique :** Séparer sous-profils avant de fixer pente et vocabulaire ; pas de lucarnes françaises par défaut sur palais italien.
- **Capacités à vérifier :** `mullions`, `dormers`, `regional_variant`. **Recette :** Le meneau divise la baie ; une lucarne ne sort pas de son pan support.

## Vernaculaire maçonné

### Toulousain (brique) — `toulousain`

**V0.1 · Toulouse et Midi toulousain ; XVIIe–début XXe selon variante.** Calibrage : 2–5 ; 2,7–3,8 ; 15–35°.

- **Géométrie :** Façade plane, fenêtres verticales, deux pans ou croupe ; encadrement en V0.1, génoise ultérieure.
- **Matériaux :** Brique foraine, terre cuite canal, pierre ponctuelle, enduit à la chaux.
- **Cohérence historique :** Maison populaire, immeuble urbain XIXe (défaut), hôtel particulier distincts ; génoise facultative.
- **Capacités à vérifier :** `gable`, `hip`, `surrounds`. **Recette :** Couverture deux pans en tuiles canal et mur brique ; variante croupe testable.

### Provençal — `provencal`

**Planifié · Provence, vernaculaire rural et villageois.** Calibrage : 1–3 ; 2,4–3,2 ; 15–30°.

- **Géométrie :** Volume simple, toit bas, débords modérés, baies petites à moyennes, volets.
- **Matériaux :** Calcaire, enduit ocre ou clair, tuiles canal, bois peint.
- **Cohérence historique :** Séparer mas, bastide et maison de village ; débords alpins hors profil traditionnel.
- **Capacités à vérifier :** `shutters`. **Recette :** Un mas de deux niveaux garde toit bas et débord calibré ; volets hors du vide.

### Méditerranéen — `mediterranean`

**Planifié · Méditerranée ; région obligatoire, périodes par sous-profil.** Calibrage : 1–4 ; 2,5–3,5 ; 0–35° selon variante.

- **Géométrie :** Cycladique : volumes compacts et terrasse ; andalou : patio/arcades ; variantes maghrébines distinctes.
- **Matériaux :** Chaux claire, pierre, terre cuite, bois, selon région.
- **Cohérence historique :** Le parent ne se génère pas. Ne pas fusionner les traditions ni faire de Provençal son synonyme.
- **Capacités à vérifier :** `regional_variant`, `patio`, `round_arch`. **Recette :** Sans sous-profil, refuser. Le cycladique ne reçoit pas automatiquement un patio andalou.

### Breton — `breton`

**Planifié · Bretagne ; variantes rurales, côtières et urbaines.** Calibrage : 1–3 ; 2,3–3,0 ; 35–55°.

- **Géométrie :** Longère allongée ou maison compacte ; murs épais, percements anciens modestes, toit pentu.
- **Matériaux :** Granite ou schiste, ardoise, enduits locaux et bois.
- **Cohérence historique :** Éviter matériau et proportions uniformes entre territoires ; distinguer longère et maison de pêcheur.
- **Capacités à vérifier :** `regional_variant`. **Recette :** Une longère a une largeur supérieure à sa profondeur, un matériau local et un toit incliné.

## Ossature bois traditionnelle

### Basque — `basque`

**Planifié · Pays basque ; distinguer ferme labourdine et néobasque.** Calibrage : 2–3 ; 2,4–3,2 ; 25–45°.

- **Géométrie :** Volume compact, pignon avant, grand débord ; pan de bois dépendant du sous-profil.
- **Matériaux :** Enduit blanc, bois peint rouge ou vert, tuiles terre cuite, pierre.
- **Cohérence historique :** Éviter d'imposer le colombage à toutes les maisons ; usage et orientation du pignon varient.
- **Capacités à vérifier :** `gable_axis`, `timber_frame`. **Recette :** La variante sans bois ne contient aucune pièce de colombage.

### Maison à colombages — `half_timbered`

**Planifié · Technique transrégionale ; du bâti ancien aux réemplois modernes.** Calibrage : 2–4 ; 2,3–3,2 ; 35–60° selon variante.

- **Géométrie :** Poteaux, traverses, diagonales entre nœuds ; encorbellement facultatif ; trame coordonnée aux baies.
- **Matériaux :** Ossature bois, torchis/brique/enduit de remplissage ; couverture régionale.
- **Cohérence historique :** Associer région et technique ; aucune diagonale flottante en historique strict.
- **Capacités à vérifier :** `timber_frame`, `jetties`. **Recette :** Chaque extrémité de diagonale aboutit à un nœud et ne traverse aucune baie.

### Normand — `norman`

**Planifié · Normandie ; variantes pays d'Auge, pays de Caux, bâti urbain.** Calibrage : 1–3 ; 2,3–3,2 ; 35–55°.

- **Géométrie :** Volumes souvent allongés ; croupes et lucarnes ; trame bois selon sous-profil.
- **Matériaux :** Bois/torchis, brique/silex, pierre, chaume ou ardoise.
- **Cohérence historique :** Colombage non systématique ; cohérence couverture/territoire et datation.
- **Capacités à vérifier :** `regional_variant`, `timber_frame`, `dormers`. **Recette :** Une variante maçonnée n'instancie pas l'ossature bois.

### Alsacien — `alsatian`

**Planifié · Alsace, vernaculaire ancien et moderne.** Calibrage : 2–4 ; 2,3–3,2 ; 40–60°.

- **Géométrie :** Pans de bois serrés, toits pentus, lucarnes ; encorbellements selon sous-profil.
- **Matériaux :** Bois, remplissage enduit/brique, tuiles plates, soubassement pierre.
- **Cohérence historique :** Contreventement plausible ; couleurs vives facultatives, non universelles.
- **Capacités à vérifier :** `timber_frame`, `jetties`, `dormers`. **Recette :** Les pièces bois restent raccordées sur les paliers en encorbellement.

## Historique monumental

### Roman — `romanesque`

**Planifié · Europe ; env. Xe–XIIe siècles, avec prolongements régionaux.** Calibrage : 1–3 volumes ; 3–8 ; 25–50° (repères).

- **Géométrie :** Murs massifs, arcs plein cintre, fenêtres étroites ; abside, berceau en variante d'église.
- **Matériaux :** Pierre locale, chaux ; pierre, tuile ou métal pour couverture selon région.
- **Cohérence historique :** Faible part de vides en maçonnerie porteuse ; distinguer église, abbaye et bâti civil.
- **Capacités à vérifier :** `round_arch`, `apse`, `barrel_vault`. **Recette :** L'arc plein cintre a un rayon égal à la demi-portée ; abside jointive à la nef.

### Gothique — `gothic`

**Planifié · Europe, XIIe–XVIe siècles selon région.** Calibrage : 1–4 volumes ; 4–12 ; 40–65° (repères).

- **Géométrie :** Verticalité, arcs brisés, remplages, ogives, contreforts, rosace selon variante.
- **Matériaux :** Pierre, vitrail, bois de charpente, ardoise ou tuile.
- **Cohérence historique :** Séparer primitif, rayonnant, flamboyant ; relier les grandes baies à la reprise de charge figurée.
- **Capacités à vérifier :** `pointed_arch`, `rib_vault`, `buttress`, `tracery`. **Recette :** Les retombées d'ogive et contreforts sont alignés avec la trame.

## Décoratif géométrique ou organique

### Art déco — `art_deco`

**Planifié · Europe et international, vers 1920–1940.** Calibrage : 2–8 ; 2,8–4,0 ; 0–30°.

- **Géométrie :** Retraits en gradins ; trame axiale ou angle courbe ; motifs de chevrons, éventails, reliefs.
- **Matériaux :** Béton enduit, pierre, brique décorative, céramique, métal.
- **Cohérence historique :** Séparer immeuble géométrique et variante paquebot ; exclure les motifs végétaux fluides du profil strict.
- **Capacités à vérifier :** `setbacks`, `geometric_relief`. **Recette :** Le retrait reste derrière la façade de l'étage inférieur ; décor géométrique sans collision.

### Art nouveau — `art_nouveau`

**Planifié · Europe, vers 1890–1914.** Calibrage : 2–6 ; 2,8–4,0 ; selon variante.

- **Géométrie :** Composition éventuellement asymétrique, baies courbes, bow-window, motifs organiques.
- **Matériaux :** Pierre, brique, fer travaillé, verre coloré, céramique.
- **Cohérence historique :** Limiter le motif répétitif uniforme ; variantes selon centres régionaux.
- **Capacités à vérifier :** `curved_opening`, `bow_window`, `organic_relief`. **Recette :** Un motif organique est relié à son support ; contrôler la continuité des contours.

## Moderne modulaire

### Bauhaus — `bauhaus`

**Planifié · Allemagne, école 1919–1933 ; héritages internationaux.** Calibrage : 1–5 ; 2,7–4,0 ; plat dominant.

- **Géométrie :** Volumes orthogonaux articulés, composition fonctionnelle, verrière et asymétrie possibles.
- **Matériaux :** Enduit clair, brique, béton, acier et verre.
- **Cohérence historique :** Séparer la période de l'école et ses héritages ; écarter les ordres classiques appliqués.
- **Capacités à vérifier :** `joined_volumes`, `curtain_wall`. **Recette :** La verrière suit la grille de l'aile, sans motif historiciste.

### Brutaliste — `brutalist`

**V0.1 · International, surtout vers 1950–1980.** Calibrage : 2–15 ; 2,7–4,0 ; plat en V0.1.

- **Géométrie :** Masse, répétition, ouvertures profondes ; retraits, joints et porte-à-faux ultérieurs.
- **Matériaux :** Béton brut ou préfabriqué, métal et verre.
- **Cohérence historique :** Ne pas appliquer de décor classique ; joints et structure exprimés quand pris en charge.
- **Capacités à vérifier :** `flat`. **Recette :** En Structural LOD 1, les cadres reculent dans le tableau ; mêmes baies qu'en Shell.

### Contemporain minimaliste — `minimalist`

**Planifié · International, fin XXe siècle et période contemporaine.** Calibrage : 1–4 ; 2,6–3,5 ; 0–20°.

- **Géométrie :** Volumes simples, toiture discrète, baies larges alignées, ornement minimal.
- **Matériaux :** Béton, bois, verre, métal, enduit lisse.
- **Cohérence historique :** Éviter de présumer une portée ou une protection solaire vérifiée.
- **Capacités à vérifier :** `wide_glazing`, `joined_volumes`. **Recette :** Les grandes baies gardent des rives cohérentes avec la trame et le volume.

### Mid-century — `mid_century`

**Planifié · International, vers 1945–1970 ; régions distinctes.** Calibrage : 1–3 ; 2,4–3,4 ; 0–25°.

- **Géométrie :** Horizontalité, toit bas ou plat, grands débords, grandes baies et continuité vers l'extérieur.
- **Matériaux :** Bois, pierre, brique, verre, acier.
- **Cohérence historique :** Différencier américain, scandinave, européen ; plans ouverts réservés à Interior.
- **Capacités à vérifier :** `wide_glazing`, `deep_eaves`, `regional_variant`. **Recette :** La variante à débord prononcé garde une rive au-dessus du sol et des baies.

### Moderniste — `modernist`

**Planifié · International, principalement XXe siècle.** Calibrage : 1–8 ; 2,6–4,0 ; 0–20°.

- **Géométrie :** Toiture-terrasse et fenêtres en bandeau ; pilotis et plan libre selon sous-profil.
- **Matériaux :** Béton, acier, verre, enduit.
- **Cohérence historique :** Distinguer courant international, rationalisme et branches régionales ; ne pas imposer les pilotis.
- **Capacités à vérifier :** `ribbon_windows`, `pilotis`, `regional_variant`. **Recette :** Les ouvertures en bandeau sont continues ; aucun pilotis dans un passage ou une baie.

## Technique et environnemental

### High-tech — `high_tech`

**Planifié · International, à partir des années 1970.** Calibrage : 2–15 ; 3–5 ; selon variante.

- **Géométrie :** Poteaux-poutres visibles, contreventement, façade rideau ; circulation extériorisée en option.
- **Matériaux :** Acier, aluminium, verre, composites.
- **Cohérence historique :** Équipements apparents optionnels ; ossature lisible et raccordée, sans affirmation de résistance.
- **Capacités à vérifier :** `structural_grid`, `curtain_wall`. **Recette :** Panneaux de façade indexés par travée ; diagonales connectées aux nœuds.

### Écologique / bioclimatique — `bioclimatic`

**Planifié · Approche contemporaine transversale ; climat et nord requis.** Calibrage : 1–5 ; 2,5–3,5 ; selon climat.

- **Géométrie :** Compacité, orientation, protections passives et ventilation traversante selon cas ; toiture végétalisée en option.
- **Matériaux :** Bois, terre, isolants biosourcés et verre selon contexte.
- **Cohérence historique :** Appliquer une stratégie climatique à un profil compatible ; aucune certification ni performance prédite sans simulation.
- **Capacités à vérifier :** `climate_context`, `solar_shading`. **Recette :** Sans nord et scénario climatique, bloquer la stratégie ; vérifier le changement d'orientation des protections.

### Industriel — `industrial`

**Planifié · XIXe–XXIe siècles ; halle, usine et entrepôt distincts.** Calibrage : 1–4 ; 4–10 ; 0–35° hors sheds spécifiques.

- **Géométrie :** Grandes travées, portes utilitaires, sheds orientés selon variante, trame poteaux-poutres.
- **Matériaux :** Brique et acier pour variantes anciennes ; béton ou bardage métallique selon époque.
- **Cohérence historique :** Empêcher le bardage contemporain dans une usine brique 1880 en strict, sauf transformation documentée.
- **Capacités à vérifier :** `sawtooth_roof`, `structural_grid`, `large_door`. **Recette :** Sheds répétitifs sans recouvrement, pan vitré orienté et distinct.
