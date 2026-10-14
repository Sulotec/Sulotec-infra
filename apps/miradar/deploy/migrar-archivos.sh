#!/usr/bin/env bash
# Copia las fotos y firmas de MiRadar desde Backblaze B2 al bucket de Oracle, con las MISMAS rutas (la base guarda
# solo la ruta de cada archivo), y comprueba que no falte ninguno. Del origen solo LEE.
#   sudo bash /data/apps/miradar/migrar-archivos.sh
# Se puede repetir: solo copia lo que falte. Corre preparar.sh antes (las claves del destino salen de miradar.env).
# Para pruebas se pueden fijar ORIGEN_* y DESTINO_* (ENDPOINT, REGION, BUCKET, KEY, SECRET) y RED_DOCKER.
set -euo pipefail

ENVFILE="${ENVFILE:-/opt/sulotec/miradar.env}"
RED_DOCKER="${RED_DOCKER:-sulotec_data}"

[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }
valor() { if [ -r "$ENVFILE" ]; then grep -E "^$1=" "$ENVFILE" | head -1 | cut -d= -f2- || true; fi; }
limpiar() { local v="$1"; v="${v//$'\e'\[200~/}"; v="${v//$'\e'\[201~/}"; v="${v//\[200~/}"; v="${v//\[201~/}"; printf '%s' "${v//[[:space:]]/}"; }
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

DESTINO_ENDPOINT="${DESTINO_ENDPOINT:-$(valor B2_ENDPOINT)}"
DESTINO_REGION="${DESTINO_REGION:-$(valor B2_REGION)}"
DESTINO_BUCKET="${DESTINO_BUCKET:-$(valor B2_BUCKET)}"
DESTINO_KEY="${DESTINO_KEY:-$(valor B2_KEY_ID)}"
DESTINO_SECRET="${DESTINO_SECRET:-$(valor B2_APPLICATION_KEY)}"
if [ -z "$DESTINO_ENDPOINT" ] || [ -z "$DESTINO_BUCKET" ] || [ -z "$DESTINO_KEY" ] || [ -z "$DESTINO_SECRET" ]; then
  echo "Faltan los datos del bucket de Oracle en $ENVFILE (corre preparar.sh)." >&2
  exit 1
fi

echo "Datos de Backblaze B2 (solo lectura). Lo que ya venga como ORIGEN_ENDPOINT/REGION/BUCKET/KEY/SECRET no se vuelve a preguntar."
[ -n "${ORIGEN_ENDPOINT:-}" ] || read -rp "Endpoint S3 de B2 (ej. https://s3.us-west-004.backblazeb2.com): " ORIGEN_ENDPOINT
[ -n "${ORIGEN_REGION:-}" ]   || read -rp "Region (ej. us-west-004): " ORIGEN_REGION
[ -n "${ORIGEN_BUCKET:-}" ]   || read -rp "Bucket (ej. afacop-evidencias): " ORIGEN_BUCKET
[ -n "${ORIGEN_KEY:-}" ]      || read -rp "keyID: " ORIGEN_KEY
if [ -z "${ORIGEN_SECRET:-}" ]; then leer_secreto "applicationKey (saldran asteriscos): "; ORIGEN_SECRET="$V"; fi
ORIGEN_ENDPOINT="$(limpiar "$ORIGEN_ENDPOINT")"
ORIGEN_REGION="$(limpiar "$ORIGEN_REGION")"
ORIGEN_BUCKET="$(limpiar "$ORIGEN_BUCKET")"
ORIGEN_KEY="$(limpiar "$ORIGEN_KEY")"
ORIGEN_SECRET="$(limpiar "$ORIGEN_SECRET")"
echo "   origen: $ORIGEN_ENDPOINT | region $ORIGEN_REGION | bucket $ORIGEN_BUCKET | keyID ${ORIGEN_KEY:0:8}... | applicationKey ${#ORIGEN_SECRET} caracteres"
echo "   destino: $DESTINO_ENDPOINT | bucket $DESTINO_BUCKET"

# rclone se configura por variables de entorno: nada se guarda en disco ni se muestra
rc() {
  docker run --rm --network "$RED_DOCKER" \
    -e RCLONE_CONFIG_ORIGEN_TYPE=s3 -e RCLONE_CONFIG_ORIGEN_PROVIDER=Other \
    -e RCLONE_CONFIG_ORIGEN_ENDPOINT="$ORIGEN_ENDPOINT" -e RCLONE_CONFIG_ORIGEN_REGION="$ORIGEN_REGION" \
    -e RCLONE_CONFIG_ORIGEN_ACCESS_KEY_ID="$ORIGEN_KEY" -e RCLONE_CONFIG_ORIGEN_SECRET_ACCESS_KEY="$ORIGEN_SECRET" \
    -e RCLONE_CONFIG_DESTINO_TYPE=s3 -e RCLONE_CONFIG_DESTINO_PROVIDER=Other \
    -e RCLONE_CONFIG_DESTINO_ENDPOINT="$DESTINO_ENDPOINT" -e RCLONE_CONFIG_DESTINO_REGION="$DESTINO_REGION" \
    -e RCLONE_CONFIG_DESTINO_ACCESS_KEY_ID="$DESTINO_KEY" -e RCLONE_CONFIG_DESTINO_SECRET_ACCESS_KEY="$DESTINO_SECRET" \
    rclone/rclone:latest "$@"
}

echo "== 1. Lo que hay en el origen"
rc size "ORIGEN:$ORIGEN_BUCKET" 2>&1 | sed 's/^/   /'

echo "== 2. Copiando al bucket de Oracle (solo lo que falte)"
rc copy "ORIGEN:$ORIGEN_BUCKET" "DESTINO:$DESTINO_BUCKET" --s3-no-check-bucket --transfers 8 --checkers 16 --stats 15s --stats-one-line 2>&1 | tail -3 | sed 's/^/   /'

echo "== 3. Comprobacion: todo lo del origen debe estar en el destino"
resultado="$(rc check "ORIGEN:$ORIGEN_BUCKET" "DESTINO:$DESTINO_BUCKET" --one-way --size-only --s3-no-check-bucket 2>&1 || true)"
echo "$resultado" | tail -4 | sed 's/^/   /'
faltan="$(echo "$resultado" | grep -c -E 'not in DESTINO|sizes differ' || true)"

echo "== 4. Tipo de contenido (la API solo acepta image/jpeg y image/png)"
raros="$(rc lsf "DESTINO:$DESTINO_BUCKET" -R --files-only --format "m" --s3-no-check-bucket 2>/dev/null | grep -v -E '^image/(jpeg|png)$' | sort | uniq -c | sort -rn || true)"
if [ -n "$raros" ]; then
  echo "   ATENCION: hay archivos con otro tipo de contenido (la API los rechazaria al verificarlos):"
  echo "$raros" | sed 's/^/     /'
else
  echo "   todos son image/jpeg o image/png"
fi

echo
if [ "${faltan:-0}" != "0" ]; then
  echo "FALTAN O DIFIEREN $faltan archivo(s): no cierres Backblaze. Repite este script." >&2
  exit 1
fi
echo "TODO COPIADO: el bucket de Oracle tiene todo lo del origen, con las mismas rutas."
echo "Siguiente: sudo bash /data/apps/miradar/probar.sh"
