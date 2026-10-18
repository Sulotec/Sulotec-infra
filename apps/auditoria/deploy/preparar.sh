#!/usr/bin/env bash
# Crea o actualiza la configuracion de Auditoria de Visitas en el servidor: /opt/sulotec/auditoria.env
# (solo root y el grupo docker pueden leerla). Se puede repetir para cambiar valores: Enter conserva el actual.
#   sudo bash /data/apps/auditoria/preparar.sh
# Antes hay que crear la base:   sudo /opt/sulotec/scripts/new-project-db.sh mysql auditoria
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

ENV="${ENVFILE:-/opt/sulotec/auditoria.env}"
RED_DOCKER="${RED_DOCKER:-sulotec_data}"
mkdir -p "$(dirname "$ENV")"

# Quita los caracteres que algunos terminales web agregan al pegar, las flechas del teclado y los espacios
limpiar() { local v="$1"; v="$(printf '%s' "$v" | sed -E $'s/\e\[[0-9;]*[A-Za-z~]//g')"; v="${v//\[200~/}"; v="${v//\[201~/}"; printf '%s' "${v//[[:space:]]/}"; }
limpiar_texto() { local v="$1"; v="$(printf '%s' "$v" | sed -E $'s/\e\[[0-9;]*[A-Za-z~]//g')"; v="${v//\[200~/}"; v="${v//\[201~/}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; printf '%s' "$v"; }
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
# pregunta VARIABLE "texto" [por_defecto] [secreto]  -> deja el resultado en $R
pregunta() {
  local var="$1" texto="$2" def="${3:-}" secreto="${4:-}" act v
  act="$(actual "$var")"; [ -n "$act" ] && def="$act"
  if [ -n "$secreto" ]; then
    leer_secreto "$texto [Enter = $([ -n "$act" ] && echo conservar || echo vacio)]: "; v="$V"
  else
    read -rp "$texto [Enter = ${def:-vacio}]: " v
  fi
  v="$(limpiar "${v:-}")"; R="${v:-$def}"
  if [ -n "$secreto" ] && [ -n "$v" ]; then echo "   recibido: ${#v} caracteres"; fi
}
aleatorio() { openssl rand -hex 32; }

echo "== Base de datos"
echo "   Pega la cadena 'Node' que mostro new-project-db.sh (empieza con mysql://)."
pregunta DATABASE_URL "DATABASE_URL" "" secreto; DB="$R"
echo "   $(printf '%s' "$DB" | sed -E 's#(://[^:/@]+:)[^@]*@#\1***@#')"
re='^mysql://([^:/@]+):([^@]*)@([^:/]+):([0-9]+)/([A-Za-z0-9_]+)'
[[ "$DB" =~ $re ]] || { echo "La cadena debe tener la forma mysql://usuario:clave@mysql:3306/auditoria" >&2; exit 1; }
DB_USER="${BASH_REMATCH[1]}"; DB_PASS="${BASH_REMATCH[2]}"; DB_HOST="${BASH_REMATCH[3]}"; DB_PORT="${BASH_REMATCH[4]}"; DB_NAME="${BASH_REMATCH[5]}"
# Comprobacion que falla a la vista: entrar a la base con esa clave desde la red de datos
if [ -z "${PRUEBA:-}" ]; then
  tablas="$(docker run --rm --network "$RED_DOCKER" -e MYSQL_PWD="$DB_PASS" mysql:8.4 mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -N -e "select count(*) from information_schema.tables where table_schema='$DB_NAME'" "$DB_NAME" 2>/dev/null || true)"
  [ -n "$tablas" ] || { echo "No pude entrar a la base '$DB_NAME' con esa clave. ¿Corriste new-project-db.sh mysql auditoria y pegaste la cadena completa?" >&2; exit 1; }
  echo "   conecta: la base '$DB_NAME' tiene $tablas tablas"
fi

echo
echo "== ¿La base ya tiene datos (vienen de Aiven/Render con migrar-datos.sh, o ya se uso)?"
# Primera vez: lo normal es que si. Si ya se configuro antes sin clave inicial, se mantiene ese modo.
if [ -n "$(actual MFA_ENCRYPTION_KEY)" ] && [ -n "$(actual INITIAL_ADMIN_PASSWORD)" ]; then migrando_def="n"; else migrando_def="s"; fi
read -rp "   [s/n, Enter = $migrando_def]: " migrando; migrando="${migrando:-$migrando_def}"

if [[ "$migrando" =~ ^[sS]$ ]]; then
  echo "   Pega la MISMA MFA_ENCRYPTION_KEY que tiene Render (Environment del servicio). Si es distinta, nadie podra usar su verificacion en dos pasos."
  pregunta MFA_ENCRYPTION_KEY "MFA_ENCRYPTION_KEY de Render (minimo 32 caracteres)" "" secreto; MFA="$R"
  [ "${#MFA}" -ge 32 ] || { echo "Debe tener al menos 32 caracteres (recibi ${#MFA}). Vuelve a correr el script y pegala completa." >&2; exit 1; }
  # Con un administrador ya existente, el backend NO debe recibir clave inicial: si el administrador nunca entro,
  # el arranque le cambiaria la contrasena y le borraria la verificacion en dos pasos.
  ADMIN_PASS=""
  pregunta INITIAL_ADMIN_USERNAME "Usuario administrador (el mismo INITIAL_ADMIN_USERNAME de Render)" "CajaHuancayo"; ADMIN_USER="$R"
else
  MFA="$(actual MFA_ENCRYPTION_KEY)"; [ -n "$MFA" ] || MFA="$(aleatorio)"
  pregunta INITIAL_ADMIN_USERNAME "Usuario del administrador inicial" "CajaHuancayo"; ADMIN_USER="$R"
  echo "   Clave del administrador inicial: minimo 12 caracteres con mayuscula, minuscula, numero y simbolo."
  leer_secreto "   [Enter = generar una]: "; ADMIN_PASS="$(limpiar "${V:-}")"
  if [ -z "$ADMIN_PASS" ]; then ADMIN_PASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 16)Aa1!"; GENERADA=1; fi
