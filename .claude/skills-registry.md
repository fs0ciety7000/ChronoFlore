# Registre des skills

Source de vérité du routage : **type de projet → skills à charger**. Claude lit ce fichier avant de commencer une tâche et ne charge que les skills de la ligne correspondante.

## Skills installés

| Skill | Source | Rôle |
|---|---|---|
| `find-skills` | vercel-labs/skills | Chercher/installer un skill qui manque |
| `writing-for-agents` | mattpocock/skills | Rédiger CLAUDE.md, AGENTS.md, SKILL.md, prompts |
| gamedev (pack) | gamedev-skills/awesome-gamedev-agent-skills | Pratiques générales de jeu vidéo |
| `shopify-liquid` | Shopify/Shopify-AI-Toolkit | Thèmes Liquid |
| `shopify-admin` | Shopify/Shopify-AI-Toolkit | API Admin GraphQL |
| emilkowalski (pack) | emilkowalski/skills | Design d'interface, détails UI |
| `animate` | emilkowalski/skills | Animations/transitions UI |
| `design-taste-frontend` | Leonxlnx/taste-skill | Goût visuel, éviter l'esthétique « template » |
| `slideshow` | heygen-com/hyperframes | Diaporamas/vidéos de présentation |
| `golang-database` | samber/cc-skills-golang | Accès base de données en Go |
| `rust-backend` | windmill-labs/windmill | Backend Rust |
| `godot-skill-judge` | thedivergentai/gd-agentic-skills | Évaluer la qualité de skills/code Godot |
| Superpowers (plugin) | obra/superpowers | Workflow : brainstorming, plans, TDD, revue |

## Table de routage

| Type de projet | Détection (mots-clés / fichiers) | Skills à charger, dans l'ordre |
|---|---|---|
| `web-frontend` | React, Vue, Next, Svelte, CSS, landing page, `package.json` + composants | `design-taste-frontend`, emilkowalski (pack), `animate` |
| `shopify` | thème, Liquid, `*.liquid`, `shopify.app.toml`, Admin API | `shopify-liquid` (thème) et/ou `shopify-admin` (API/données) ; + `design-taste-frontend` si UI |
| `gamedev-godot` | `project.godot`, GDScript, `.tscn` | gamedev (pack), `godot-skill-judge` |
| `gamedev-autre` | Unity, Unreal, Bevy, jeu 2D/3D sans Godot | gamedev (pack) |
| `backend-go` | `go.mod`, `*.go`, SQL, migrations | `golang-database` |
| `backend-rust` | `Cargo.toml`, `*.rs`, serveur/API Rust | `rust-backend` |
| `video-slides` | présentation, diaporama, vidéo explicative | `slideshow` ; + `animate` si animations UI |
| `meta-agents` | écrire/réviser CLAUDE.md, AGENTS.md, SKILL.md | `writing-for-agents` |
| `autre` / inconnu | aucun match ci-dessus | `find-skills` pour chercher, proposer avant d'installer |

## Règles de routage

1. **Toujours actifs** : Superpowers (workflow) et `writing-for-agents` (dès qu'on écrit un fichier destiné à un agent).
2. **Combiner** quand le projet mélange plusieurs types (ex. site Shopify + backend Go : `shopify-liquid` + `golang-database`).
3. **Ne pas tout charger** : un skill par besoin réel. Moins de contexte = meilleures réponses.
4. **Skill manquant** : exécute `find-skills`, présente les candidats à l'utilisateur, installe seulement après accord, puis ajoute une ligne à ce registre.
5. **Après installation d'un nouveau skill** : mets à jour les deux tableaux ci-dessus.

## Ajouter un skill

1. Ajoute la commande `npx skills add ...` dans `scripts/setup-skills.sh`.
2. Ajoute la ligne dans « Skills installés ».
3. Ajoute-le à la ou aux lignes concernées de « Table de routage ».
