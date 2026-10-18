#!/usr/bin/env bash
# Primera instalacion de Dashboard Empresarial en el servidor, de principio a fin y SIN preguntas: ninguna clave pasa por la pantalla.
#   sudo bash instalar.sh revisar     solo MIRA el servidor (no cambia nada)
#   sudo bash instalar.sh             instala: copia el kit, crea la base y la configuracion, publica y crea las tablas (vacias)
# Se puede repetir: lo que ya existe se conserva. NO toca ningun otro contenedor, base ni ruta del servidor.
# Despues faltan (a mano): las dos rutas en el tunel de Cloudflare, cargar los datos (importar-datos.sh) y crear-admin.sh.
set -euo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REPO_INFRA="${REPO_INFRA:-https://github.com/Sulotec/Sulotec-infra.git}"
RAW_BACKEND="${RAW_BACKEND:-https://raw.githubusercontent.com/Henry-InformaPeru/dashboard-empresarial-backend}"
BASE=/opt/sulotec
APP=/data/apps/dashboard
ENVF=$BASE/dashboard.env
WEB_URL="${WEB_URL:-https://dashboards.sulotec.com}"
MODO="${1:-instalar}"

[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0 $*" >&2; exit 1; }
case "$MODO" in revisar|instalar) ;; *) echo "uso: sudo bash $0 [revisar]" >&2; exit 1 ;; esac

pg() { (cd "$BASE" && docker compose exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 "$@"); }

echo "== Revision (solo lectura)"
echo "   Contenedores corriendo:"; docker ps --format '     {{.Names}}  {{.Status}}'
echo "   Memoria:"; free -h | sed -n 1,2p | sed 's/^/     /'
echo "   Disco /data:"; df -h /data | tail -1 | sed 's/^/     /'
faltan=0
for red in sulotec_edge sulotec_data; do
  if docker network inspect "$red" >/dev/null 2>&1; then echo "   red $red: existe"; else echo "   red $red: NO EXISTE" >&2; faltan=1; fi
done
echo "   Bases de PostgreSQL:"; pg -Atc "select datname from pg_database where not datistemplate order by 1" | sed 's/^/     /'
echo "   Roles de PostgreSQL:"; pg -Atc "select rolname from pg_roles where rolname !~ '^pg_' order by 1" | sed 's/^/     /'
echo "   Ya hay algo de dashboard?  carpeta: $([ -d "$APP" ] && echo si || echo no)   configuracion: $([ -f "$ENVF" ] && echo si || echo no)   contenedores: $(docker ps -a --format '{{.Names}}' | grep -c '^dashboard-' || true)"
[ "$faltan" -eq 0 ] || { echo "Faltan redes del servidor: no sigo." >&2; exit 1; }
[ "$MODO" = instalar ] || { echo; echo "Solo revision: no se cambio nada."; exit 0; }

echo
echo "== 1. Kit en $APP"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git clone -q --depth 1 "$REPO_INFRA" "$TMP/infra"
mkdir -p "$APP"
cp "$TMP/infra/apps/dashboard/docker-compose.yml" "$TMP/infra/apps/dashboard/deploy/"*.sh "$APP/"
echo "   copiado: $(ls "$APP" | tr '\n' ' ')"

echo "== 2. Base y configuracion"
if [ -f "$ENVF" ]; then
  echo "   $ENVF ya existe: se conserva"
else
  if [ -n "$(pg -Atc "select 1 from pg_database where datname='dashboard'")" ]; then
    echo "La base 'dashboard' ya existe pero falta $ENVF: no puedo recuperar su clave. Mira «Rotar claves» en el README." >&2; exit 1
  fi
  salida="$("$BASE/scripts/new-project-db.sh" postgres dashboard)"
  cadena="$(printf '%s\n' "$salida" | sed -n 's/^  Node : //p')"
  [ -n "$cadena" ] || { echo "No pude leer la cadena de la base nueva." >&2; exit 1; }
  CADENA="$cadena" WEB_URL="$WEB_URL" bash "$APP/preparar.sh" | sed 's#postgresql://[^ ]*#postgresql://***#'
  unset salida cadena
fi

echo "== 3. Publicar"
# Hasta que se unan los Pull Requests, el codigo nuevo vive en las ramas feature/*; con la rama main lista se usa main.
if [ -z "${RAMA_BACKEND:-}" ]; then
  if curl -fsI "$RAW_BACKEND/main/db/schema.sql" >/dev/null 2>&1; then RAMA_BACKEND=main; else RAMA_BACKEND=feature/oracle-postgres; fi
fi
if [ -z "${RAMA_FRONTEND:-}" ]; then
  if curl -fsI "https://raw.githubusercontent.com/Henry-InformaPeru/dashboard-empresarial-frontend/main/Dockerfile" >/dev/null 2>&1; then RAMA_FRONTEND=main; else RAMA_FRONTEND=feature/oracle-docker; fi
fi
echo "   ramas: backend=$RAMA_BACKEND  web=$RAMA_FRONTEND"
RAMA_BACKEND="$RAMA_BACKEND" RAMA_FRONTEND="$RAMA_FRONTEND" bash "$APP/desplegar.sh"

echo "== 4. Tablas (vacias)"
SOLO_ESQUEMA=1 bash "$APP/importar-datos.sh"

echo
echo "Listo en el servidor. Faltan: rutas del tunel en Cloudflare, cargar los datos (importar-datos.sh) y crear-admin.sh."
