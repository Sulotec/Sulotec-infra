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
[[ "$CARPETA" == /* ]] && { mkdir -p "$CARPETA"; chmod 700 "$CARPETA"; }

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
  echo "Pega la direccion EXTERNA de la base de origen (Render: 'External Database URL'; Aiven: 'Service URI'). Saldran asteriscos."
  leer_secreto "ORIGEN: "; ORIGEN_URI="$V"
fi
ORIGEN_URI="${ORIGEN_URI//[[:space:]]/}"; ORIGEN_URI="${ORIGEN_URI//$'\e'\[200~/}"; ORIGEN_URI="${ORIGEN_URI//$'\e'\[201~/}"
# Prisma y otros agregan parametros (schema, connection_limit...) que psql y pg_dump no entienden: se quitan
ORIGEN_URI="$(printf '%s' "$ORIGEN_URI" | sed -E 's/[?&](schema|connection_limit|pool_timeout|pgbouncer|socket_timeout|statement_cache_size)=[^&]*//g')"
case "$ORIGEN_URI" in *'?'*) ;; *'&'*) ORIGEN_URI="${ORIGEN_URI/&/?}" ;; esac
[[ "$ORIGEN_URI" =~ ^postgres(ql)?:// ]]  || { echo "El origen debe empezar con postgres:// o postgresql:// (recibi ${#ORIGEN_URI} caracteres)." >&2; exit 1; }
# La direccion INTERNA de Render (dpg-xxxx-a, sin dominio) solo funciona dentro de Render: se busca la region mas abajo
resto_origen="${ORIGEN_URI#*://}"; resto_origen="${resto_origen#*@}"; host_origen="${resto_origen%%[:/?]*}"
BUSCAR_REGION=""
if [[ "$host_origen" != *.* ]]; then
  if [[ "$host_origen" == dpg-* ]]; then
    BUSCAR_REGION=1
  else
    echo "La direccion de origen no tiene dominio ($host_origen): hace falta la direccion EXTERNA de la base." >&2
    echo "En Render: la base de datos (PostgreSQL) -> Connections -> 'External Database URL'." >&2
    exit 1
  fi
fi
# La copia viaja por internet: siempre cifrada
case "$ORIGEN_URI" in *sslmode=*) ;; *'?'*) ORIGEN_URI="$ORIGEN_URI&sslmode=${SSLMODE_ORIGEN:-require}" ;; *) ORIGEN_URI="$ORIGEN_URI?sslmode=${SSLMODE_ORIGEN:-require}" ;; esac
echo "   origen: $(printf '%s' "$ORIGEN_URI" | sed -E 's#(://[^:/@]+:)[^@]*@#\1***@#')"
[[ "$DESTINO_URI" =~ ^postgres(ql)?:// ]] || { echo "El destino no es una direccion PostgreSQL valida" >&2; exit 1; }

# psql/pg_dump/pg_restore corren en contenedores: $1 = version del cliente, resto = comando. Las URI viajan por entorno.
cliente() { local v="$1"; shift; docker run --rm --network "$RED_DOCKER" -e ORIGEN="$ORIGEN_URI" -e DESTINO="$DESTINO_URI" -v "$CARPETA:/backup" "postgres:$v" "$@"; }
sql_origen()  { cliente "$VCLI" sh -c 'psql "$ORIGEN" -X -At -v ON_ERROR_STOP=1 -c "$0"' "$1"; }
sql_destino() { cliente "$VDEST" sh -c 'psql "$DESTINO" -X -At -v ON_ERROR_STOP=1 -c "$0"' "$1"; }

# Si pegaron la direccion interna de Render (dpg-xxxx-a), se prueba con las cinco regiones de Render hasta que una conecte
if [ -n "$BUSCAR_REGION" ]; then
  echo "== 0. La direccion es la interna de Render: busco la region de la base (puede tardar hasta un minuto)"
  VCLI=16; encontrada=""; sin_region="$ORIGEN_URI"
  for region in oregon ohio virginia frankfurt singapore; do
    ORIGEN_URI="${sin_region/@$host_origen/@$host_origen.$region-postgres.render.com}"
    case "$ORIGEN_URI" in *'?'*) ORIGEN_URI="$ORIGEN_URI&connect_timeout=10" ;; *) ORIGEN_URI="$ORIGEN_URI?connect_timeout=10" ;; esac
    printf '   %s: ' "$region"
    if sql_origen 'select 1' >/dev/null 2>&1; then echo "conecta"; encontrada="$region"; break; else echo "no"; fi
  done
  if [ -z "$encontrada" ]; then
    echo "No pude conectar desde fuera de Render en ninguna region. En Render abre la base (afacop-postgres) y revisa:" >&2
    echo "  - Connections -> 'External Database URL': pega esa en vez de la interna." >&2
    echo "  - Access Control: debe permitir la IP publica de este servidor." >&2
    exit 1
  fi
  echo "   region de la base: $encontrada"
fi

