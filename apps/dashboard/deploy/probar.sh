#!/usr/bin/env bash
# Pruebas de humo de Dashboard Empresarial despues de publicar. No cambia nada ni usa cuentas reales.
#   sudo bash /data/apps/dashboard/probar.sh
# Las pruebas de direcciones publicas avisan (no fallan) si el tunel de Cloudflare todavia no tiene las rutas.
set -uo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

API_PUBLICA="${API_PUBLICA:-https://api-dashboards.sulotec.com}"
WEB_PUBLICA="${WEB_PUBLICA:-https://dashboards.sulotec.com}"
ENVFILE=/opt/sulotec/dashboard.env
fallos=0
avisos=0
ok()    { echo "  OK     $*"; }
falla() { echo "  FALLA  $*"; fallos=$((fallos+1)); }
aviso() { echo "  AVISO  $*"; avisos=$((avisos+1)); }
salud() { docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null || echo ninguno; }
codigo() { curl -s -m 15 -o /dev/null -w '%{http_code}' "$@" 2>/dev/null || true; }
cabecera_cors() { curl -s -m 15 -D - -o /dev/null -X OPTIONS "$API_PUBLICA/auth/login" -H "Origin: $1" -H "Access-Control-Request-Method: POST" 2>/dev/null | tr -d '\r' | grep -i '^access-control-allow-origin:' | cut -d' ' -f2- || true; }

echo "== Contenedores"
for c in dashboard-api dashboard-web; do
  if [ "$(salud "$c")" = healthy ]; then ok "$c sano"; else falla "$c no esta sano ($(salud "$c"))"; fi
done

echo "== API por dentro"
if docker exec dashboard-api node -e "fetch('http://127.0.0.1:3100/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"; then
  ok "/health: la API ve la base de datos"
else
  falla "/health no responde bien (mira: docker logs dashboard-api)"
fi
# Un usuario que no existe debe dar 401: prueba que la ruta de login llega a la base y rechaza
cod="$(docker exec dashboard-api node -e "fetch('http://127.0.0.1:3100/auth/login',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({username:'no.existe.prueba',password:'Clave-De-Prueba-123!'})}).then(r=>console.log(r.status)).catch(()=>console.log('error'))" 2>/dev/null || true)"
if [ "$cod" = 401 ]; then ok "login con un usuario inexistente responde 401"; else falla "login de prueba respondio '$cod' (se esperaba 401)"; fi

echo "== Datos"
if [ -r "$ENVFILE" ]; then
  leer() { grep -E "^$1=" "$ENVFILE" | head -1 | cut -d= -f2- || true; }
  PGPASSWORD="$(leer DB_PASSWORD)"; export PGPASSWORD
  for t in 'comercial."Empresas"' 'seguridad."Usuarios"' 'reportes."Dashboards"' 'reportes."DashboardPeriodos"' 'comercial."EmpresaDashboards"'; do
    n="$(docker run --rm --network sulotec_data -e PGPASSWORD postgres:16 psql -h "$(leer DB_HOST)" -p "$(leer DB_PORT)" -U "$(leer DB_USER)" -d "$(leer DB_NAME)" -Atc "select count(*) from $t" 2>/dev/null || echo '?')"
    if [ "$n" = '?' ]; then falla "no pude contar $t (¿falta importar-datos.sh?)"; else ok "$t: $n filas"; fi
  done
  unset PGPASSWORD
else
  aviso "no encuentro $ENVFILE; me salto el conteo de filas"
fi

echo "== Direcciones publicas (Cloudflare)"
c=$(codigo "$API_PUBLICA/health")
if [ "$c" = 200 ]; then ok "$API_PUBLICA/health"; else aviso "$API_PUBLICA/health responde $c (¿falta la ruta del tunel?)"; fi
c=$(codigo "$WEB_PUBLICA/")
if [ "$c" != 200 ]; then
  aviso "$WEB_PUBLICA responde $c (¿falta la ruta del tunel?)"
else
  # Que responda no basta: se compara con lo que sirve el contenedor de este servidor.
  propio="$(docker exec dashboard-web node -e "fetch('http://127.0.0.1:3000/').then(r=>r.text()).then(t=>process.stdout.write(t))" 2>/dev/null || true)"
  publico="$(curl -s -m 15 "$WEB_PUBLICA/" 2>/dev/null || true)"
  if [ -z "$propio" ]; then aviso "$WEB_PUBLICA responde, pero no pude leer la web local para compararla"
  elif [ "$propio" = "$publico" ]; then ok "$WEB_PUBLICA sale de ESTE servidor"
  else aviso "$WEB_PUBLICA responde, pero NO es la web de este servidor"; fi
fi
permitido="$(cabecera_cors "$WEB_PUBLICA")"
if [ "$permitido" = "$WEB_PUBLICA" ]; then ok "CORS: la web puede llamar a la API"; else aviso "CORS no devuelve el origen de la web (valor: '${permitido:-ninguno}')"; fi
ajeno="$(cabecera_cors "https://sitio-ajeno.example")"
if [ -z "$ajeno" ]; then ok "CORS: un sitio ajeno NO puede llamar a la API"; else falla "CORS permite un origen ajeno: $ajeno"; fi

echo
if [ "$fallos" -eq 0 ]; then echo "TODO BIEN ($avisos aviso(s))."; exit 0; fi
echo "$fallos prueba(s) fallaron."
exit 1
