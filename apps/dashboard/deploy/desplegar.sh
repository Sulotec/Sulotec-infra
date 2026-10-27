#!/usr/bin/env bash
# Publica Dashboard Empresarial (API y web): baja el codigo, construye las imagenes, aplica el esquema de la base (solo agrega lo que falta),
# las levanta y espera a que esten sanas.
# Si la version nueva no arranca, vuelve a la anterior. Se puede repetir las veces que haga falta:
#   sudo bash /data/apps/dashboard/desplegar.sh
# Para probar una rama antes de unirla a main:
#   RAMA_BACKEND=mi-rama RAMA_FRONTEND=mi-rama sudo -E bash /data/apps/dashboard/desplegar.sh
set -euo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REPO_BACKEND="${REPO_BACKEND:-https://github.com/Henry-InformaPeru/dashboard-empresarial-backend.git}"
REPO_FRONTEND="${REPO_FRONTEND:-https://github.com/Henry-InformaPeru/dashboard-empresarial-frontend.git}"
RAMA_BACKEND="${RAMA_BACKEND:-main}"
RAMA_FRONTEND="${RAMA_FRONTEND:-main}"
API_PUBLICA="${API_PUBLICA:-https://api-dashboards.sulotec.com}"   # queda incrustada en la web al compilarla
APP=/data/apps/dashboard
ENVFILE=/opt/sulotec/dashboard.env

[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }
[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE: primero corre preparar.sh" >&2; exit 1; }
[ -f "$APP/docker-compose.yml" ] || { echo "Falta $APP/docker-compose.yml: primero copia el kit desde GitHub (apps/dashboard)." >&2; exit 1; }

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
echo "   backend $RAMA_BACKEND @ $cb   web $RAMA_FRONTEND @ $cf"
[ -f "$APP/backend/Dockerfile" ]  || { echo "El backend de esa rama no tiene Dockerfile (¿falta unir el cambio a la rama?)" >&2; exit 1; }
[ -f "$APP/frontend/Dockerfile" ] || { echo "La web de esa rama no tiene Dockerfile (¿falta unir el cambio a la rama?)" >&2; exit 1; }
[ -f "$APP/backend/db/schema.sql" ] || { echo "El backend de esa rama no trae db/schema.sql (¿falta unir el cambio a la rama?)" >&2; exit 1; }

echo "== Construyendo imagenes (la primera vez tarda unos minutos)"
docker build -q -t "dashboard-api:$cb" "$APP/backend" >/dev/null
docker build -q -t "dashboard-web:$cf" --build-arg "NEXT_PUBLIC_API_URL=$API_PUBLICA" "$APP/frontend" >/dev/null

echo "== Base de datos (el esquema solo agrega lo que falta y no toca datos)"
leer() { grep -E "^$1=" "$ENVFILE" | head -1 | cut -d= -f2- || true; }
DB_HOST="$(leer DB_HOST)"; DB_PORT="$(leer DB_PORT)"; DB_NAME="$(leer DB_NAME)"; DB_USER="$(leer DB_USER)"; PGPASSWORD="$(leer DB_PASSWORD)"; export PGPASSWORD
{ [ -n "$DB_HOST" ] && [ -n "$DB_NAME" ] && [ -n "$DB_USER" ] && [ -n "$PGPASSWORD" ]; } || { echo "$ENVFILE no tiene los datos de la base." >&2; exit 1; }
# El esquema viaja dentro de la imagen de la API recien construida y corre ANTES de levantar la version nueva: si falla, no se publica nada
# y la version actual sigue corriendo. Es repetible: crea solo lo que falta (por ejemplo columnas nuevas) y no cambia ni borra datos.
if ! docker run --rm --entrypoint cat "dashboard-api:$cb" /app/db/schema.sql \
  | docker run --rm -i --network sulotec_data -e PGPASSWORD -e PGOPTIONS="-c client_min_messages=warning" postgres:16 \
      psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -X -q -v ON_ERROR_STOP=1 >/dev/null; then
  echo "No se pudo actualizar el esquema de la base: no se publico nada y la version actual sigue corriendo." >&2
  exit 1
fi

anterior_api=$(docker image inspect -f '{{.Id}}' dashboard-api:latest 2>/dev/null || true)
anterior_web=$(docker image inspect -f '{{.Id}}' dashboard-web:latest 2>/dev/null || true)
docker tag "dashboard-api:$cb" dashboard-api:latest
docker tag "dashboard-web:$cf" dashboard-web:latest

echo "== Levantando"
(cd "$APP" && docker compose up -d --force-recreate)

ok=1
for contenedor in dashboard-api dashboard-web; do
  for _ in $(seq 1 40); do [ "$(salud $contenedor)" = healthy ] && break; sleep 3; done
  if [ "$(salud $contenedor)" = healthy ]; then echo "   $contenedor: sano"; else echo "   $contenedor: NO arranco bien" >&2; ok=0; fi
done

if [ "$ok" -eq 0 ]; then
  echo "== La version nueva fallo. Ultimas lineas de la API:" >&2
  docker logs --tail 25 dashboard-api >&2 || true
  if [ -n "$anterior_api" ] || [ -n "$anterior_web" ]; then
    echo "== Volviendo a la version anterior" >&2
    [ -n "$anterior_api" ] && docker tag "$anterior_api" dashboard-api:latest
    [ -n "$anterior_web" ] && docker tag "$anterior_web" dashboard-web:latest
    (cd "$APP" && docker compose up -d --force-recreate)
  fi
  exit 1
fi

# Conserva las 3 ultimas versiones de cada imagen por si hay que volver atras a mano
for img in dashboard-api dashboard-web; do
  docker images "$img" --format '{{.Tag}}' | grep -v '^latest$' | tail -n +4 | xargs -r -I{} docker rmi -f "$img:{}" >/dev/null 2>&1 || true
done
echo "Listo: Dashboard Empresarial publicado (backend $cb, web $cf)."
echo "Siguiente: importar-datos.sh (primera vez), crear-admin.sh y probar.sh en /data/apps/dashboard/"
