#!/usr/bin/env bash
# Pruebas de humo del servicio de licencias despues de publicar. No cambia nada.
#   sudo bash /data/apps/licencias/probar.sh
# La prueba de la direccion publica avisa (no falla) si el tunel de Cloudflare todavia no tiene la ruta.
set -uo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

API_PUBLICA="${API_PUBLICA:-https://api-licencias.sulotec.com}"
ENVFILE=/opt/sulotec/licencias.env
fallos=0
avisos=0
ok()    { echo "  OK     $*"; }
falla() { echo "  FALLA  $*"; fallos=$((fallos+1)); }
aviso() { echo "  AVISO  $*"; avisos=$((avisos+1)); }
salud() { docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null || echo ninguno; }
dentro() { docker exec licencias node -e "fetch('http://127.0.0.1:3200$1',{method:'${2:-GET}'}).then(r=>{console.log(r.status)}).catch(()=>console.log('000'))" 2>/dev/null || echo 000; }

echo "== Contenedor"
if [ "$(salud licencias)" = healthy ]; then ok "licencias sano"; else falla "licencias no esta sano ($(salud licencias))"; fi

echo "== Servicio por dentro"
cod="$(dentro /health)"
if [ "$cod" = 200 ]; then ok "/health: el servicio ve la base"; else falla "/health respondio '$cod' (mira: docker logs licencias)"; fi
cod="$(dentro /v1/licencias/00000000-0000-0000-0000-000000000000)"
if [ "$cod" = 401 ]; then ok "sin token de producto responde 401"; else falla "sin token respondio '$cod' (se esperaba 401)"; fi
cod="$(dentro /v1/admin/planes)"
if [ "$cod" = 401 ]; then ok "sin sesion de persona responde 401"; else falla "/v1/admin sin sesion respondio '$cod' (se esperaba 401)"; fi

echo "== Datos"
if [ -r "$ENVFILE" ]; then
  URL="$(grep -E '^DATABASE_URL=' "$ENVFILE" | head -1 | cut -d= -f2-)"
  consulta() { docker run --rm --network sulotec_data postgres:16 psql "$URL" -Atc "$1" 2>/dev/null || echo '?'; }
  n="$(consulta 'select count(*) from productos')"
  if [ "$n" = 5 ]; then ok "productos: 5 registrados"; else falla "productos: '$n' (se esperaban 5; ¿arranco el servicio?)"; fi
  echo "  INFO   licencias: $(consulta 'select count(*) from licencias') · planes: $(consulta 'select count(*) from planes')"
  sin="$(consulta "select string_agg(clave, ', ') from productos where token_hash is null")"
  if [ -n "$sin" ] && [ "$sin" != '?' ]; then aviso "productos sin token todavia: $sin (sudo docker exec licencias node scripts/token-producto.js <clave>)"; else ok "todos los productos tienen token"; fi
  if grep -qE '^SMTP_HOST=.+' "$ENVFILE"; then ok "correo de salida configurado"; else aviso "sin correo de salida: los avisos solo quedan en el log (preparar.sh)"; fi
  if grep -qE '^KEYCLOAK_CLIENT_SECRET=.+' "$ENVFILE"; then ok "cliente de Keycloak configurado (empresas desde el portal)"; else aviso "sin clave del cliente de Keycloak: repite preparar.sh despues de publicar apps/cuenta"; fi
else
  aviso "no encuentro $ENVFILE; me salto las pruebas de datos"
fi

echo "== Direccion publica"
cod="$(curl -s -m 15 -o /dev/null -w '%{http_code}' "$API_PUBLICA/health" 2>/dev/null || true)"
if [ "$cod" = 200 ]; then ok "$API_PUBLICA/health responde"; else aviso "$API_PUBLICA/health respondio '$cod': agrega en Cloudflare la ruta api-licencias.sulotec.com -> http://licencias:3200"; fi
cors="$(curl -s -m 15 -D - -o /dev/null -X OPTIONS "$API_PUBLICA/v1/mi-licencia" -H "Origin: https://sulotec.com" -H "Access-Control-Request-Method: GET" 2>/dev/null | tr -d '\r' | grep -i '^access-control-allow-origin' || true)"
if [ -n "$cors" ]; then ok "el portal (sulotec.com) puede llamar al servicio"; else aviso "sin respuesta CORS para sulotec.com (normal si la ruta publica aun no existe)"; fi

echo
echo "Resultado: $fallos fallas, $avisos avisos"
[ "$fallos" -eq 0 ]
