#!/usr/bin/env bash
# Pruebas de humo de Indira despues de publicar. No cambia nada.
#   sudo bash /data/apps/indira/probar.sh
# Prueba larga del tunel (opcional): un turno con el proveedor falso que tarda mas de 150 s debe llegar entero por
# api-indira.sulotec.com, con los pings SSE pasando por Cloudflare. Necesita el access token de una cuenta con empresa
# y licencia indira (consume 1 token). En sulotec.com, con la sesion abierta, en la consola del navegador:
#   copy(await sulotecCuenta.token())
# y luego (el token dura pocos minutos; no lo pegues en un chat):
#   read -rs TOKEN && export TOKEN && sudo -E bash /data/apps/indira/probar.sh
# Antes, INDIRA_FALSO_DEMORA_S=160 en /opt/sulotec/indira.env y desplegar.sh; al terminar, vuelve a 0.
set -uo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

API_PUBLICA="${API_PUBLICA:-https://api-indira.sulotec.com}"
ENVFILE=/opt/sulotec/indira.env
fallos=0
avisos=0
ok()    { echo "  OK     $*"; }
falla() { echo "  FALLA  $*"; fallos=$((fallos+1)); }
aviso() { echo "  AVISO  $*"; avisos=$((avisos+1)); }
salud() { docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null || echo ninguno; }
dentro() { docker exec indira python -c "
import urllib.request as u, urllib.error as e
try:
    print(u.urlopen(u.Request('http://127.0.0.1:3300$1', method='${2:-GET}'), timeout=5).status)
except e.HTTPError as x:
    print(x.code)
except Exception:
    print('000')" 2>/dev/null || echo 000; }

echo "== Contenedor"
if [ "$(salud indira)" = healthy ]; then ok "indira sano"; else falla "indira no esta sano ($(salud indira))"; fi
prov="$(grep -E '^INDIRA_PROVEEDOR=' "$ENVFILE" 2>/dev/null | cut -d= -f2-)"
echo "  INFO   proveedor: ${prov:-falso}"

echo "== Servicio por dentro"
cod="$(dentro /health)"
if [ "$cod" = 200 ]; then ok "/health responde"; else falla "/health respondio '$cod' (mira: docker logs indira)"; fi
cod="$(dentro /v1/yo)"
if [ "$cod" = 401 ]; then ok "sin token responde 401"; else falla "/v1/yo sin token respondio '$cod' (se esperaba 401)"; fi
cod="$(dentro /docs)"
if [ "$cod" = 404 ]; then ok "/docs apagado"; else falla "/docs respondio '$cod' (debe estar apagado)"; fi
cod="$(docker exec indira python -c "import urllib.request as u; print(u.urlopen('http://licencias:3200/health', timeout=5).status)" 2>/dev/null || echo 000)"
if [ "$cod" = 200 ]; then ok "llega al servicio de licencias"; else falla "no llega a http://licencias:3200 ('$cod')"; fi
if [ "${prov:-falso}" = ollama ]; then
  cod="$(docker exec indira python -c "import urllib.request as u; print(u.urlopen('http://plaft-ollama:11434/api/tags', timeout=5).status)" 2>/dev/null || echo 000)"
  if [ "$cod" = 200 ]; then ok "llega al Ollama de PLAFT"; else falla "proveedor ollama pero no llega a plaft-ollama ('$cod'); ¿existe /data/apps/indira/usar-ollama?"; fi
fi

echo "== Direccion publica"
cod="$(curl -s -m 15 -o /dev/null -w '%{http_code}' "$API_PUBLICA/health" 2>/dev/null || true)"
if [ "$cod" = 200 ]; then ok "$API_PUBLICA/health responde"; else aviso "$API_PUBLICA/health respondio '$cod': agrega en Cloudflare la ruta api-indira.sulotec.com -> http://indira:3300"; fi
cors="$(curl -s -m 15 -D - -o /dev/null -X OPTIONS "$API_PUBLICA/v1/turnos" -H "Origin: https://sulotec.com" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: authorization,content-type,idempotency-key" 2>/dev/null | tr -d '\r' | grep -i '^access-control-allow-origin' || true)"
if [ -n "$cors" ]; then ok "el portal (sulotec.com) puede llamar al servicio"; else aviso "sin respuesta CORS para sulotec.com (normal si la ruta publica aun no existe)"; fi

if [ -n "${TOKEN:-}" ]; then
  echo "== Turno largo por el tunel (con TOKEN)"
  demora="$(grep -E '^INDIRA_FALSO_DEMORA_S=' "$ENVFILE" 2>/dev/null | cut -d= -f2-)"
  [ "${demora:-0}" -ge 150 ] 2>/dev/null || aviso "INDIRA_FALSO_DEMORA_S=${demora:-0}: para medir el corte de 100 s de Cloudflare ponlo en 160"
  clave="$(cat /proc/sys/kernel/random/uuid)"
  resp="$(curl -s -m 30 -X POST "$API_PUBLICA/v1/turnos" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -H "Idempotency-Key: $clave" -d '{"mensaje":"Prueba del tunel desde probar.sh","pantalla":"/"}')"
  turno="$(printf '%s' "$resp" | sed -n 's/.*"turno_id" *: *"\([^"]*\)".*/\1/p')"
  if [ -z "$turno" ]; then
    falla "no se acepto el turno: $(printf '%s' "$resp" | head -c 200)"
  else
    inicio=$(date +%s)
    eventos="$(curl -s -N -m 330 "$API_PUBLICA/v1/turnos/$turno/eventos" -H "Authorization: Bearer $TOKEN" -H 'Accept: text/event-stream' | grep -m1 -E '^event: (fin|error)')"
    dur=$(( $(date +%s) - inicio ))
    case "$eventos" in
      "event: fin") ok "el turno llego entero por el tunel en ${dur} s" ;;
      "event: error") falla "el turno termino con error en ${dur} s (mira: docker logs indira)" ;;
      *) falla "el flujo se corto a los ${dur} s sin fin ni error (¿Cloudflare corta el SSE?)" ;;
    esac
  fi
  unset TOKEN
fi

echo
echo "Resultado: $fallos fallas, $avisos avisos"
[ "$fallos" -eq 0 ]
