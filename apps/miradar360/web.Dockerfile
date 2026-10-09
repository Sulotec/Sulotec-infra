# Panel web de MiRadar360 (repo jeliases-informaDev/Afacop-FrontEnd). Se construye con: scripts/desplegar.sh
#
# OJO: en produccion el panel ignora VITE_API_URL y SIEMPRE usa https://afacop-backend.onrender.com
# (src/app/providers/AuthContext.jsx, PRODUCTION_API_URL: se puso asi a proposito para que una variable vieja no
# desvie el login). Para el dia del cambio hace falta un cambio previo en ese archivo que lea VITE_PROD_API_URL;
# esta imagen ya lo pasa al construir. Ver README.md, "Cambio previo en el panel web".
FROM node:24-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG VITE_PROD_API_URL
ENV VITE_PROD_API_URL=$VITE_PROD_API_URL
RUN npm run build

FROM nginx:stable-alpine
COPY --from=build /app/dist /usr/share/nginx/html
# La configuracion de nginx se monta desde web.nginx.conf (ver docker-compose.yml).
