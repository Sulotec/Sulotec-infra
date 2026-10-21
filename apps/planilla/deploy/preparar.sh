#!/usr/bin/env bash
# Crea o actualiza la configuracion del Sistema de Planillas en el servidor: /opt/sulotec/planilla.env
# (solo root y el grupo docker pueden leerla). Se puede repetir para cambiar valores: Enter conserva el actual.
#   sudo bash /data/apps/planilla/preparar.sh
# Antes hay que crear la base:   sudo /opt/sulotec/scripts/new-project-db.sh mysql planilla
# Sin preguntas (la cadena no pasa por la pantalla):
#   CADENA="$(sudo /opt/sulotec/scripts/new-project-db.sh mysql planilla | sed -n 's/^  Node : //p')" sudo -E bash /data/apps/planilla/preparar.sh
# WEB_URL=https://... evita la pregunta de la direccion. SIN_CORREO=1 salta la configuracion del correo.
# La clave del usuario inicial "admin" se genera aqui y se muestra UNA sola vez; al entrar el sistema obliga a cambiarla.
set -euo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

ENV=/opt/sulotec/planilla.env
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

echo "== Base de datos (MySQL compartida de la VM)"
if [ -n "${CADENA:-}" ]; then
  CADENA="$(limpiar "$CADENA")"
else
  echo "   Pega la cadena 'Node' que mostro new-project-db.sh (empieza con mysql://)."
  if [ -n "$(actual DB_PASSWORD)" ]; then
    leer_secreto "Cadena de la base [Enter = conservar la actual]: "
  else
    leer_secreto "Cadena de la base: "
  fi
  CADENA="$(limpiar "$V")"
fi
if [ -n "$CADENA" ]; then
  echo "   recibido: ${#CADENA} caracteres"
  re='^mysql://([^:/@]+):([^@]+)@([^:/]+):([0-9]+)/([^?]+)$'
  [[ "$CADENA" =~ $re ]] || { echo "No entendi la cadena: debe ser mysql://usuario:clave@mysql:3306/planilla" >&2; exit 1; }
  DB_USER="${BASH_REMATCH[1]}"; DB_PASSWORD="${BASH_REMATCH[2]}"; DB_HOST="${BASH_REMATCH[3]}"; DB_PORT="${BASH_REMATCH[4]}"; DB_NAME="${BASH_REMATCH[5]}"
else
  DB_USER="$(actual DB_USER)"; DB_PASSWORD="$(actual DB_PASSWORD)"; DB_HOST="$(actual DB_HOST)"; DB_PORT="$(actual DB_PORT)"; DB_NAME="$(actual DB_NAME)"
  [ -n "$DB_PASSWORD" ] || { echo "Falta la cadena de la base." >&2; exit 1; }
fi
echo "   usuario=$DB_USER base=$DB_NAME servidor=$DB_HOST:$DB_PORT clave=***"

echo "   Comprobando que entra a la base..."
if MYSQL_PWD="$DB_PASSWORD" docker run --rm --network sulotec_data -e MYSQL_PWD mysql:8.4 mysql -h "$DB_HOST" -P "$DB_PORT" -u"$DB_USER" -N -e 'select 1' "$DB_NAME" >/dev/null 2>/tmp/planilla-prep.err; then
  echo "   OK: la base responde"
else
  echo "No pude entrar a la base. Detalle:" >&2; sed 's/^/   /' /tmp/planilla-prep.err >&2; rm -f /tmp/planilla-prep.err; exit 1
fi
rm -f /tmp/planilla-prep.err

echo
echo "== Direccion publica del sistema"
act_web="$(actual WEB_URL)"; def_web="${act_web:-https://planilla.sulotec.com}"
if [ -n "${WEB_URL:-}" ]; then WEB="$(limpiar "$WEB_URL")"; else
  read -rp "Direccion, sin barra final [Enter = $def_web]: " w; w="$(limpiar "${w:-}")"; WEB="${w:-$def_web}"
