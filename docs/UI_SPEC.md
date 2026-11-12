# Panneau ARCHGEN

Menu **Extensions → ARCHGEN** et barre d'outils ARCHGEN, nourris de la même liste de commandes (`ui/commands.rb`, ADR-70) : « Nouveau bâtiment », « Modifier la sélection » (et sous-menu « Modifier… » par genre). Réglages fins du panneau en sections repliables par thème ([bilan](BILAN_INTERFACE.md)). Panneau modeless, local, en français au départ (messages identifiés, traduisibles). Création au repère du modèle ; l'utilisateur déplace ensuite le composant avec SketchUp. Aucun outil de placement dédié en V0.1. Exemples de messages : « Cette fenêtre ne tient pas dans la travée. Réduisez sa largeur ou le nombre de travées. » ; « Le bâtiment sélectionné a changé. Rechargez la sélection. »

| Zone | Contenu et comportement |
|---|---|
| Projet | Nom, style, type de bâtiment, mode, LOD. Afficher trois profils disponibles et leurs signatures. |
| Dimensions | Largeur, profondeur, nombre de niveaux, hauteur courante. Indiquer « RDC inclus ». |
| Façade | Travées avant/arrière et latérales ; options de baies/entrée en section avancée. |
| Avancé | Hauteurs par niveau, marges, jitter, épaisseur et dalle, toiture, matériaux, détails, seed, fidélité. Masquer les champs de toit inactifs ; ne pas les renvoyer. |
| Aperçu | Élévation avant et plan 2D, toit selon données, nombre de baies et portes, hauteur totale ; axes, unités, échelle commune. Distinguer une estimation 2D d'un modèle natif. |
| Terrain | En édition seulement : retenir un terrain, réglages d'assise, Relever, Adapter au terrain, Retirer l'assise ; valeurs relevées et avertissements. Voir [le contrat terrain](TERRAIN_CONTRACT.md). |
| Actions | Générer ou Régénérer ; afficher avertissements, résumé du changement de style et dialogue de remplacement ; annuler garde la sélection et le brouillon. |

Entrées numériques affichables avec virgule en français ; parser une représentation décimale non ambiguë et envoyer un nombre JSON. Une saisie vide ou invalide est indiquée, sans envoi. Un champ désactivé n'est pas écrasé. À la sélection d'un nouveau profil en édition, envoyer le couple `id/revision` reçu dans `init`, vider les overrides locaux des blocs que le profil reprend, montrer les nouvelles valeurs issues de l'aperçu et permettre de les modifier avant application.

## Panneau de rue

