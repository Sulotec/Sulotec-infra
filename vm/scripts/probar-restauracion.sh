#!/usr/bin/env bash
# Prueba de restauracion de los respaldos (ISO/IEC 27001, control 8.13). Restaura el ultimo respaldo en contenedores
# TEMPORALES y aislados (sin red: no tocan ni ven las bases reales) y comprueba que las bases y las tablas esten.
# No imprime datos de las bases: solo nombres, numero de tablas y de filas. Al terminar borra todo lo temporal.
#   sudo /opt/sulotec/scripts/probar-restauracion.sh [--respaldar-ahora] [--desde-bucket]
#   --respaldar-ahora  corre backup.sh antes, para que el respaldo incluya lo ultimo
#   --desde-bucket     usa la copia FUERA del servidor (bucket sulotec-backups) en vez de la local
# Variables solo para pruebas: DIR_RESPALDOS, SULOTEC_DIR, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo $0" >&2; exit 1; }

BASE="${SULOTEC_DIR:-/opt/sulotec}"
DIR="${DIR_RESPALDOS:-/var/backups/sulotec}"
BUCKET="${BACKUP_BUCKET:-sulotec-backups}"
AHORA=""; DESDE_BUCKET=""
for a in "$@"; do case "$a" in --respaldar-ahora) AHORA=1;; --desde-bucket) DESDE_BUCKET=1;; *) echo "opcion desconocida: $a" >&2; exit 1;; esac; done

TMP="$(mktemp -d)"; chmod 700 "$TMP"
contenedores=()
limpiar_todo() {
  local c
  for c in "${contenedores[@]:-}"; do [ -n "$c" ] && docker rm -f "$c" >/dev/null 2>&1 || true; done
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}
trap limpiar_todo EXIT
fallos=0
falla() { echo "  FALLA  $*"; fallos=$((fallos+1)); }
ok() { echo "  OK     $*"; }
tam() { du -h "$1" | cut -f1; }

if [ -n "$AHORA" ]; then
  echo "== Respaldo nuevo (backup.sh)"
  "$BASE/scripts/backup.sh" | tail -1
fi

echo "== Respaldos que se van a probar"
if [ -n "$DESDE_BUCKET" ]; then
  origen="bucket $BUCKET (copia fuera del servidor)"
  for tipo in postgres mysql apps; do
    obj=""
    for mes in "$(date +%Y/%m)" "$(date -d 'last month' +%Y/%m)"; do
      obj="$(oci os object list --auth instance_principal --bucket-name "$BUCKET" --prefix "$mes/${tipo}_" --all --query 'data[-1].name' --raw-output 2>/dev/null || true)"
      [ -n "$obj" ] && [ "$obj" != "null" ] && break
      obj=""
    done
    [ -n "$obj" ] || { falla "no encontre un respaldo de $tipo en el bucket $BUCKET"; continue; }
    oci os object get --auth instance_principal --bucket-name "$BUCKET" --name "$obj" --file "$TMP/$(basename "$obj")" >/dev/null 2>&1 \
      && ok "descargado de $BUCKET: $obj" || falla "no pude descargar $obj"
  done
  pgf="$(ls -1 "$TMP"/postgres_*.sql.gz 2>/dev/null | head -1 || true)"; myf="$(ls -1 "$TMP"/mysql_*.sql.gz 2>/dev/null | head -1 || true)"; af="$(ls -1 "$TMP"/apps_*.tar.gz 2>/dev/null | head -1 || true)"
else
  origen="disco del servidor ($DIR)"
  pgf="$(ls -1t "$DIR"/postgres_*.sql.gz 2>/dev/null | head -1 || true)"; myf="$(ls -1t "$DIR"/mysql_*.sql.gz 2>/dev/null | head -1 || true)"; af="$(ls -1t "$DIR"/apps_*.tar.gz 2>/dev/null | head -1 || true)"
fi
for f in "$pgf" "$myf" "$af"; do [ -n "$f" ] && echo "   $(basename "$f")  $(tam "$f")  $(date -r "$f" '+%F %H:%M' 2>/dev/null || true)"; done
[ -n "$pgf" ] || { falla "no hay respaldo de PostgreSQL"; }

echo "== Integridad de los archivos"
[ -z "$pgf" ] || { gzip -t "$pgf" && ok "PostgreSQL: el archivo comprimido esta sano" || falla "PostgreSQL: archivo danado"; }
[ -z "$myf" ] || { gzip -t "$myf" && ok "MySQL: el archivo comprimido esta sano" || falla "MySQL: archivo danado"; }
[ -z "$af" ]  || { n="$(tar -tzf "$af" 2>/dev/null | wc -l || true)"; [ "${n:-0}" -gt 0 ] && ok "archivos de las apps: $n entradas legibles" || falla "archivos de las apps: no se pudo leer"; }

