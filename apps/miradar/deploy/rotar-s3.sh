#!/usr/bin/env bash
# Cambia la clave S3 de svc-miradar (Access key y Secret key del almacenamiento de fotos) en /opt/sulotec/miradar.env.
# Primero PRUEBA la clave nueva en un contenedor aparte (Oracle puede tardar unos minutos en activarla: se reintenta);
# solo si funciona se cambia el archivo y se recrea la API. Si algo falla, la API sigue con la clave anterior.
#   sudo bash /data/apps/miradar/rotar-s3.sh
# Antes: en Cloud Shell se crea la clave nueva (ver README, "Rotar claves"). Despues de este script se borra la anterior en Oracle.
# Variables solo para pruebas: ENVFILE, MIRADAR_DIR, IMAGEN, ESPERAS, PAUSA, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ENVFILE="${ENVFILE:-/opt/sulotec/miradar.env}"
MIRADAR_DIR="${MIRADAR_DIR:-/data/apps/miradar}"
IMAGEN="${IMAGEN:-miradar-api:latest}"
ESPERAS="${ESPERAS:-10}"   # intentos mientras Oracle activa la clave
PAUSA="${PAUSA:-30}"       # segundos entre intentos
LOG=/tmp/rotar-s3.log
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }
[ -r "$ENVFILE" ] || { echo "No encuentro $ENVFILE" >&2; exit 1; }

valor() { grep -E "^$1=" "$ENVFILE" | head -1 | cut -d= -f2- || true; }
limpiar() { local v="$1"; v="${v//$'\e'\[200~/}"; v="${v//$'\e'\[201~/}"; v="${v//\[200~/}"; v="${v//\[201~/}"; printf '%s' "${v//[[:space:]]/}"; }
# Lee un secreto mostrando un * por cada caracter (asi se ve que el pegado funciono sin mostrar el valor). Resultado en $V.
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
# Cambia VAR=valor en el archivo sin tocar el resto, y conserva dueño y permisos del archivo
poner() {
  local k="$1" v="$2" tmp
  grep -q "^$k=" "$ENVFILE" || { echo "No encuentro $k en $ENVFILE" >&2; return 1; }
  tmp="$(mktemp "$ENVFILE.XXXXXX")"
  awk -v k="$k" -v v="$v" 'BEGIN{FS=OFS="="} $1==k {print k "=" v; next} {print}' "$ENVFILE" > "$tmp"
  cat "$tmp" > "$ENVFILE"; rm -f "$tmp"
}
espera_sano() { local c="$1" t="${2:-90}" i; for i in $(seq 1 "$t"); do [ "$(docker inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null || echo none)" = healthy ] && return 0; sleep 1; done; return 1; }
recrear_api() { ( cd "$MIRADAR_DIR" && docker compose up -d --force-recreate api >/dev/null 2>&1 ); }
# Prueba el almacenamiento con una clave en un contenedor aparte, sin tocar la API en marcha.
# Devuelve 0 si funciona, 1 si Oracle todavia no conoce la clave (reintentar) y 2 si es otro error.
probar_clave() {
  if docker run --rm --env-file "$ENVFILE" -e B2_KEY_ID="$1" -e B2_APPLICATION_KEY="$2" "$IMAGEN" node scripts/probar-almacenamiento.js > "$LOG" 2>&1; then return 0; fi
  if grep -q "could not be found" "$LOG"; then return 1; fi
  return 2
}

vieja_id="$(valor B2_KEY_ID)"; vieja_sec="$(valor B2_APPLICATION_KEY)"
[ -n "$vieja_id" ] && [ -n "$vieja_sec" ] || { echo "No encuentro la clave actual (B2_KEY_ID / B2_APPLICATION_KEY) en $ENVFILE" >&2; exit 1; }

echo "Pega la clave NUEVA que creaste en Cloud Shell (la tabla ACCESO / SECRETO)."
read -rp "Access key (ACCESO): " nuevo_id; nuevo_id="$(limpiar "$nuevo_id")"
leer_secreto "Secret key (SECRETO, saldran asteriscos): "; nuevo_sec="$(limpiar "$V")"
echo "   recibido: access key de ${#nuevo_id} caracteres, secret key de ${#nuevo_sec} caracteres"
[ "${#nuevo_id}" -ge 20 ] || { echo "La Access key es muy corta: ¿pegaste la columna ACCESO?" >&2; exit 1; }
[ "${#nuevo_sec}" -ge 30 ] || { echo "La Secret key es muy corta: ¿pegaste la columna SECRETO completa?" >&2; exit 1; }
[ "$nuevo_id" != "$vieja_id" ] || { echo "Esa Access key es la misma que ya esta en uso: crea una clave nueva en Cloud Shell." >&2; exit 1; }

echo "== Probando la clave nueva (Oracle puede tardar unos minutos en activarla)"
n=0
while :; do
  n=$((n+1))
  if probar_clave "$nuevo_id" "$nuevo_sec"; then rc=0; else rc=$?; fi
  [ "$rc" -eq 0 ] && break
  if [ "$rc" -eq 1 ] && [ "$n" -lt "$ESPERAS" ]; then
    echo "   Oracle todavia no activa la clave (intento $n de $ESPERAS); espero $PAUSA segundos..."
    sleep "$PAUSA"; continue
  fi
  echo "FALLO con la clave nueva. Detalle:" >&2
  tail -8 "$LOG" 2>/dev/null | sed 's/^/   /' >&2 || true
  echo "No se cambio nada: la API sigue con la clave anterior." >&2
  exit 1
done
echo "   OK: la clave nueva funciona (subir, descargar y borrar una foto de prueba)"

echo "== Cambiando la clave en la configuracion y recreando la API"
cp -p "$ENVFILE" "$ENVFILE.antes-rotacion"
poner B2_KEY_ID "$nuevo_id"
poner B2_APPLICATION_KEY "$nuevo_sec"
recrear_api
if espera_sano miradar-api 90 && docker exec miradar-api node scripts/probar-almacenamiento.js > "$LOG" 2>&1; then
  echo "   OK: la API en marcha usa la clave nueva"
else
  echo "FALLO al arrancar con la clave nueva. Vuelvo a la clave anterior (sigue valida en Oracle)..." >&2
  cat "$ENVFILE.antes-rotacion" > "$ENVFILE"; rm -f "$ENVFILE.antes-rotacion"
  recrear_api || true
  exit 1
fi
rm -f "$ENVFILE.antes-rotacion" "$LOG"

echo
echo "Listo. Ahora borra la clave ANTERIOR en Oracle (Cloud Shell), asi deja de valer:"
echo "   USR=\$(oci iam user list --all --query \"data[?name=='svc-miradar'].id | [0]\" --raw-output); oci iam customer-secret-key delete --user-id \"\$USR\" --customer-secret-key-id $vieja_id --force"
