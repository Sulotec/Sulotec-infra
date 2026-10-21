#!/usr/bin/env bash
# Limpieza TOTAL de datos del Sistema de Planillas: borra trabajadores, asistencias, horarios, movimientos, planillas y
# boletas (y su auditoria). CONSERVA los usuarios y la configuracion (regimenes, conceptos, AFP, feriados, reglas de tardanza),
# asi nadie pierde el acceso. Antes guarda una copia completa de la base en /var/backups/sulotec/.
#   sudo bash /data/apps/planilla/limpiar-datos.sh
# Para volver atras con la copia:  zcat /var/backups/sulotec/planilla-antes-limpieza-<fecha>.sql.gz | sudo bash /data/apps/planilla/limpiar-datos.sh --restaurar
set -euo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

ENVFILE=/opt/sulotec/planilla.env
[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE" >&2; exit 1; }
leer() { grep -E "^$1=" "$ENVFILE" | head -1 | cut -d= -f2-; }
DB_USER="$(leer DB_USER)"; DB_PASSWORD="$(leer DB_PASSWORD)"; DB_NAME="$(leer DB_NAME)"; DB_HOST="$(leer DB_HOST)"; DB_PORT="$(leer DB_PORT)"
{ [ -n "$DB_USER" ] && [ -n "$DB_PASSWORD" ] && [ -n "$DB_NAME" ]; } || { echo "$ENVFILE no tiene los datos de la base." >&2; exit 1; }
# La clave de la base viaja por entorno, nunca por la linea de comandos
sql() { MYSQL_PWD="$DB_PASSWORD" docker run --rm -i --network sulotec_data -e MYSQL_PWD mysql:8.4 mysql -h "$DB_HOST" -P "$DB_PORT" -u"$DB_USER" "$@" "$DB_NAME"; }

if [ "${1:-}" = "--restaurar" ]; then
  echo "== Restaurando la base $DB_NAME desde lo que llega por la entrada..."
  sql
  echo "== Listo. Reinicia la app: cd /data/apps/planilla && docker compose restart"
  exit 0
fi

# Orden: primero las tablas que dependen de otras. Las *_aud son la auditoria (Envers) de cada una.
DATOS="boleta_detalle boleta_pago movimiento_planilla asistencia_diaria horario_programado planilla_cabecera empleado"

contar() { sql -N -e "select count(*) from $1" 2>/dev/null || echo "(no existe)"; }

echo "== Sistema de Planillas: limpieza total de datos (base $DB_NAME)"
echo "   Se CONSERVAN: usuarios, regimenes, conceptos, AFP, feriados y reglas de tardanza."
echo "== Filas que se van a borrar"
for t in $DATOS; do printf '   %-22s %s\n' "$t" "$(contar "$t")"; done
printf '   %-22s %s\n' "usuario (se conserva)" "$(contar usuario)"
read -rp "Escribe SI (en mayusculas) para borrar: " ok
[ "$ok" = "SI" ] || { echo "Cancelado: no se borro nada."; exit 1; }

mkdir -p /var/backups/sulotec
copia="/var/backups/sulotec/planilla-antes-limpieza-$(date +%Y%m%d-%H%M%S).sql.gz"
MYSQL_PWD="$DB_PASSWORD" docker run --rm --network sulotec_data -e MYSQL_PWD mysql:8.4 \
  mysqldump -h "$DB_HOST" -P "$DB_PORT" -u"$DB_USER" --single-transaction --quick "$DB_NAME" | gzip > "$copia"
chmod 600 "$copia"
echo "   Copia guardada en $copia (por si hay que volver atras)"

# Solo se tocan las tablas que existan (las _aud las crea Envers al primer cambio)
existentes="$(sql -N -e "select table_name from information_schema.tables where table_schema = database()")"
{
  echo "SET FOREIGN_KEY_CHECKS=0;"
  for t in $DATOS; do
    for x in "$t" "${t}_aud"; do
      if grep -qx "$x" <<< "$existentes"; then echo "TRUNCATE TABLE $x;"; fi
    done
  done
  echo "SET FOREIGN_KEY_CHECKS=1;"
} | sql

echo "== Listo. Filas ahora:"
for t in $DATOS; do printf '   %-22s %s\n' "$t" "$(contar "$t")"; done
echo "Los usuarios siguen igual. Puedes volver a cargar los trabajadores desde Empleados -> Importar."
