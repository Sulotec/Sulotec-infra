#!/usr/bin/env bash
# Pruebas de humo de PLAFT despues de publicar. No cambia nada ni sube datos reales (el archivo de prueba se borra).
#   sudo bash /data/apps/plaft/probar.sh
# Las pruebas de direcciones publicas avisan (no fallan) si el tunel de Cloudflare todavia no tiene las rutas.
set -uo pipefail
export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True

API_PUBLICA="${API_PUBLICA:-https://api-plaft.sulotec.com}"
WEB_PUBLICA="${WEB_PUBLICA:-https://plaft.sulotec.com}"
OCI_DIR="${OCI_DIR:-/opt/sulotec/plaft-oci}"
NS="${OCI_NAMESPACE:-axkjo5bh8iys}"; BUCKET="${OCI_BUCKET:-plaft-archivos}"; REGION="${OCI_REGION:-sa-santiago-1}"
fallos=0; avisos=0
ok()    { echo "  OK     $*"; }
falla() { echo "  FALLA  $*"; fallos=$((fallos+1)); }
aviso() { echo "  AVISO  $*"; avisos=$((avisos+1)); }
salud() { docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null || echo ninguno; }
codigo() { curl -s -m 15 -o /dev/null -w '%{http_code}' "$@" 2>/dev/null || true; }
interno() { docker exec plaft-api wget -q -S -O /dev/null "http://127.0.0.1:8081$1" 2>&1 | awk '/HTTP\//{c=$2} END{print c+0}'; }
TMP="$(mktemp -d)"; trap '[ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"' EXIT

echo "== Contenedores"
for c in plaft-api plaft-web; do
  if [ "$(salud "$c")" = healthy ]; then ok "$c sano"; else falla "$c no esta sano ($(salud "$c"))"; fi
done

echo "== API por dentro"
if docker exec plaft-api wget -qO- http://127.0.0.1:8081/actuator/health 2>/dev/null | grep -q UP; then ok "/actuator/health: la API y su base de datos responden"; else falla "/actuator/health no responde UP (mira: docker logs plaft-api)"; fi
for ruta in /swagger-ui.html /v3/api-docs /actuator/metrics /actuator/env; do
  c="$(interno "$ruta")"
  if [ "$c" = 200 ]; then falla "$ruta es PUBLICA (responde 200): no debe estarlo"; else ok "$ruta cerrada (responde $c)"; fi
done
c="$(docker exec plaft-api wget -q -S -O /dev/null --header 'Content-Type: application/json' --post-data '{"usuario":"noexiste01","clave":"xxxxxxxx01"}' http://127.0.0.1:8081/api/auth/login 2>&1 | awk '/HTTP\//{c=$2} END{print c+0}')"
case "$c" in 400|401|403) ok "login con datos falsos rechazado (HTTP $c)";; *) falla "el login con datos falsos respondio HTTP $c (se esperaba 400, 401 o 403)";; esac

echo "== Base de datos"
dbpass="$(grep -E '^DB_PASSWORD=' /opt/sulotec/plaft.env 2>/dev/null | head -1 | cut -d= -f2- || true)"
n="$(docker run --rm --network sulotec_data -e MYSQL_PWD="$dbpass" mysql:8.4 mysql -h mysql -uplaft -N -e "select count(*) from information_schema.tables where table_schema='plaft'" plaft 2>/dev/null || true)"
if [ "${n:-0}" -ge 10 ] 2>/dev/null; then ok "la base 'plaft' tiene $n tablas"; else falla "la base 'plaft' tiene ${n:-0} tablas (se esperaban muchas mas)"; fi

echo "== Almacenamiento de denuncias (Oracle, bucket $BUCKET)"
if [ -f "$OCI_DIR/config" ]; then
  sed "s#/run/oci/key.pem#$OCI_DIR/key.pem#" "$OCI_DIR/config" > "$TMP/config"
  obj="pruebas/humo-$(date +%s).txt"; openssl rand -hex 16 > "$TMP/a.txt"
  if oci --config-file "$TMP/config" --profile DEFAULT os object put --namespace-name "$NS" --bucket-name "$BUCKET" --name "$obj" --file "$TMP/a.txt" --force >/dev/null 2>"$TMP/e.txt" \
     && oci --config-file "$TMP/config" --profile DEFAULT os object get --namespace-name "$NS" --bucket-name "$BUCKET" --name "$obj" --file "$TMP/b.txt" >/dev/null 2>&1 && cmp -s "$TMP/a.txt" "$TMP/b.txt"; then
    ok "subir y leer un archivo de prueba funciona"
    a="$(codigo "https://objectstorage.$REGION.oraclecloud.com/n/$NS/b/$BUCKET/o/$obj")"
    if [ "$a" = 200 ]; then falla "el bucket entrega archivos SIN firma"; else ok "el bucket no es publico (sin firma: HTTP $a)"; fi
    oci --config-file "$TMP/config" --profile DEFAULT os object delete --namespace-name "$NS" --bucket-name "$BUCKET" --name "$obj" --force >/dev/null 2>&1 && ok "borrar funciona"
  else
    falla "el almacenamiento no funciona. Detalle:"; grep -E '"(code|message|status)"' "$TMP/e.txt" | sed 's/^ */         /'
  fi
else
  falla "no existe $OCI_DIR/config (corre crear-llave-oci.sh)"
fi

echo "== Direcciones publicas (Cloudflare)"
c="$(codigo "$API_PUBLICA/actuator/health")"
if [ "$c" = 200 ]; then ok "$API_PUBLICA/actuator/health"; else aviso "$API_PUBLICA/actuator/health responde ${c:-000} (¿falta la ruta del tunel?)"; fi
c="$(codigo "$WEB_PUBLICA/")"
if [ "$c" != 200 ]; then
  aviso "$WEB_PUBLICA responde ${c:-000} (¿falta la ruta del tunel?)"
else
  propio="$(docker exec plaft-web wget -qO- http://127.0.0.1:3000/ 2>/dev/null || true)"
  publico="$(curl -s -m 15 "$WEB_PUBLICA/" 2>/dev/null || true)"
  if [ -z "$propio" ]; then aviso "$WEB_PUBLICA responde, pero no pude leer la web local para compararla"
  elif [ "$propio" = "$publico" ]; then ok "$WEB_PUBLICA sale de ESTE servidor"
  else aviso "$WEB_PUBLICA responde, pero NO es la web de este servidor"; fi
fi
cors() { curl -s -m 15 -D - -o /dev/null -X OPTIONS "$API_PUBLICA/api/auth/login" -H "Origin: $1" -H "Access-Control-Request-Method: POST" 2>/dev/null | tr -d '\r' | grep -i '^access-control-allow-origin:' | cut -d' ' -f2- || true; }
permitido="$(cors "$WEB_PUBLICA")"
if [ "$permitido" = "$WEB_PUBLICA" ]; then ok "CORS: la web puede llamar a la API"; else aviso "CORS no devuelve el origen de la web (valor: '${permitido:-ninguno}')"; fi
ajeno="$(cors "https://sitio-ajeno.example")"
if [ -z "$ajeno" ]; then ok "CORS: un sitio ajeno NO puede llamar a la API"; else falla "CORS permite un origen ajeno: $ajeno"; fi

echo
if [ "$fallos" -eq 0 ]; then echo "TODO BIEN ($avisos aviso(s))."; exit 0; fi
echo "$fallos prueba(s) fallaron."
exit 1
