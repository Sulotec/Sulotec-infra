# Panel web de MiRadar360 (repo jeliases-informaDev/Afacop-FrontEnd). Se construye con: scripts/desplegar.sh
# La direccion de la API se fija al construir (VITE_API_URL), no al arrancar.
FROM node:24-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG VITE_API_URL
ENV VITE_API_URL=$VITE_API_URL
RUN npm run build

FROM nginx:stable-alpine
COPY --from=build /app/dist /usr/share/nginx/html
# La configuracion de nginx se monta desde web.nginx.conf (ver docker-compose.yml).
