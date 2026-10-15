#!/usr/bin/env bash
# Carga en la base de PLAFT el catalogo de listas (colorimetria) y las personas/empresas sancionadas por la SBS, con la herramienta del
# propio backend (tools/cargar_datos.py; desplegar.sh ya baja el codigo en /data/apps/plaft/backend).
#   sudo bash /data/apps/plaft/cargar-datos.sh              SIMULA: muestra que se cargaria y no escribe nada
#   sudo bash /data/apps/plaft/cargar-datos.sh --aplicar    escribe de verdad (antes guarda un respaldo de la base y lo comprueba)
# Los Excel ("Listas y Colorimetría.xlsx" y "Lista de empresas sancionadas.xlsx") se toman del bucket sulotec-backups, prefijo
# externos/plaft/ (con la identidad de la VM), o de una carpeta:  CARPETA=/ruta sudo -E bash /data/apps/plaft/cargar-datos.sh
# Se puede repetir sin duplicar (busca por nombre de lista y por tipo + numero de documento) y nunca borra nada.
# Tambien carga las figuras politicas (PEP) y sus casos en prensa que estan en la base del servicio de IA (plaft_ml): las exporta a un JSON
# y la herramienta las registra como entidades PEP con sus noticias "pendientes de revision". Para omitirlas:  SIN_POLITICOS=1
# Variables solo para pruebas: APP, ENVFILE, ENVML, RED_DOCKER, RESPALDOS, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

APP="${APP:-/data/apps/plaft}"
ENVFILE="${ENVFILE:-/opt/sulotec/plaft.env}"
ENVML="${ENVML:-/opt/sulotec/plaft-ml.env}"
BUCKET="${BACKUP_BUCKET:-sulotec-backups}"
PREFIJO="${PREFIJO:-externos/plaft/}"
RED="${RED_DOCKER:-sulotec_data}"
RESPALDOS="${RESPALDOS:-/var/backups/sulotec}"
HERRAMIENTAS="$APP/backend/tools"
# Nombres que la herramienta busca (los Excel se guardan con estos nombres aunque en el bucket se llamen distinto)
F_LISTAS="Listas y Colorimetría.xlsx"
F_SANC="Lista de empresas sancionadas.xlsx"

APLICAR=0
case "${1:-}" in
  "") ;;
  --aplicar) APLICAR=1 ;;
  *) echo "uso: sudo bash $0 [--aplicar]" >&2; exit 1 ;;
esac

[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE: primero corre preparar.sh" >&2; exit 1; }
[ -f "$HERRAMIENTAS/cargar_datos.py" ] || { echo "Falta $HERRAMIENTAS/cargar_datos.py: corre primero desplegar.sh (baja el codigo del backend)." >&2; exit 1; }
leer() { grep -E "^$1=" "$ENVFILE" | head -1 | cut -d= -f2- || true; }
DB_URL="$(leer DB_URL)"; DB_USER="$(leer DB_USER)"; DB_PASSWORD="$(leer DB_PASSWORD)"
{ [ -n "$DB_URL" ] && [ -n "$DB_USER" ] && [ -n "$DB_PASSWORD" ]; } || { echo "$ENVFILE no tiene DB_URL, DB_USER y DB_PASSWORD." >&2; exit 1; }
export DB_URL DB_USER DB_PASSWORD
BASE="${DB_URL#*://}"; BASE="${BASE#*/}"; BASE="${BASE%%[?]*}"      # nombre de la base dentro de la URL jdbc
[ -n "$BASE" ] || { echo "No pude sacar el nombre de la base de DB_URL." >&2; exit 1; }
command -v python3 >/dev/null || { echo "Falta python3 en el servidor." >&2; exit 1; }

TMP="$(mktemp -d)"; chmod 700 "$TMP"
trap '[ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"' EXIT
mkdir "$TMP/datos" "$TMP/pkgs"

# ---- 1. Los Excel
# Dice cual archivo es cual por su nombre (sin importar tildes, mayusculas ni un "(1)" al final). Lee nombres por la entrada estandar.
clasificar() {
  PYTHONIOENCODING=utf-8 python3 -c '
import sys, unicodedata
for linea in sys.stdin:
    nombre = linea.rstrip(chr(10))
    base = nombre.rsplit("/", 1)[-1]
    plano = unicodedata.normalize("NFD", base).encode("ascii", "ignore").decode().lower()
    if not plano.endswith(".xlsx"):
        continue
    if "colorimetr" in plano:
        print("listas|" + nombre)
    elif "sancionad" in plano:
        print("sancionadas|" + nombre)
'
}
nombres_bucket() {
  local a=(--auth instance_principal --bucket-name "$BUCKET" --all)
  [ -z "${1:-}" ] || a+=(--prefix "$1")
  oci os object list "${a[@]}" 2>/dev/null | PYTHONIOENCODING=utf-8 python3 -c 'import json, sys; [print(o["name"]) for o in json.load(sys.stdin).get("data", [])]'
}

# Personas de la base de la IA (menos las descartadas) con sus casos, en el formato JSON que lee la herramienta del backend
SQL_POLITICOS="select coalesce(json_agg(p order by p.apellidos, p.nombres), '[]'::json) from (
  select pe.id, pe.tipo_documento::text as tipo_documento, pe.numero_documento, pe.nombres, pe.apellidos,
         to_json(pe.nombres_alternativos) as nombres_alternativos, pe.es_pep, pe.cargo_pep,
         coalesce((select json_agg(json_build_object('estado_revision', c.estado_revision::text, 'url_fuente', c.url_fuente,
                   'creado_en', c.creado_en, 'tipo', c.tipo::text, 'resumen', c.resumen, 'categoria_delito', c.categoria_delito)
                   order by c.creado_en)
                   from casos c where c.persona_id = pe.id and c.estado_revision::text <> 'DESCARTADO'), '[]'::json) as casos
  from personas pe where pe.estado_verificacion::text <> 'DESCARTADO'
) p"
exportar_politicos() {
  local url dest
  url="$(grep -E '^DATABASE_URL=' "$ENVML" | head -1 | cut -d= -f2-)"
  dest="${url/postgresql+psycopg:/postgresql:}"
  echo "$SQL_POLITICOS" | DESTINO="$dest" docker run --rm -i --network "$RED" -e DESTINO postgres:16 sh -c 'exec psql "$DESTINO" -X -At -v ON_ERROR_STOP=1'
}

