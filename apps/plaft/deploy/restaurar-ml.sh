#!/usr/bin/env bash
# Restaura en la PostgreSQL de la VM el respaldo de la base del servicio de IA de PLAFT ("security_ml", hecho con pg_dump -Fc,
# aunque venga de una PostgreSQL mas nueva que la del servidor). Es todo o nada: si algo falla, la base queda como estaba.
#   sudo bash /data/apps/plaft/restaurar-ml.sh [archivo.dump]
# Sin argumento descarga  externos/plaft/security_ml.dump  del bucket sulotec-backups (con la identidad de la VM).
# Antes: 1) sudo /opt/sulotec/scripts/new-project-db.sh postgres plaft_ml   2) sudo bash /data/apps/plaft/preparar-ml.sh
# La base debe estar vacia; para reemplazar su contenido:  BORRAR_DESTINO=si sudo -E bash /data/apps/plaft/restaurar-ml.sh
# Variables solo para pruebas: ENVFILE_ML, RED_DOCKER, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

ENVML="${ENVFILE_ML:-/opt/sulotec/plaft-ml.env}"
RED="${RED_DOCKER:-sulotec_data}"
BUCKET="${BACKUP_BUCKET:-sulotec-backups}"
OBJETO="${OBJETO:-externos/plaft/security_ml.dump}"
[ -r "$ENVML" ] || { echo "Falta $ENVML: primero corre preparar-ml.sh" >&2; exit 1; }
TMP="$(mktemp -d)"; chmod 700 "$TMP"
trap '[ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"' EXIT

url="$(grep -E '^DATABASE_URL=' "$ENVML" | head -1 | cut -d= -f2-)"
[ -n "$url" ] || { echo "$ENVML no tiene DATABASE_URL" >&2; exit 1; }
DESTINO="${url/postgresql+psycopg:/postgresql:}"       # psql no entiende el prefijo de SQLAlchemy
[[ "$DESTINO" =~ ^postgresql://[^:]+:[^@]+@[^/]+/[A-Za-z0-9_]+$ ]] || { echo "DATABASE_URL de $ENVML no tiene la forma esperada (postgresql+psycopg://usuario:clave@servidor:5432/base)" >&2; exit 1; }
echo "   destino: $(printf '%s' "$DESTINO" | sed -E 's#(://[^:]+:)[^@]*@#\1***@#')"

archivo="${1:-}"
if [ -z "$archivo" ]; then
  echo "== Descargando $OBJETO del bucket $BUCKET"
  oci os object get --auth instance_principal --bucket-name "$BUCKET" --name "$OBJETO" --file "$TMP/security_ml.dump" >/dev/null \
    || { echo "No pude descargar $OBJETO. ¿Lo subiste al bucket con el prefijo externos/plaft/ ?" >&2; exit 1; }
  archivo="$TMP/security_ml.dump"
fi
[ -f "$archivo" ] || { echo "No existe $archivo" >&2; exit 1; }
echo "   respaldo: $(basename "$archivo") ($(du -h "$archivo" | cut -f1))"
carpeta="$(cd "$(dirname "$archivo")" && pwd)"; nombre="$(basename "$archivo")"

cli() { docker run --rm --network "$RED" -e DESTINO="$DESTINO" -v "$carpeta:/backup:ro" postgres:18 "$@"; }
# SQL por la entrada estandar: asi no hay que escaparlo dentro de "sh -c" (alli "$$" seria el numero del proceso)
sql() { docker run --rm -i --network "$RED" -e DESTINO="$DESTINO" postgres:18 sh -c 'exec psql "$DESTINO" -X -At -v ON_ERROR_STOP=1'; }

echo "== 1. El destino debe estar vacio"
tablas="$(printf '%s\n' "select count(*) from information_schema.tables where table_schema='public'" | sql)" || { echo "No pude conectar con la base de destino (¿clave o red?)." >&2; exit 1; }
if [ "$tablas" != "0" ]; then
  [ "${BORRAR_DESTINO:-}" = "si" ] || { echo "La base ya tiene $tablas tablas. Para reemplazarla: BORRAR_DESTINO=si sudo -E bash $0" >&2; exit 1; }
  echo "   BORRAR_DESTINO=si: se vacia el esquema public"
  cli sh -c 'psql "$DESTINO" -X -q -v ON_ERROR_STOP=1 -c "drop schema public cascade; create schema public;"' >/dev/null
fi

echo "== 2. Restaurando (en una sola transaccion)"
# pg_restore genera el SQL sin el esquema public, extensiones ni estadisticas, y sin "SET transaction_timeout" (no existe antes de PostgreSQL 17)
RESTAURAR='set -e
pg_restore -l "/backup/$1" | grep -v -e " SCHEMA - public " -e " EXTENSION " -e " STATISTICS DATA " > /tmp/lista.txt
pg_restore --no-owner --no-acl -L /tmp/lista.txt -f /tmp/restore.sql "/backup/$1"
sed -i "/^SET transaction_timeout/d" /tmp/restore.sql
psql "$DESTINO" -X -q -1 -v ON_ERROR_STOP=1 -f /tmp/restore.sql -o /dev/null'
cli sh -c "$RESTAURAR" restaurar "$nombre" || { echo "La restauracion se cancelo y la base quedo como estaba. Pasame las lineas de error de arriba." >&2; exit 1; }
cli sh -c 'psql "$DESTINO" -X -q -c "analyze"' >/dev/null 2>&1 || true

echo "== 3. Lo que quedo en la base (tablas y filas)"
sql <<'SQL' | awk -F'|' '{printf "   %-26s %10s filas\n", $1, $2}'
select c.relname || '|' || (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I', c.relname), false, true, '')))[1]::text
from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' order by c.relname;
SQL
echo
echo "LISTO: la base del servicio de IA quedo restaurada. Siguiente: sudo bash /data/apps/plaft/desplegar.sh"
