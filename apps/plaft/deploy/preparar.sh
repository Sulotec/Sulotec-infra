#!/usr/bin/env bash
# Crea o actualiza la configuracion de PLAFT en el servidor: /opt/sulotec/plaft.env (solo root y el grupo docker la leen).
# Volver a correrlo conserva lo que ya existe (Enter) y no cambia las claves generadas.
#   sudo bash /data/apps/plaft/preparar.sh
# Antes:
#   1) sudo /opt/sulotec/scripts/new-project-db.sh mysql plaft     (crea la base y el usuario "plaft")
#   2) sudo bash /data/apps/plaft/crear-llave-oci.sh                (llave del bucket plaft-archivos)
# Variables solo para pruebas: ENVFILE, OCI_DIR, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

ENV="${ENVFILE:-/opt/sulotec/plaft.env}"
OCI_DIR="${OCI_DIR:-/opt/sulotec/plaft-oci}"
mkdir -p "$(dirname "$ENV")"

limpiar() { local v="$1"; v="${v//$'\e'\[200~/}"; v="${v//$'\e'\[201~/}"; v="${v//\[200~/}"; v="${v//\[201~/}"; printf '%s' "${v//[[:space:]]/}"; }
actual() { [ -f "$ENV" ] && grep -E "^$1=" "$ENV" | head -1 | cut -d= -f2- || true; }
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
# pregunta VARIABLE "texto" [por_defecto]  -> deja el resultado en $R
pregunta() {
  local var="$1" texto="$2" def="${3:-}" act v
  act="$(actual "$var")"; [ -n "$act" ] && def="$act"
  read -rp "$texto [Enter = ${def:-vacio}]: " v
  v="$(limpiar "${v:-}")"; R="${v:-$def}"
}
aleatorio() { openssl rand -hex "${1:-32}"; }
# 12 caracteres (el login del backend acepta de 8 a 12): letras y numeros
clave_admin() { local c; while :; do c="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 12)"; [[ "$c" =~ [a-z] && "$c" =~ [A-Z] && "$c" =~ [0-9] ]] && { printf '%s' "$c"; return; }; done; }

echo "== Base de datos (MySQL de la VM, base y usuario 'plaft')"
echo "   Pega la clave que mostro new-project-db.sh. Saldran asteriscos."
act_pass="$(actual DB_PASSWORD)"
leer_secreto "Clave del usuario plaft [Enter = $([ -n "$act_pass" ] && echo conservar || echo vacio)]: "
DBPASS="$(limpiar "${V:-}")"; DBPASS="${DBPASS:-$act_pass}"
[ -n "$DBPASS" ] || { echo "Hace falta la clave de la base." >&2; exit 1; }
echo "   recibido: clave de ${#DBPASS} caracteres"
if [ -z "${PRUEBA:-}" ]; then
  tablas="$(docker run --rm --network sulotec_data -e MYSQL_PWD="$DBPASS" mysql:8.4 mysql -h mysql -uplaft -N -e "select count(*) from information_schema.tables where table_schema='plaft'" plaft 2>/dev/null || true)"
  [ -n "$tablas" ] || { echo "No pude entrar a la base 'plaft' con esa clave. ¿Corriste new-project-db.sh mysql plaft y pegaste la clave completa?" >&2; exit 1; }
  echo "   OK: la clave funciona (la base tiene $tablas tablas)"
else
  tablas=0
fi

echo "== Direcciones"
pregunta WEB_URL "Direccion de la web (sin barra final)" "https://plaft.sulotec.com"; WEB="$R"
echo "== Administrador inicial"
if [ "$tablas" = "0" ] && [ -z "$(actual APP_SEED_ADMIN_PASSWORD)" ] && [ "$(actual APP_SEED_ENABLED)" != "false" ]; then
  SEMILLA=true; ADMIN_PASS="$(clave_admin)"; GENERADA=1
  echo "   Base nueva: se crean los roles, los catalogos y el usuario 'superadmin' (la clave se muestra al final, una sola vez)."
