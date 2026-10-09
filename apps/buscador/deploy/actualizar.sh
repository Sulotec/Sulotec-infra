#!/usr/bin/env bash
# Publica el frontend del Buscador cuando hay un commit nuevo en main de Sulotec/buscador-interno.
# Lo ejecuta cada 2 minutos el temporizador systemd "buscador-actualizador" (lo instala instalar-actualizador.sh).
# Lee el repositorio con una llave de SOLO LECTURA: quien trabaja en el codigo no tiene acceso a este servidor.
# Si la version nueva no compila o no arranca, se queda (o vuelve) la anterior y no se reintenta ese commit.
set -euo pipefail

BASE=/opt/sulotec/buscador-actualizador
REPO="$BASE/repo"
APP=/data/apps/buscador
LOG=/var/log/buscador-actualizador.log
export GIT_SSH_COMMAND="ssh -i $BASE/llave -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$BASE/known_hosts"

exec 9>"$BASE/.bloqueo"
flock -n 9 || exit 0
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
salud() { docker inspect -f '{{.State.Health.Status}}' buscador 2>/dev/null || echo ninguno; }

git -C "$REPO" fetch -q origin main
nuevo=$(git -C "$REPO" rev-parse origin/main)
[ "$nuevo" = "$(cat "$BASE/publicado" 2>/dev/null || true)" ] && exit 0
[ "$nuevo" = "$(cat "$BASE/fallido" 2>/dev/null || true)" ] && exit 0

log "Commit nuevo ${nuevo:0:7}: construyendo"
git -C "$REPO" reset -q --hard "$nuevo"
if ! docker build -q -t "buscador-web:$nuevo" "$REPO/web" >> "$LOG" 2>&1; then
  log "ERROR: ${nuevo:0:7} no compila; sigue la version anterior"
  echo "$nuevo" > "$BASE/fallido"
  exit 1
fi

anterior=$(docker image inspect -f '{{.Id}}' buscador-web:latest 2>/dev/null || true)
docker tag "buscador-web:$nuevo" buscador-web:latest

if [ -r /opt/sulotec/buscador.env ] && [ -f "$APP/docker-compose.yml" ]; then
  (cd "$APP" && docker compose up -d --force-recreate >> "$LOG" 2>&1)
  for _ in $(seq 1 30); do [ "$(salud)" = healthy ] && break; sleep 3; done
  if [ "$(salud)" != healthy ]; then
    log "ERROR: ${nuevo:0:7} no arranca; vuelvo a la version anterior"
    if [ -n "$anterior" ]; then
      docker tag "$anterior" buscador-web:latest
      (cd "$APP" && docker compose up -d --force-recreate >> "$LOG" 2>&1)
    fi
    echo "$nuevo" > "$BASE/fallido"
    exit 1
  fi
fi

echo "$nuevo" > "$BASE/publicado"
# Conserva las 3 ultimas versiones por si hay que volver atras a mano
docker images buscador-web --format '{{.Tag}}' | grep -v '^latest$' | tail -n +4 | xargs -r -I{} docker rmi -f "buscador-web:{}" >/dev/null 2>&1 || true
log "Publicado ${nuevo:0:7}"
