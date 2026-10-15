#!/usr/bin/env bash
# Carga en la base de PLAFT los datos ficticios del modulo Operaciones (el script de demostracion que trae el propio backend:
# docs/operaciones-demo.sql) para poder probar ese modulo. Agrega 10 registros con sus personas, operaciones y beneficiarios,
# todos marcados DEMO. No se repite si ya hay datos de demostracion (FORZAR=si para agregar otros 10).
#   sudo bash /data/apps/plaft/cargar-operaciones-demo.sh
# Hace falta que exista al menos un usuario (los registros quedan a nombre del primero). Variables solo para pruebas: APP, ENVFILE, RED_DOCKER, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

APP="${APP:-/data/apps/plaft}"
ENVFILE="${ENVFILE:-/opt/sulotec/plaft.env}"
RED="${RED_DOCKER:-sulotec_data}"
SQL="$APP/backend/docs/operaciones-demo.sql"

[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE" >&2; exit 1; }
[ -f "$SQL" ] || { echo "Falta $SQL: corre primero desplegar.sh (baja el codigo del backend)." >&2; exit 1; }
leer() { grep -E "^$1=" "$ENVFILE" | head -1 | cut -d= -f2- || true; }
DB_URL="$(leer DB_URL)"; DB_USER="$(leer DB_USER)"; DB_PASSWORD="$(leer DB_PASSWORD)"
{ [ -n "$DB_URL" ] && [ -n "$DB_USER" ] && [ -n "$DB_PASSWORD" ]; } || { echo "$ENVFILE no tiene DB_URL, DB_USER y DB_PASSWORD." >&2; exit 1; }
BASE="${DB_URL#*://}"; BASE="${BASE#*/}"; BASE="${BASE%%[?]*}"
[ -n "$BASE" ] || { echo "No pude sacar el nombre de la base de DB_URL." >&2; exit 1; }

# La clave viaja por entorno (no por la linea de comandos). Todo el script va en UNA sola conexion (usa variables de sesion).
cliente() { MYSQL_PWD="$DB_PASSWORD" docker run --rm -i --network "$RED" -e MYSQL_PWD mysql:8.4 mysql -h mysql -u"$DB_USER" "$@" "$BASE"; }

usuarios="$(cliente -N -e 'select count(*) from usuarios')" || { echo "No pude conectar con la base $BASE." >&2; exit 1; }
[ "${usuarios:-0}" -ge 1 ] 2>/dev/null || { echo "No hay usuarios en la base: el script de demostracion necesita al menos uno." >&2; exit 1; }
antes="$(cliente -N -e "select count(*) from registro_operaciones_v2 where numero_registro like 'DEMO-%'")" \
  || { echo "No encuentro la tabla registro_operaciones_v2: ¿arranco el backend al menos una vez?" >&2; exit 1; }
if [ "${antes:-0}" -gt 0 ] && [ -z "${FORZAR:-}" ]; then
  echo "Ya hay $antes registros de demostracion en Operaciones: no agrego mas. (Para agregar otros 10:  sudo env FORZAR=si bash $0)"
  exit 0
fi

echo "== Cargando 10 registros de demostracion en Operaciones (base '$BASE')"
# el script trae "USE security_db;": se cambia por la base de produccion
sed "s/^USE security_db;/USE $BASE;/" "$SQL" | cliente >/dev/null \
  || { echo "El script de demostracion fallo; no quedo nada a medias (corre en una transaccion)." >&2; exit 1; }
despues="$(cliente -N -e "select count(*) from registro_operaciones_v2 where numero_registro like 'DEMO-%'")"
echo "OK: ahora hay $despues registros de demostracion (antes ${antes:-0}). Ya puedes probar el modulo Operaciones."
