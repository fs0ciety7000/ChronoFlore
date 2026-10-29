FROM node:22-alpine AS build
WORKDIR /app
# Fine-grained PAT (Contents: read on this repo) to download the game's Web
# build from the private release `game-web-latest`. Set it as a Coolify *build*
# variable. It only exists in this build stage: the final nginx image below is
# a separate stage and carries neither the build args nor this layer.
# Without it, fetch:game writes a "coming soon" page at /jouer/.
ARG GAME_RELEASE_TOKEN
COPY package*.json ./
# npm ci installs devDependencies too (needed by `astro build`).
RUN npm ci
COPY . .
# Polyfork models are not committed: download them (fails the build if one is missing).
RUN npm run fetch:models
# The game build is not committed either (never fails the build, see above).
RUN npm run fetch:game
RUN npm run build

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
