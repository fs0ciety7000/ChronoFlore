# Prompts de démarrage

Après `cp -r claude-scaffold mon-projet && cd mon-projet && git init && ./scripts/setup-skills.sh`, lance `claude` puis colle l'un de ces prompts.

## Gabarit général

```
/new-project <type> : <ce que ça fait en une phrase>.
Stack : <langage / moteur / framework>.
Cible : <web | desktop | mobile | itch.io | Shopify | Cloudflare>.
Contraintes : <ex. solo, MVP en 2 semaines, pas de dépendances lourdes>.
Premier jalon : <le premier truc jouable / visible>.
```

## Jeu 2D avec Godot

```
/new-project jeu 2D : platformer pixel-art solo, 1 niveau jouable pour commencer.
Stack : Godot 4, GDScript.
Cible : export web (HTML5) hébergé sur Cloudflare Pages + page itch.io.
Contraintes : assets libres de droits, manette + clavier, code simple et commenté.
Premier jalon : un personnage qui court, saute et ramasse des pièces dans un niveau.

Ensuite : crée le repo GitHub, branche main protégée, une PR par fonctionnalité.
Utilise le workflow Superpowers (brainstorming → plan → exécution → revue).
```

## Jeu 2D dans le navigateur (sans moteur)

```
/new-project jeu 2D web : shoot'em up vertical, canvas + TypeScript.
Stack : Vite, TypeScript, aucune lib de jeu.
Cible : Cloudflare Pages.
Premier jalon : vaisseau contrôlable, tirs, ennemis simples, score.
```

## Autres exemples

```
/new-project shopify : thème Liquid sur mesure pour une boutique de bougies + sections personnalisables.

/new-project backend-go : API REST de réservation, PostgreSQL, migrations, tests d'intégration.

/new-project video-slides : diaporama animé de 8 slides présentant mon produit.
```

## Ce que Claude doit faire après le prompt

1. Classer le projet (ex. `gamedev-godot`) via `.claude/skills-registry.md`.
2. Charger `gamedev` + `godot-skill-judge` (et `writing-for-agents` pour les fichiers d'agents).
3. Poser au plus 3 questions, puis remplir `CLAUDE.md` et `AGENTS.md`.
4. Créer le squelette, puis proposer la première fonctionnalité via Superpowers.

## Authentification (une seule fois, hors Claude)

```bash
gh auth login                      # GitHub
npx wrangler login                 # Cloudflare (ou export CLOUDFLARE_API_TOKEN=...)
```

Les secrets restent dans ton environnement ou `.env` (bloqué en lecture par `settings.json`).