echo "== Archivos de datos"
if [ -n "${CARPETA:-}" ]; then
  [ -d "$CARPETA" ] || { echo "No existe la carpeta $CARPETA" >&2; exit 1; }
  encontrados="$(ls -1 "$CARPETA" | clasificar || true)"
else
  encontrados="$(nombres_bucket "$PREFIJO" | clasificar || true)"
  # Si no estan bajo el prefijo, se buscan en todo el bucket (por si se subieron sin la carpeta)
  [ -n "$encontrados" ] || encontrados="$(nombres_bucket "" | clasificar || true)"
fi
obj_listas=""; obj_sanc=""
while IFS='|' read -r tipo nombre; do
  case "$tipo" in listas) obj_listas="$nombre" ;; sancionadas) obj_sanc="$nombre" ;; esac
done <<< "$encontrados"

traer() {   # $1 = nombre en el bucket (o en la carpeta), $2 = nombre que espera la herramienta
  if [ -n "${CARPETA:-}" ]; then cp "$CARPETA/$1" "$TMP/datos/$2"
  else oci os object get --auth instance_principal --bucket-name "$BUCKET" --name "$1" --file "$TMP/datos/$2" >/dev/null; fi
}
cmds=()
if [ -n "$obj_listas" ]; then traer "$obj_listas" "$F_LISTAS"; cmds+=(listas); echo "   catalogo de listas: $obj_listas"; fi
if [ -n "$obj_sanc" ]; then traer "$obj_sanc" "$F_SANC"; cmds+=(sancionadas); echo "   sancionadas SBS:    $obj_sanc"; fi
extra=()
if [ -r "$ENVML" ] && [ -z "${SIN_POLITICOS:-}" ]; then
  echo "== Figuras politicas (base de la IA, plaft_ml)"
  if exportar_politicos > "$TMP/datos/politicos.json" 2>"$TMP/e.txt"; then
    n_pol="$(python3 -c 'import json, sys; print(len(json.load(sys.stdin)))' < "$TMP/datos/politicos.json" 2>/dev/null || echo 0)"
    if [ "${n_pol:-0}" -ge 1 ] 2>/dev/null; then
      echo "   $n_pol personas con sus casos en prensa"; cmds+=(politicos); extra=(--politicos-json /datos/politicos.json)
    else
      echo "   la base de la IA no tiene personas: se omite esta parte"
    fi
  else
    echo "   AVISO: no pude leer la base de la IA; se omiten las figuras politicas. Detalle:"; sed 's/^/      /' "$TMP/e.txt"
  fi
