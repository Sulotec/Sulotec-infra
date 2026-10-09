#!/usr/bin/env bash
# Paso 2 (y cada vez que haya codigo nuevo): descarga el codigo, construye las imagenes y levanta todo.
#   sudo bash /data/apps/miradar360/scripts/desplegar.sh
# No toca Render ni los datos: solo construye y levanta los contenedores del servidor.
set -euo pipefail

APP="$(cd "$(dirname "$0")/.." && pwd)"
ENV=/opt/sulotec/miradar360.env
REPO_BACK="${REPO_BACK:-https://github.com/jeliases-informaDev/Afacop-Backend.git}"
REPO_WEB="${REPO_WEB:-https://github.com/jeliases-informaDev/Afacop-FrontEnd.git}"

[ -r "$ENV" ] || { echo "Falta $ENV: corre antes scripts/preparar.sh" >&2; exit 1; }
if grep -q "PEGAR_" "$ENV"; then
  echo "Faltan valores en $ENV. Lineas pendientes:" >&2
  grep -n "PEGAR_" "$ENV" | cut -d= -f1 >&2
  exit 1
fi

# 1) Codigo de la API y de la web (siempre la rama principal de cada repositorio)
mkdir -p "$APP/src"
for par in "backend|$REPO_BACK" "web|$REPO_WEB"; do
  d="${par%%|*}"; u="${par#*|}"
  if [ -d "$APP/src/$d/.git" ]; then
    git -C "$APP/src/$d" pull --ff-only
  else
    git clone --depth 1 "$u" "$APP/src/$d"
  fi
done

# 2) Imagenes
VITE_API_URL="$(grep -E '^VITE_API_URL=' "$ENV" | head -1 | cut -d= -f2-)"
docker build -f "$APP/backend.Dockerfile" -t miradar360-api:latest "$APP/src/backend"
docker build -f "$APP/web.Dockerfile" --build-arg VITE_API_URL="$VITE_API_URL" -t miradar360-web:latest "$APP/src/web"

# 3) Levantar (la API aplica las migraciones al arrancar)
cd "$APP"
docker compose --env-file "$ENV" up -d --force-recreate

echo "Esperando a que la API este sana (hasta 3 minutos)..."
for _ in $(seq 1 36); do
  estado="$(docker inspect -f '{{.State.Health.Status}}' miradar360-api 2>/dev/null || echo desconocido)"
  [ "$estado" = healthy ] && break
  sleep 5
done
docker compose --env-file "$ENV" ps
[ "$estado" = healthy ] || { echo "La API no quedo sana. Revisa:  docker logs --tail 80 miradar360-api" >&2; exit 1; }
echo "Listo. Falta (solo el dia del cambio) crear las rutas del tunel; ver README.md."
