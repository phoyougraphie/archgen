# Schéma des styles et héritage

```text
generic (base interne)
 ├─ ordered_facade       → haussmann*, baroque, neoclassical, renaissance
 ├─ masonry_vernacular   → toulousain*, provencal, mediterranean, breton
 ├─ timber_vernacular    → basque, half_timbered, norman, alsatian
 ├─ historic_monumental  → romanesque, gothic
 ├─ ornamental           → art_deco, art_nouveau
 ├─ modern_modular       → bauhaus, brutalist*, minimalist, mid_century, modernist
 └─ tech_environment     → high_tech, industrial, bioclimatic
```

* Actif V0.1. Le [catalogue](styles/CATALOGUE.md) couvre les 24 entrées. Les familles techniques sont des parents de données, pas des classes de générateur ; la région, la période et la typologie sont des dimensions distinctes. Pour plusieurs traditions sous un nom, créer à terme des feuilles régionales explicites (p. ex. Méditerranéen cycladique). Le colombage et la stratégie bioclimatique peuvent devenir des capacités composables ; V0.1 ne mélange pas les styles.

**Chargement.** Suivre le [schéma du profil](../schemas/style-profile.v1.schema.json). Identifiant ASCII stable, couple id/révision unique, parent référencé à une révision exacte. Uniquement base → famille → profil en V1 ; rejeter cycle, parent manquant, famille incohérente ou statut illégal. Charger toute la hiérarchie avant publication ; seuls les `active` dont tous les prérequis sont disponibles entrent dans les options de l'UI. Jusqu'à AG-015, l'intégration utilise le neutre interne : tester les déclarations `active` en U02 avec une liste de capacités injectée, puis enregistrer les capacités réelles à mesure de leur implémentation. La publication des trois feuilles est la porte AG-015. `internal` permet le générique de test ; `planned` ne peut pas être sélectionné. Le catalogue descriptif des 24 n'est pas chargé comme registre exécutable. Ne pas créer de profils génériques déguisés pour les styles planifiés.

**Fusion.** Les défauts sont fusionnés feuille par feuille (tableaux remplacés) ; voir la transition des toits dans [Configuration](CONFIG_SCHEMA.md). `requires` : union ordonnée parent puis enfant. Les règles fusionnent par `id` ; un enfant ne peut ni supprimer une règle héritée, ni affaiblir une règle `hard`. Pour une règle non hard remplacée, l'enfant déclare l'entrée complète. Les défauts résolus d'une feuille active doivent passer la validation après ajout d'un nom de test et de la référence profil ; une règle ou une capacité inconnue dans un profil actif bloque la publication. Les matériaux sont vérifiés dans le catalogue et ne sélectionnent pas de fichier.

| Genre | strict | plausible (défaut) | creative |
|---|---|---|---|
| hard | erreur | erreur | erreur |
| historical | erreur | avertissement | ignoré |
| soft | avertissement | avertissement | ignoré |
| decorative | choix déterministe | choix déterministe | choix déterministe |

Règles de V1 : `window_ratio` (hauteur/largeur, min/max), `level_count` (min/max), `roof_type` (values), `material_allowed` (role/values), `feature_chance` (feature/probability). Le registre impose exactement les paramètres cités, min ≤ max et clés connues ; `feature_chance` est réservé au genre decorative, à raison d'une règle résolue maximum par feature. Pour les chances, comparer `unit(seed,"feature/"+feature)` à probability à la création/changement de profil, après choix de la seed et avant override utilisateur ; aucune chance dans les profils V0.1 livrés. Une feature explicite et incompatible doit être signalée, jamais chargée sous forme de code. Les contraintes de faisabilité du noyau sont indépendantes de ce registre.

**Publication d'une feuille.** Fournir au minimum : profil JSON complet après héritage, rendu repère, source de contexte, valeurs et cas adverses, fixture Shell + Structural, budget, tests des règles strict/plausible/creative et plan canonique. Changer les défauts ou une règle implique une nouvelle révision de profil. Lire [FUTURE](FUTURE.md) pour le séquencement des nouvelles capacités.
