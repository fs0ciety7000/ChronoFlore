# CLAUDE.md

> Fichier lu automatiquement par Claude Code à chaque session. Garde-le court : les détails sont dans `.claude/skills-registry.md`.

@AGENTS.md

## Règle n°1 : router avant de coder

Avant de commencer toute tâche non triviale :

1. Identifie le **type de projet** (voir `.claude/skills-registry.md`, section « Table de routage »).
2. Charge **uniquement** les skills listés pour ce type (via le Skill tool). Ne charge pas tout.
3. Si aucun skill ne correspond, lance le skill `find-skills` pour en chercher un, et propose-le à l'utilisateur avant de l'installer.
4. Pour toute fonctionnalité nouvelle : utilise les skills Superpowers (brainstorming → plan → exécution → revue).

## Projet courant

- **Type** : `TODO` (web-frontend | shopify | gamedev-godot | backend-go | backend-rust | video-slides | autre)
- **Stack** : `TODO`
- **Commandes** : `TODO` (install, dev, test, build, lint)

> Remplis cette section avec `/new-project` ou à la main. Le reste du fichier ne change pas d'un projet à l'autre.

## Conventions

- Réponds en français, code et commentaires techniques en anglais sauf indication contraire.
- Petits commits, un sujet par commit. Jamais de `git push --force`.
- Ne jamais écrire de secrets dans le repo ; utilise `.env` (ignoré par git) et `.env.example`.
- Avant de déclarer une tâche terminée : lance les tests/lint/build et vérifie le résultat.
- Quand une instruction est ambiguë et coûteuse à refaire, pose une question ; sinon, avance et signale l'hypothèse prise.

## Écrire pour les agents

Pour tout fichier destiné à un agent (CLAUDE.md, AGENTS.md, SKILL.md, prompts) : applique le skill `writing-for-agents` (impératif, concret, exemples courts, pas de remplissage).

## Où trouver quoi

| Besoin | Fichier |
|---|---|
| Règles communes à tous les agents | `AGENTS.md` |
| Quels skills pour quel projet | `.claude/skills-registry.md` |
| Installer / mettre à jour les skills | `scripts/setup-skills.sh` |
| Démarrer un nouveau projet | `/new-project` (`.claude/commands/new-project.md`) |