fi

JWT="$(actual JWT_SECRET)"; [ -n "$JWT" ] || JWT="$(aleatorio)"

echo
echo "== Empresas (plantilla multiempresa)"
act_emp="$(actual EMPRESA_INICIAL_NOMBRE)"
read -rp "Nombre de la primera empresa (se crea solo si la base no tiene ninguna) [Enter = ${act_emp:-Caja Huancayo}]: " emp; emp="$(limpiar_texto "${emp:-}")"; EMPRESA="${emp:-${act_emp:-Caja Huancayo}}"
echo "   Administrador universal de Sulotec (ve todas las empresas; se crea solo si no existe ninguno). Enter = no crear."
pregunta INITIAL_UNIVERSAL_USERNAME "Usuario del administrador universal (minusculas, 3 a 50 caracteres)" ""; UNI_USER="$R"
UNI_PASS="$(actual INITIAL_UNIVERSAL_PASSWORD)"
if [ -n "$UNI_USER" ]; then
  echo "   Clave del administrador universal: minimo 12 caracteres con mayuscula, minuscula, numero y simbolo."
  leer_secreto "   [Enter = $([ -n "$UNI_PASS" ] && echo conservar || echo generar una)]: "; v="$(limpiar "${V:-}")"
  if [ -n "$v" ]; then UNI_PASS="$v"; elif [ -z "$UNI_PASS" ]; then UNI_PASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 16)Aa1!"; UNI_GENERADA=1; fi
else
  UNI_PASS=""
fi

echo
echo "== Seguridad y reglas: copia estos valores de Render (Enter = valor sugerido)"
pregunta REQUIRE_MFA "REQUIRE_MFA (true o false)" "true"; REQ_MFA="$R"
pregunta MFA_EXEMPT_USERNAMES "MFA_EXEMPT_USERNAMES (usuarios sin verificacion en dos pasos, separados por coma)" "$ADMIN_USER"; EXENTOS="$R"
pregunta GEOFENCE_RADIO_METROS "GEOFENCE_RADIO_METROS (radio de la geocerca por defecto)" "100"; GEO_RADIO="$R"
pregunta GEOFENCE_PRECISION_MAXIMA_METROS "GEOFENCE_PRECISION_MAXIMA_METROS" "100"; GEO_PREC="$R"
pregunta PERMITIR_AUTOASIGNACION "PERMITIR_AUTOASIGNACION (true = el auditor puede tomar casos disponibles)" "true"; AUTOASIG="$R"
pregunta TRACKING_RETENCION_DIAS "TRACKING_RETENCION_DIAS (dias que se guarda el recorrido GPS; 0 = siempre)" "90"; RETENCION="$R"
pregunta GEOCODING_WORKER_ENABLED "GEOCODING_WORKER_ENABLED (true solo con autorizacion del banco: manda direcciones a un proveedor externo)" "false"; GEO_WORKER="$R"
pregunta GEOCODING_PROVIDER "GEOCODING_PROVIDER (nominatim o mapbox)" "nominatim"; GEO_PROV="$R"

echo
echo "== Direcciones"
pregunta FRONTEND_URL "Direccion del panel web (sin barra final; varias separadas por coma)" "https://auditoria.sulotec.com"; FRONT="$R"
pregunta EVIDENCIAS_BASE_URL "Direccion publica de la API (la app sube las fotos ahi)" "https://api-auditoria.sulotec.com"; API_URL="$R"

echo
echo "== Inicio unico con la cuenta Sulotec (cuenta.sulotec.com). Enter = valores de Sulotec; vacio = solo usuario y contrasena"
pregunta SSO_ISSUER "SSO_ISSUER (emisor del realm)" "https://cuenta.sulotec.com/realms/sulotec"; SSO_ISSUER="$R"
pregunta SSO_CLIENT_ID "SSO_CLIENT_ID (cliente de Keycloak)" "auditoria"; SSO_CLIENT_ID="$R"

