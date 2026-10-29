#!/usr/bin/env bash
# Installe tous les skills et plugins du scaffold.
# Usage : ./scripts/setup-skills.sh [--only <motif>]
#   --only shopify   -> n'installe que les skills dont la commande contient "shopify"
set -uo pipefail

ONLY=""
if [[ "${1:-}" == "--only" ]]; then
  ONLY="${2:-}"
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "Erreur : npx introuvable. Installe Node.js (https://nodejs.org) puis relance." >&2
  exit 1
fi

# Une commande par ligne : npx skills add ...
SKILLS=(
  "npx skills add https://github.com/vercel-labs/skills --skill find-skills"
  "npx skills add https://github.com/mattpocock/skills --skill writing-for-agents"
  "npx skills add gamedev-skills/awesome-gamedev-agent-skills"
  "npx skills add https://github.com/Shopify/Shopify-AI-Toolkit --skill shopify-liquid"
  "npx skills add https://github.com/Shopify/Shopify-AI-Toolkit --skill shopify-admin"
  "npx skills@latest add emilkowalski/skills"
  "npx skills add https://github.com/Leonxlnx/taste-skill --skill design-taste-frontend"
  "npx skills add https://github.com/heygen-com/hyperframes --skill slideshow"
  "npx skills add https://github.com/emilkowalski/skills --skill animate"
  "npx skills add https://github.com/samber/cc-skills-golang --skill golang-database"
  "npx skills add https://github.com/windmill-labs/windmill --skill rust-backend"
  "npx skills add https://github.com/thedivergentai/gd-agentic-skills --skill godot-skill-judge"
)

ok=0
fail=0
failed=()

for cmd in "${SKILLS[@]}"; do
  if [[ -n "$ONLY" && "$cmd" != *"$ONLY"* ]]; then
    continue
  fi
  echo "→ $cmd"
  if $cmd </dev/null; then
    ok=$((ok + 1))
  else
    fail=$((fail + 1))
    failed+=("$cmd")
  fi
done

echo
echo "Skills : $ok installés, $fail en échec."
if (( fail > 0 )); then
  printf '  ✗ %s\n' "${failed[@]}"
fi

# Plugin Superpowers : à faire dans Claude Code (commandes slash, pas shell).
cat <<'EOF'

Plugin Superpowers (à lancer dans Claude Code) :
  /plugin marketplace add obra/superpowers
  /plugin install superpowers@superpowers-dev

Puis redémarre Claude Code pour charger les skills.
EOF

(( fail == 0 ))
