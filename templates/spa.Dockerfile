# Frontend React / Angular / Vite. Copia este archivo (como Dockerfile) y spa.nginx.conf a la raiz del repo.
# Carpeta de salida segun el framework:
#   Vite / React moderno -> dist      Create React App -> build      Angular -> dist/<proyecto>/browser
ARG OUT_DIR=dist

FROM node:22-alpine AS build
ARG OUT_DIR
WORKDIR /src
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
ARG OUT_DIR
COPY spa.nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/${OUT_DIR} /usr/share/nginx/html
EXPOSE 80
