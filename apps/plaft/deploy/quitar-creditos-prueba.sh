#!/usr/bin/env bash
# Quita de la base de PLAFT las cuatro tablas del modulo de creditos de prueba, que ya no usa el backend: las licencias
# viven ahora en el servicio comun 'licencias'. Simula por defecto; con --aplicar respalda la base y borra.
#   sudo bash /data/apps/plaft/quitar-creditos-prueba.sh                # muestra que se borraria (no toca nada)
#   sudo bash /data/apps/plaft/quitar-creditos-prueba.sh --aplicar      # respalda y borra
# Tablas: licencias_empresa, movimientos_credito, tarifas_credito, avisos_licencia (solo las que existan).
# No toca ninguna otra tabla: usuarios, empresas, listas, operaciones, matrices y denuncias quedan igual.
# Variables solo para pruebas: ENVFILE, RED_DOCKER, RESPALDOS, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0 [--aplicar]" >&2; exit 1; }

APLICAR=0; [ "${1:-}" = "--aplicar" ] && APLICAR=1
ENVFILE="${ENVFILE:-/opt/sulotec/plaft.env}"
RED="${RED_DOCKER:-sulotec_data}"
RESPALDOS="${RESPALDOS:-/var/backups/sulotec}"
TABLAS="licencias_empresa movimientos_credito tarifas_credito avisos_licencia"

[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE" >&2; exit 1; }
leer() { grep -E "^$1=" "$ENVFILE" | head -1 | cut -d= -f2- || true; }
DB_URL="$(leer DB_URL)"; DB_USER="$(leer DB_USER)"; DB_PASSWORD="$(leer DB_PASSWORD)"
{ [ -n "$DB_URL" ] && [ -n "$DB_USER" ] && [ -n "$DB_PASSWORD" ]; } || { echo "$ENVFILE no tiene DB_URL, DB_USER y DB_PASSWORD." >&2; exit 1; }
BASE="${DB_URL#*://}"; BASE="${BASE#*/}"; BASE="${BASE%%[?]*}"
[ -n "$BASE" ] || { echo "No pude sacar el nombre de la base de DB_URL." >&2; exit 1; }

# La clave viaja por entorno (no por la linea de comandos).
cliente() { MYSQL_PWD="$DB_PASSWORD" docker run --rm -i --network "$RED" -e MYSQL_PWD mysql:8.4 mysql -h mysql -u"$DB_USER" "$@" "$BASE"; }
existe_tabla() { [ "$(cliente -N -e "select count(*) from information_schema.tables where table_schema='$BASE' and table_name='$1'")" = "1" ]; }

cliente -N -e 'select 1' >/dev/null || { echo "No pude conectar con la base $BASE." >&2; exit 1; }

echo "== Base '$BASE': tablas del modulo de creditos de prueba"
existentes=""
for t in $TABLAS; do
  if existe_tabla "$t"; then
    existentes="$existentes $t"
    printf '   %-24s %s fila(s)\n' "$t" "$(cliente -N -e "select count(*) from $t")"
  else
    printf '   %-24s no existe (nada que borrar)\n' "$t"
  fi
done
[ -n "$existentes" ] || { echo "No hay tablas que quitar. Listo."; exit 0; }

if [ "$APLICAR" != 1 ]; then
  echo
  echo "Simulacion: no se borro nada. Para borrar de verdad:  sudo bash $0 --aplicar"
  exit 0
fi

echo "== Respaldo de la base '$BASE' antes de borrar"
mkdir -p "$RESPALDOS"; chmod 700 "$RESPALDOS"
copia="$RESPALDOS/${BASE}_antes-de-quitar-creditos_$(date +%F_%H%M).sql.gz"
if ! MYSQL_PWD="$DB_PASSWORD" docker run --rm --network "$RED" -e MYSQL_PWD mysql:8.4 \
     mysqldump -h mysql -u"$DB_USER" --no-tablespaces --single-transaction "$BASE" | gzip > "$copia"; then
  rm -f "$copia"; echo "No pude respaldar la base: no borro nada." >&2; exit 1
fi
echo "   $copia ($(du -h "$copia" | cut -f1))"

# Las tablas no tienen claves foraneas hacia otras; DROP es DDL y no se puede deshacer, por eso el respaldo va antes.
SQL="set foreign_key_checks = 0;"
for t in $existentes; do SQL="$SQL drop table if exists $t;"; done
SQL="$SQL set foreign_key_checks = 1;"

echo "== Quitando las tablas"
printf '%s\n' "$SQL" | cliente || { echo "Fallo el borrado. Revisa las tablas con el respaldo en $copia (si hace falta, restaurar desde ahi)." >&2; exit 1; }
for t in $existentes; do
  if existe_tabla "$t"; then echo "FALLA: la tabla $t sigue en la base. Respaldo: $copia" >&2; exit 1; fi
done
echo "Listo. Se quitaron:$existentes"
echo "La copia de la base esta en $copia (guardala unos dias y luego borrala)."
echo "Siguiente: sudo bash /data/apps/plaft/probar.sh"
