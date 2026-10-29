# AGENTS.md

Règles communes à tous les agents de code (Claude Code, Codex, Cursor, etc.). Format volontairement neutre : rien ici n'est spécifique à Claude.

## Contexte du projet

- **Nom** : ChronoFlore
- **Type** : `gamedev-godot` (`game/`) + `web-frontend` (`site/`)
- **Résumé en une phrase** : jeu d'action-arcade isométrique kawaï et mélancolique où une rêveuse lucide, botaniste-chasseuse, capture au filet, au harpon et au fusil tranquillisant les plantes nées de ses émotions avant de se réveiller. Une run = une nuit de 8 h de sommeil, sans chronomètre en temps réel : chaque capture fait avancer l'heure, une jauge de lucidité (pétales) qui se vide la réveille trop tôt (voir `docs/superpowers/specs/`).

### Direction artistique (référence pour tout asset)

- **Diorama** : île de terrain flottante, bords en coupe de terre, lumière douce, ombres légères, fond crème uni, couleurs pastel.
- **Caméra** : 3D, `Camera3D` orthographique, angle isométrique fixe.
- **Héroïne** : peau foncée, longues tresses noires, lunettes rondes teintées roses, grand sourire, haut à rayures multicolores (vert, rouge, orange, violet), petit collier doré. Proportions chibi.
- **Rendu** (réf. vidéo pêche) : 3D stylisée vue de dessus/iso, eau turquoise translucide aux caustiques, écume blanche, ombres franches et douces, HUD minimal en cartouches crème arrondies.
- **Ton** : mélancolique mais kawaï ; les plantes sont des émotions, des souvenirs et des pensées.

### Assets 3D

- **Source** : modèles faits maison (Blender `bpy` par script) ou catalogue Polyfork (MCP `polyfork`). Aucune autre banque d'assets.
- **Fait maison (choix actuel du jeu)** : héroïne, héros, île, décor et les 12 plantes. Chaque GLB est généré par un script commité à côté de lui dans `game/assets/custom/<sujet>/` (ex. `build_heroine.py`, `build_island.py`, `build_plants.py`) ; régénère avec le Python de `bpy` au lieu d'éditer le GLB. Matériaux nommés avec couleur de base (pas de vertex colors).
- **Polyfork → Godot** (si besoin) : télécharge le GLB (pas le `.mjs`), range-le dans `game/assets/polyfork/<asset-id>/`. Tailles en mètres réels, origine au sol : choisis la bonne taille au lieu de rescaler. Ses couleurs de sommets s'importent avec `vertex_color_use_as_albedo = false`.

## Commandes

```bash
# Jeu (Godot 4.7.2, binaire `godot` dans le PATH ; export Web : templates 4.7.2 installés)
import:  godot --headless --path game --import
test:    godot --headless --path game --import && godot --headless --path game --script res://tests/test_runner.gd
run:     godot --path game
build:   mkdir -p build/web && godot --headless --path game --export-release "Web" ../build/web/index.html

# Site vitrine (Node 22, depuis site/)
install: npm install
dev:     npm run dev
build:   npm run build          # sortie dans site/dist/
lint:    npm run check          # astro check
deploy:  push sur la branche suivie par Coolify -> build du Dockerfile de site/
```

## Déploiement

- Coolify : `site/Dockerfile` (build Astro puis nginx). Variables d'API dans `.env` (voir `.env.example`).
- DNS : enregistrement Cloudflare `chronoflore.cardormedia.com` vers `COOLIFY_SERVER_IP`.
- Jeu Web (`/jouer/`) : construit par `.github/workflows/game-web.yml` (release `game-web-latest`), téléchargé au build du site par `npm run fetch:game` avec `GAME_RELEASE_TOKEN` = variable de *build* Coolify, PAT fine-grained `Contents: read` sur ce dépôt (sans lui : page « Le jeu arrive bientôt »).

## Structure du dépôt

```
.
├── AGENTS.md, CLAUDE.md     # règles agents
├── .claude/                 # settings, commandes, registre des skills, skills installés
├── .agents/skills/          # sources des skills (npx skills)
├── scripts/setup-skills.sh  # installation des skills
├── game/                    # projet Godot (project.godot)
│   ├── scenes/  scripts/  assets/
│   └── tests/test_runner.gd
├── site/                    # site vitrine Astro
│   ├── src/pages/  public/
│   └── Dockerfile, nginx.conf
└── branding/                # logo (sources SVG + exports)
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
