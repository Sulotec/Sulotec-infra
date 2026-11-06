#!/usr/bin/env bash
# Crea o actualiza la configuracion de Indira en el servidor: /opt/sulotec/indira.env
# (solo root y el grupo docker pueden leerla). Se puede repetir: Enter conserva el valor actual.
#   sudo bash /data/apps/indira/preparar.sh
# Antes: la base (sudo /opt/sulotec/scripts/new-project-db.sh postgres indira) y el servicio de licencias con el producto
# "indira" (Licencias-Backend#6 unido y desplegado).
# Sin preguntas (la cadena no pasa por la pantalla):
#   CADENA="$(sudo /opt/sulotec/scripts/new-project-db.sh postgres indira | sed -n 's/^  Node : //p')" sudo -E bash /data/apps/indira/preparar.sh
# Proveedor: falso por defecto (sin costo). PROVEEDOR=ollama solo con permiso del dueno (ver docker-compose.ollama.yml).
# Claude NO se configura aqui: el servicio se niega a arrancar con claude sin INDIRA_PRIVACIDAD_ACEPTADA=si.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

ENV=/opt/sulotec/indira.env
mkdir -p /opt/sulotec

limpiar() { local v="$1"; v="${v//$'\e'\[200~/}"; v="${v//$'\e'\[201~/}"; v="${v//\[200~/}"; v="${v//\[201~/}"; printf '%s' "${v//[[:space:]]/}"; }
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
actual() { [ -f "$ENV" ] && grep -E "^$1=" "$ENV" | head -1 | cut -d= -f2- || true; }

echo "== Base de datos"
if [ -n "${CADENA:-}" ]; then
  CADENA="$(limpiar "$CADENA")"
else
  echo "   Pega la cadena 'Node' que mostro new-project-db.sh (empieza con postgresql://; sirve igual para Python)."
  if [ -n "$(actual DATABASE_URL)" ]; then leer_secreto "Cadena de la base [Enter = conservar la actual]: "; else leer_secreto "Cadena de la base: "; fi
  CADENA="$(limpiar "$V")"
fi
if [ -n "$CADENA" ]; then
  echo "   recibido: ${#CADENA} caracteres"
  [[ "$CADENA" =~ ^postgres(ql)?(\+[a-z0-9]+)?://[^:/@]+:[^@]+@[^:/]+:[0-9]+/[^?]+$ ]] || { echo "No entendi la cadena: debe ser postgresql://usuario:clave@postgres:5432/indira" >&2; exit 1; }
  DATABASE_URL="$CADENA"
else
  DATABASE_URL="$(actual DATABASE_URL)"
  [ -n "$DATABASE_URL" ] || { echo "Falta la cadena de la base." >&2; exit 1; }
fi
echo "   Comprobando que entra a la base..."
PSQL_URL="${DATABASE_URL/postgresql+asyncpg:/postgresql:}"
if docker run --rm --network sulotec_data postgres:16 psql "$PSQL_URL" -Atc 'select 1' >/dev/null 2>/tmp/indira-prep.err; then
  echo "   OK: la base responde"
else
  echo "No pude entrar a la base. Detalle:" >&2; sed 's/^/   /' /tmp/indira-prep.err >&2; rm -f /tmp/indira-prep.err; exit 1
fi
rm -f /tmp/indira-prep.err

echo
echo "== Token del producto indira (servicio de licencias)"
TOKEN="$(actual LICENCIAS_TOKEN)"
if [ -n "$TOKEN" ]; then
  read -rp "   Ya hay un token guardado. ¿Generar uno nuevo? El anterior deja de valer. [s/N] " r
  [[ "${r:-}" =~ ^[sS]$ ]] && TOKEN=""
fi
if [ -z "$TOKEN" ]; then
  docker ps --format '{{.Names}}' | grep -qx licencias || { echo "No encuentro el contenedor licencias: despliega antes el servicio de licencias." >&2; exit 1; }
  # Se genera y se guarda directo: el token no pasa por la pantalla.
  TOKEN="$(docker exec licencias node scripts/token-producto.js indira 2>/tmp/indira-tok.err | sed -n 's/^LICENCIAS_TOKEN=//p' || true)"
  if [ -z "$TOKEN" ]; then
    echo "No pude generar el token. Detalle (¿falta unir Licencias-Backend#6 y desplegarlo?):" >&2; sed 's/^/   /' /tmp/indira-tok.err >&2; rm -f /tmp/indira-tok.err; exit 1
  fi
  rm -f /tmp/indira-tok.err
  echo "   OK: token nuevo generado y guardado (no se muestra)"
fi
[[ "$TOKEN" == indira.* ]] || { echo "El token guardado no es del producto indira." >&2; exit 1; }

echo
echo "== Modelo"
PROVEEDOR_ACTUAL="$(actual INDIRA_PROVEEDOR)"
PROVEEDOR="${PROVEEDOR:-${PROVEEDOR_ACTUAL:-falso}}"
case "$PROVEEDOR" in
  falso|ollama) ;;
  claude) echo "Claude no se enciende desde aqui (decision del dueno: falta el aviso de privacidad)." >&2; exit 1 ;;
  *) echo "PROVEEDOR debe ser falso u ollama" >&2; exit 1 ;;
esac
echo "   INDIRA_PROVEEDOR=$PROVEEDOR"
if [ "$PROVEEDOR" = ollama ] && [ ! -f /data/apps/indira/usar-ollama ]; then
  echo "   AVISO: con ollama, crea tambien /data/apps/indira/usar-ollama (sudo touch) para que desplegar.sh lo conecte a la red de PLAFT."
fi

install -m 640 -o root -g docker /dev/null "$ENV"
{
  echo "DATABASE_URL=$DATABASE_URL"
  echo "INDIRA_PROVEEDOR=$PROVEEDOR"
  echo "INDIRA_CORS=https://sulotec.com,https://www.sulotec.com"
  echo "INDIRA_AZP_PERMITIDOS=portal"
  echo "KEYCLOAK_ISSUER=https://cuenta.sulotec.com/realms/sulotec"
  echo "KEYCLOAK_AUDIENCE=indira"
  echo "ROL_UNIVERSAL=administrador-general"
  echo "LICENCIAS_URL=http://licencias:3200"
  echo "LICENCIAS_PRODUCTO=indira"
  echo "LICENCIAS_TOKEN=$TOKEN"
  echo "OLLAMA_URL=http://plaft-ollama:11434"
  echo "OLLAMA_MODELO=$(actual OLLAMA_MODELO | grep . || echo qwen2.5:7b)"
  echo "OLLAMA_NUM_CTX=4096"
  echo "INDIRA_RETENCION_DIAS=90"
  # Solo para probar el tunel (probar.sh con DEMORA): segundos que tarda el proveedor falso. 0 en uso normal.
  echo "INDIRA_FALSO_DEMORA_S=$(actual INDIRA_FALSO_DEMORA_S | grep . || echo 0)"
} > "$ENV"
echo
echo "Listo: $ENV guardado (permisos 640, grupo docker). Siguiente: sudo bash /data/apps/indira/desplegar.sh"