if [ -n "$pgf" ]; then
  echo "== Restaurando PostgreSQL en un contenedor temporal sin red"
  pc="restauracion-pg-$$"; clave="$(openssl rand -hex 16)"
  docker run -d --name "$pc" --network none -e POSTGRES_PASSWORD="$clave" postgres:16 >/dev/null; contenedores+=("$pc")
  listo=""; for i in $(seq 1 90); do docker exec "$pc" pg_isready -h 127.0.0.1 -U postgres -q 2>/dev/null && { listo=1; break; }; sleep 1; done
  [ -n "$listo" ] || falla "el PostgreSQL temporal no arranco"
  if [ -n "$listo" ]; then
    gunzip -c "$pgf" | docker exec -i "$pc" psql -U postgres -X -q -f - >/dev/null 2>"$TMP/pg.err" || true
    # "ya existe" (el rol postgres y las bases de plantilla) es normal en una restauracion completa
    malos="$(grep -E 'ERROR' "$TMP/pg.err" | grep -v 'already exists' || true)"
    if [ -n "$malos" ]; then falla "PostgreSQL: errores al restaurar ($(echo "$malos" | wc -l)); el primero: $(echo "$malos" | head -1 | cut -c1-150)"; else ok "PostgreSQL: restauracion sin errores"; fi
    bases="$(docker exec "$pc" psql -U postgres -X -At -c "select datname from pg_database where not datistemplate and datname <> 'postgres' order by 1" 2>/dev/null || true)"
    [ -n "$bases" ] || falla "PostgreSQL: no aparecio ninguna base de datos restaurada"
    echo "   base de datos          tablas        filas (restaurado)    filas (en vivo)"
    for b in $bases; do
      calc() { docker exec -i "$1" psql -U postgres -X -At -d "$b" <<'SQL' 2>/dev/null || echo "?|?"
select count(*) || '|' || coalesce(sum((xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text::bigint), 0)
from information_schema.tables where table_schema not in ('pg_catalog','information_schema') and table_type = 'BASE TABLE';
SQL
      }
      r="$(calc "$pc")"
      vivo="n/d"
      if [ -r "$BASE/docker-compose.yml" ] && [ -z "${PRUEBA:-}" ]; then
        vivo="$( ( cd "$BASE" && docker compose exec -T postgres psql -U postgres -X -At -d "$b" <<'SQL' 2>/dev/null || echo "?|?"
select count(*) || '|' || coalesce(sum((xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text::bigint), 0)
from information_schema.tables where table_schema not in ('pg_catalog','information_schema') and table_type = 'BASE TABLE';
SQL
        ) | cut -d'|' -f2)"
      fi
      printf '   %-22s %6s %18s %18s\n' "$b" "${r%%|*}" "${r##*|}" "$vivo"
      [ "${r%%|*}" != "?" ] && [ "${r%%|*}" != "0" ] || falla "base $b: sin tablas"
    done
  fi
fi

if [ -n "$myf" ]; then
  echo "== Restaurando MySQL en un contenedor temporal sin red"
  mc="restauracion-my-$$"; clave="$(openssl rand -hex 16)"
  docker run -d --name "$mc" --network none -e MYSQL_ROOT_PASSWORD="$clave" mysql:8.4 >/dev/null; contenedores+=("$mc")
  listo=""; for i in $(seq 1 90); do docker exec -e MYSQL_PWD="$clave" "$mc" mysqladmin ping -h 127.0.0.1 -uroot --silent >/dev/null 2>&1 && { listo=1; break; }; sleep 2; done
  [ -n "$listo" ] || falla "el MySQL temporal no arranco"
  if [ -n "$listo" ]; then
    # se omiten las bases del sistema (mysql, sys...): traerian los usuarios y claves originales
    gunzip -c "$myf" | awk '/^-- Current Database: `/ { skip = ($0 ~ /`(mysql|sys|performance_schema|information_schema)`/) } !skip' \
      | docker exec -i -e MYSQL_PWD="$clave" "$mc" mysql -uroot >/dev/null 2>"$TMP/my.err" || true
    malos="$(grep -E 'ERROR' "$TMP/my.err" || true)"
    if [ -n "$malos" ]; then falla "MySQL: errores al restaurar ($(echo "$malos" | wc -l)); el primero: $(echo "$malos" | head -1 | cut -c1-150)"; else ok "MySQL: restauracion sin errores"; fi
    docker exec -e MYSQL_PWD="$clave" "$mc" mysql -uroot -N -e "select table_schema, count(*) from information_schema.tables where table_schema not in ('mysql','sys','performance_schema','information_schema') group by 1 order by 1" 2>/dev/null \
      | awk '{printf "   %-22s %6s tablas\n", $1, $2} END{if (NR==0) print "   (sin bases de usuario en MySQL)"}'
  fi
fi

echo
if [ "$fallos" -eq 0 ]; then resultado="OK"; else resultado="REVISAR ($fallos problema(s))"; fi
echo "RESULTADO: $resultado"
echo "Para anotar en SEGURIDAD-ISO27001.md (control 8.13): $(date '+%F %H:%M') - restauracion de $( [ -n "$pgf" ] && basename "$pgf" || echo '-' ) desde $origen: $resultado"
[ "$fallos" -eq 0 ]
