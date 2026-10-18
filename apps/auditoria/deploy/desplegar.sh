#!/usr/bin/env bash
# Publica Auditoria de Visitas (API y panel web): baja el codigo, construye las imagenes, las levanta y espera a que esten sanas.
# Si la version nueva no arranca, vuelve a la anterior. Se puede repetir las veces que haga falta:
#   sudo bash /data/apps/auditoria/desplegar.sh
# Para probar una rama antes de unirla a main:
#   RAMA_BACKEND=mi-rama RAMA_FRONTEND=mi-rama sudo -E bash /data/apps/auditoria/desplegar.sh
set -euo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REPO_BACKEND="${REPO_BACKEND:-https://github.com/jeliases-informaDev/Huancayo-Backend.git}"
REPO_FRONTEND="${REPO_FRONTEND:-https://github.com/jeliases-informaDev/CajaHuancayo-Web.git}"
RAMA_BACKEND="${RAMA_BACKEND:-main}"
RAMA_FRONTEND="${RAMA_FRONTEND:-main}"
API_PUBLICA="${API_PUBLICA:-https://api-auditoria.sulotec.com}"   # queda incrustada en el panel web al compilarlo
APP=/data/apps/auditoria
ENVFILE=/opt/sulotec/auditoria.env

[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }
[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE: primero corre preparar.sh" >&2; exit 1; }
[ -f "$APP/docker-compose.yml" ] || { echo "Falta $APP/docker-compose.yml: primero copia el kit desde GitHub (apps/auditoria)." >&2; exit 1; }

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
echo "   backend $RAMA_BACKEND @ $cb   panel $RAMA_FRONTEND @ $cf"
[ -f "$APP/backend/Dockerfile" ]  || { echo "El backend de esa rama no tiene Dockerfile (¿falta unir el cambio a la rama?)" >&2; exit 1; }
[ -f "$APP/frontend/Dockerfile" ] || { echo "El panel de esa rama no tiene Dockerfile (¿falta unir el cambio a la rama?)" >&2; exit 1; }

echo "== Construyendo imagenes (la primera vez tarda unos minutos)"
docker build -q -t "auditoria-api:$cb" "$APP/backend" >/dev/null
docker build -q -t "auditoria-web:$cf" --build-arg "VITE_API_URL=$API_PUBLICA" "$APP/frontend" >/dev/null

anterior_api=$(docker image inspect -f '{{.Id}}' auditoria-api:latest 2>/dev/null || true)
anterior_web=$(docker image inspect -f '{{.Id}}' auditoria-web:latest 2>/dev/null || true)
docker tag "auditoria-api:$cb" auditoria-api:latest
docker tag "auditoria-web:$cf" auditoria-web:latest

echo "== Levantando"
(cd "$APP" && docker compose up -d --force-recreate)

ok=1
for contenedor in auditoria-api auditoria-web; do
  for _ in $(seq 1 40); do [ "$(salud $contenedor)" = healthy ] && break; sleep 3; done
  if [ "$(salud $contenedor)" = healthy ]; then echo "   $contenedor: sano"; else echo "   $contenedor: NO arranco bien" >&2; ok=0; fi
done

if [ "$ok" -eq 0 ]; then
  echo "== La version nueva fallo. Ultimas lineas de la API:" >&2
  docker logs --tail 25 auditoria-api >&2 || true
  if [ -n "$anterior_api" ] || [ -n "$anterior_web" ]; then
    echo "== Volviendo a la version anterior" >&2
    [ -n "$anterior_api" ] && docker tag "$anterior_api" auditoria-api:latest
    [ -n "$anterior_web" ] && docker tag "$anterior_web" auditoria-web:latest
    (cd "$APP" && docker compose up -d --force-recreate)
  fi
  exit 1
fi

# Conserva las 3 ultimas versiones de cada imagen por si hay que volver atras a mano
for img in auditoria-api auditoria-web; do
  docker images "$img" --format '{{.Tag}}' | grep -v '^latest$' | tail -n +4 | xargs -r -I{} docker rmi -f "$img:{}" >/dev/null 2>&1 || true
done
echo "Listo: Auditoria de Visitas publicada (backend $cb, panel $cf)."
echo "Comprobar: sudo bash /data/apps/auditoria/probar.sh"
