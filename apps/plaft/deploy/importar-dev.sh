#!/usr/bin/env bash
# Trae a ESTE servidor la base de desarrollo completa que estaba en Aiven (el respaldo que hizo respaldar-mysql-externo.sh)
# y la compara, tabla por tabla, con la base de produccion de PLAFT. NO toca la base de produccion: la copia queda en una base
# aparte dentro de la MySQL de la VM (se llama aiven_<nombre original>; entra en el respaldo nocturno) y el script muestra
# cuantas filas tiene cada tabla alli y en 'plaft'.
#   sudo bash /data/apps/plaft/importar-dev.sh [archivo.sql.gz]       (sin argumento usa el respaldo mas reciente)
# Si la copia ya existe no la pisa; para reemplazarla (solo las bases aiven_*):  BORRAR_DESTINO=si sudo -E bash /data/apps/plaft/importar-dev.sh
# Variables solo para pruebas: CARPETA, SULOTEC_DIR, BASE_PROD, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

CARPETA="${CARPETA:-/data/backups/externos}"
SULOTEC="${SULOTEC_DIR:-/opt/sulotec}"
PROD="${BASE_PROD:-plaft}"
PREFIJO="aiven_"

archivo="${1:-}"
if [ -z "$archivo" ]; then
  archivo="$(ls -1t "$CARPETA"/mysql-externo-*.sql.gz 2>/dev/null | head -1 || true)"
  [ -n "$archivo" ] || { echo "No encontre respaldos en $CARPETA (mysql-externo-*.sql.gz). Primero: sudo /opt/sulotec/scripts/respaldar-mysql-externo.sh" >&2; exit 1; }
fi
[ -f "$archivo" ] || { echo "No existe $archivo" >&2; exit 1; }
gzip -t "$archivo" || { echo "$archivo esta danado (gzip -t fallo)." >&2; exit 1; }
echo "== Respaldo: $archivo ($(du -h "$archivo" | cut -f1))"

cd "$SULOTEC"
set -a; . ./.env; set +a
sqlr() { docker compose exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot -N "$@"; }

# Bases que trae el respaldo (la linea CREATE DATABASE de cada una; el nombre va entre comillas invertidas)
bases="$(gunzip -c "$archivo" | awk -F'`' '/^CREATE DATABASE/ {print $2}')"
[ -n "$bases" ] || { echo "El respaldo no trae bases (no vi lineas CREATE DATABASE)." >&2; exit 1; }
echo "   bases dentro del respaldo: $(echo $bases)"
existentes="$(sqlr -e 'show databases')"
for b in $bases; do
  if echo "$existentes" | grep -x "$PREFIJO$b" >/dev/null; then
    if [ "${BORRAR_DESTINO:-}" = "si" ]; then
      echo "   BORRAR_DESTINO=si: se reemplaza $PREFIJO$b (solo esa copia; produccion no se toca)"
      sqlr -e "drop database $PREFIJO$b"
    else
      echo "   $PREFIJO$b ya existe: no se pisa (para reemplazarla: BORRAR_DESTINO=si sudo -E bash $0)"
      YA_ESTABA=1
    fi
  fi
done

if [ -z "${YA_ESTABA:-}" ]; then
  echo "== Restaurando la copia (cada base queda como $PREFIJO<nombre>)"
  # a cada CREATE DATABASE y USE se le antepone el prefijo, para que nada choque con las bases de las aplicaciones
  gunzip -c "$archivo" | awk '/^CREATE DATABASE/ {sub(/`/, "`aiven_")} /^USE `/ {sub(/`/, "`aiven_")} {print}' \
    | docker compose exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot \
    || { echo "FALLO al restaurar. Las bases ${PREFIJO}* pueden haber quedado a medias: se pueden borrar y repetir con BORRAR_DESTINO=si." >&2; exit 1; }
fi

echo "== Filas por tabla: copia de desarrollo contra produccion ($PROD)"
prod_tablas="$(sqlr -e "select table_name from information_schema.tables where table_schema='$PROD' and table_type='BASE TABLE'")"
total_dev=0
for b in $bases; do
  copia="$PREFIJO$b"
  tablas="$(sqlr -e "select table_name from information_schema.tables where table_schema='$copia' and table_type='BASE TABLE' order by 1")"
  [ -n "$tablas" ] || { echo "   $copia: sin tablas"; continue; }
  consulta=""
  for t in $tablas; do
    if echo "$prod_tablas" | grep -x "$t" >/dev/null; then en_prod="(select count(*) from $PROD.$t)"; else en_prod="NULL"; fi
    parte="select '$t', (select count(*) from $copia.$t), $en_prod"
    if [ -z "$consulta" ]; then consulta="$parte"; else consulta="$consulta union all $parte"; fi
  done
  echo "   base $copia"
  printf '   %-34s %10s %12s\n' "tabla" "desarrollo" "produccion"
  sqlr -e "$consulta" | awk -F'\t' '{printf "   %-34s %10s %12s\n", $1, $2, ($3 == "NULL" ? "(no existe)" : $3)}'
done
echo
echo "LISTO: la base de desarrollo completa esta en este servidor (bases ${PREFIJO}*, dentro de la MySQL de la VM; el respaldo nocturno ya la incluye)."
echo "La base de produccion ($PROD) no se toco. Con esta tabla se decide que pasa a produccion."
