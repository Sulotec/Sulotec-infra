#!/usr/bin/env bash
# Pruebas de humo del Sistema de Planillas despues de publicar. No cambia nada ni usa cuentas reales.
#   sudo bash /data/apps/planilla/probar.sh
# Las pruebas de la direccion publica avisan (no fallan) si el tunel de Cloudflare todavia no tiene la ruta.
set -uo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ENVFILE=/opt/sulotec/planilla.env
leer() { grep -E "^$1=" "$ENVFILE" 2>/dev/null | head -1 | cut -d= -f2- || true; }
WEB_PUBLICA="${WEB_PUBLICA:-$(leer WEB_URL)}"; WEB_PUBLICA="${WEB_PUBLICA:-https://planilla.sulotec.com}"
fallos=0; avisos=0
ok()    { echo "  OK     $*"; }
falla() { echo "  FALLA  $*"; fallos=$((fallos+1)); }
aviso() { echo "  AVISO  $*"; avisos=$((avisos+1)); }
salud() { docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null || echo ninguno; }
codigo() { curl -s -m 15 -o /dev/null -w '%{http_code}' "$@" 2>/dev/null || true; }
dentro() { docker exec planilla curl -s -m 10 -o /dev/null -w '%{http_code}' "$@" 2>/dev/null || true; }

echo "== Contenedor"
if [ "$(salud planilla)" = healthy ]; then ok "planilla sano"; else falla "planilla no esta sano ($(salud planilla))"; fi

echo "== API por dentro"
if docker exec planilla curl -fsS http://127.0.0.1:8080/actuator/health 2>/dev/null | grep -q UP; then ok "/actuator/health: UP (la API ve la base)"; else falla "/actuator/health no responde UP (mira: docker logs planilla)"; fi
c="$(dentro http://127.0.0.1:8080/api/regimenes)"
if [ "$c" = 401 ]; then ok "la API exige sesion (401 sin token)"; else falla "/api/regimenes sin token respondio '$c' (se esperaba 401)"; fi
c="$(dentro -X POST http://127.0.0.1:8080/api/auth/login -H 'Content-Type: application/json' -d '{"username":"no.existe.prueba","password":"Clave-De-Prueba-123"}')"
if [ "$c" = 400 ]; then ok "login con un usuario inexistente responde 400"; else falla "login de prueba respondio '$c' (se esperaba 400)"; fi
c="$(dentro http://127.0.0.1:8080/login)"
if [ "$c" = 200 ]; then ok "la pantalla (Angular) sale del mismo contenedor"; else falla "/login respondio '$c' (¿la imagen no trae la pantalla?)"; fi

echo "== Datos"
if [ -r "$ENVFILE" ]; then
  MYSQL_PWD="$(leer DB_PASSWORD)"; export MYSQL_PWD
  for t in usuario regimen_laboral afp feriado concepto_remunerativo empleado boleta_pago; do
    n="$(docker run --rm --network sulotec_data -e MYSQL_PWD mysql:8.4 mysql -h "$(leer DB_HOST)" -P "$(leer DB_PORT)" -u"$(leer DB_USER)" -N -e "select count(*) from $t" "$(leer DB_NAME)" 2>/dev/null || echo '?')"
    if [ "$n" = '?' ]; then falla "no pude contar $t"; else ok "$t: $n filas"; fi
  done
  unset MYSQL_PWD
  if [ -n "$(leer ADMIN_PASSWORD)" ]; then aviso "ADMIN_PASSWORD sigue en $ENVFILE (desplegar.sh la borra cuando ya existe el usuario inicial)"; else ok "la clave inicial ya no esta en el archivo de configuracion"; fi
else
  aviso "no encuentro $ENVFILE; me salto el conteo de filas"
fi

echo "== Direccion publica (Cloudflare)"
c=$(codigo "$WEB_PUBLICA/login")
if [ "$c" != 200 ]; then
  aviso "$WEB_PUBLICA/login responde $c (¿falta la ruta del tunel, o Access pide iniciar sesion?)"
else
  propio="$(docker exec planilla curl -s -m 10 http://127.0.0.1:8080/ 2>/dev/null || true)"
  publico="$(curl -s -m 15 "$WEB_PUBLICA/" 2>/dev/null || true)"
  if [ -z "$propio" ]; then aviso "$WEB_PUBLICA responde, pero no pude leer la pantalla local para compararla"
  elif [ "$propio" = "$publico" ]; then ok "$WEB_PUBLICA sale de ESTE servidor"
  else aviso "$WEB_PUBLICA responde, pero NO es la pantalla de este servidor"; fi
  c=$(codigo "$WEB_PUBLICA/api/regimenes")
  if [ "$c" = 401 ]; then ok "la API publica exige sesion"; else aviso "$WEB_PUBLICA/api/regimenes sin token responde $c (se esperaba 401)"; fi
fi

echo
if [ "$fallos" -eq 0 ]; then echo "TODO BIEN ($avisos aviso(s))."; exit 0; fi
echo "$fallos prueba(s) fallaron."
exit 1