echo "== 1. Versiones"
VCLI=16; VDEST=16   # para la primera consulta basta cualquier cliente: psql se conecta a servidores mas nuevos
num_origen="$(sql_origen 'show server_version_num')"  || { echo "No pude conectar con el ORIGEN: revisa que sea la direccion EXTERNA y que el origen permita la IP publica de este servidor (en Render: la base -> Access Control)." >&2; exit 1; }
mayor_origen=$(( num_origen / 10000 ))
VCLI="$mayor_origen"; [ "$VCLI" -ge 14 ] || VCLI=14
VDEST=16
num_destino="$(sql_destino 'show server_version_num')" || { echo "No pude conectar con el DESTINO." >&2; exit 1; }
mayor_destino=$(( num_destino / 10000 )); VDEST="$mayor_destino"
echo "   origen: PostgreSQL $mayor_origen   destino: PostgreSQL $mayor_destino"
VREST="$VDEST"
if [ "$mayor_origen" -gt "$mayor_destino" ]; then
  VREST="$VCLI"   # un volcado de una version mas nueva solo lo lee bien el pg_restore de esa misma version
  echo "   AVISO: el origen (PostgreSQL $mayor_origen) es mas nuevo que el destino ($mayor_destino): se restaura con las herramientas de la $VREST."
  echo "          Si algo del esquema no existe en la $mayor_destino, la restauracion se cancela entera y el destino queda vacio (el origen no se toca)."
fi

# SOLO_COMPARAR=1: no copia nada; solo compara las filas de cada tabla entre el origen y el destino (para decidir si se puede cerrar el origen)
if [ -n "${SOLO_COMPARAR:-}" ]; then
  echo "== Comparacion de filas, origen contra destino (no se copia ni se cambia nada)"
  tablas="$(sql_origen "select tablename from pg_tables where schemaname='public' order by 1")"
  mal=0
  printf "   %-32s %12s %12s  %s\n" tabla origen destino resultado
  for t in $tablas; do
    o="$(sql_origen "select count(*) from public.\"$t\"")"
    d="$(sql_destino "select count(*) from public.\"$t\"" 2>/dev/null || echo FALTA)"
    if [ "$o" = "$d" ]; then r="OK"; else r="DIFERENTE"; mal=1; fi
    printf "   %-32s %12s %12s  %s\n" "$t" "$o" "$d" "$r"
  done
  echo
  if [ "$mal" -eq 0 ]; then echo "IGUALES: el origen y el destino tienen las mismas filas."; else echo "HAY DIFERENCIAS: lo que tenga mas filas el origen no esta en el destino (auditoria_seguridad siempre difiere: cada inicio de sesion la aumenta)."; fi
  exit 0
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
extensiones="$(sql_origen "select extname from pg_extension where extname <> 'plpgsql' order by 1")"
if [ -n "$extensiones" ]; then
  echo "   extensiones: $(echo $extensiones)"
  for e in $extensiones; do
    sql_destino 'create extension if not exists "'"$e"'"' >/dev/null 2>&1 || { echo "No pude crear la extension '$e' en el destino: hay que instalarla con un usuario administrador." >&2; exit 1; }
  done
fi

echo "== 4. Volcado del origen -> $CARPETA/$ARCHIVO"
cliente "$VCLI" sh -c "pg_dump \"\$ORIGEN\" --format=custom --no-owner --no-acl --schema=public -f /backup/$ARCHIVO"
chmod 600 "$CARPETA/$ARCHIVO" 2>/dev/null || true
echo "   tamano: $(du -h "$CARPETA/$ARCHIVO" 2>/dev/null | cut -f1 || echo ok)"

echo "== 5. Restaurando en el destino"
# La restauracion es todo o nada: pg_restore genera el SQL (sin el esquema public, las extensiones ni las estadisticas de PG18, que el destino
# ya tiene o no entiende; ademas se quita "SET transaction_timeout", que no existe antes de PostgreSQL 17) y psql lo carga en UNA transaccion.
RESTAURAR='set -e
pg_restore -l "/backup/$1" | grep -v -e " SCHEMA - public " -e " EXTENSION " -e " STATISTICS DATA " > /tmp/lista.txt
pg_restore --no-owner --no-acl -L /tmp/lista.txt -f /tmp/restore.sql "/backup/$1"
sed -i "/^SET transaction_timeout/d" /tmp/restore.sql
psql "$DESTINO" -X -q -1 -v ON_ERROR_STOP=1 -f /tmp/restore.sql -o /dev/null'
if ! cliente "$VREST" sh -c "$RESTAURAR" restaurar "$ARCHIVO"; then
  echo "La restauracion se cancelo y el destino quedo vacio (el origen no se toca). El volcado esta en $CARPETA/$ARCHIVO." >&2
  echo "Copia las lineas de error de arriba y mandalas para ajustar." >&2
  exit 1
fi
echo "   actualizando estadisticas (ANALYZE)"
sql_destino 'analyze' >/dev/null 2>&1 || true

echo "== 6. Comparacion tabla por tabla"
mal=0
printf "   %-32s %12s %12s  %s\n" tabla origen destino resultado
for t in $tablas; do
  d="$(sql_destino "select count(*) from public.\"$t\"" 2>/dev/null || echo FALTA)"
  if [ "$d" = "${filas_origen[$t]}" ]; then r="OK"; else r="DIFERENTE"; mal=1; fi
  printf "   %-32s %12s %12s  %s\n" "$t" "${filas_origen[$t]}" "$d" "$r"
done

if [ "$mal" -ne 0 ]; then
  echo; echo "HAY DIFERENCIAS: no cierres el origen. Revisa arriba. El volcado queda en $CARPETA/$ARCHIVO." >&2
  exit 1
fi
echo
echo "TODO IGUAL: $(echo "$tablas" | wc -l) tablas, mismas filas en origen y destino."
echo "Copia del origen guardada en $CARPETA/$ARCHIVO (no la borres hasta cerrar el origen)."
echo "Siguiente: sudo bash /data/apps/miradar/desplegar.sh"