elif [ "$(actual APP_SEED_ENABLED)" = "true" ]; then
  SEMILLA=true; ADMIN_PASS="$(actual APP_SEED_ADMIN_PASSWORD)"
  echo "   La semilla inicial sigue pendiente (se apaga sola despues del primer arranque sano)."
else
  SEMILLA=false; ADMIN_PASS=""
  echo "   La base ya tiene datos: no se crea ningun usuario inicial."
fi
pregunta APP_SEED_ADMIN_EMAIL "Correo del administrador inicial" "serviciosdigitales@informaperu.com"; ADMIN_MAIL="$R"

if [ ! -f "$OCI_DIR/config" ] || [ ! -f "$OCI_DIR/key.pem" ]; then
  echo "Falta la llave de Oracle en $OCI_DIR. Primero corre:  sudo bash /data/apps/plaft/crear-llave-oci.sh" >&2
  exit 1
fi

JWT="$(actual JWT_SECRET)"; [ -n "$JWT" ] || JWT="$(aleatorio 32)"
MLKEY="$(actual ML_API_KEY)"; [ -n "$MLKEY" ] || MLKEY="$(aleatorio 24)"
MLT="$(actual ML_CHATTIMEOUTSECONDS)"      # lo pone activar-indira.sh (cuanto espera el backend a Indira); se conserva

install -m 640 -o root -g docker /dev/null "$ENV" 2>/dev/null || install -m 640 /dev/null "$ENV"
{
  echo "# Generado por deploy/preparar.sh. Secretos: no subir a ningun repositorio."
  echo "DB_URL=jdbc:mysql://mysql:3306/plaft?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true"
  echo "DB_USER=plaft"
  echo "DB_PASSWORD=$DBPASS"
  echo "JWT_SECRET=$JWT"
  echo "CORS_ALLOWED_ORIGINS=$WEB"
  echo "WEB_URL=$WEB"
  echo "ML_BASE_URL=http://plaft-ml:8000"
  echo "ML_API_KEY=$MLKEY"
  [ -z "$MLT" ] || echo "ML_CHATTIMEOUTSECONDS=$MLT"
  echo "STORAGE_PROVIDER=oracle"
  echo "OCI_REGION=sa-santiago-1"
  echo "OCI_NAMESPACE=axkjo5bh8iys"
  echo "OCI_BUCKET=plaft-archivos"
  echo "OCI_AUTH_MODE=CONFIG_FILE"
  echo "OCI_CONFIG_FILE=/run/oci/config"
  echo "OCI_PROFILE=DEFAULT"
  echo "APP_SEED_ENABLED=$SEMILLA"
  echo "APP_SEED_ADMIN_USER=superadmin"
  echo "APP_SEED_ADMIN_PASSWORD=$ADMIN_PASS"
  echo "APP_SEED_ADMIN_EMAIL=$ADMIN_MAIL"
  echo "# Endurecimiento: sin documentacion publica de la API, solo /actuator/health, sin SQL en los registros"
  echo "SPRINGDOC_API_DOCS_ENABLED=false"
  echo "SPRINGDOC_SWAGGER_UI_ENABLED=false"
  echo "MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE=health"
  echo "SPRING_JPA_SHOW_SQL=false"
  echo "SPRING_JPA_PROPERTIES_HIBERNATE_FORMAT_SQL=false"
  echo "TZ=America/Lima"
} > "$ENV"

echo
echo "Configuracion guardada en $ENV"
if [ "${GENERADA:-}" = 1 ]; then
  echo
  echo "CLAVE DEL ADMINISTRADOR (se muestra UNA sola vez; guardala en el gestor de contrasenas):"
  echo "   usuario: superadmin"
  echo "   clave:   $ADMIN_PASS"
fi
echo "Siguiente: sudo bash /data/apps/plaft/desplegar.sh"
