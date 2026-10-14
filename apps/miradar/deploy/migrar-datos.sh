#!/usr/bin/env bash
# Copia la base de MiRadar desde Aiven (u otro PostgreSQL) a la PostgreSQL de este servidor y comprueba
# tabla por tabla que quedo igual. Del origen SOLO LEE: no modifica ni borra nada.
#   sudo bash /data/apps/miradar/migrar-datos.sh
# Antes: crear la base (new-project-db.sh postgres miradar) y correr preparar.sh. NO levantar la API todavia.
# Guarda el volcado en /data/backups/miradar (se conserva: es la copia de seguridad de lo que habia en Aiven).
# Para pruebas se pueden fijar: ORIGEN_URI, DESTINO_URI, RED_DOCKER, CARPETA_RESPALDOS.
set -euo pipefail

ENVFILE=/opt/sulotec/miradar.env
RED_DOCKER="${RED_DOCKER:-sulotec_data}"
CARPETA="${CARPETA_RESPALDOS:-/data/backups/miradar}"
STAMP="$(date +%Y%m%d-%H%M)"
ARCHIVO="miradar-origen-$STAMP.dump"

[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }
[[ "$CARPETA" == /* ]] && mkdir -p "$CARPETA"

# Lee un secreto mostrando un * por cada caracter: asi se ve que el pegado funciono sin mostrar el valor. Resultado en $V.
leer_secreto() {
  local c; V=""
  printf '%s' "$1"
  while IFS= read -rsn1 c; do
    if [ -z "$c" ] || [ "$c" = $'\r' ]; then break; fi
    if [ "$c" = $'\177' ] || [ "$c" = $'\b' ]; then
      if [ -n "$V" ]; then V="${V%?}"; printf '\b \b'; fi
    else
      V+="$c"; printf '*'
    fi
  done
  echo
}

# --- Direcciones de origen y destino (nunca se muestran en pantalla)
if [ -z "${DESTINO_URI:-}" ]; then
  [ -r "$ENVFILE" ] || { echo "Falta $ENVFILE: primero corre preparar.sh" >&2; exit 1; }
  DESTINO_URI="$(grep -E '^DATABASE_URL=' "$ENVFILE" | head -1 | cut -d= -f2-)"
fi
if [ -z "${ORIGEN_URI:-}" ]; then
  echo "Pega la 'Service URI' de Aiven (postgres://...?sslmode=require). No se muestra al escribir."
  leer_secreto "ORIGEN: "; ORIGEN_URI="$V"
fi
ORIGEN_URI="${ORIGEN_URI//[[:space:]]/}"; ORIGEN_URI="${ORIGEN_URI//$'\e'\[200~/}"; ORIGEN_URI="${ORIGEN_URI//$'\e'\[201~/}"
[[ "$ORIGEN_URI" =~ ^postgres(ql)?:// ]]  || { echo "El origen debe empezar con postgres:// o postgresql:// (recibi ${#ORIGEN_URI} caracteres)." >&2; exit 1; }
echo "   origen: $(printf '%s' "$ORIGEN_URI" | sed -E 's#(://[^:/@]+:)[^@]*@#***@#')"
[[ "$DESTINO_URI" =~ ^postgres(ql)?:// ]] || { echo "El destino no es una direccion PostgreSQL valida" >&2; exit 1; }

# psql/pg_dump/pg_restore corren en contenedores: $1 = version del cliente, resto = comando. Las URI viajan por entorno.
cliente() { local v="$1"; shift; docker run --rm --network "$RED_DOCKER" -e ORIGEN="$ORIGEN_URI" -e DESTINO="$DESTINO_URI" -v "$CARPETA:/backup" "postgres:$v" "$@"; }
sql_origen()  { cliente "$VCLI" sh -c 'psql "$ORIGEN" -X -At -v ON_ERROR_STOP=1 -c "$0"' "$1"; }
sql_destino() { cliente "$VDEST" sh -c 'psql "$DESTINO" -X -At -v ON_ERROR_STOP=1 -c "$0"' "$1"; }

echo "== 1. Versiones"
VCLI=16; VDEST=16   # para la primera consulta basta cualquier cliente: psql se conecta a servidores mas nuevos
num_origen="$(sql_origen 'show server_version_num')"  || { echo "No pude conectar con el ORIGEN (¿Aiven permite la IP de este servidor?)." >&2; exit 1; }
mayor_origen=$(( num_origen / 10000 ))
VCLI="$mayor_origen"; [ "$VCLI" -ge 14 ] || VCLI=14
VDEST=16
num_destino="$(sql_destino 'show server_version_num')" || { echo "No pude conectar con el DESTINO." >&2; exit 1; }
mayor_destino=$(( num_destino / 10000 )); VDEST="$mayor_destino"
echo "   origen: PostgreSQL $mayor_origen   destino: PostgreSQL $mayor_destino"
if [ "$mayor_origen" -gt "$mayor_destino" ] && [ -z "${FORZAR:-}" ]; then
  echo "El origen es MAS NUEVO que el destino: un volcado de PostgreSQL $mayor_origen puede no restaurarse en $mayor_destino." >&2
  echo "Hay que subir la version del servidor o usar un PostgreSQL propio para MiRadar. (FORZAR=1 para intentarlo igual.)" >&2
  exit 1
fi

echo "== 2. El destino debe estar vacio"
tablas_destino="$(sql_destino "select count(*) from information_schema.tables where table_schema='public'")"
if [ "$tablas_destino" != "0" ]; then
  if [ "${BORRAR_DESTINO:-}" != "si" ]; then
    echo "La base de destino ya tiene $tablas_destino tablas (¿se levanto la API antes?)." >&2
    echo "Si quieres reemplazar su contenido por el del origen: BORRAR_DESTINO=si sudo -E bash $0" >&2
    exit 1
  fi
  echo "   BORRAR_DESTINO=si: se vacia el esquema public del destino"
  sql_destino 'drop schema public cascade; create schema public;' >/dev/null
fi

echo "== 3. Conteo de filas en el origen"
tablas="$(sql_origen "select tablename from pg_tables where schemaname='public' order by 1")"
[ -n "$tablas" ] || { echo "El origen no tiene tablas en el esquema public." >&2; exit 1; }
declare -A filas_origen
for t in $tablas; do filas_origen[$t]="$(sql_origen "select count(*) from public.\"$t\"")"; done
echo "   $(echo "$tablas" | wc -l) tablas"

echo "== 4. Volcado del origen -> $CARPETA/$ARCHIVO"
cliente "$VCLI" sh -c "pg_dump \"\$ORIGEN\" --format=custom --no-owner --no-acl --schema=public -f /backup/$ARCHIVO"
echo "   tamano: $(du -h "$CARPETA/$ARCHIVO" 2>/dev/null | cut -f1 || echo ok)"

echo "== 5. Restaurando en el destino"
# El volcado trae "CREATE SCHEMA public", que el destino ya tiene: se restaura con una lista que omite solo esa linea.
cliente "$VDEST" sh -c "pg_restore -l /backup/$ARCHIVO | grep -v ' SCHEMA - public ' > /tmp/lista.txt; pg_restore --no-owner --no-acl --exit-on-error -L /tmp/lista.txt -d \"\$DESTINO\" /backup/$ARCHIVO"

echo "== 6. Comparacion tabla por tabla"
mal=0
printf "   %-32s %12s %12s  %s\n" tabla origen destino resultado
for t in $tablas; do
  d="$(sql_destino "select count(*) from public.\"$t\"" 2>/dev/null || echo FALTA)"
  if [ "$d" = "${filas_origen[$t]}" ]; then r="OK"; else r="DIFERENTE"; mal=1; fi
  printf "   %-32s %12s %12s  %s\n" "$t" "${filas_origen[$t]}" "$d" "$r"
done

if [ "$mal" -ne 0 ]; then
  echo; echo "HAY DIFERENCIAS: no apagues Aiven. Revisa arriba. El volcado queda en $CARPETA/$ARCHIVO." >&2
  exit 1
fi
echo
echo "TODO IGUAL: $(echo "$tablas" | wc -l) tablas, mismas filas en origen y destino."
echo "Copia del origen guardada en $CARPETA/$ARCHIVO (no la borres hasta cerrar Aiven)."
echo "Siguiente: sudo bash /data/apps/miradar/desplegar.sh"
