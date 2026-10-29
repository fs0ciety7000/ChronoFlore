# Déploiement du site vitrine (Coolify + Cloudflare)

Procédure rejouable pour mettre `site/` en ligne sur `https://chronoflore.cardormedia.com`.
Aucun secret n'est écrit ici : tout passe par les variables d'environnement.

## Prérequis

Variables d'environnement (jamais commitées, jamais affichées) :

| Variable | Rôle |
|---|---|
| `COOLIFY_API_URL` | URL de l'instance Coolify (sans `/api/v1`) |
| `COOLIFY_API_TOKEN` | jeton API Coolify (droits lecture + écriture + déploiement) |
| `COOLIFY_SERVER_IP` | IP publique du serveur Coolify (cible du DNS) |
| `CLOUDFLARE_API_TOKEN` | jeton Cloudflare avec `Zone:DNS:Edit` sur `cardormedia.com` |
| `CLOUDFLARE_ACCOUNT_ID` | compte Cloudflare (informatif) |
| `GAME_RELEASE_TOKEN` | PAT GitHub fine-grained, `Contents: read` sur `fs0ciety7000/ChronoFlore` : télécharge le jeu Web au build (variable de **build** Coolify, voir étape 2 bis) |

Outils : `curl`, `jq`.

```bash
CF=(-H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json")
CO=(-H "Authorization: Bearer $COOLIFY_API_TOKEN" -H "Content-Type: application/json" -H "Accept: application/json")
API="$COOLIFY_API_URL/api/v1"
```

## Paramètres de l'application

