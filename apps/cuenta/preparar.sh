#!/usr/bin/env bash
# Prepara y levanta cuenta.sulotec.com (Keycloak) en el servidor.
#   sudo bash /data/apps/cuenta/preparar.sh
# Primera vez:
#   - crea la base "keycloak" en PostgreSQL con una clave aleatoria que nadie ve,
#   - crea el administrador temporal "admin-temporal" y muestra su clave UNA vez,
#   - guarda todo en /opt/sulotec/cuenta.env (solo root y el grupo docker) y levanta el contenedor.
# Volver a correrlo no cambia la base ni el administrador; sirve para configurar el correo (SMTP).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

ENV=/opt/sulotec/cuenta.env
APP=/data/apps/cuenta
aleatoria() { openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | head -c "$1"; }
# Quita lo que agrega el "pegado" de la terminal del navegador ([200~ ... [201~) y los espacios
limpiar() { local v="$1"; v="${v//$'\e'\[200~/}"; v="${v//$'\e'\[201~/}"; v="${v//\[200~/}"; v="${v//\[201~/}"; printf '%s' "${v//[[:space:]]/}"; }
guardar() {
  local clave="$1" valor="$2"
  sed -i "/^$clave=/d" "$ENV"
  printf "%s='%s'\n" "$clave" "$valor" >> "$ENV"
}
[ -f "$APP/docker-compose.yml" ] || { echo "Falta $APP: primero se publica desde GitHub (workflow 'Publicar cuenta')." >&2; exit 1; }

if [ -f "$ENV" ]; then
  echo "Ya existe $ENV: se conservan la base y el administrador."
  set -a; . "$ENV"; set +a
else
  echo "Creando la base 'keycloak' en PostgreSQL..."
  db_clave="$(aleatoria 32)"
  cd /opt/sulotec
  docker compose exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 -q <<SQL
DO \$\$ BEGIN
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'keycloak') THEN
    ALTER ROLE keycloak LOGIN PASSWORD '$db_clave';
  ELSE
    CREATE ROLE keycloak LOGIN PASSWORD '$db_clave';
  END IF;
END \$\$;
SQL
  docker compose exec -T postgres psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname = 'keycloak'" | grep -q 1 \
    || docker compose exec -T postgres psql -U postgres -q -c 'CREATE DATABASE keycloak OWNER keycloak'
  docker compose exec -T postgres psql -U postgres -q -c 'REVOKE ALL ON DATABASE keycloak FROM PUBLIC'

  install -m 640 -o root -g docker /dev/null "$ENV"
  KC_BOOTSTRAP_ADMIN_USERNAME=admin-temporal
  KC_BOOTSTRAP_ADMIN_PASSWORD="$(aleatoria 24)"
  guardar KC_DB_PASSWORD "$db_clave"
  guardar KC_BOOTSTRAP_ADMIN_USERNAME "$KC_BOOTSTRAP_ADMIN_USERNAME"
  guardar KC_BOOTSTRAP_ADMIN_PASSWORD "$KC_BOOTSTRAP_ADMIN_PASSWORD"
  echo
  echo "=================================================================="
  echo " Administrador temporal de cuenta.sulotec.com"
  echo "   usuario: $KC_BOOTSTRAP_ADMIN_USERNAME"
  echo "   clave:   $KC_BOOTSTRAP_ADMIN_PASSWORD"
  echo " Guardala en el gestor de contrasenas de la empresa. NO la pegues en chats."
  echo " Si la pierdes: sudo grep ADMIN $ENV"
  echo "=================================================================="
  echo
fi

smtp=""
read -rp "¿Configurar ahora el correo de salida (SMTP de OCI Email Delivery)? [s/N] " r
if [[ "$r" =~ ^[sS]$ ]]; then
  read -rp "Servidor SMTP (ej. smtp.email.sa-santiago-1.oci.oraclecloud.com): " h
  read -rp "Usuario SMTP (empieza con ocid1.user...): " u
  read -rsp "Clave SMTP (no se muestra al pegarla): " p; echo
  # No se guardan en cuenta.env: Keycloak las guarda en su base al configurar el realm
  KC_SMTP_HOST="$(limpiar "$h")"; KC_SMTP_USER="$(limpiar "$u")"; KC_SMTP_PASSWORD="$(limpiar "$p")"
  export KC_SMTP_HOST KC_SMTP_USER KC_SMTP_PASSWORD KC_BOOTSTRAP_ADMIN_USERNAME KC_BOOTSTRAP_ADMIN_PASSWORD
  smtp=1
fi

echo "Levantando cuenta.sulotec.com..."
cd "$APP"
docker compose up -d
for _ in $(seq 1 40); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' cuenta 2>/dev/null)" = healthy ] && break
  sleep 6
done
[ "$(docker inspect -f '{{.State.Health.Status}}' cuenta)" = healthy ] || { docker logs --tail 40 cuenta; echo "Keycloak no arranco." >&2; exit 1; }
echo "Keycloak esta listo."

if [ -n "$smtp" ]; then
  echo "Configurando el correo del realm 'sulotec'..."
  docker exec -e KC_SMTP_HOST -e KC_SMTP_USER -e KC_SMTP_PASSWORD -e KC_BOOTSTRAP_ADMIN_USERNAME -e KC_BOOTSTRAP_ADMIN_PASSWORD cuenta bash -c '
    k=/opt/keycloak/bin/kcadm.sh; c="--config /tmp/kcadm.config"
    $k config credentials $c --server http://127.0.0.1:8080 --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null
    $k update realms/sulotec $c -s smtpServer.host="$KC_SMTP_HOST" -s smtpServer.port=587 -s smtpServer.starttls=true \
      -s smtpServer.auth=true -s smtpServer.user="$KC_SMTP_USER" -s smtpServer.password="$KC_SMTP_PASSWORD" \
      -s smtpServer.from=no-reply@sulotec.com -s smtpServer.fromDisplayName=Sulotec
    rm -f /tmp/kcadm.config'
  echo "Correo configurado. Pruebalo en la consola: Configuracion del realm > Correo electronico > Probar conexion."
fi
echo "Listo."
