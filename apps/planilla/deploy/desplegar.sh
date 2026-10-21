#!/usr/bin/env bash
# Publica el Sistema de Planillas: baja el codigo (backend y pantalla), construye UNA imagen, la levanta y espera a que este sana.
# Si la version nueva no arranca, vuelve a la anterior. Se puede repetir las veces que haga falta:
#   sudo bash /data/apps/planilla/desplegar.sh
# Para probar una rama antes de unirla a main:
#   RAMA_BACKEND=mi-rama RAMA_FRONTEND=mi-rama sudo -E bash /data/apps/planilla/desplegar.sh
# La primera vez tarda varios minutos (compila Angular y Maven en el servidor).
# Tras el primer arranque con base nueva, cuando ya existe el usuario inicial, borra su clave del archivo de configuracion.
set -euo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REPO_BACKEND="${REPO_BACKEND:-https://github.com/Jeliases/PlanillaBackend.git}"
REPO_FRONTEND="${REPO_FRONTEND:-https://github.com/jeliases-informaDev/PlanillaFrontEd.git}"
RAMA_BACKEND="${RAMA_BACKEND:-main}"
RAMA_FRONTEND="${RAMA_FRONTEND:-main}"
APP=/data/apps/planilla
ENVFILE=/opt/sulotec/planilla.env
CONTENEDOR=planilla

[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }
[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE: primero corre preparar.sh" >&2; exit 1; }
[ -f "$APP/docker-compose.yml" ] && [ -f "$APP/Dockerfile" ] || { echo "Faltan $APP/docker-compose.yml o $APP/Dockerfile: primero copia el kit desde GitHub (apps/planilla)." >&2; exit 1; }

salud() { docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null || echo ninguno; }
leer() { grep -E "^$1=" "$ENVFILE" | head -1 | cut -d= -f2- || true; }
poner() { grep -q "^$1=" "$ENVFILE" && sed -i "s|^$1=.*|$1=$2|" "$ENVFILE" || echo "$1=$2" >> "$ENVFILE"; }

# Baja o actualiza un repositorio y devuelve el commit. $1 = carpeta, $2 = url, $3 = rama
bajar() {
  if [ -d "$1/.git" ]; then git -C "$1" fetch -q origin "$3"; else git clone -q "$2" "$1"; git -C "$1" fetch -q origin "$3"; fi
  git -C "$1" reset -q --hard "origin/$3"
  git -C "$1" rev-parse --short=12 HEAD
}

echo "== Codigo"
cb=$(bajar "$APP/backend"  "$REPO_BACKEND"  "$RAMA_BACKEND")
cf=$(bajar "$APP/frontend" "$REPO_FRONTEND" "$RAMA_FRONTEND")
echo "   backend $RAMA_BACKEND @ $cb   pantalla $RAMA_FRONTEND @ $cf"
[ -f "$APP/backend/pom.xml" ] || { echo "El backend de esa rama no tiene pom.xml" >&2; exit 1; }
[ -f "$APP/frontend/angular.json" ] || { echo "La pantalla de esa rama no tiene angular.json" >&2; exit 1; }
[ -f "$APP/frontend/src/environments/environment.production.ts" ] || { echo "La pantalla de esa rama no trae src/environments/environment.production.ts (¿falta unir el cambio a la rama?)" >&2; exit 1; }

version="$cb-$cf"
echo "== Construyendo la imagen planilla:$version (la primera vez tarda varios minutos)"
docker build -q -t "planilla:$version" -f "$APP/Dockerfile" "$APP" >/dev/null

anterior=$(docker image inspect -f '{{.Id}}' planilla:latest 2>/dev/null || true)
docker tag "planilla:$version" planilla:latest

echo "== Levantando"
(cd "$APP" && docker compose up -d --force-recreate)

for _ in $(seq 1 60); do [ "$(salud $CONTENEDOR)" = healthy ] && break; sleep 3; done
if [ "$(salud $CONTENEDOR)" != healthy ]; then
  echo "== La version nueva NO arranco bien. Ultimas lineas:" >&2
  docker logs --tail 40 $CONTENEDOR >&2 || true
  if [ -n "$anterior" ]; then
    echo "== Volviendo a la version anterior" >&2
    docker tag "$anterior" planilla:latest
    (cd "$APP" && docker compose up -d --force-recreate)
  fi
  exit 1
fi
echo "   $CONTENEDOR: sano"

# Primer arranque con base nueva: cuando ya existe el usuario inicial, su clave se borra del archivo (solo sirve una vez)
if [ -n "$(leer ADMIN_PASSWORD)" ]; then
  dbpass="$(leer DB_PASSWORD)"; dbuser="$(leer DB_USER)"; dbname="$(leer DB_NAME)"
  usuarios=0
  for _ in $(seq 1 20); do
    usuarios="$(MYSQL_PWD="$dbpass" docker run --rm --network sulotec_data -e MYSQL_PWD mysql:8.4 mysql -h "$(leer DB_HOST)" -P "$(leer DB_PORT)" -u"$dbuser" -N -e 'select count(*) from usuario' "$dbname" 2>/dev/null || echo 0)"
    [ "${usuarios:-0}" -ge 1 ] 2>/dev/null && break
    sleep 3
  done
  if [ "${usuarios:-0}" -ge 1 ] 2>/dev/null; then
    poner ADMIN_PASSWORD ""
    echo "   usuario inicial creado: la clave inicial ya no esta en $ENVFILE (si se pierde: resetear-clave.sh admin)"
  else
    echo "AVISO: no vi usuarios en la base; dejo ADMIN_PASSWORD en $ENVFILE. Revisa: docker logs planilla" >&2
  fi
fi

# Conserva las 3 ultimas versiones de la imagen por si hay que volver atras a mano
docker images planilla --format '{{.Tag}}' | grep -v '^latest$' | tail -n +4 | xargs -r -I{} docker rmi -f "planilla:{}" >/dev/null 2>&1 || true
echo "Listo: Sistema de Planillas publicado (backend $cb, pantalla $cf)."
echo "Siguiente: sudo bash /data/apps/planilla/probar.sh"
