#!/usr/bin/env bash
# Copia la base de Auditoria de Visitas desde Aiven (u otra MySQL externa) a la MySQL de este servidor (base 'auditoria') y comprueba
# tabla por tabla que quedo igual. Del origen SOLO LEE: no modifica ni borra nada.
#   sudo bash /data/apps/auditoria/migrar-datos.sh
# Antes: crear la base (new-project-db.sh mysql auditoria) y correr preparar.sh. NO levantar la API todavia (si ya corrio, ver BORRAR_DESTINO).
# Guarda el volcado en /data/backups/auditoria (se conserva: es la copia de seguridad de lo que habia en Aiven).
# Solo comparar filas sin copiar nada (para decidir si se puede cerrar el origen):  SOLO_COMPARAR=1 sudo -E bash /data/apps/auditoria/migrar-datos.sh
# Reemplazar un destino que ya tiene tablas:                                       BORRAR_DESTINO=si sudo -E bash /data/apps/auditoria/migrar-datos.sh
# Para pruebas se pueden fijar: ORIGEN_URI, DESTINO_URI, RED_DOCKER, CARPETA_RESPALDOS, SSL_ORIGEN (REQUIRED por defecto), PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ENVFILE="${ENVFILE:-/opt/sulotec/auditoria.env}"
RED_DOCKER="${RED_DOCKER:-sulotec_data}"
CARPETA="${CARPETA_RESPALDOS:-/data/backups/auditoria}"
IMAGEN="${IMAGEN:-mysql:8.4}"
SSL_ORIGEN="${SSL_ORIGEN:-REQUIRED}"
STAMP="$(date +%Y%m%d-%H%M)"
ARCHIVO="auditoria-origen-$STAMP.sql.gz"

[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }
mkdir -p "$CARPETA"; chmod 700 "$CARPETA"

limpiar() { local v="$1"; v="$(printf '%s' "$v" | sed -E $'s/\e\[[0-9;]*[A-Za-z~]//g')"; v="${v//\[200~/}"; v="${v//\[201~/}"; printf '%s' "${v//[[:space:]]/}"; }
# Lee un secreto mostrando un * por cada caracter: asi se ve que el pegado funciono sin mostrar el valor. Resultado en $V.
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
# Las claves pueden venir codificadas en la URL (%40 = @): se decodifican para el cliente mysql
decodificar() { printf '%b' "${1//%/\\x}"; }

# --- Direcciones de origen y destino (nunca se muestran en pantalla)
if [ -z "${DESTINO_URI:-}" ]; then
  [ -r "$ENVFILE" ] || { echo "Falta $ENVFILE: primero corre preparar.sh" >&2; exit 1; }
  DESTINO_URI="$(grep -E '^DATABASE_URL=' "$ENVFILE" | head -1 | cut -d= -f2-)"
fi
if [ -z "${ORIGEN_URI:-}" ]; then
  echo "Pega la direccion de la base de ORIGEN: en Aiven, Overview -> 'Service URI' (boton de copiar); o la DATABASE_URL del servicio en Render. Saldran asteriscos."
  leer_secreto "ORIGEN: "; ORIGEN_URI="$V"
fi
ORIGEN_URI="$(limpiar "$ORIGEN_URI")"
re='^mysql://([^:/@]+):([^@]*)@([^:/]+):([0-9]+)/([A-Za-z0-9_]+)'
[[ "$ORIGEN_URI" =~ $re ]]  || { echo "No entiendo el origen: debe ser mysql://usuario:clave@servidor:puerto/base (recibi ${#ORIGEN_URI} caracteres)." >&2; exit 1; }
OU="${BASH_REMATCH[1]}"; OP="$(decodificar "${BASH_REMATCH[2]}")"; OH="${BASH_REMATCH[3]}"; OPT="${BASH_REMATCH[4]}"; ODB="${BASH_REMATCH[5]}"
[[ "$DESTINO_URI" =~ $re ]] || { echo "El destino (DATABASE_URL de $ENVFILE) no es una direccion MySQL valida" >&2; exit 1; }
DU="${BASH_REMATCH[1]}"; DP="$(decodificar "${BASH_REMATCH[2]}")"; DH="${BASH_REMATCH[3]}"; DPT="${BASH_REMATCH[4]}"; DDB="${BASH_REMATCH[5]}"
echo "   origen:  $OU@$OH:$OPT/$ODB (clave de ${#OP} caracteres)"
echo "   destino: $DU@$DH:$DPT/$DDB"

# Los clientes mysql corren en contenedores; la clave viaja por entorno, nunca por la linea de comandos
mysql_o() { docker run --rm --network "$RED_DOCKER" -e MYSQL_PWD="$OP" "$IMAGEN" mysql -h "$OH" -P "$OPT" -u "$OU" --ssl-mode="$SSL_ORIGEN" -N "$@" "$ODB"; }
mysql_d() { docker run --rm -i --network "$RED_DOCKER" -e MYSQL_PWD="$DP" "$IMAGEN" mysql -h "$DH" -P "$DPT" -u "$DU" -N "$@" "$DDB"; }
tablas_de() { "$1" -e "select table_name from information_schema.tables where table_schema='$2' and table_type='BASE TABLE' order by 1"; }

echo "== 1. Conexion"
vo="$(mysql_o -e 'select version()' 2>/tmp/migrar-origen.err)" || { echo "No pude conectar con el ORIGEN. ¿Es la direccion externa y permite la IP de este servidor? Detalle:" >&2; sed 's/^/   /' /tmp/migrar-origen.err >&2; exit 1; }
vd="$(mysql_d -e 'select version()' 2>/dev/null)" || { echo "No pude conectar con el DESTINO (revisa DATABASE_URL en $ENVFILE)." >&2; exit 1; }
echo "   origen: MySQL $vo   destino: MySQL $vd"

