#!/usr/bin/env bash
# Activa a Indira (el asistente) y la deteccion automatica de casos en prensa del servicio de IA de PLAFT.
# Instala Ollama (el modelo de lenguaje corre en ESTE servidor: ningun dato sale a terceros), baja el modelo (unos 5 GB),
# lo conecta con plaft-ml y hace una prueba real de Indira con datos de la base. Se puede repetir las veces que haga falta.
#   sudo bash /data/apps/plaft/activar-indira.sh
# Otro modelo (por defecto qwen2.5:7b; uno mas liviano y rapido, pero menos fino):  MODELO=qwen2.5:3b MEM_MIN=4000 sudo -E bash /data/apps/plaft/activar-indira.sh
# Apagarla (el modelo descargado se conserva):         sudo bash /data/apps/plaft/activar-indira.sh --apagar
# Variables solo para pruebas: APP, ENVFILE, ENVML, RED_DOCKER, MEM_MIN, TIEMPO_CHAT, MEM_DISPONIBLE_MB, DISCO_LIBRE_GB, PRUEBA, FORZAR.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

APP="${APP:-/data/apps/plaft}"
ENVAPI="${ENVFILE:-/opt/sulotec/plaft.env}"
ENVML="${ENVML:-/opt/sulotec/plaft-ml.env}"
RED="${RED_DOCKER:-sulotec_data}"
# qwen2.5:7b maneja bien las herramientas de Indira en Ollama; llama3.1:8b a veces devuelve la llamada a la herramienta como texto
MODELO="${MODELO:-qwen2.5:7b}"
TIEMPO_CHAT="${TIEMPO_CHAT:-300}"         # segundos que el backend espera la respuesta de Indira (el modelo corre en CPU)
MEM_MIN="${MEM_MIN:-8000}"                # MB de memoria disponible que hacen falta para el modelo
USUARIO_PRUEBA="00000000-0000-4000-8000-0000000000aa"

[ -r "$ENVML" ] || { echo "Falta $ENVML: primero corre preparar-ml.sh" >&2; exit 1; }
[ -r "$ENVAPI" ] || { echo "Falta $ENVAPI: primero corre preparar.sh" >&2; exit 1; }
grep -q '^  ollama:' "$APP/docker-compose.yml" || { echo "El docker-compose.yml de $APP no trae Ollama: actualiza el kit (README, paso 1)." >&2; exit 1; }
command -v python3 >/dev/null || { echo "Falta python3 en el servidor." >&2; exit 1; }

salud() { docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null || echo ninguno; }
espera_sano() { local c="$1" i; for i in $(seq 1 "${2:-60}"); do [ "$(salud "$c")" = healthy ] && return 0; sleep 3; done; return 1; }
compose() { (cd "$APP" && docker compose --profile ml --profile ia "$@"); }
# Pone una clave en un archivo de configuracion (si no esta, la agrega). Conserva dueno y permisos del archivo.
poner() {
  local f="$1" k="$2" v="$3" tmp; tmp="$(mktemp "$f.XXXXXX")"
  if grep -q "^$k=" "$f"; then awk -v k="$k" -v v="$v" 'BEGIN{FS=OFS="="} $1==k {print k "=" v; next} {print}' "$f" > "$tmp"
  else { cat "$f"; echo "$k=$v"; } > "$tmp"; fi
  cat "$tmp" > "$f"; rm -f "$tmp"
}

# Corre un comando en segundo plano mostrando un punto cada 5 s (asi se ve que sigue trabajando).
# $1 = mensaje, $2 = archivo para la salida, $3 = archivo para los errores, el resto = comando.
con_puntos() {
  local msg="$1" salida="$2" errores="$3" pid; shift 3
  printf "   %s" "$msg"
  "$@" >"$salida" 2>"$errores" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do printf "."; sleep 5; done
  wait "$pid" || true
  echo
}

