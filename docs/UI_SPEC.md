# Panneau ARCHGEN

Menu **Extensions → ARCHGEN** : « Nouveau bâtiment », « Modifier le bâtiment sélectionné ». Panneau modeless, local, en français au départ (messages identifiés, traduisibles). Création au repère du modèle ; l'utilisateur déplace ensuite le composant avec SketchUp. Aucun outil de placement dédié en V0.1. Exemples de messages : « Cette fenêtre ne tient pas dans la travée. Réduisez sa largeur ou le nombre de travées. » ; « Le bâtiment sélectionné a changé. Rechargez la sélection. »

| Zone | Contenu et comportement |
|---|---|
| Projet | Nom, style, type de bâtiment, mode, LOD. Afficher trois profils disponibles et leurs signatures. |
| Dimensions | Largeur, profondeur, nombre de niveaux, hauteur courante. Indiquer « RDC inclus ». |
| Façade | Travées avant/arrière et latérales ; options de baies/entrée en section avancée. |
| Avancé | Hauteurs par niveau, marges, jitter, épaisseur et dalle, toiture, matériaux, détails, seed, fidélité. Masquer les champs de toit inactifs ; ne pas les renvoyer. |
| Aperçu | Élévation avant et plan 2D, toit selon données, nombre de baies et portes, hauteur totale ; axes, unités, échelle commune. Distinguer une estimation 2D d'un modèle natif. |
| Actions | Générer ou Régénérer ; afficher avertissements, résumé du changement de style et dialogue de remplacement ; annuler garde la sélection et le brouillon. |

Entrées numériques affichables avec virgule en français ; parser une représentation décimale non ambiguë et envoyer un nombre JSON. Une saisie vide ou invalide est indiquée, sans envoi. Un champ désactivé n'est pas écrasé. À la sélection d'un nouveau profil en édition, envoyer le couple `id/revision` reçu dans `init`, vider les overrides locaux des blocs que le profil reprend, montrer les nouvelles valeurs issues de l'aperçu et permettre de les modifier avant application.

## Contrat du pont

Un callback `archgen_dispatch` reçoit **une chaîne JSON** : `{v:1,request_id:"...",action:"preview",payload:{...}}`. Réponse : `{v:1,request_id:"...",ok:true,result:{...},diagnostics:[]}`. Si échec, `ok:false,result:null`. Pour les identifiants, utiliser des chaînes ; Ruby valide toutes les entrées indépendamment de JS.

| Action | Payload | Résultat |
|---|---|---|
| `init` | `{}` | Profils actifs, défauts, catalogues, limites, textes utiles. |
| `load_selection` | `{}` | Config effective, jeton de cible opaque, révision. |
| `preview` | `{draft,target_token?}` | Config effective, tracés 2D, métriques, digest ; si édition valide, jeton de confirmation lié à cette cible et config. |
| `generate` | `{draft}` | Résumé du bâtiment et jeton de cible si la sélection est valable. |
| `regenerate` | `{draft,target_token,confirmation_token}` | Résumé, nouveau jeton, révision. Jeton de confirmation unique, valable 120 s et consommé avant écriture. Une nouvelle prévisualisation d'édition valide remplace la confirmation précédente. Une nouvelle saisie ou l'annulation ferme la confirmation côté panneau ; Ruby refuse un brouillon différent, et la confirmation est invalidée à la fermeture, lors d'un Undo/Redo, d'un changement de sélection/document ou de la session. Annuler garde le brouillon ; redemander un aperçu avant de confirmer. |

Codes d'état : prêt, modifié, validation en cours, invalide, aperçu prêt, confirmation, écriture en cours, succès, cible périmée. Temporiser l'aperçu à 250 ms après la dernière saisie ; ignorer les réponses d'aperçu d'un ancien request_id. Un seul travail hôte actif, requête de mutation dédoublonnée par request_id sur la session, boutons d'écriture désactivés pendant l'action. Recréation du panneau : réattacher les callbacks avant affichage et refaire `init`. Sur `E_TARGET_STALE`, recharger la sélection avant un nouvel aperçu ; sur `E_CONFIRMATION_STALE`, conserver le brouillon et refaire l'aperçu. Un changement de modèle ou de sélection rend l'édition indisponible jusqu'au rechargement ; aucune ancienne réponse ne doit viser le nouveau document.

Le dialogue n'écrit pas dans SketchUp pendant l'aperçu. Les erreurs sont affichées sous le champ et dans un résumé navigable ; les avertissements ne désactivent pas l'action. Contrôles clavier, labels et focus visible ; zone d'état annoncée par `aria-live` ; après échec, focus sur le résumé ou le premier champ. Tester 100 % et 150 % de mise à l'échelle, fenêtre étroite, clavier seul et absence de réseau. Voir [sécurité du pont](SECURITY_PERFORMANCE.md).
