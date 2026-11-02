#!/usr/bin/env bash
# Publica el servicio de licencias: baja el codigo, construye la imagen, la levanta y espera a que este sana.
# El esquema de la base lo aplica el servicio al arrancar (solo crea lo que falta; no toca datos).
# Si la version nueva no arranca, vuelve a la anterior. Se puede repetir las veces que haga falta:
#   sudo bash /data/apps/licencias/desplegar.sh
# Para probar una rama antes de unirla a main:
#   RAMA=mi-rama sudo -E bash /data/apps/licencias/desplegar.sh
set -euo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REPO="${REPO:-https://github.com/jeliases-informaDev/Licencias-Backend.git}"
RAMA="${RAMA:-main}"
APP=/data/apps/licencias
ENVFILE=/opt/sulotec/licencias.env

[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }
[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE: primero corre preparar.sh" >&2; exit 1; }
[ -f "$APP/docker-compose.yml" ] || { echo "Falta $APP/docker-compose.yml: primero copia el kit desde GitHub (apps/licencias)." >&2; exit 1; }

salud() { docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null || echo ninguno; }

echo "== Codigo"
if [ -d "$APP/backend/.git" ]; then git -C "$APP/backend" fetch -q origin "$RAMA"; else git clone -q "$REPO" "$APP/backend"; git -C "$APP/backend" fetch -q origin "$RAMA"; fi
git -C "$APP/backend" reset -q --hard "origin/$RAMA"
c=$(git -C "$APP/backend" rev-parse --short=12 HEAD)
echo "   $RAMA @ $c"
[ -f "$APP/backend/Dockerfile" ] || { echo "Esa rama no tiene Dockerfile (¿falta unir el cambio a la rama?)" >&2; exit 1; }

echo "== Construyendo la imagen (la primera vez tarda unos minutos)"
docker build -q -t "licencias:$c" "$APP/backend" >/dev/null

anterior=$(docker image inspect -f '{{.Id}}' licencias:latest 2>/dev/null || true)
docker tag "licencias:$c" licencias:latest

echo "== Levantando"
(cd "$APP" && docker compose up -d --force-recreate)
for _ in $(seq 1 40); do [ "$(salud licencias)" = healthy ] && break; sleep 3; done
if [ "$(salud licencias)" = healthy ]; then
  echo "   licencias: sano"
else
  echo "   licencias: NO arranco bien. Ultimas lineas:" >&2
  docker logs --tail 25 licencias >&2 || true
  if [ -n "$anterior" ]; then
    echo "== Volviendo a la version anterior" >&2
    docker tag "$anterior" licencias:latest
    (cd "$APP" && docker compose up -d --force-recreate)
  fi
  exit 1
fi

# Conserva las 3 ultimas versiones por si hay que volver atras a mano
docker images licencias --format '{{.Tag}}' | grep -v '^latest$' | tail -n +4 | xargs -r -I{} docker rmi -f "licencias:{}" >/dev/null 2>&1 || true
echo "Listo: servicio de licencias publicado ($c). Siguiente: sudo bash /data/apps/licencias/probar.sh"