echo
echo "== Almacenamiento de fotos (Oracle Object Storage, API compatible con S3)"
pregunta S3_ENDPOINT "Endpoint" "https://axkjo5bh8iys.compat.objectstorage.sa-santiago-1.oraclecloud.com"; S3E="$R"
pregunta S3_REGION "Region" "sa-santiago-1"; S3R="$R"
pregunta S3_BUCKET "Bucket" "huancayo-archivos"; S3B="$R"
pregunta S3_ACCESS_KEY_ID "Access key (de svc-auditoria)" ""; S3K="$R"
pregunta S3_SECRET_ACCESS_KEY "Secret key (de svc-auditoria)" "" secreto; S3S="$R"
[ -n "$S3K" ] && [ -n "$S3S" ] || { echo "Hacen falta la Access key y la Secret key de svc-auditoria (ver README, paso 1)." >&2; exit 1; }

echo
echo "== Servicios externos (Enter si no se usan)"
pregunta MAPBOX_ACCESS_TOKEN "Token de Mapbox" "" secreto; MAPBOX="$R"
if [ "$GEO_PROV" = "mapbox" ] && [ -z "$MAPBOX" ]; then echo "Con GEOCODING_PROVIDER=mapbox hace falta el token de Mapbox." >&2; exit 1; fi

install -m 640 -o root -g docker /dev/null "$ENV" 2>/dev/null || install -m 640 /dev/null "$ENV"
{
  echo "NODE_ENV=production"
  echo "PORT=4100"
  echo "DATABASE_URL=$DB"
  echo "JWT_SECRET=$JWT"
  echo "MFA_ENCRYPTION_KEY=$MFA"
  echo "INITIAL_ADMIN_USERNAME=$ADMIN_USER"
  echo "INITIAL_ADMIN_PASSWORD=$ADMIN_PASS"
  echo "RESET_INITIAL_ADMIN=false"
  echo "EMPRESA_INICIAL_NOMBRE=$EMPRESA"
  echo "INITIAL_UNIVERSAL_USERNAME=$UNI_USER"
  echo "INITIAL_UNIVERSAL_PASSWORD=$UNI_PASS"
  echo "REQUIRE_MFA=$REQ_MFA"
  echo "MFA_EXEMPT_USERNAMES=$EXENTOS"
  echo "JWT_EXPIRES_IN=8h"
  echo "JWT_FIELD_EXPIRES_IN=12h"
  echo "JWT_ISSUER=caja-huancayo-auditoria-api"
  echo "JWT_AUDIENCE=caja-huancayo-auditoria-clients"
  echo "MAX_LOGIN_FAILURES=5"
  echo "ACCOUNT_LOCK_MINUTES=15"
  echo "ENFORCE_DEVICE_BINDING=true"
  echo "FRONTEND_URL=$FRONT"
  echo "CORS_ALLOW_ALL=false"
  echo "TRUST_PROXY=true"
  echo "LOG_LEVEL=info"
  echo "EVIDENCIAS_BACKEND=s3"
  echo "EVIDENCIAS_BASE_URL=$API_URL"
  echo "SSO_ISSUER=$SSO_ISSUER"
  echo "SSO_CLIENT_ID=$SSO_CLIENT_ID"
  echo "S3_ENDPOINT=$S3E"
  echo "S3_REGION=$S3R"
  echo "S3_BUCKET=$S3B"
  echo "S3_ACCESS_KEY_ID=$S3K"
  echo "S3_SECRET_ACCESS_KEY=$S3S"
  echo "S3_FORCE_PATH_STYLE=true"
  echo "GEOFENCE_RADIO_METROS=$GEO_RADIO"
  echo "GEOFENCE_PRECISION_MAXIMA_METROS=$GEO_PREC"
  echo "PERMITIR_AUTOASIGNACION=$AUTOASIG"
  echo "TRACKING_RETENCION_DIAS=$RETENCION"
  echo "GEOCODING_WORKER_ENABLED=$GEO_WORKER"
  echo "GEOCODING_PROVIDER=$GEO_PROV"
  [ -n "$MAPBOX" ] && echo "MAPBOX_ACCESS_TOKEN=$MAPBOX"
} > "$ENV"

echo
echo "Configuracion guardada en $ENV"
if [ "${GENERADA:-}" = 1 ]; then
  echo
  echo "CLAVE GENERADA del administrador '$ADMIN_USER' (se muestra una sola vez, guardala en el gestor de contrasenas):"
  echo "   $ADMIN_PASS"
fi
if [ "${UNI_GENERADA:-}" = 1 ]; then
  echo
  echo "CLAVE GENERADA del administrador universal '$UNI_USER' (se muestra una sola vez, guardala en el gestor de contrasenas):"
  echo "   $UNI_PASS"
fi
if [[ "$migrando" =~ ^[sS]$ ]]; then
  echo "Siguiente: sudo bash /data/apps/auditoria/migrar-datos.sh   (y despues desplegar.sh)"
else
  echo "Siguiente: sudo bash /data/apps/auditoria/desplegar.sh"
fi