| Paramètre | Valeur |
|---|---|
| Dépôt | `fs0ciety7000/ChronoFlore` (privé, lu via la source GitHub App de Coolify) |
| Branche | `claude/focused-cerf-d2kgbx` (puis `master` après fusion) |
| Build pack | `dockerfile` |
| Base directory | `/site` |
| Dockerfile | `/Dockerfile` (relatif à la base, donc `site/Dockerfile`) |
| Port exposé | `80` (nginx) |
| Domaine | `https://chronoflore.cardormedia.com` (HTTPS Let's Encrypt via Traefik/Coolify) |
| Projet Coolify | `ChronoFlore`, environnement `production`, serveur `localhost` |

Le `Dockerfile` fait `npm ci`, `npm run fetch:models` (modèles Polyfork, non commités), `npm run fetch:game` (build Web du jeu, non commité, dans `public/jouer/`) puis `npm run build` (Astro) et sert `dist/` avec nginx.
`nginx.conf` : cache long (`immutable`, 1 an) sur `/_astro/*` et `/models/*`, `no-cache` sur le HTML et sur tout `/jouer/` (fichiers Godot non hachés).

> **Attention** : tout fichier sous `/models/` est servi `immutable` pendant un an. Un modèle modifié
> doit donc changer de nom (nom versionné ou haché, ex. `island.3f9a2c.glb`), sinon les navigateurs
> garderont l'ancienne version.

## 1. Coolify : découverte (lecture seule)

```bash
curl -sS "${CO[@]}" "$API/servers"      | jq -c '.[] | {uuid,name,ip}'
curl -sS "${CO[@]}" "$API/projects"     | jq -c '.[] | {uuid,name}'
curl -sS "${CO[@]}" "$API/github-apps"  | jq -c '.[] | {id,uuid,name,is_public}'

# Valeurs réutilisées à l'étape 2 (vides si l'objet n'existe pas encore)
SERVER_UUID=$(curl -sS "${CO[@]}" "$API/servers" | jq -r '.[] | select(.name=="localhost") | .uuid')
GITHUB_APP_UUID=$(curl -sS "${CO[@]}" "$API/github-apps" | jq -r '[.[] | select(.is_public==false)][0].uuid // empty')
PROJECT_UUID=$(curl -sS "${CO[@]}" "$API/projects" | jq -r '[.[] | select(.name=="ChronoFlore")][0].uuid // empty')
# Une application porte-t-elle déjà ce domaine ? Si oui, la réutiliser.
APP_UUID=$(curl -sS "${CO[@]}" "$API/applications" \
  | jq -r '[.[] | select((.fqdn // "") | contains("chronoflore.cardormedia.com"))][0].uuid // empty')
echo "server=$SERVER_UUID github_app=$GITHUB_APP_UUID project=${PROJECT_UUID:-<à créer>} app=${APP_UUID:-<à créer>}"
```

Vérifier que `SERVER_UUID` et `GITHUB_APP_UUID` sont non vides (et uniques) avant de continuer.

## 2. Coolify : projet et application (seulement s'ils n'existent pas)

```bash
# Projet dédié (convention : un projet Coolify par produit)
if [ -z "$PROJECT_UUID" ]; then
  PROJECT_UUID=$(curl -sS "${CO[@]}" -X POST "$API/projects" \
    -d '{"name":"ChronoFlore","description":"Site vitrine ChronoFlore"}' | jq -r .uuid)
fi

# Application depuis le dépôt privé via la GitHub App (uuids lus à l'étape 1)
if [ -z "$APP_UUID" ]; then
  APP_UUID=$(curl -sS "${CO[@]}" -X POST "$API/applications/private-github-app" -d "$(jq -n \
    --arg p "$PROJECT_UUID" --arg s "$SERVER_UUID" --arg g "$GITHUB_APP_UUID" '{
      project_uuid:$p, environment_name:"production", server_uuid:$s, github_app_uuid:$g,
      git_repository:"fs0ciety7000/ChronoFlore", git_branch:"claude/focused-cerf-d2kgbx",
      build_pack:"dockerfile", base_directory:"/site", dockerfile_location:"/Dockerfile",
      ports_exposes:"80", domains:"https://chronoflore.cardormedia.com",
      name:"chronoflore-site", instant_deploy:false }')" | jq -r .uuid)
fi
```

## 2 bis. Jeu Web : jeton de build `GAME_RELEASE_TOKEN`

Le jeu (`/jouer/`) est exporté par GitHub Actions (`.github/workflows/game-web.yml`) sur la
pré-release `game-web-latest` (asset `chronoflore-web.zip`). Le dépôt étant privé, le build Docker
le télécharge avec un PAT. Sans jeton (ou si le téléchargement échoue), le build réussit quand même
et `/jouer/` affiche « Le jeu arrive bientôt ».

1. GitHub → Settings → Developer settings → Fine-grained tokens → *Generate new token* :
   propriétaire `fs0ciety7000`, *Only select repositories* → `ChronoFlore`,
   *Repository permissions* → `Contents: Read-only` (rien d'autre), expiration au choix.
2. Coolify → application `chronoflore-site` → *Environment Variables* → ajouter
   `GAME_RELEASE_TOKEN`, cocher **Build Variable** (pas runtime). Ou par l'API :

```bash
curl -sS "${CO[@]}" -X POST "$API/applications/$APP_UUID/envs" -d "$(jq -n --arg v "$GAME_RELEASE_TOKEN" \
  '{key:"GAME_RELEASE_TOKEN", value:$v, is_build_time:true, is_preview:false}')" | jq -c .
```

3. Le jeu est publié après le workflow (quelques minutes après un push sur `game/**`) : redéployer
   le site ensuite (étape 4) pour qu'il prenne le nouveau build.

Le jeton ne finit pas dans l'image : `ARG` n'existe que dans l'étage de build, l'image nginx finale
est un étage séparé.

## 3. Cloudflare : enregistrement DNS

`A chronoflore` → `$COOLIFY_SERVER_IP`, **DNS only** (`proxied: false`) pour que Coolify obtienne
son certificat Let's Encrypt sans conflit. TTL auto (`1`).

```bash
ZONE_ID=$(curl -sS "${CF[@]}" "https://api.cloudflare.com/client/v4/zones?name=cardormedia.com" | jq -r '.result[0].id')
REC=$(curl -sS "${CF[@]}" "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=chronoflore.cardormedia.com")
REC_ID=$(echo "$REC" | jq -r '.result[0].id // empty')
BODY=$(jq -n --arg ip "$COOLIFY_SERVER_IP" '{type:"A",name:"chronoflore",content:$ip,ttl:1,proxied:false}')
if [ -z "$REC_ID" ]; then
  curl -sS "${CF[@]}" -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" -d "$BODY" | jq -c '{success, id:.result.id}'
elif [ "$(echo "$REC" | jq -r '.result[0].content')" != "$COOLIFY_SERVER_IP" ]; then
  curl -sS "${CF[@]}" -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$REC_ID" -d "$BODY" | jq -c '{success, id:.result.id}'
fi
```

## 4. Déployer et suivre

```bash
DEP=$(curl -sS "${CO[@]}" "$API/deploy?uuid=$APP_UUID&force=false" | jq -r '.deployments[0].deployment_uuid')
# Répéter jusqu'à "finished" (ou "failed" : lire .logs)
curl -sS "${CO[@]}" "$API/deployments/$DEP" | jq -r .status
```

Chaque push sur la branche redéclenche un déploiement automatique (webhook de la GitHub App).

## 5. Vérifier

```bash
curl -sI https://chronoflore.cardormedia.com/                  # HTTP/2 200, cache-control: no-cache
curl -s  https://chronoflore.cardormedia.com/ | grep -c '<h1'  # >= 1
# Certificat valide : curl sans -k ne doit pas échouer
```

## Après fusion dans `master`

Changer la branche de l'application :

```bash
curl -sS "${CO[@]}" -X PATCH "$API/applications/$APP_UUID" -d '{"git_branch":"master"}'
```

## État actuel (premier déploiement, 2026-10-29)

| Objet | Identifiant |
|---|---|
| Projet Coolify `ChronoFlore` | `pkuyhk3pw9zy76q4rx9pyebz` (environnement `production`) |
| Application Coolify `chronoflore-site` | `cms2yruxtetdmhilpvob7e6t` |
| Serveur Coolify | `localhost` (`r0os4cws004gs88k840wckok`) |
| Source GitHub App | `cckkooog08wk8088gg8wg4sk` |
| Enregistrement Cloudflare `A chronoflore` | `28cd3ae6853d8de2dd27865c4626dc03` (DNS only) |
