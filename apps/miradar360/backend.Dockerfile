# API de MiRadar360 (repo jeliases-informaDev/Afacop-Backend). Se construye con: scripts/desplegar.sh
# Node 24 + Chromium del sistema (Puppeteer genera los PDF de admision; funciona en ARM).
FROM node:24-bookworm-slim

ENV NODE_ENV=production \
    PUPPETEER_SKIP_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    HOME=/tmp

RUN apt-get update \
 && apt-get install -y --no-install-recommends chromium fonts-liberation fonts-noto-color-emoji ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Dependencias primero (aprovecha la cache). postinstall corre "prisma generate", por eso va el esquema.
COPY package.json package-lock.json ./
COPY prisma ./prisma
COPY prisma.config.ts ./
RUN npm ci --omit=dev

COPY . .
RUN npm run build        # prisma generate: deja el cliente listo con el codigo final

USER node
EXPOSE 4000
# "npm start" aplica las migraciones y crea el administrador inicial solo si la base esta vacia.
CMD ["npm", "start"]
