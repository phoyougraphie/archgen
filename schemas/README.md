# Schémas et contrôles

- [Brouillon V1](building-draft.v1.schema.json) : messages de saisie partiels.
- [Configuration V1](building-config.v1.schema.json) : données effectives persistées.
- [Profil de style V1](style-profile.v1.schema.json) : structure des profils, familles et base.
- [Réglages d'assise V1](site-settings.v1.schema.json) et [grille de relevé V1](survey-grid.v1.schema.json) : voir [le contrat terrain](../docs/TERRAIN_CONTRACT.md).

Format [JSON Schema 2020-12](https://json-schema.org/draft/2020-12). Ces fichiers sont autonomes. Le contrôle structurel et le contrôle sémantique sont deux étapes : les contraintes croisées, l'héritage, la disponibilité des capacités et les relations géométriques vivent dans [les contrats](../docs/CONFIG_SCHEMA.md). V0.1 n'embarque pas de moteur de validation tiers dans SketchUp : vérifier la parité du validateur Ruby contre les cas positifs/négatifs en CI. Ne télécharger aucun schéma au runtime.
