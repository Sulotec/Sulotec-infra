#!/usr/bin/env bash
# Pruebas de humo de Auditoria de Visitas despues de publicar. No cambia nada ni sube datos reales.
#   sudo bash /data/apps/auditoria/probar.sh
# Las pruebas de direcciones publicas avisan (no fallan) si el tunel de Cloudflare todavia no tiene las rutas.
set -uo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

API_PUBLICA="${API_PUBLICA:-https://api-auditoria.sulotec.com}"
WEB_PUBLICA="${WEB_PUBLICA:-https://auditoria.sulotec.com}"
fallos=0
avisos=0
ok()    { echo "  OK     $*"; }
falla() { echo "  FALLA  $*"; fallos=$((fallos+1)); }
aviso() { echo "  AVISO  $*"; avisos=$((avisos+1)); }
salud() { docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null || echo ninguno; }
codigo() { curl -s -m 15 -o /dev/null -w '%{http_code}' "$@" 2>/dev/null || true; }
cabecera_cors() { curl -s -m 15 -D - -o /dev/null -X OPTIONS "$API_PUBLICA/api/auth/login" -H "Origin: $1" -H "Access-Control-Request-Method: POST" 2>/dev/null | tr -d '\r' | grep -i '^access-control-allow-origin:' | cut -d' ' -f2- || true; }

echo "== Contenedores"
for c in auditoria-api auditoria-web; do
  if [ "$(salud "$c")" = healthy ]; then ok "$c sano"; else falla "$c no esta sano ($(salud "$c"))"; fi
done

echo "== API por dentro"
if docker exec auditoria-api node -e "fetch('http://127.0.0.1:'+(process.env.PORT||4100)+'/health/ready').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"; then
  ok "/health/ready: la API ve la base de datos"
else
  falla "/health/ready no responde bien (mira: docker logs auditoria-api)"
fi

echo "== Almacenamiento de fotos (bucket de Oracle)"
if docker exec auditoria-api node scripts/probar-almacenamiento.js > /tmp/probar-almacenamiento.log 2>&1; then
  ok "subir, verificar, leer y borrar una foto de prueba; el bucket no es publico"
else
  falla "el almacenamiento no funciona. Detalle:"
  tail -12 /tmp/probar-almacenamiento.log | sed 's/^/         /'
fi

echo "== Direcciones publicas (Cloudflare)"
c=$(codigo "$API_PUBLICA/health/live")
if [ "$c" = 200 ]; then ok "$API_PUBLICA/health/live"; else aviso "$API_PUBLICA/health/live responde $c (¿falta la ruta del tunel?)"; fi
c=$(codigo "$WEB_PUBLICA/")
if [ "$c" != 200 ]; then
  aviso "$WEB_PUBLICA responde $c (¿falta la ruta del tunel?)"
else
  # Que responda no basta: se compara con lo que sirve el contenedor de este servidor.
  propio="$(docker exec auditoria-web wget -qO- http://127.0.0.1:8080/ 2>/dev/null || true)"
  publico="$(curl -s -m 15 "$WEB_PUBLICA/" 2>/dev/null || true)"
  if [ -z "$propio" ]; then aviso "$WEB_PUBLICA responde, pero no pude leer la web local para compararla"
  elif [ "$propio" = "$publico" ]; then ok "$WEB_PUBLICA sale de ESTE servidor"
  else aviso "$WEB_PUBLICA responde, pero NO es la web de este servidor"; fi
  c=$(codigo "$WEB_PUBLICA/privacidad")
  if [ "$c" = 200 ]; then ok "politica de privacidad ($WEB_PUBLICA/privacidad)"; else aviso "politica de privacidad responde $c"; fi
fi
permitido="$(cabecera_cors "$WEB_PUBLICA")"
if [ "$permitido" = "$WEB_PUBLICA" ]; then ok "CORS: el panel puede llamar a la API"; else aviso "CORS no devuelve el origen del panel (valor: '${permitido:-ninguno}')"; fi
ajeno="$(cabecera_cors "https://sitio-ajeno.example")"
if [ -z "$ajeno" ]; then ok "CORS: un sitio ajeno NO puede llamar a la API"; else falla "CORS permite un origen ajeno: $ajeno"; fi

echo
if [ "$fallos" -eq 0 ]; then echo "TODO BIEN ($avisos aviso(s))."; exit 0; fi
echo "$fallos prueba(s) fallaron."
exit 1
