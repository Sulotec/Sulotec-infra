#!/usr/bin/env bash
# Publica Indira: baja el codigo, construye la imagen, la levanta y espera a que este sana.
# Si la version nueva no arranca, vuelve a la anterior. Se puede repetir las veces que haga falta:
#   sudo bash /data/apps/indira/desplegar.sh
# Para probar una rama antes de unirla a main:
#   RAMA=feature/primera-entrega sudo -E bash /data/apps/indira/desplegar.sh
# Volver atras a mano (se conservan las 3 ultimas versiones):
#   docker images indira  ->  sudo docker tag indira:<version> indira:latest && cd /data/apps/indira && sudo docker compose up -d --force-recreate
# Apagar Indira sin borrar nada:  cd /data/apps/indira && sudo docker compose stop
set -euo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REPO="${REPO:-https://github.com/jeliases-informaDev/Indira-Backend.git}"
RAMA="${RAMA:-main}"
APP=/data/apps/indira
ENVFILE=/opt/sulotec/indira.env

[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }
[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE: primero corre preparar.sh" >&2; exit 1; }
[ -f "$APP/docker-compose.yml" ] || { echo "Falta $APP/docker-compose.yml: primero copia el kit desde GitHub (apps/indira)." >&2; exit 1; }

salud() { docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null || echo ninguno; }
ARCHIVOS=(-f docker-compose.yml)
if [ -f "$APP/usar-ollama" ]; then
  [ -f "$APP/docker-compose.ollama.yml" ] || { echo "Existe usar-ollama pero falta docker-compose.ollama.yml: copia de nuevo el kit." >&2; exit 1; }
  docker network inspect plaft_ia >/dev/null 2>&1 || { echo "No existe la red plaft_ia: ¿esta corriendo PLAFT con su Ollama?" >&2; exit 1; }
  ARCHIVOS+=(-f docker-compose.ollama.yml)
  echo "== Con el Ollama de PLAFT (red plaft_ia)"
fi
compose() { (cd "$APP" && docker compose "${ARCHIVOS[@]}" "$@"); }

echo "== Codigo"
if [ -d "$APP/backend/.git" ]; then git -C "$APP/backend" fetch -q origin "$RAMA"; else git clone -q "$REPO" "$APP/backend"; git -C "$APP/backend" fetch -q origin "$RAMA"; fi
git -C "$APP/backend" reset -q --hard "origin/$RAMA"
c=$(git -C "$APP/backend" rev-parse --short=12 HEAD)
echo "   $RAMA @ $c"
[ -f "$APP/backend/Dockerfile" ] || { echo "Esa rama no tiene Dockerfile (¿falta unir Indira-Backend#1?)" >&2; exit 1; }

echo "== Construyendo la imagen (la primera vez tarda unos minutos)"
docker build -q -t "indira:$c" "$APP/backend" >/dev/null

anterior=$(docker image inspect -f '{{.Id}}' indira:latest 2>/dev/null || true)
docker tag "indira:$c" indira:latest

echo "== Levantando"
compose up -d --force-recreate
for _ in $(seq 1 40); do [ "$(salud indira)" = healthy ] && break; sleep 3; done
if [ "$(salud indira)" = healthy ]; then
  echo "   indira: sano"
else
  echo "   indira: NO arranco bien. Ultimas lineas:" >&2
  docker logs --tail 25 indira >&2 || true
  if [ -n "$anterior" ]; then
    echo "== Volviendo a la version anterior" >&2
    docker tag "$anterior" indira:latest
    compose up -d --force-recreate
  fi
  exit 1
fi

docker images indira --format '{{.Tag}}' | grep -v '^latest$' | tail -n +4 | xargs -r -I{} docker rmi -f "indira:{}" >/dev/null 2>&1 || true
echo "Listo: Indira publicada ($c). Siguiente: sudo bash /data/apps/indira/probar.sh"
