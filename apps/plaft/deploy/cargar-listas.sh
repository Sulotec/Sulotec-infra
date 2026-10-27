#!/usr/bin/env bash
# Carga masiva de listas en la base de PLAFT: «Base total.xlsx» (ASBANC), «base antigua pep.xlsx» (hoja RISK) o la PLANTILLA oficial
# (apps/plaft/plantillas/PLANTILLA-Carga-Listas-PLAFT.xlsx). Convierte cada formato a la plantilla, revisa, y carga con la herramienta
# apps/plaft/herramientas/cargar_listas_masivas.py. Se puede repetir sin duplicar y nunca borra nada.
#   cd /tmp && sudo rm -rf si && git clone -q --depth 1 https://github.com/Sulotec/Sulotec-infra.git si
#   sudo bash si/apps/plaft/deploy/cargar-listas.sh              SIMULA: muestra el informe y no escribe nada
#   sudo bash si/apps/plaft/deploy/cargar-listas.sh --aplicar    escribe de verdad (antes guarda un respaldo de la base y lo comprueba)
# Los archivos se toman del bucket sulotec-backups, prefijo externos/plaft/ (con la identidad de la VM), o de una carpeta:
#   CARPETA=/ruta sudo -E bash si/apps/plaft/deploy/cargar-listas.sh
# Se reconocen por el nombre: «Base total», «base antigua pep» y los que digan «plantilla». Las filas con error no se cargan: quedan en un CSV
# de rechazadas (tiene datos personales) dentro de /var/backups/sulotec/.
# Variables solo para pruebas: ENVFILE, RED_DOCKER, RESPALDOS, TMP_BASE, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

ENVFILE="${ENVFILE:-/opt/sulotec/plaft.env}"
BUCKET="${BACKUP_BUCKET:-sulotec-backups}"
PREFIJO="${PREFIJO:-externos/plaft/}"
RED="${RED_DOCKER:-sulotec_data}"
RESPALDOS="${RESPALDOS:-/var/backups/sulotec}"
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERRAMIENTAS="${HERRAMIENTAS:-$AQUI/../herramientas}"

APLICAR=0
case "${1:-}" in
  "") ;;
  --aplicar) APLICAR=1 ;;
  *) echo "uso: sudo bash $0 [--aplicar]" >&2; exit 1 ;;
esac

