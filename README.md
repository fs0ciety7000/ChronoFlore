# Claude project scaffold

Squelette réutilisable : skills pré-installés, routage automatique par type de projet, `CLAUDE.md` / `AGENTS.md` prêts à remplir.

## Démarrage

```bash
# 1. Copier ce dossier comme base d'un nouveau projet
cp -r claude-scaffold mon-projet && cd mon-projet && git init

# 2. Installer les skills
chmod +x scripts/setup-skills.sh
./scripts/setup-skills.sh                 # tout
./scripts/setup-skills.sh --only shopify  # ou un sous-ensemble

# 3. Dans Claude Code : installer le plugin Superpowers
#    /plugin marketplace add obra/superpowers
#    /plugin install superpowers@superpowers-marketplace

# 4. Lancer Claude Code et initialiser
claude
> /new-project boutique Shopify avec un thème sur mesure et un petit backend Go
```

## Comment ça marche

- `CLAUDE.md` impose la règle : **router avant de coder**. Il importe `AGENTS.md`.
- `.claude/skills-registry.md` contient la table *type de projet → skills*. Claude n'y charge que les skills utiles.
- `/new-project` classe le projet, vérifie les skills, remplit `CLAUDE.md` et `AGENTS.md`, crée le squelette.
- Skill manquant : `find-skills` cherche, propose, et on met à jour le registre.

## Fichiers

| Fichier | Rôle |
|---|---|
| `CLAUDE.md` | Entrée Claude Code, règle de routage, section « Projet courant » |
| `AGENTS.md` | Règles communes à tous les agents, commandes, structure |
| `.claude/skills-registry.md` | Inventaire + table de routage |
| `.claude/commands/new-project.md` | Commande `/new-project` |
| `scripts/setup-skills.sh` | Installation de tous les skills |
| `.claude/settings.json` | Permissions par défaut (GitHub et Cloudflare larges, destructif sur confirmation) |
| `PROMPTS.md` | Prompts de démarrage par type de projet (jeu 2D, Shopify, Go, etc.) |

## Notes

- Les noms exacts de skills dans les packs (`gamedev-skills`, `emilkowalski/skills`) dépendent de ce que publient ces dépôts. Après installation, vérifie la liste avec `npx skills list` et ajuste le registre.
- `/plugin ...` sont des commandes slash de Claude Code : elles ne peuvent pas être lancées depuis le script shell.