if [ "${1:-}" = "--apagar" ]; then
  poner "$ENVML" INDIRA_ENABLED false
  compose up -d --force-recreate ml >/dev/null
  compose stop ollama >/dev/null 2>&1 || true
  echo "Indira apagada (el modelo descargado se conserva en $APP/ollama). Para volver a activarla: sudo bash $0"
  exit 0
fi
[ -z "${1:-}" ] || { echo "uso: sudo bash $0 [--apagar]" >&2; exit 1; }

echo "== 0. Recursos del servidor"
mem="${MEM_DISPONIBLE_MB:-$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo)}"
libre="${DISCO_LIBRE_GB:-$(df -P -BG /data | awk 'NR==2 {gsub("G", "", $4); print $4}')}"
echo "   memoria disponible: ${mem} MB | disco libre en /data: ${libre} GB | nucleos: $(nproc)"
if ! docker ps --format '{{.Names}}' | grep -x plaft-ollama >/dev/null; then
  if [ "${mem:-0}" -lt "$MEM_MIN" ] && [ -z "${FORZAR:-}" ]; then
    echo "Hay poca memoria libre (${mem} MB; el modelo necesita unos ${MEM_MIN} MB). Con un modelo mas liviano:  MODELO=qwen2.5:3b MEM_MIN=4000 sudo -E bash $0" >&2; exit 1
  fi
  if [ "${libre:-0}" -lt 12 ] && [ -z "${FORZAR:-}" ]; then echo "Poco disco libre en /data (${libre} GB): el modelo pesa unos 5 GB y se necesita margen." >&2; exit 1; fi
fi

echo "== 1. Ollama (el modelo de lenguaje, dentro de este servidor)"
mkdir -p "$APP/ollama"
compose up -d ollama
espera_sano plaft-ollama 40 || { echo "Ollama no arranco bien. Ultimas lineas:" >&2; docker logs --tail 30 plaft-ollama >&2 || true; exit 1; }
echo "   plaft-ollama: sano"

echo "== 2. Modelo $MODELO"
if docker exec plaft-ollama ollama list | awk 'NR>1 {print $1}' | grep -x "$MODELO" >/dev/null; then
  echo "   ya esta descargado"
else
  echo "   descargando (unos 5 GB; tarda varios minutos)"
  t=""; [ -t 1 ] && t="-t"
  docker exec $t plaft-ollama ollama pull "$MODELO" || { echo "No pude descargar el modelo $MODELO (¿el servidor tiene salida a internet?)." >&2; exit 1; }
fi
v_out="$(mktemp)"; v_err="$(mktemp)"
con_puntos "cargando el modelo en memoria y midiendo la velocidad (1 a 3 minutos, sin mensajes; no cierres esta ventana) " "$v_out" "$v_err" docker exec plaft-ollama ollama run "$MODELO" --verbose "Responde con una sola frase corta: ¿que es el lavado de activos?"
grep -E 'load duration|prompt eval rate|^eval rate' "$v_err" | sed 's/^/      /' || true
rm -f "$v_out" "$v_err"

echo "== 3. Conectando la IA con el modelo"
poner "$ENVML" INDIRA_ENABLED true
poner "$ENVML" OLLAMA_BASE_URL http://ollama:11434
poner "$ENVML" OLLAMA_MODEL "$MODELO"
poner "$ENVAPI" ML_CHATTIMEOUTSECONDS "$TIEMPO_CHAT"
compose up -d --force-recreate ml api >/dev/null
espera_sano plaft-ml 60 || { echo "plaft-ml no arranco bien. Ultimas lineas:" >&2; docker logs --tail 30 plaft-ml >&2 || true; exit 1; }
espera_sano plaft-api 120 || { echo "plaft-api no volvio a arrancar. Ultimas lineas:" >&2; docker logs --tail 30 plaft-api >&2 || true; exit 1; }
echo "   plaft-ml y plaft-api: sanos, Indira encendida"