fi
[[ "$WEB" =~ ^https?://[^/]+$ ]] || { echo "La direccion debe verse asi: https://planilla.sulotec.com" >&2; exit 1; }

echo
echo "== Correo para enviar boletas (opcional; Enter en todo = sin correo)"
MAIL_HOST="$(actual MAIL_HOST)"; MAIL_PORT="$(actual MAIL_PORT)"; MAIL_USER="$(actual MAIL_USER)"; MAIL_PASSWORD="$(actual MAIL_PASSWORD)"; MAIL_FROM="$(actual MAIL_FROM)"
if [ -z "${SIN_CORREO:-}" ]; then
  echo "   Con OCI Email Delivery: servidor smtp.email.<region>.oci.oraclecloud.com, puerto 587, usuario y clave SMTP de la consola de Oracle."
  read -rp "Servidor SMTP [Enter = ${MAIL_HOST:-sin correo}]: " h; h="$(limpiar "${h:-}")"; MAIL_HOST="${h:-$MAIL_HOST}"
  if [ -n "$MAIL_HOST" ]; then
    read -rp "Puerto [Enter = ${MAIL_PORT:-587}]: " p; p="$(limpiar "${p:-}")"; MAIL_PORT="${p:-${MAIL_PORT:-587}}"
    read -rp "Usuario SMTP [Enter = ${MAIL_USER:-vacio}]: " u; u="$(limpiar "${u:-}")"; MAIL_USER="${u:-$MAIL_USER}"
    leer_secreto "Clave SMTP [Enter = conservar la actual]: "; [ -n "$V" ] && MAIL_PASSWORD="$(limpiar "$V")"
    read -rp "Remitente [Enter = ${MAIL_FROM:-no-reply@sulotec.com}]: " f; f="$(limpiar "${f:-}")"; MAIL_FROM="${f:-${MAIL_FROM:-no-reply@sulotec.com}}"
  fi
fi
MAIL_HABILITADO=false; [ -n "$MAIL_HOST" ] && [ -n "$MAIL_PASSWORD" ] && MAIL_HABILITADO=true

JWT="$(actual JWT_SECRET)"; [ -n "$JWT" ] || JWT="$(openssl rand -base64 48 | tr -d '\n')"

# Clave inicial del administrador: solo se usa la primera vez que arranca con la base vacia.
ADMIN_PASSWORD="$(actual ADMIN_PASSWORD)"
mostrar_clave=""
if [ -z "$ADMIN_PASSWORD" ] && [ ! -f "$ENV" ]; then
  while :; do
    ADMIN_PASSWORD="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 16)"
    [[ "$ADMIN_PASSWORD" =~ [a-z] && "$ADMIN_PASSWORD" =~ [A-Z] && "$ADMIN_PASSWORD" =~ [0-9] ]] && break
  done
  mostrar_clave=1
fi

[ -f "$ENV" ] && cp -p "$ENV" "$ENV.bak"
install -m 640 -o root -g docker /dev/null "$ENV"
{
  echo "PORT=8080"
  echo "TZ=America/Lima"
  echo "DB_HOST=$DB_HOST"
  echo "DB_PORT=$DB_PORT"
  echo "DB_NAME=$DB_NAME"
  echo "DB_USER=$DB_USER"
  echo "DB_PASSWORD=$DB_PASSWORD"
  echo "DB_URL=jdbc:mysql://$DB_HOST:$DB_PORT/$DB_NAME?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC"
  echo "JWT_SECRET=$JWT"
  echo "JWT_EXPIRATION_MS=28800000"
  echo "ADMIN_USER=admin"
  echo "ADMIN_PASSWORD=$ADMIN_PASSWORD"
  echo "SEED_ENABLED=true"
  echo "WEB_URL=$WEB"
  echo "CORS_ORIGINS=$WEB"
  echo "SHOW_SQL=false"
  echo "RMV=${RMV:-$(actual RMV)}"
  echo "UIT=${UIT:-$(actual UIT)}"
  echo "EMPRESA_RUC=$(actual EMPRESA_RUC)"
  echo "EMPRESA_RAZON_SOCIAL=$(actual EMPRESA_RAZON_SOCIAL)"
  echo "EMPRESA_DIRECCION=$(actual EMPRESA_DIRECCION)"
  echo "EMPRESA_REPRESENTANTE=${EMPRESA_REPRESENTANTE:-$(actual EMPRESA_REPRESENTANTE)}"
  echo "EMPRESA_REPRESENTANTE_DOC=${EMPRESA_REPRESENTANTE_DOC:-$(actual EMPRESA_REPRESENTANTE_DOC)}"
  echo "MAIL_HOST=$MAIL_HOST"
  echo "MAIL_PORT=${MAIL_PORT:-587}"
  echo "MAIL_USER=$MAIL_USER"
  echo "MAIL_PASSWORD=$MAIL_PASSWORD"
  echo "MAIL_FROM=${MAIL_FROM:-no-reply@sulotec.com}"
  echo "MAIL_HABILITADO=$MAIL_HABILITADO"
} > "$ENV"
# Las variables vacias se quitan para que la app use sus valores por defecto (RMV, UIT, RUC...)
sed -i '/^[A-Z_]*=$/d' "$ENV"

echo
echo "Listo: $ENV guardado (permisos 640, grupo docker). Correo: $MAIL_HABILITADO."
if [ -n "$mostrar_clave" ]; then
  echo
  echo "   Usuario inicial: admin"
  echo "   Clave inicial:   $ADMIN_PASSWORD"
  echo "   Se muestra UNA sola vez. Al entrar, el sistema obliga a cambiarla. Si se pierde: resetear-clave.sh admin"
fi
echo "Siguiente: sudo bash /data/apps/planilla/desplegar.sh"
