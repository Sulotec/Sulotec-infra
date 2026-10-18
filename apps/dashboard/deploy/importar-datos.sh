#!/usr/bin/env bash
# Carga en la base de Dashboard Empresarial (PostgreSQL de la VM) los datos exportados de SQL Server con
# herramientas/exportar-sqlserver.ps1. Crea las tablas si faltan y carga TODO en una sola transaccion: si algo falla, no queda nada a medias.
#   sudo bash /data/apps/dashboard/importar-datos.sh              toma el .sql MAS NUEVO de sulotec-backups, carpeta externos/dashboard/
#   ARCHIVO=/ruta/datos.sql sudo -E bash /data/apps/dashboard/importar-datos.sh     usa un archivo del servidor
#   SHA256=<huella> sudo -E bash ...                              ademas exige que el archivo tenga esa huella (la que mostro el exportador)
#   REEMPLAZAR=1 sudo -E bash ...                                 si la base YA tiene datos: guarda un respaldo, la vacia y carga de nuevo
#   SOLO_ESQUEMA=1 sudo -E bash ...                               solo crea las tablas vacias (no necesita el archivo de datos)
# Antes: preparar.sh y desplegar.sh (este script saca el esquema de la imagen dashboard-api ya construida).
set -euo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ENVFILE="${ENVFILE:-/opt/sulotec/dashboard.env}"      # ENVFILE, RESPALDOS y PRUEBA solo se usan para probar el script fuera del servidor
BUCKET="${BACKUP_BUCKET:-sulotec-backups}"
PREFIJO="${PREFIJO:-externos/dashboard/}"
RED=sulotec_data
RESPALDOS="${RESPALDOS:-/data/backups/dashboard}"
TABLAS=('comercial."Empresas"' 'seguridad."Usuarios"' 'reportes."Dashboards"' 'reportes."DashboardPeriodos"' 'comercial."EmpresaDashboards"')