echo "== 2. Tablas y filas en el origen"
tablas="$(tablas_de mysql_o "$ODB")"
[ -n "$tablas" ] || { echo "El origen no tiene tablas en la base '$ODB'." >&2; exit 1; }
declare -A filas_origen
for t in $tablas; do filas_origen[$t]="$(mysql_o -e "select count(*) from \`$t\`")"; done
echo "   $(echo "$tablas" | wc -l) tablas"

# SOLO_COMPARAR=1: no copia nada; solo compara las filas de cada tabla entre el origen y el destino
if [ -n "${SOLO_COMPARAR:-}" ]; then
  echo "== Comparacion de filas, origen contra destino (no se copia ni se cambia nada)"
  mal=0
  printf "   %-32s %12s %12s  %s\n" tabla origen destino resultado
  for t in $tablas; do
    d="$(mysql_d -e "select count(*) from \`$t\`" 2>/dev/null || echo FALTA)"
    if [ "$d" = "${filas_origen[$t]}" ]; then r="OK"; else r="DIFERENTE"; mal=1; fi
    printf "   %-32s %12s %12s  %s\n" "$t" "${filas_origen[$t]}" "$d" "$r"
  done
  echo
  if [ "$mal" -eq 0 ]; then echo "IGUALES: el origen y el destino tienen las mismas filas."; else echo "HAY DIFERENCIAS: lo que tenga mas filas el origen no esta en el destino (auditoria_seguridad y tracking_ubicacion crecen con el uso: si el destino ya se usa, es normal que difieran)."; fi
  exit 0
fi

echo "== 3. El destino debe estar vacio"
tablas_destino="$(tablas_de mysql_d "$DDB")"
if [ -n "$tablas_destino" ]; then
  if [ "${BORRAR_DESTINO:-}" != "si" ]; then
    echo "La base de destino ya tiene $(echo "$tablas_destino" | wc -l) tablas (¿se levanto la API antes?)." >&2
    echo "Si quieres reemplazar su contenido por el del origen: BORRAR_DESTINO=si sudo -E bash $0" >&2
    exit 1
  fi
  echo "   BORRAR_DESTINO=si: se vacian las tablas del destino"
  { echo "SET FOREIGN_KEY_CHECKS=0;"; for t in $tablas_destino; do echo "DROP TABLE IF EXISTS \`$t\`;"; done; echo "SET FOREIGN_KEY_CHECKS=1;"; } | mysql_d
fi

echo "== 4. Volcado del origen -> $CARPETA/$ARCHIVO"
# Sin --databases: el volcado no trae CREATE DATABASE ni USE, asi que se carga en la base de destino aunque se llame distinto (Aiven: defaultdb).
# Se quitan los DEFINER (usuarios del origen que no existen aqui). La copia viaja cifrada (ssl-mode).
docker run --rm --network "$RED_DOCKER" -e MYSQL_PWD="$OP" "$IMAGEN" mysqldump -h "$OH" -P "$OPT" -u "$OU" --ssl-mode="$SSL_ORIGEN" \
  --single-transaction --quick --no-tablespaces --set-gtid-purged=OFF --skip-add-locks --triggers "$ODB" \
  | sed -E 's#/\*!50017 DEFINER=[^*]*\*/##g; s#DEFINER=`[^`]*`@`[^`]*`##g' | gzip > "$CARPETA/$ARCHIVO"
chmod 600 "$CARPETA/$ARCHIVO"
gzip -t "$CARPETA/$ARCHIVO" || { echo "El volcado quedo danado (gzip -t fallo)." >&2; exit 1; }
echo "   archivo: $(du -h "$CARPETA/$ARCHIVO" | cut -f1)"

echo "== 5. Restaurando en el destino"
if ! gunzip -c "$CARPETA/$ARCHIVO" | mysql_d 2>/tmp/migrar-destino.err; then
  echo "FALLO al restaurar. El destino puede haber quedado a medias: repite con BORRAR_DESTINO=si. Detalle:" >&2
  head -5 /tmp/migrar-destino.err | sed 's/^/   /' >&2
  echo "El volcado queda en $CARPETA/$ARCHIVO (el origen no se toca)." >&2
  exit 1
fi

echo "== 6. Comparacion tabla por tabla"
mal=0
printf "   %-32s %12s %12s  %s\n" tabla origen destino resultado
for t in $tablas; do
  d="$(mysql_d -e "select count(*) from \`$t\`" 2>/dev/null || echo FALTA)"
  if [ "$d" = "${filas_origen[$t]}" ]; then r="OK"; else r="DIFERENTE"; mal=1; fi
  printf "   %-32s %12s %12s  %s\n" "$t" "${filas_origen[$t]}" "$d" "$r"
done

if [ "$mal" -ne 0 ]; then
  echo; echo "HAY DIFERENCIAS: no cierres el origen. Revisa arriba. El volcado queda en $CARPETA/$ARCHIVO." >&2
  exit 1
fi
echo
echo "TODO IGUAL: $(echo "$tablas" | wc -l) tablas, mismas filas en origen y destino."
echo "Copia del origen guardada en $CARPETA/$ARCHIVO (no la borres hasta cerrar el origen)."
echo "Siguiente: sudo bash /data/apps/auditoria/desplegar.sh"
