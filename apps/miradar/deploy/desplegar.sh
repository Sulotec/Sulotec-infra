#!/usr/bin/env bash
# Publica MiRadar (API y web): baja el codigo, construye las imagenes, las levanta y espera a que esten sanas.
# Si la version nueva no arranca, vuelve a la anterior. Se puede repetir las veces que haga falta:
#   sudo bash /data/apps/miradar/desplegar.sh
# Variables opcionales (para probar una rama antes de unirla a main):
#   Para probar otra rama: RAMA_BACKEND=mi-rama RAMA_FRONTEND=mi-rama sudo -E bash /data/apps/miradar/desplegar.sh
set -euo pipefail

REPO_BACKEND="${REPO_BACKEND:-https://github.com/jeliases-informaDev/Afacop-Backend.git}"
REPO_FRONTEND="${REPO_FRONTEND:-https://github.com/jeliases-informaDev/Afacop-FrontEnd.git}"
RAMA_BACKEND="${RAMA_BACKEND:-main}"
RAMA_FRONTEND="${RAMA_FRONTEND:-main}"
APP=/data/apps/miradar
ENVFILE=/opt/sulotec/miradar.env

[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }
[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE: primero corre preparar.sh" >&2; exit 1; }
[ -f "$APP/docker-compose.yml" ] || { echo "Falta $APP/docker-compose.yml: primero se publica desde GitHub (apps/miradar)." >&2; exit 1; }

salud() { docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null || echo ninguno; }

# Baja o actualiza un repositorio y devuelve el commit. $1 = carpeta, $2 = url, $3 = rama
bajar() {
  if [ -d "$1/.git" ]; then git -C "$1" fetch -q origin "$3"; else git clone -q "$2" "$1"; git -C "$1" fetch -q origin "$3"; fi
  git -C "$1" reset -q --hard "origin/$3"
  git -C "$1" rev-parse --short=12 HEAD
}

echo "== Codigo"
cb=$(bajar "$APP/backend"  "$REPO_BACKEND"  "$RAMA_BACKEND")
cf=$(bajar "$APP/frontend" "$REPO_FRONTEND" "$RAMA_FRONTEND")
echo "   backend $RAMA_BACKEND @ $cb   frontend $RAMA_FRONTEND @ $cf"
[ -f "$APP/backend/Dockerfile" ]  || { echo "El backend de esa rama no tiene Dockerfile (¿falta unir el cambio a la rama?)" >&2; exit 1; }
[ -f "$APP/frontend/Dockerfile" ] || { echo "El frontend de esa rama no tiene Dockerfile (¿falta unir el cambio a la rama?)" >&2; exit 1; }

echo "== Construyendo imagenes (la primera vez tarda unos minutos)"
docker build -q -t "miradar-api:$cb"  "$APP/backend"  >/dev/null
docker build -q -t "miradar-web:$cf"  "$APP/frontend" >/dev/null

anterior_api=$(docker image inspect -f '{{.Id}}' miradar-api:latest 2>/dev/null || true)
anterior_web=$(docker image inspect -f '{{.Id}}' miradar-web:latest 2>/dev/null || true)
docker tag "miradar-api:$cb" miradar-api:latest
docker tag "miradar-web:$cf" miradar-web:latest

echo "== Levantando"
(cd "$APP" && docker compose up -d --force-recreate)

ok=1
for contenedor in miradar-api miradar-web; do
  for _ in $(seq 1 40); do [ "$(salud $contenedor)" = healthy ] && break; sleep 3; done
  if [ "$(salud $contenedor)" = healthy ]; then echo "   $contenedor: sano"; else echo "   $contenedor: NO arranco bien" >&2; ok=0; fi
done

if [ "$ok" -eq 0 ]; then
  echo "== La version nueva fallo. Ultimas lineas de la API:" >&2
  docker logs --tail 25 miradar-api >&2 || true
  if [ -n "$anterior_api" ] || [ -n "$anterior_web" ]; then
    echo "== Volviendo a la version anterior" >&2
    [ -n "$anterior_api" ] && docker tag "$anterior_api" miradar-api:latest
    [ -n "$anterior_web" ] && docker tag "$anterior_web" miradar-web:latest
    (cd "$APP" && docker compose up -d --force-recreate)
  fi
  exit 1
fi

# Conserva las 3 ultimas versiones de cada imagen por si hay que volver atras a mano
for img in miradar-api miradar-web; do
  docker images "$img" --format '{{.Tag}}' | grep -v '^latest$' | tail -n +4 | xargs -r -I{} docker rmi -f "$img:{}" >/dev/null 2>&1 || true
done
echo "Listo: MiRadar publicado (backend $cb, frontend $cf)."