[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }
[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE: primero corre preparar.sh" >&2; exit 1; }
docker image inspect dashboard-api:latest >/dev/null 2>&1 || { echo "Falta la imagen dashboard-api: primero corre desplegar.sh" >&2; exit 1; }

leer() { grep -E "^$1=" "$ENVFILE" | head -1 | cut -d= -f2- || true; }
DB_HOST="$(leer DB_HOST)"; DB_PORT="$(leer DB_PORT)"; DB_NAME="$(leer DB_NAME)"; DB_USER="$(leer DB_USER)"; PGPASSWORD="$(leer DB_PASSWORD)"; export PGPASSWORD
{ [ -n "$DB_HOST" ] && [ -n "$DB_NAME" ] && [ -n "$DB_USER" ] && [ -n "$PGPASSWORD" ]; } || { echo "$ENVFILE no tiene los datos de la base." >&2; exit 1; }

# psql / pg_dump contra la base, con la identidad del propio proyecto (la clave viaja por variable de entorno, no por argumento)
psqlx()  { docker run --rm -i --network "$RED" -e PGPASSWORD postgres:16 psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -X -v ON_ERROR_STOP=1 "$@"; }
pgdump() { docker run --rm --network "$RED" -e PGPASSWORD postgres:16 pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" "$@"; }

TMP="$(mktemp -d)"; chmod 700 "$TMP"
trap '[ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"' EXIT
DATOS="$TMP/datos.sql"

# ---- 0. Solo el esquema
if [ "${SOLO_ESQUEMA:-}" = 1 ]; then
  docker run --rm --entrypoint cat dashboard-api:latest /app/db/schema.sql | psqlx -q >/dev/null
  echo "Tablas creadas (vacias). Los datos se cargan despues con importar-datos.sh."
  exit 0
fi

# ---- 1. El archivo
echo "== Archivo de datos"
if [ -n "${ARCHIVO:-}" ]; then
  [ -r "$ARCHIVO" ] || { echo "No puedo leer $ARCHIVO" >&2; exit 1; }
  cp "$ARCHIVO" "$DATOS"; echo "   $ARCHIVO"
else
  command -v oci >/dev/null || { echo "Falta el comando oci en el servidor." >&2; exit 1; }
  nombre="$(oci os object list --auth instance_principal --bucket-name "$BUCKET" --prefix "$PREFIJO" --all 2>/dev/null \
    | python3 -c 'import json, sys; [print(o["name"]) for o in json.load(sys.stdin).get("data", [])]' | grep -E '\.sql$' | sort | tail -1 || true)"
  [ -n "$nombre" ] || { echo "No encontre ningun .sql en $BUCKET/$PREFIJO. Sube el archivo que genero exportar-sqlserver.ps1 (ver el README)." >&2; exit 1; }
  oci os object get --auth instance_principal --bucket-name "$BUCKET" --name "$nombre" --file "$DATOS" >/dev/null
  echo "   $BUCKET/$nombre"
fi
head -c 200000 "$DATOS" | grep -q '^-- Dashboard Empresarial: datos exportados' || { echo "Ese archivo no parece un export de Dashboard Empresarial." >&2; exit 1; }
huella="$(sha256sum "$DATOS" | cut -d' ' -f1)"
echo "   SHA256: $huella   ($(du -k "$DATOS" | cut -f1) KB)"
echo "   $(sed -n '2p' "$DATOS")"
if [ -n "${SHA256:-}" ] && [ "${SHA256,,}" != "$huella" ]; then echo "La huella NO coincide con la esperada ($SHA256): el archivo cambio en el camino." >&2; exit 1; fi
[ -n "${SHA256:-}" ] || echo "   (compara esa huella con la que mostro el exportador en la PC; con SHA256=... el script lo exige)"

# ---- 2. Tablas
echo "== Esquema"
docker run --rm --entrypoint cat dashboard-api:latest /app/db/schema.sql | psqlx -q >/dev/null
echo "   tablas listas"

# ---- 3. La base debe estar vacia (o REEMPLAZAR=1)
hay=0
for t in "${TABLAS[@]}"; do n="$(psqlx -Atc "select count(*) from $t")"; [ "$n" = 0 ] || hay=1; done
if [ "$hay" = 1 ]; then
  if [ "${REEMPLAZAR:-}" != 1 ]; then
    echo "La base YA tiene datos. No se toca nada. Si de verdad quieres cargar de nuevo (reemplaza todo, tambien las cuentas creadas aqui):" >&2
    echo "   REEMPLAZAR=1 sudo -E bash $0" >&2
    exit 1
  fi
  mkdir -p "$RESPALDOS"; chmod 700 "$RESPALDOS"
  copia="$RESPALDOS/antes-de-reemplazar-$(date +%Y%m%d-%H%M).sql"
  pgdump --no-owner > "$copia"; chmod 600 "$copia"
  [ -s "$copia" ] || { echo "El respaldo previo quedo vacio; no sigo." >&2; exit 1; }
  echo "== Respaldo previo guardado: $copia"
  psqlx -q -c "TRUNCATE $(IFS=,; echo "${TABLAS[*]}") RESTART IDENTITY" >/dev/null
  echo "   base vaciada"
fi

# ---- 4. Carga (todo o nada)
echo "== Cargando"
psqlx -q --single-transaction -f - < "$DATOS" >/dev/null
echo "   carga completa (el propio archivo comprobo fila por fila los totales)"

echo "== Filas en PostgreSQL"
for t in "${TABLAS[@]}"; do printf '   %-36s %s\n' "$t" "$(psqlx -Atc "select count(*) from $t")"; done
echo
echo "Listo. Siguiente: sudo bash /data/apps/dashboard/crear-admin.sh   y luego   sudo bash /data/apps/dashboard/probar.sh"
echo "Recuerda: el archivo .sql tiene datos personales. Cuando todo funcione, borralo del bucket ($BUCKET/$PREFIJO) y de la PC."
