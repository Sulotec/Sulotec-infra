#!/usr/bin/env bash
# Crea o actualiza la configuracion de MiRadar en el servidor: /opt/sulotec/miradar.env
# (solo root y el grupo docker pueden leerla). Se puede repetir para cambiar valores: Enter conserva el actual.
#   sudo bash /data/apps/miradar/preparar.sh
# Antes hay que crear la base:   sudo /opt/sulotec/scripts/new-project-db.sh postgres miradar
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

ENV=/opt/sulotec/miradar.env
mkdir -p /opt/sulotec

# Quita los caracteres que algunos terminales web agregan al pegar, y los espacios
limpiar() { local v="$1"; v="${v//$'\e'\[200~/}"; v="${v//$'\e'\[201~/}"; v="${v//\[200~/}"; v="${v//\[201~/}"; printf '%s' "${v//[[:space:]]/}"; }
actual() { [ -f "$ENV" ] && grep -E "^$1=" "$ENV" | head -1 | cut -d= -f2- || true; }
# pregunta VARIABLE "texto" [por_defecto] [secreto]  -> deja el resultado en $R
pregunta() {
  local var="$1" texto="$2" def="${3:-}" secreto="${4:-}" act v
  act="$(actual "$var")"; [ -n "$act" ] && def="$act"
  if [ -n "$secreto" ]; then
    read -rsp "$texto [Enter = $([ -n "$act" ] && echo conservar || echo vacio)]: " v; echo
  else
    read -rp "$texto [Enter = ${def:-vacio}]: " v
  fi
  v="$(limpiar "${v:-}")"; R="${v:-$def}"
}
aleatorio() { openssl rand -hex 32; }

