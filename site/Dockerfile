FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
# npm ci installs devDependencies too (needed by `astro build`).
RUN npm ci
COPY . .
# Polyfork models are not committed: download them (fails the build if one is missing).
RUN npm run fetch:models && npm run build

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