Fenêtre séparée, ouverte par « Tracer une rue » : son pont `archgen_street`, ses actions et son geste sont décrits dans [le contrat d'ensemble](ENSEMBLE_CONTRACT.md). Elle ne reçoit jamais de géométrie du tracé par le pont : le tracé vient de l'outil seul.

## Recettes (AG-148, ADR-71)

Les panneaux du bâtiment, de la rue et de la voirie ont un bloc repliable **Mes recettes** : choisir une recette, **Appliquer**, **Effacer** (confirmation dans le bloc : « Oui, effacer » ou « Non ») ; saisir un nom, **Enregistrer** (**Remplacer** si le nom existe). Une recette appliquée remplace la saisie et repasse par l'aperçu : un style retiré depuis est refusé avec son diagnostic. Une saisie invalide ne s'enregistre pas.

- **Bâtiment :** le style et les champs changés, sans le nom du bâtiment.
- **Rue :** les réglages de la rue ; le tracé en cours décide si la disposition (rue ouverte) ou les accès (rue fermée) s'appliquent. Les réglages propres posés au clic droit n'en font pas partie.
- **Voirie :** la coupe composée ; le nom de la recette devient celui de la coupe. Ces coupes apparaissent aussi dans la liste « Type de voie » du réseau, sous **Mes coupes**.

Stockage sur ce poste, un fichier par genre dans `%APPDATA%\ARCHGEN\recettes` : `recipes_building.json`, `recipes_street.json`, `recipes_road.json`, au format `{schema_version:1,recipes:[{name,data}]}`. Écriture atomique (fichier temporaire puis renommé) par le seul module d'écriture d'ARCHGEN. Les préférences de SketchUp ont été écartées : `Sketchup.read_default` évalue la valeur stockée comme du Ruby, et SketchUp 2026 n'a gardé aucune valeur d'une session à l'autre. Nom de 1 à 60 caractères, sans caractère de contrôle ; 40 recettes et 64 Ko par recette au plus. Un fichier illisible est copié en `_illisible.json` avant d'être remplacé ; une écriture impossible est refusée avec un message.

## Contrat du pont

Un callback `archgen_dispatch` reçoit **une chaîne JSON** : `{v:1,request_id:"...",action:"preview",payload:{...}}`. Réponse : `{v:1,request_id:"...",ok:true,result:{...},diagnostics:[]}`. Si échec, `ok:false,result:null`. Pour les identifiants, utiliser des chaînes ; Ruby valide toutes les entrées indépendamment de JS.

Une écriture répétée avec le même `request_id` reçoit la réponse mémorisée, sans seconde écriture. Cette mémoire ne vaut que pour une page : `init` et la fermeture du panneau la vident, car une page neuve recompte ses identifiants depuis le début. Le rappel de fermeture est rattaché avant chaque affichage : SketchUp ne le conserve pas d'une ouverture à l'autre.

| Action | Payload | Résultat |
|---|---|---|
| `init` | `{}` | Profils actifs, défauts, catalogues, limites, textes utiles. |
| `load_selection` | `{}` | Config effective, jeton de cible opaque, révision. |
| `preview` | `{draft,target_token?}` | Config effective, tracés 2D, métriques, digest ; si édition valide, jeton de confirmation lié à cette cible et config. |
| `generate` | `{draft}` | Résumé du bâtiment et jeton de cible si la sélection est valable. |
| `regenerate` | `{draft,target_token,confirmation_token}` | Résumé, nouveau jeton, révision. Jeton de confirmation unique, valable 120 s et consommé avant écriture. Une nouvelle prévisualisation d'édition valide remplace la confirmation précédente. Une nouvelle saisie ou l'annulation ferme la confirmation côté panneau ; Ruby refuse un brouillon différent, et la confirmation est invalidée à la fermeture, lors d'un Undo/Redo, d'un changement de sélection/document ou de la session. Annuler garde le brouillon ; redemander un aperçu avant de confirmer. |
| `retain_terrain` | `{}` | La sélection devient le terrain retenu ; jeton opaque lié au document. |
| `site_status` | `{target_token}` | `has_site`, et si oui `moved` et les réglages enregistrés. |
| `site_preview` | `{site,target_token,terrain_token?}` | Relève et calcule sans écrire : métriques, lignes lisibles, jeton de confirmation. Sans jeton de terrain, le terrain enregistré par la racine. |
| `adapt_site` | `{site,target_token,terrain_token?,confirmation_token}` | Écrit l'assise ; même réponse que `regenerate`. Terrain changé depuis l'aperçu : refus. |
| `site_remove_preview`, `remove_site` | `{target_token}`, `{target_token,confirmation_token}` | Confirmation, puis retrait de l'assise. |
| `save_recipe`, `delete_recipe` | `{name,data}`, `{name}` | Recettes (AG-148, ADR-71), aussi dans les ponts de la rue et de la voirie : liste à jour `{recipes:[{name,data}]}`. `init` rend aussi `recipes`. N'écrit rien dans le modèle et n'ouvre aucune opération. |

Les confirmations de l'assise sont distinctes de celle du brouillon : relever ne périme pas un aperçu du bâtiment, et réciproquement. Même durée, même usage unique, mêmes invalidations.

Codes d'état : prêt, modifié, validation en cours, invalide, aperçu prêt, confirmation, écriture en cours, succès, cible périmée. Temporiser l'aperçu à 250 ms après la dernière saisie ; ignorer les réponses d'aperçu d'un ancien request_id. Un seul travail hôte actif, requête de mutation dédoublonnée par request_id sur la session, boutons d'écriture désactivés pendant l'action. Recréation du panneau : réattacher les callbacks avant affichage et refaire `init`. Sur `E_TARGET_STALE`, recharger la sélection avant un nouvel aperçu ; sur `E_CONFIRMATION_STALE`, conserver le brouillon et refaire l'aperçu. Un changement de modèle ou de sélection rend l'édition indisponible jusqu'au rechargement ; aucune ancienne réponse ne doit viser le nouveau document.

Le dialogue n'écrit pas dans SketchUp pendant l'aperçu. Les erreurs sont affichées sous le champ et dans un résumé navigable ; les avertissements ne désactivent pas l'action. Contrôles clavier, labels et focus visible ; zone d'état annoncée par `aria-live` ; après échec, focus sur le résumé ou le premier champ. Tester 100 % et 150 % de mise à l'échelle, fenêtre étroite, clavier seul et absence de réseau. Voir [sécurité du pont](SECURITY_PERFORMANCE.md).
