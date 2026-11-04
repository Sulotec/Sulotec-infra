#!/usr/bin/env bash
# Crea o actualiza la configuracion del servicio de licencias en el servidor: /opt/sulotec/licencias.env
# (solo root y el grupo docker pueden leerla). Se puede repetir para cambiar valores: Enter conserva el actual.
#   sudo bash /data/apps/licencias/preparar.sh
# Antes hay que crear la base:   sudo /opt/sulotec/scripts/new-project-db.sh postgres licencias
# Sin preguntas (la cadena no pasa por la pantalla):
#   CADENA="$(sudo /opt/sulotec/scripts/new-project-db.sh postgres licencias | sed -n 's/^  Node : //p')" sudo -E bash /data/apps/licencias/preparar.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

ENV=/opt/sulotec/licencias.env
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
  if [ -n "$(actual DATABASE_URL)" ]; then
    leer_secreto "Cadena de la base [Enter = conservar la actual]: "
  else
    leer_secreto "Cadena de la base: "
  fi
  CADENA="$(limpiar "$V")"
fi
if [ -n "$CADENA" ]; then
  echo "   recibido: ${#CADENA} caracteres"
  [[ "$CADENA" =~ ^postgres(ql)?://[^:/@]+:[^@]+@[^:/]+:[0-9]+/[^?]+$ ]] || { echo "No entendi la cadena: debe ser postgresql://usuario:clave@postgres:5432/licencias" >&2; exit 1; }
  DATABASE_URL="$CADENA"
else
  DATABASE_URL="$(actual DATABASE_URL)"
  [ -n "$DATABASE_URL" ] || { echo "Falta la cadena de la base." >&2; exit 1; }
fi

echo "   Comprobando que entra a la base..."
if docker run --rm --network sulotec_data postgres:16 psql "$DATABASE_URL" -Atc 'select 1' >/dev/null 2>/tmp/licencias-prep.err; then
  echo "   OK: la base responde"
else
  echo "No pude entrar a la base. Detalle:" >&2; sed 's/^/   /' /tmp/licencias-prep.err >&2; rm -f /tmp/licencias-prep.err; exit 1
fi
rm -f /tmp/licencias-prep.err

echo
echo "== Correo de salida (OCI Email Delivery). Sin correo, los avisos solo quedan en el log del contenedor."
SMTP_HOST="$(actual SMTP_HOST)"; SMTP_USER="$(actual SMTP_USER)"; SMTP_PASS="$(actual SMTP_PASS)"
if [ -n "$SMTP_HOST" ]; then
  read -rp "¿Cambiar el correo de salida ya configurado? [s/N] " r
else
  read -rp "¿Configurar ahora el correo de salida? [s/N] " r
fi
if [[ "${r:-}" =~ ^[sS]$ ]]; then
  read -rp "Servidor SMTP [Enter = smtp.email.sa-santiago-1.oci.oraclecloud.com]: " h
  SMTP_HOST="$(limpiar "${h:-smtp.email.sa-santiago-1.oci.oraclecloud.com}")"
  read -rp "Usuario SMTP (empieza con ocid1.user...; usa una credencial propia del servicio, no la de Keycloak): " u
  SMTP_USER="$(limpiar "$u")"
  leer_secreto "Clave SMTP: "
  SMTP_PASS="$(limpiar "$V")"
  [ -n "$SMTP_USER" ] && [ -n "$SMTP_PASS" ] || { echo "Faltan el usuario o la clave SMTP." >&2; exit 1; }
fi

echo
echo "== Cliente de Keycloak (para leer y crear empresas desde sulotec.com/licencias)"
SECRETO=""
if docker ps --format '{{.Names}}' | grep -qx cuenta; then
  SECRETO="$(docker exec -i cuenta bash -s <<'EOF' 2>/dev/null || true
kc() { /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/lic.config; }
kc config credentials --server http://127.0.0.1:8080 --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null
cid=$(kc get clients -r sulotec -q clientId=licencias --fields id --format csv --noquotes | head -1)
[ -n "$cid" ] && kc get "clients/$cid/client-secret" -r sulotec --fields value --format csv --noquotes
rm -f /tmp/lic.config
EOF
)"
fi
SECRETO="$(limpiar "$SECRETO")"
if [ -n "$SECRETO" ]; then
  echo "   OK: clave del cliente 'licencias' tomada de Keycloak (no se muestra)"
else
  SECRETO="$(actual KEYCLOAK_CLIENT_SECRET)"
  if [ -n "$SECRETO" ]; then echo "   se conserva la clave guardada"; else echo "   AVISO: no encontre el cliente 'licencias' en Keycloak (publica apps/cuenta o corre ajustar-realm.sh); las empresas no se podran crear desde el portal hasta repetir preparar.sh"; fi
fi

install -m 640 -o root -g docker /dev/null "$ENV"
{
  echo "NODE_ENV=production"
  echo "PORT=3200"
  echo "DATABASE_URL=$DATABASE_URL"
  echo "KEYCLOAK_ISSUER=https://cuenta.sulotec.com/realms/sulotec"
  echo "KEYCLOAK_AUDIENCE=licencias"
  echo "ROL_UNIVERSAL=administrador-general"
  echo "KEYCLOAK_INTERNO=http://cuenta:8080"
  echo "KEYCLOAK_CLIENT_ID=licencias"
  echo "KEYCLOAK_CLIENT_SECRET=$SECRETO"
  echo "CORS_ORIGENES=https://sulotec.com,https://www.sulotec.com"
  echo "PORTAL_URL=https://sulotec.com"
  echo "SMTP_HOST=$SMTP_HOST"
  echo "SMTP_PORT=587"
  echo "SMTP_USER=$SMTP_USER"
  echo "SMTP_PASS=$SMTP_PASS"
  echo "CORREO_REMITENTE=Sulotec <no-reply@sulotec.com>"
  echo "CORREO_CONTACTO=contacto@sulotec.com"
  echo "ZONA_HORARIA=America/Lima"
  echo "TAREAS=1"
} > "$ENV"
echo
echo "Listo: $ENV guardado (permisos 640, grupo docker). Siguiente: sudo bash /data/apps/licencias/desplegar.sh"