[ -f "$HERRAMIENTAS/cargar_listas_masivas.py" ] || { echo "No encuentro la herramienta en $HERRAMIENTAS. Corre este script desde el clon del repositorio:  cd /tmp && sudo rm -rf si && git clone -q --depth 1 https://github.com/Sulotec/Sulotec-infra.git si && sudo bash si/apps/plaft/deploy/cargar-listas.sh" >&2; exit 1; }
[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE: primero corre preparar.sh" >&2; exit 1; }
leer() { grep -E "^$1=" "$ENVFILE" | head -1 | cut -d= -f2- || true; }
DB_URL="$(leer DB_URL)"; DB_USER="$(leer DB_USER)"; DB_PASSWORD="$(leer DB_PASSWORD)"
{ [ -n "$DB_URL" ] && [ -n "$DB_USER" ] && [ -n "$DB_PASSWORD" ]; } || { echo "$ENVFILE no tiene DB_URL, DB_USER y DB_PASSWORD." >&2; exit 1; }
export DB_URL DB_USER DB_PASSWORD
BASE="${DB_URL#*://}"; BASE="${BASE#*/}"; BASE="${BASE%%[?]*}"          # nombre de la base dentro de la URL jdbc
HOST="${DB_URL#*://}"; HOST="${HOST%%/*}"; HOST="${HOST%%:*}"            # servidor de la base
[ -n "$BASE" ] && [ -n "$HOST" ] || { echo "No pude sacar la base ni el servidor de DB_URL." >&2; exit 1; }
command -v python3 >/dev/null || { echo "Falta python3 en el servidor." >&2; exit 1; }

TMP="$(mktemp -d "${TMP_BASE:-/tmp}/cargar-listas.XXXXXX")"; chmod 700 "$TMP"
trap '[ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"' EXIT
mkdir "$TMP/datos" "$TMP/pkgs" "$TMP/salida"

# ---- 1. Los archivos
# Dice cuales sirven por su nombre (sin importar tildes, mayusculas ni un "(1)" al final). Lee nombres por la entrada estandar.
clasificar() {
  PYTHONIOENCODING=utf-8 python3 -c '
import sys, unicodedata
for linea in sys.stdin:
    nombre = linea.rstrip(chr(10))
    base = nombre.rsplit("/", 1)[-1]
    plano = unicodedata.normalize("NFD", base).encode("ascii", "ignore").decode().lower()
    if not (plano.endswith(".xlsx") or plano.endswith(".csv")):
        continue
    if "base total" in plano:
        print("total|" + nombre)
    elif "antigua" in plano:
        print("antigua|" + nombre)
    elif "plantilla" in plano:
        print("plantilla|" + nombre)
'
}
nombres_bucket() {
  local a=(--auth instance_principal --bucket-name "$BUCKET" --all)
  [ -z "${1:-}" ] || a+=(--prefix "$1")
  oci os object list "${a[@]}" 2>/dev/null | PYTHONIOENCODING=utf-8 python3 -c 'import json, sys; [print(o["name"]) for o in json.load(sys.stdin).get("data", [])]'
}
echo "== Archivos"
if [ -n "${CARPETA:-}" ]; then
  [ -d "$CARPETA" ] || { echo "No existe la carpeta $CARPETA" >&2; exit 1; }
  encontrados="$(ls -1 "$CARPETA" | clasificar || true)"
else
  encontrados="$(nombres_bucket "$PREFIJO" | clasificar || true)"
  [ -n "$encontrados" ] || encontrados="$(nombres_bucket "" | clasificar || true)"
fi
[ -n "$encontrados" ] || { echo "No encontre los archivos. Sube «Base total.xlsx» y «base antigua pep.xlsx» al bucket $BUCKET con el prefijo $PREFIJO (o usa CARPETA=/ruta)." >&2; exit 1; }
archivos=(); hay_total=0; hay_antigua=0; n=0
while IFS='|' read -r tipo nombre; do
  nombre="${nombre%$'\r'}"
  n=$((n + 1)); destino="$TMP/datos/$(basename "$nombre")"
  if [ -n "${CARPETA:-}" ]; then cp "$CARPETA/$nombre" "$destino"
  else oci os object get --auth instance_principal --bucket-name "$BUCKET" --name "$nombre" --file "$destino" >/dev/null; fi
  archivos+=(--archivo "/datos/$(basename "$destino")")
  [ "$tipo" = total ] && hay_total=1
  [ "$tipo" = antigua ] && hay_antigua=1
  echo "   $tipo: $nombre ($(du -h "$destino" | cut -f1))"
done <<< "$encontrados"
omitir=()
if [ "$hay_total" = 1 ] && [ "$hay_antigua" = 1 ]; then
  omitir=(--omitir-hoja ASBANC)
  echo "   la hoja ASBANC de la base antigua no se carga: sus documentos ya estan en «Base total» y solo duplicaria apariciones"
fi

# ---- 2. La herramienta (se instala en una carpeta temporal; nada queda en el servidor)
echo "== Preparando la herramienta"
docker run --rm -v "$TMP/pkgs:/pkgs" python:3.12-slim \
  pip install -q --no-cache-dir --root-user-action=ignore --target /pkgs openpyxl pymysql cryptography >/dev/null \
  || { echo "No pude instalar las librerias de la herramienta (¿el servidor tiene salida a internet?)." >&2; exit 1; }

corre_herramienta() {
  docker run --rm --network "$RED" --memory 6g -v "$TMP/pkgs:/pkgs:ro" -v "$HERRAMIENTAS:/tools:ro" -v "$TMP/datos:/datos:ro" -v "$TMP/salida:/salida" \
    -e PYTHONPATH=/pkgs -e PYTHONDONTWRITEBYTECODE=1 -e PYTHONIOENCODING=utf-8 -e DB_URL -e DB_USER -e DB_PASSWORD \
    python:3.12-slim python -u /tools/cargar_listas_masivas.py "${archivos[@]}" ${omitir[@]+"${omitir[@]}"} --rechazados /salida/rechazados.csv "$@"
}

# ---- 3. Con --aplicar: respaldo primero
if [ "$APLICAR" = 1 ]; then
  echo "== Respaldo de la base '$BASE' antes de escribir"
  mkdir -p "$RESPALDOS"; chmod 700 "$RESPALDOS"
  copia="$RESPALDOS/${BASE}_antes-de-cargar-listas_$(date +%F_%H%M).sql.gz"
  if ! MYSQL_PWD="$DB_PASSWORD" docker run --rm --network "$RED" -e MYSQL_PWD mysql:8.4 \
       mysqldump -h "$HOST" -u"$DB_USER" --no-tablespaces --single-transaction "$BASE" | gzip > "$copia"; then
    rm -f "$copia"; echo "No pude respaldar la base: no escribo nada." >&2; exit 1
  fi
  tablas="$(zcat "$copia" | grep -c '^CREATE TABLE' || true)"
  if ! [ "${tablas:-0}" -ge 5 ] 2>/dev/null; then
    rm -f "$copia"; echo "El respaldo salio incompleto (${tablas:-0} tablas): no escribo nada." >&2; exit 1
  fi
  echo "   OK: $copia ($(du -h "$copia" | cut -f1), $tablas tablas)"
fi

# ---- 4. La carga (sin --aplicar solo lee y muestra el informe)
if [ "$APLICAR" = 1 ]; then echo "== Cargando (ESCRIBE en la base)"; flag=(--aplicar); else echo "== Simulacion (no escribe nada)"; flag=(); fi
fallo=0
corre_herramienta ${flag[@]+"${flag[@]}"} || fallo=1

# Las filas rechazadas tienen datos personales: se guardan con permiso solo para root
if [ -s "$TMP/salida/rechazados.csv" ] && [ "$(wc -l < "$TMP/salida/rechazados.csv")" -gt 1 ]; then
  mkdir -p "$RESPALDOS"; chmod 700 "$RESPALDOS"
  rech="$RESPALDOS/plaft_listas_rechazadas_$(date +%F_%H%M).csv"
  cp "$TMP/salida/rechazados.csv" "$rech"; chmod 600 "$rech"
  echo "== Filas rechazadas (con su motivo): $rech  [tiene datos personales; borralo cuando termines]"
fi
[ "$fallo" = 0 ] || { echo "La herramienta fallo (arriba esta el detalle). Lo que alcanzo a cargarse queda; puedes volver a correr el comando: no duplica." >&2; exit 1; }

if [ "$APLICAR" = 1 ]; then
  echo
  echo "LISTO: datos cargados. Los Excel tienen datos de personas: cuando verifiques en la web, borralos del bucket $BUCKET (consola de Oracle, carpeta $PREFIJO)."
else
  echo
  echo "Eso fue una SIMULACION: no se escribio nada. Si el informe se ve bien:  sudo bash $0 --aplicar"
fi