fi
[ "${#cmds[@]}" -gt 0 ] || { echo "No encontre los Excel. Sube 'Listas y Colorimetría.xlsx' y 'Lista de empresas sancionadas.xlsx' al bucket $BUCKET con el prefijo $PREFIJO (o usa CARPETA=/ruta)." >&2; exit 1; }
[ -n "$obj_listas" ] || echo "   AVISO: falta el Excel de listas; la herramienta pedira que el catalogo ya exista en la base."

# ---- 2. La herramienta (se instala en una carpeta temporal; nada queda en el servidor)
echo "== Preparando la herramienta"
docker run --rm -v "$TMP/pkgs:/pkgs" -v "$HERRAMIENTAS:/tools:ro" python:3.12-slim \
  pip install -q --no-cache-dir --root-user-action=ignore --target /pkgs -r /tools/requirements.txt cryptography >/dev/null \
  || { echo "No pude instalar las librerias de la herramienta (¿el servidor tiene salida a internet?)." >&2; exit 1; }

corre_herramienta() {
  docker run --rm --network "$RED" -v "$TMP/pkgs:/pkgs:ro" -v "$HERRAMIENTAS:/tools:ro" -v "$TMP/datos:/datos:ro" \
    -e PYTHONPATH=/pkgs -e PYTHONDONTWRITEBYTECODE=1 -e DB_URL -e DB_USER -e DB_PASSWORD \
    python:3.12-slim python /tools/cargar_datos.py "$@" --carpeta /datos
}

# ---- 3. Con --aplicar: respaldo primero
if [ "$APLICAR" = 1 ]; then
  echo "== Respaldo de la base '$BASE' antes de escribir"
  mkdir -p "$RESPALDOS"; chmod 700 "$RESPALDOS"
  copia="$RESPALDOS/${BASE}_antes-de-cargar_$(date +%F_%H%M).sql.gz"
  if ! MYSQL_PWD="$DB_PASSWORD" docker run --rm --network "$RED" -e MYSQL_PWD mysql:8.4 \
       mysqldump -h mysql -u"$DB_USER" --no-tablespaces --single-transaction "$BASE" | gzip > "$copia"; then
    rm -f "$copia"; echo "No pude respaldar la base: no escribo nada." >&2; exit 1
  fi
  tablas="$(zcat "$copia" | grep -c '^CREATE TABLE' || true)"
  if ! [ "${tablas:-0}" -ge 5 ] 2>/dev/null; then
    rm -f "$copia"; echo "El respaldo salio incompleto (${tablas:-0} tablas): no escribo nada." >&2; exit 1
  fi
  echo "   OK: $copia ($(du -h "$copia" | cut -f1), $tablas tablas)"
fi

# ---- 4. La carga (con la simulacion, la herramienta hace todo dentro de una transaccion y la deshace)
if [ "$APLICAR" = 1 ]; then echo "== Cargando (ESCRIBE en la base)"; else echo "== Simulacion (no escribe nada)"; fi
if [ "$APLICAR" = 1 ]; then flag="--aplicar"; else flag=""; fi
corre_herramienta "${cmds[@]}" ${extra[@]+"${extra[@]}"} ${flag:+"$flag"} \
  || { echo "La herramienta fallo (arriba esta el detalle). La carga es todo o nada: no se guardo nada." >&2; exit 1; }

if [ "$APLICAR" = 1 ]; then
  echo "== Filas por tabla ahora"
  MYSQL_PWD="$DB_PASSWORD" docker run --rm --network "$RED" -e MYSQL_PWD mysql:8.4 mysql -h mysql -u"$DB_USER" -N "$BASE" -e \
    "select 'lista_grupo', count(*) from lista_grupo union all select 'tipo_lista', count(*) from tipo_lista union all select 'entidades', count(*) from entidades union all select 'personas_naturales', count(*) from personas_naturales union all select 'personas_juridicas', count(*) from personas_juridicas union all select 'historial_manchas', count(*) from historial_manchas" \
    2>/dev/null | awk '{printf "   %-20s %8s\n", $1, $2}' || true
  echo
  echo "LISTO: datos cargados. Los Excel tienen datos de personas: cuando verifiques en la web, borralos del bucket $BUCKET (consola de Oracle, carpeta $PREFIJO)."
else
  echo
  echo "Eso fue una SIMULACION: no se escribio nada. Si el resumen se ve bien:  sudo bash $0 --aplicar"
fi