echo "== 4. Prueba real: Indira responde con datos de la base (puede tardar un par de minutos)"
url="$(grep -E '^DATABASE_URL=' "$ENVML" | head -1 | cut -d= -f2-)"
DESTINO="${url/postgresql+psycopg:/postgresql:}"
psql_ml() { docker run --rm -i --network "$RED" -e DESTINO="$DESTINO" postgres:16 sh -c 'exec psql "$DESTINO" -X -At -v ON_ERROR_STOP=1'; }
SQL_PERSONA="select nombres || ' ' || apellidos from personas where estado_verificacion::text <> 'DESCARTADO' order by creado_en limit 1"
persona="$(echo "$SQL_PERSONA" | psql_ml)" || persona=""
[ -n "$persona" ] || persona="una persona registrada"
pregunta="¿Qué casos hay registrados de $persona?"
cuerpo="$(python3 -c 'import json, sys; print(json.dumps({"usuario_id": sys.argv[1], "canal": "web", "mensaje": sys.argv[2]}))' "$USUARIO_PRUEBA" "$pregunta")"
echo "   pregunta: $pregunta"
r_out="$(mktemp)"; r_err="$(mktemp)"
inicio="$(date +%s)"
con_puntos "esperando la respuesta de Indira (puede tardar un par de minutos) " "$r_out" "$r_err" docker exec -e BODY="$cuerpo" plaft-api sh -c 'wget -q -t 1 -T 600 --content-on-error -O - --header "Content-Type: application/json" --header "X-Internal-Key: $ML_API_KEY" --post-data "$BODY" http://plaft-ml:8000/api/v1/indira/chat'
segundos=$(( $(date +%s) - inicio ))
respuesta="$(cat "$r_out")"; rm -f "$r_out" "$r_err"
texto="$(printf '%s' "$respuesta" | PYTHONIOENCODING=utf-8 python3 -c 'import json, sys; print(json.load(sys.stdin)["respuesta"])' 2>/dev/null || true)"
# se borra lo que dejo la prueba (solo la conversacion de este usuario de prueba)
psql_ml >/dev/null <<SQL || true
delete from mensajes_indira where conversacion_id in (select id from conversaciones_indira where usuario_id = '$USUARIO_PRUEBA');
delete from conversaciones_indira where usuario_id = '$USUARIO_PRUEBA';
SQL

if [ -z "$texto" ]; then
  echo "   Indira NO respondio (${segundos} s). Lo que devolvio la IA: $(printf '%s' "$respuesta" | cut -c1-300)" >&2
  echo "   Revisa: docker logs --tail 40 plaft-ml    y    docker logs --tail 40 plaft-ollama" >&2
  exit 1
fi
echo "   Indira respondio en ${segundos} s:"
printf '%s\n' "$texto" | cut -c1-1500 | fold -s -w 100 | sed 's/^/      | /'
case "$texto" in
  "{"*|"[{"*|"<tool_call>"*)
    echo >&2
    echo "FALLA: Indira devolvio la llamada a la herramienta como texto en bruto en vez de una respuesta: este modelo no maneja bien las herramientas." >&2
    echo "       Prueba con otro:  MODELO=qwen2.5:7b sudo -E bash $0" >&2
    exit 1 ;;
esac
if [ "$segundos" -gt 90 ]; then
  echo
  echo "AVISO: tardo ${segundos} s. Cloudflare corta cualquier respuesta que pase de 100 s: en la web algunas preguntas podrian dar error."
  echo "       Si pasa, usa un modelo mas liviano y rapido:  MODELO=qwen2.5:3b MEM_MIN=4000 sudo -E bash $0"
fi
echo
echo "LISTO: Indira esta activa (modelo $MODELO) y la vigilancia de prensa ya puede decidir casos con el modelo."
echo "La vigilancia diaria corre a las 6:00 (hora de Lima) y usa bastante CPU un buen rato; el chat puede ir mas lento en ese horario."
otros="$(docker exec plaft-ollama ollama list | awk -v m="$MODELO" 'NR>1 && $1 != m {print $1}')"
[ -z "$otros" ] || echo "Otros modelos descargados (ocupan disco; para borrar uno: docker exec plaft-ollama ollama rm <nombre>): $(echo $otros)"
