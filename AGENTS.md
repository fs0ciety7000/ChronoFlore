# AGENTS.md

Règles communes à tous les agents de code (Claude Code, Codex, Cursor, etc.). Format volontairement neutre : rien ici n'est spécifique à Claude.

## Contexte du projet

- **Nom** : `TODO`
- **Type** : `TODO` (voir `.claude/skills-registry.md`)
- **Résumé en une phrase** : `TODO`

## Commandes

```bash
# À remplir selon la stack
install: TODO
dev:     TODO
test:    TODO
lint:    TODO
build:   TODO
```

## Structure du dépôt

```
.
├── AGENTS.md            # ce fichier
├── CLAUDE.md            # entrée Claude Code (importe AGENTS.md)
├── .claude/
│   ├── skills-registry.md   # routage type de projet → skills
│   └── commands/new-project.md
├── scripts/setup-skills.sh  # installation des skills
└── src/                 # code (TODO)
```

## Règles de travail

1. Lis avant d'écrire : ouvre les fichiers concernés avant de les modifier.
2. Fais le plus petit changement qui résout le problème. Pas de refactor non demandé.
3. Suis le style existant (nommage, formatage, structure) plutôt que d'en imposer un.
4. Ajoute ou mets à jour les tests avec chaque changement de comportement.
5. Lance `test` et `lint` avant de conclure ; rapporte les résultats réels, pas supposés.
6. Ne touche jamais à : `.env*`, fichiers de lock générés à la main, `dist/`, `build/`.
7. Si une tâche dépasse ~5 fichiers ou change l'architecture, propose d'abord un plan.

## Sécurité

- Aucun secret dans le code, les logs ou les commits.
- Valide toutes les entrées externes. Requêtes SQL paramétrées uniquement.
- Demande confirmation avant toute action destructive (suppression, reset, migration en prod).

## Skills

Les skills disponibles et leur usage par type de projet sont décrits dans `.claude/skills-registry.md`. Charge le minimum nécessaire pour la tâche en cours.
