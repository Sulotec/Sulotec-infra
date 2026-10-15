#!/usr/bin/env bash
# Crea o actualiza la configuracion del servicio de IA de PLAFT (Security-MachineLearning): /opt/sulotec/plaft-ml.env
# (solo root y el grupo docker la leen). La clave interna con la que el backend le habla es la MISMA que ya tiene /opt/sulotec/plaft.env.
#   sudo bash /data/apps/plaft/preparar-ml.sh
# Antes:  sudo /opt/sulotec/scripts/new-project-db.sh postgres plaft_ml    (crea la base y el usuario "plaft_ml")
# Despues: sudo bash /data/apps/plaft/restaurar-ml.sh   (si hay un respaldo para cargar)  y  sudo bash /data/apps/plaft/desplegar.sh
# Variables solo para pruebas: ENVFILE_API, ENVFILE_ML, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

ENVAPI="${ENVFILE_API:-/opt/sulotec/plaft.env}"
ENVML="${ENVFILE_ML:-/opt/sulotec/plaft-ml.env}"
[ -r "$ENVAPI" ] || { echo "Falta $ENVAPI: primero corre preparar.sh" >&2; exit 1; }
CLAVE_INTERNA="$(grep -E '^ML_API_KEY=' "$ENVAPI" | head -1 | cut -d= -f2-)"
[ -n "$CLAVE_INTERNA" ] || { echo "$ENVAPI no tiene ML_API_KEY" >&2; exit 1; }

limpiar() { local v="$1"; v="${v//$'\e'\[200~/}"; v="${v//$'\e'\[201~/}"; v="${v//\[200~/}"; v="${v//\[201~/}"; printf '%s' "${v//[[:space:]]/}"; }
actual() { [ -f "$ENVML" ] && grep -E "^$1=" "$ENVML" | head -1 | cut -d= -f2- || true; }
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

echo "== Base de datos (PostgreSQL de la VM, base y usuario 'plaft_ml')"
echo "   Pega la clave que mostro new-project-db.sh postgres plaft_ml. Saldran asteriscos."
url_actual="$(actual DATABASE_URL)"
pass_actual="$(printf '%s' "$url_actual" | sed -nE 's#^postgresql\+psycopg://plaft_ml:([^@]*)@.*#\1#p')"
leer_secreto "Clave del usuario plaft_ml [Enter = $([ -n "$pass_actual" ] && echo conservar || echo vacio)]: "
DBPASS="$(limpiar "${V:-}")"; DBPASS="${DBPASS:-$pass_actual}"
[ -n "$DBPASS" ] || { echo "Hace falta la clave de la base." >&2; exit 1; }
echo "   recibido: clave de ${#DBPASS} caracteres"
if [ -z "${PRUEBA:-}" ]; then
  r="$(docker run --rm --network sulotec_data -e PGPASSWORD="$DBPASS" postgres:16 psql -h postgres -U plaft_ml -d plaft_ml -At -c 'select 1' 2>/dev/null || true)"
  [ "$r" = 1 ] || { echo "No pude entrar a la base 'plaft_ml' con esa clave. ¿Corriste new-project-db.sh postgres plaft_ml y pegaste la clave completa?" >&2; exit 1; }
  echo "   OK: la clave funciona"
fi

echo "== Indira (el agente con modelo local; necesita Ollama y unos 8 GB de RAM)"
act_ind="$(actual INDIRA_ENABLED)"; def_ind="n"; [ "$act_ind" = "true" ] && def_ind="s"
MODELO="$(actual OLLAMA_MODEL)"; MODELO="${MODELO:-llama3.1:8b}"      # el modelo que dejo activar-indira.sh se conserva
read -rp "¿Activar Indira ahora? [s/n, Enter = $def_ind]: " ind; ind="$(limpiar "${ind:-$def_ind}")"
if [[ "$ind" =~ ^[sS]$ ]]; then INDIRA=true; else INDIRA=false; fi
[ "$INDIRA" = false ] && echo "   Indira apagada: responde 'servicio no disponible'; la vigilancia de prensa, las personas y el scoring funcionan igual."

install -m 640 -o root -g docker /dev/null "$ENVML" 2>/dev/null || install -m 640 /dev/null "$ENVML"
{
  echo "# Generado por deploy/preparar-ml.sh. Secretos: no subir a ningun repositorio."
  echo "ENTORNO=prod"
  echo "DATABASE_URL=postgresql+psycopg://plaft_ml:$DBPASS@postgres:5432/plaft_ml"
  echo "INTERNAL_API_KEY=$CLAVE_INTERNA"
  echo "ALLOWED_ORIGINS=http://plaft-api:8081"
  echo "INDIRA_ENABLED=$INDIRA"
  echo "OLLAMA_BASE_URL=http://ollama:11434"
  echo "OLLAMA_MODEL=$MODELO"
  echo "SCRAPING_AL_ARRANCAR=false"
  echo "ZONA_HORARIA=America/Lima"
  echo "SCRAPING_HORA=6"
  echo "VIGILANCIA_DIAS=30"
  echo "VIGILANCIA_MAX_POR_PERSONA=6"
} > "$ENVML"

echo
echo "Configuracion guardada en $ENVML"
echo "Siguiente: sudo bash /data/apps/plaft/restaurar-ml.sh   (carga el respaldo de security_ml)   y despues   sudo bash /data/apps/plaft/desplegar.sh"
