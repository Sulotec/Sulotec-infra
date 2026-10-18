#!/usr/bin/env bash
# Crea o actualiza la configuracion de Dashboard Empresarial en el servidor: /opt/sulotec/dashboard.env
# (solo root y el grupo docker pueden leerla). Se puede repetir para cambiar valores: Enter conserva el actual.
#   sudo bash /data/apps/dashboard/preparar.sh
# Antes hay que crear la base:   sudo /opt/sulotec/scripts/new-project-db.sh postgres dashboard
# Sin preguntas (la cadena no pasa por la pantalla):
#   CADENA="$(sudo /opt/sulotec/scripts/new-project-db.sh postgres dashboard | sed -n 's/^  Node : //p')" sudo -E bash /data/apps/dashboard/preparar.sh
# WEB_URL=https://... tambien evita la pregunta de la direccion de la web.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

ENV=/opt/sulotec/dashboard.env
mkdir -p /opt/sulotec

# Quita los caracteres que algunos terminales web agregan al pegar, y los espacios
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
actual() { [ -f "$ENV" ] && grep -E "^$1=" "$ENV" | head -1 | cut -d= -f2- || true; }

echo "== Base de datos"
if [ -n "${CADENA:-}" ]; then
  CADENA="$(limpiar "$CADENA")"
else
  echo "   Pega la cadena 'Node' que mostro new-project-db.sh (empieza con postgresql://)."
  if [ -n "$(actual DB_PASSWORD)" ]; then
    leer_secreto "Cadena de la base [Enter = conservar la actual]: "
  else
    leer_secreto "Cadena de la base: "
  fi
  CADENA="$(limpiar "$V")"
fi
if [ -n "$CADENA" ]; then
  echo "   recibido: ${#CADENA} caracteres"
  re='^postgres(ql)?://([^:/@]+):([^@]+)@([^:/]+):([0-9]+)/([^?]+)$'
  [[ "$CADENA" =~ $re ]] || { echo "No entendi la cadena: debe ser postgresql://usuario:clave@postgres:5432/dashboard" >&2; exit 1; }
  DB_USER="${BASH_REMATCH[2]}"; DB_PASSWORD="${BASH_REMATCH[3]}"; DB_HOST="${BASH_REMATCH[4]}"; DB_PORT="${BASH_REMATCH[5]}"; DB_NAME="${BASH_REMATCH[6]}"
else
  DB_USER="$(actual DB_USER)"; DB_PASSWORD="$(actual DB_PASSWORD)"; DB_HOST="$(actual DB_HOST)"; DB_PORT="$(actual DB_PORT)"; DB_NAME="$(actual DB_NAME)"
  [ -n "$DB_PASSWORD" ] || { echo "Falta la cadena de la base." >&2; exit 1; }
fi
echo "   usuario=$DB_USER base=$DB_NAME servidor=$DB_HOST:$DB_PORT clave=***"

echo "   Comprobando que entra a la base..."
export PGPASSWORD="$DB_PASSWORD"
if docker run --rm --network sulotec_data -e PGPASSWORD postgres:16 psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc 'select 1' >/dev/null 2>/tmp/dashboard-prep.err; then
  echo "   OK: la base responde"
else
  echo "No pude entrar a la base. Detalle:" >&2; sed 's/^/   /' /tmp/dashboard-prep.err >&2; rm -f /tmp/dashboard-prep.err; exit 1
fi
rm -f /tmp/dashboard-prep.err
unset PGPASSWORD

echo
echo "== Direccion de la web (la unica que puede llamar a la API)"
act_front="$(actual CORS_ORIGIN)"; def_front="${act_front:-https://dashboards.sulotec.com}"
if [ -n "${WEB_URL:-}" ]; then FRONT="$(limpiar "$WEB_URL")"; else
  read -rp "Direccion de la web, sin barra final [Enter = $def_front]: " front; front="$(limpiar "${front:-}")"; FRONT="${front:-$def_front}"
fi
[[ "$FRONT" =~ ^https?://[^/]+$ ]] || { echo "La direccion debe verse asi: https://dashboards.sulotec.com" >&2; exit 1; }

JWT="$(actual JWT_SECRET)"; [ -n "$JWT" ] || JWT="$(openssl rand -hex 32)"

install -m 640 -o root -g docker /dev/null "$ENV"
{
  echo "NODE_ENV=production"
  echo "PORT=3100"
  echo "DB_HOST=$DB_HOST"
  echo "DB_PORT=$DB_PORT"
  echo "DB_NAME=$DB_NAME"
  echo "DB_USER=$DB_USER"
  echo "DB_PASSWORD=$DB_PASSWORD"
  echo "DB_SSL=false"
  echo "JWT_SECRET=$JWT"
  echo "JWT_EXPIRES_IN=1h"
  echo "CORS_ORIGIN=$FRONT"
  echo "TRUST_PROXY=true"
} > "$ENV"
echo
echo "Listo: $ENV guardado (permisos 640, grupo docker). Siguiente: sudo bash /data/apps/dashboard/desplegar.sh"
