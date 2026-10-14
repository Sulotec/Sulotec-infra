#!/usr/bin/env bash
# Respalda una MySQL EXTERNA (por ejemplo Aiven) hacia este servidor y VERIFICA el respaldo restaurandolo en un contenedor
# temporal sin red. Del origen solo LEE: no cambia ni borra nada. La direccion se pide con asteriscos (no se muestra).
#   sudo /opt/sulotec/scripts/respaldar-mysql-externo.sh
# El respaldo queda en /data/backups/externos (solo root puede leerlo). Sirve como copia de seguridad antes de cerrar el origen.
# Variables solo para pruebas: ORIGEN_URI, SSL_MODE (por defecto REQUIRED), CARPETA, RED_DOCKER, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo $0" >&2; exit 1; }

CARPETA="${CARPETA:-/data/backups/externos}"
SSL_MODE="${SSL_MODE:-REQUIRED}"
IMAGEN="${IMAGEN:-mysql:8.4}"
RED="${RED_DOCKER:-}"
SISTEMA="'information_schema','mysql','performance_schema','sys'"
TMP="$(mktemp -d)"; chmod 700 "$TMP"
contenedores=()
limpiar_todo() { local c; for c in "${contenedores[@]:-}"; do [ -n "$c" ] && docker rm -f "$c" >/dev/null 2>&1 || true; done; [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }
trap limpiar_todo EXIT

limpiar() { local v="$1"; v="${v//$'\e'\[200~/}"; v="${v//$'\e'\[201~/}"; v="${v//\[200~/}"; v="${v//\[201~/}"; printf '%s' "${v//[[:space:]]/}"; }
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

if [ -z "${ORIGEN_URI:-}" ]; then
  echo "Pega la 'Service URI' de la MySQL de origen (en Aiven: Overview -> Service URI, boton de copiar). Saldran asteriscos."
  leer_secreto "ORIGEN: "; ORIGEN_URI="$V"
fi
ORIGEN_URI="$(limpiar "$ORIGEN_URI")"
re='^mysql://([^:]+):([^@]*)@([^:/]+):([0-9]+)(/[^?]*)?'
[[ "$ORIGEN_URI" =~ $re ]] || { echo "No entiendo la direccion: debe ser mysql://usuario:clave@servidor:puerto/base (recibi ${#ORIGEN_URI} caracteres)." >&2; exit 1; }
U="${BASH_REMATCH[1]}"; P="${BASH_REMATCH[2]}"; H="${BASH_REMATCH[3]}"; PT="${BASH_REMATCH[4]}"
echo "   origen: $U@$H:$PT (clave de ${#P} caracteres)"

red=(); [ -n "$RED" ] && red=(--network "$RED")
# comandos de cliente en contenedores: la clave viaja por entorno, no por la linea de comandos
mysqlo() { docker run --rm "${red[@]}" -e MYSQL_PWD="$P" "$IMAGEN" mysql -h "$H" -P "$PT" -u "$U" --ssl-mode="$SSL_MODE" "$@"; }

echo "== 1. Conectando con el origen"
version="$(mysqlo -N -e 'select version()' 2>"$TMP/e.txt")" || { echo "No pude conectar con el origen. ¿Permite la IP de este servidor? Detalle:" >&2; sed 's/^/   /' "$TMP/e.txt" >&2; exit 1; }
echo "   MySQL $version"
bases="$(mysqlo -N -e "select schema_name from information_schema.schemata where schema_name not in ($SISTEMA) order by 1")"
[ -n "$bases" ] || { echo "El origen no tiene bases de usuario." >&2; exit 1; }
echo "   bases de usuario: $(echo $bases)"
mysqlo -N -e "select table_schema, count(*), coalesce(sum(table_rows),0), round(coalesce(sum(data_length+index_length),0)/1024/1024,1) from information_schema.tables where table_schema not in ($SISTEMA) group by 1 order by 1" > "$TMP/origen.txt"
echo "   base                    tablas   filas(aprox)   MB"
awk '{printf "   %-22s %6s %12s %8s\n", $1, $2, $3, $4}' "$TMP/origen.txt"

echo "== 2. Volcado hacia $CARPETA"
mkdir -p "$CARPETA"; chmod 700 "$CARPETA"
archivo="mysql-externo-$H-$(date +%Y%m%d-%H%M).sql.gz"
docker run --rm "${red[@]}" -e MYSQL_PWD="$P" "$IMAGEN" sh -c "mysqldump -h '$H' -P '$PT' -u '$U' --ssl-mode='$SSL_MODE' --single-transaction --routines --triggers --events --no-tablespaces --set-gtid-purged=OFF --databases $(echo $bases) | gzip" > "$CARPETA/$archivo"
chmod 600 "$CARPETA/$archivo"
gzip -t "$CARPETA/$archivo" && echo "   archivo: $CARPETA/$archivo ($(du -h "$CARPETA/$archivo" | cut -f1)), compresion sana"

echo "== 3. Verificando: se restaura en un contenedor temporal sin red"
mc="verificar-mysql-$$"; clave="$(openssl rand -hex 16)"
docker run -d --name "$mc" --network none -e MYSQL_ROOT_PASSWORD="$clave" "$IMAGEN" >/dev/null; contenedores+=("$mc")
listo=""; for i in $(seq 1 90); do docker exec -e MYSQL_PWD="$clave" "$mc" mysqladmin ping -h 127.0.0.1 -uroot --silent >/dev/null 2>&1 && { listo=1; break; }; sleep 2; done
[ -n "$listo" ] || { echo "El MySQL temporal no arranco" >&2; exit 1; }
gunzip -c "$CARPETA/$archivo" | docker exec -i -e MYSQL_PWD="$clave" "$mc" mysql -uroot 2>"$TMP/r.txt" || { echo "FALLO al restaurar el volcado:" >&2; head -5 "$TMP/r.txt" | sed 's/^/   /' >&2; exit 1; }
docker exec -e MYSQL_PWD="$clave" "$mc" mysql -uroot -N -e "select table_schema, count(*) from information_schema.tables where table_schema not in ($SISTEMA) group by 1 order by 1" > "$TMP/restaurado.txt"
mal=0
echo "   base                    tablas origen / restauradas"
while read -r base tablas _; do
  r="$(awk -v b="$base" '$1==b {print $2}' "$TMP/restaurado.txt")"
  if [ "${r:-0}" = "$tablas" ]; then estado=OK; else estado=DIFERENTE; mal=1; fi
  printf '   %-22s %6s / %-6s %s\n' "$base" "$tablas" "${r:-0}" "$estado"
done < "$TMP/origen.txt"
echo
if [ "$mal" -ne 0 ]; then echo "HAY DIFERENCIAS: no cierres el origen. El volcado queda en $CARPETA/$archivo." >&2; exit 1; fi
echo "RESPALDO VERIFICADO: $CARPETA/$archivo"
echo "Es una copia completa y restaurable de las bases de usuario del origen. No la borres hasta haber migrado y comprobado todo."