echo "== Base de datos"
echo "   Pega la cadena 'Node' que mostro new-project-db.sh (empieza con postgresql://)."
pregunta DATABASE_URL "DATABASE_URL" "" secreto; DB="$R"
[[ "$DB" =~ ^postgres(ql)?:// ]] || { echo "La cadena debe empezar con postgresql://" >&2; exit 1; }

echo
echo "== ¿La base de MiRadar ya tiene datos (vienen de Aiven/Render, o ya se uso)?"
# Primera vez: lo normal es que si. Si ya se configuro antes sin clave inicial, se mantiene ese modo.
if [ -n "$(actual MFA_ENCRYPTION_KEY)" ] && [ -n "$(actual INITIAL_ADMIN_PASSWORD)" ]; then migrando_def="n"; else migrando_def="s"; fi
read -rp "   [s/n, Enter = $migrando_def]: " migrando; migrando="${migrando:-$migrando_def}"

if [[ "$migrando" =~ ^[sS]$ ]]; then
  echo "   Pega la MISMA MFA_ENCRYPTION_KEY que tiene Render. Si es distinta, nadie podra usar su verificacion en dos pasos."
  pregunta MFA_ENCRYPTION_KEY "MFA_ENCRYPTION_KEY de Render (minimo 32 caracteres)" "" secreto; MFA="$R"
  [ "${#MFA}" -ge 32 ] || { echo "Debe tener al menos 32 caracteres." >&2; exit 1; }
  # Con un administrador ya existente, el backend NO debe recibir clave inicial: si el administrador nunca entro,
  # el arranque le cambiaria la contrasena y le borraria la verificacion en dos pasos.
  ADMIN_PASS=""
  pregunta INITIAL_ADMIN_USERNAME "Usuario administrador (el mismo INITIAL_ADMIN_USERNAME de Render)" "Afacop"; ADMIN_USER="$R"
else
  MFA="$(actual MFA_ENCRYPTION_KEY)"; [ -n "$MFA" ] || MFA="$(aleatorio)"
  pregunta INITIAL_ADMIN_USERNAME "Usuario del administrador inicial" "Afacop"; ADMIN_USER="$R"
  echo "   Clave del administrador inicial: minimo 12 caracteres con mayuscula, minuscula, numero y simbolo."
  read -rsp "   [Enter = generar una]: " ADMIN_PASS; echo; ADMIN_PASS="$(limpiar "${ADMIN_PASS:-}")"
  if [ -z "$ADMIN_PASS" ]; then ADMIN_PASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 16)Aa1!"; GENERADA=1; fi
fi

JWT="$(actual JWT_SECRET)"; [ -n "$JWT" ] || JWT="$(aleatorio)"

echo
echo "== Seguridad y servicios: copia estos valores de Render (Enter = valor sugerido)"
pregunta REQUIRE_MFA "REQUIRE_MFA (true o false)" "true"; REQ_MFA="$R"
pregunta MFA_EXEMPT_USERNAMES "MFA_EXEMPT_USERNAMES (usuarios sin verificacion en dos pasos, separados por coma)" ""; EXENTOS="$R"
pregunta GEOCODING_PROVIDER "GEOCODING_PROVIDER (nominatim o mapbox)" "nominatim"; GEO_PROV="$R"
pregunta GEOCODING_WORKER_ENABLED "GEOCODING_WORKER_ENABLED (true o false)" "true"; GEO_WORKER="$R"

echo
echo "== Direcciones"
pregunta FRONTEND_URL "Direccion de la web (sin barra final)" "https://miradar360.sulotec.com"; FRONT="$R"

echo
echo "== Almacenamiento de fotos y firmas (Oracle Object Storage, API compatible con S3)"
pregunta B2_ENDPOINT "Endpoint" "https://axkjo5bh8iys.compat.objectstorage.sa-santiago-1.oraclecloud.com"; S3E="$R"
pregunta B2_REGION "Region" "sa-santiago-1"; S3R="$R"
pregunta B2_BUCKET "Bucket" "miradar-archivos"; S3B="$R"
pregunta B2_KEY_ID "Access key (de svc-miradar)" "" ; S3K="$R"
pregunta B2_APPLICATION_KEY "Secret key (de svc-miradar)" "" secreto; S3S="$R"

echo
echo "== Servicios externos (Enter si no se usan)"
pregunta MAPBOX_ACCESS_TOKEN "Token de Mapbox" "" secreto; MAPBOX="$R"
pregunta RRCC_API_URL "Direccion de la RRCC-API" ""; RRCC_URL="$R"
pregunta RRCC_API_KEY "Clave de la RRCC-API" "" secreto; RRCC_KEY="$R"

if [ "$GEO_PROV" = "mapbox" ] && [ -z "$MAPBOX" ]; then echo "Con GEOCODING_PROVIDER=mapbox hace falta el token de Mapbox." >&2; exit 1; fi

install -m 640 -o root -g docker /dev/null "$ENV"
{
  echo "NODE_ENV=production"
  echo "PORT=4000"
  echo "DATABASE_URL=$DB"
  echo "JWT_SECRET=$JWT"
  echo "MFA_ENCRYPTION_KEY=$MFA"
  echo "INITIAL_ADMIN_USERNAME=$ADMIN_USER"
  echo "INITIAL_ADMIN_PASSWORD=$ADMIN_PASS"
  echo "RESET_INITIAL_ADMIN=false"
  echo "REQUIRE_MFA=$REQ_MFA"
  echo "MFA_EXEMPT_USERNAMES=$EXENTOS"
  echo "JWT_EXPIRES_IN=8h"
  echo "JWT_ADVISOR_EXPIRES_IN=15m"
  echo "MAX_LOGIN_FAILURES=5"
  echo "ACCOUNT_LOCK_MINUTES=15"
  echo "FRONTEND_URL=$FRONT"
  echo "CORS_ALLOW_ALL=false"
  echo "TRUST_PROXY=true"
  echo "LOG_LEVEL=info"
  echo "B2_ENDPOINT=$S3E"
  echo "B2_REGION=$S3R"
  echo "B2_BUCKET=$S3B"
  echo "B2_KEY_ID=$S3K"
  echo "B2_APPLICATION_KEY=$S3S"
  echo "GEOCODING_PROVIDER=$GEO_PROV"
  echo "GEOCODING_BASE_URL=https://nominatim.openstreetmap.org"
  echo "GEOCODING_USER_AGENT=Radar360/1.0 (soporte@sulotec.com)"
  echo "GEOCODING_WORKER_ENABLED=$GEO_WORKER"
  echo "GEOCODING_BATCH_SIZE=5"
  [ -n "$MAPBOX" ]   && echo "MAPBOX_ACCESS_TOKEN=$MAPBOX"
  [ -n "$RRCC_URL" ] && echo "RRCC_API_URL=$RRCC_URL"
  [ -n "$RRCC_KEY" ] && echo "RRCC_API_KEY=$RRCC_KEY"
} > "$ENV"

echo
echo "Configuracion guardada en $ENV"
if [ "${GENERADA:-}" = 1 ]; then
  echo
  echo "CLAVE GENERADA del administrador '$ADMIN_USER' (se muestra una sola vez, guardala en el gestor de contrasenas):"
  echo "   $ADMIN_PASS"
fi
echo "Siguiente: sudo bash /data/apps/miradar/desplegar.sh"
