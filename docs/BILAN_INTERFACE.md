# Bilan de l'interface (AG-145, 2026-11-12)

Passe faite dans SketchUp 2026 avec ARCHGEN 0.35.0, puis 0.36.0, sur un écran de 1456 × 819 points. Six fenêtres examinées : bâtiment, rue, voirie, réseau, import de carte et menus. Le panneau de parcelle n'a pas été rouvert (il demande une rue ouverte). Décision : [ADR-70](DECISIONS.md).

## Ce qui va

- **Sûreté du pont.** Pages locales sous CSP stricte, sans réseau ni script en ligne. Tout est validé en Ruby. Une action réussie compte pour une seule opération d'Annuler.
- **Aperçu avant écriture.** Le panneau du bâtiment dessine l'élévation et le plan calculés par le moteur, compte les baies et donne le sommet. Remplacer un bâtiment demande une confirmation qui liste les changements.
- **Messages.** Les messages sont en français et disent quoi corriger. Les erreurs s'affichent sous le champ et dans un résumé cliquable. L'état est annoncé (`aria-live`) et le focus reste visible.
- **Champs dépendants masqués.** Les réglages du toit suivent le type de toit. Hauteur et devanture du commerce, matières des volets, du bardage et du pan de bois n'apparaissent qu'avec leur case.
- **Voirie.** C'est le panneau le plus abouti : préréglages, coupe dessinée à l'échelle avec personnage et gabarits, vue en plan, bandes réordonnables, mobilier par bande et refus localisés.
- **Rue.** Le panneau est étroit, il laisse la vue libre pour tracer. Son pied collant garde Créer et Effacer toujours visibles.
- **Clic droit.** Il ne propose que ce qui s'applique à la sélection.

## Ce qui n'allait pas, corrigé en 0.36.0

| # | Constat | Correction |
|---|---|---|
| 1 | **Aucun accès direct.** Tout passait par Extensions → ARCHGEN : onze entrées à plat, et quatre « Modifier … » à choisir selon le genre de l'objet. | **Barre d'outils ARCHGEN** de neuf boutons à icône, avec info-bulle et texte de barre d'état : créer (bâtiment, rue, voie, réseau), **Modifier la sélection**, carte (fond de plan, import autour du point, import de fichier), export. « Modifier » et « Exporter » sont grisés quand la sélection ne s'y prête pas. Le menu reprend les mêmes commandes, groupées par séparateurs ; les quatre « Modifier » par genre sont rangés dans un sous-menu. La barre s'affiche au premier lancement et peut être rouverte depuis le menu. |
| 2 | **Section « Avancé » fourre-tout.** 62 champs dans un seul bloc : clocher et transept voisinaient avec les balconnets, cases et listes s'entremêlaient. | **Dix sections repliables par thème** sous « Réglages fins » : baies et entrée, niveaux et structure, toiture, matériaux, décor de façade, balcons et saillies, rez-de-chaussée, architecture moderne, édifices religieux, génération. Une erreur ouvre la section du champ fautif. |
| 3 | Largeur et profondeur de l'aile restaient affichées pour un bâtiment rectangulaire. | Ces deux champs n'apparaissent qu'avec une aile (L, T ou U). |
| 4 | **Aperçu minuscule** : un immeuble de cinq niveaux était dessiné sur 130 px de large, dans une colonne vide aux deux tiers. | Le cadre de dessin passe de 420 × 240 à 520 × 320 ; les textes du dessin gardent leur taille. |
| 5 | Sur un petit écran, le bouton **Générer** sortait de la fenêtre sous l'aperçu. | L'aperçu défile dans sa colonne. Générer et Revenir aux valeurs du style restent collés en bas. |
| 6 | **Voirie** : les libellés d'un élément de bande se chevauchaient (« Lampadaire » sur « Côté ») et la liste était écrasée, faute de place dans la colonne de 26 rem. | L'élément tient sur sa propre ligne, ses réglages en dessous ; la colonne passe à 28 rem. |
| 7 | **Import de carte** : le panneau restait sur « Lecture… » et ne répondait à aucun bouton. Il lisait comme un objet la chaîne JSON envoyée par Ruby. | La réponse est relue comme une chaîne, comme dans les autres panneaux. Un test contrôle désormais tous les récepteurs. |
| 8 | **Import de carte** : chaque texte d'aide prenait une case de la grille, ce qui décalait Latitude et Longitude sur deux lignes. | Une aide, une erreur ou une rangée de boutons occupe toute la ligne. La règle est commune à tous les panneaux. |
| 9 | **Réseau** : couleurs et tailles en pixels écrites en dur, d'une autre allure que le reste ; plan figé à 640 px de haut. | Le panneau prend les couleurs et les boîtes communes, et le plan suit la hauteur de la fenêtre. |
| 10 | Rien n'identifiait les fenêtres ARCHGEN parmi celles de SketchUp. | Marque ARCHGEN dans l'en-tête de chaque panneau. |
| 11 | Le clic droit ne proposait rien sur une voie ou un réseau. | « Modifier cette voie » et « Modifier ce réseau » sont ajoutés. |
| 12 | **Panneau de rue** : 52 champs à plat, dont 17 cases de détails avant les réglages de la rue elle-même (0.36.1, AG-146). | Bâtiments et Rue et parcelles en tête, toujours ouverts ; Détails de façade et Variété repliables ; Accès à la cour et Terrain ouverts quand ils s'appliquent. |

## Ce qui ne va pas encore

- **Voirie** : 20 préréglages forment un mur de boutons. Les grouper par famille (ville, campagne, rail, eau, côte) les rendrait lisibles.
- **Réseau** : la vue en plan est vide au départ, sans consigne dans le cadre ; la consigne n'est que dans la barre d'état.
- **Positions d'ouverture** : elles sont fixes. Le panneau de voirie (1 100 px) déborde un écran de 1 456 points, et la console Ruby passe sous les panneaux.
- **Jargon** : « Shell (surfaces) » et « Structural (murs épais) » restent en anglais ; « LOD » n'est expliqué qu'au guide.
- **Import de carte** : les boutons « Choisir… » ont chacun leur ligne sous le champ de fichier.
- **Non vérifié** : mise à l'échelle Windows à 150 %, clavier seul sur les nouvelles sections, Annuler après une action lancée depuis la barre d'outils.
