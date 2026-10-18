#!/usr/bin/env bash
# Borra de la base de PLAFT las cuentas de prueba (todas menos las que se indiquen conservar) junto con lo que registraron,
# para volver a crear las cuentas limpias con la carga masiva. Simula por defecto; con --aplicar respalda la base y borra.
#   sudo bash /data/apps/plaft/limpiar-cuentas-prueba.sh                      # muestra que se borraria (no toca nada)
#   sudo bash /data/apps/plaft/limpiar-cuentas-prueba.sh --aplicar            # respalda y borra
#   sudo env CONSERVAR="superadmin otro" bash /data/apps/plaft/limpiar-cuentas-prueba.sh --aplicar
# Conserva siempre 'superadmin' (y lo que diga CONSERVAR). Se borran: las cuentas, sus roles y enlaces de recuperacion, sus
# registros de operaciones (con personas, operacion y beneficiarios), sus evaluaciones de scoring, su historial de consultas,
# sus matrices de riesgo (areas, procesos y analisis) y se quita su nombre de las denuncias (las denuncias se conservan).
# Las listas negativas, PEP, sancionadas y la lista de empresas NO se tocan.
# Variables solo para pruebas: ENVFILE, RED_DOCKER, RESPALDOS, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0 [--aplicar]" >&2; exit 1; }

APLICAR=0; [ "${1:-}" = "--aplicar" ] && APLICAR=1
ENVFILE="${ENVFILE:-/opt/sulotec/plaft.env}"
RED="${RED_DOCKER:-sulotec_data}"
RESPALDOS="${RESPALDOS:-/var/backups/sulotec}"
CONSERVAR="superadmin ${CONSERVAR:-}"

for u in $CONSERVAR; do
  [[ "$u" =~ ^[A-Za-z0-9._@-]+$ ]] || { echo "Nombre de usuario no valido en CONSERVAR: '$u'." >&2; exit 1; }
done
lista=""; for u in $CONSERVAR; do lista="${lista:+$lista, }'$u'"; done

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

# Cuentas a borrar
BORRAR="select id from usuarios where usuario not in ($lista)"
cuantas="$(cliente -N -e "select count(*) from usuarios where usuario not in ($lista)")"
echo "== Base '$BASE': se conservan [$CONSERVAR]; cuentas a borrar: $cuantas"
cliente -t -e "select usuario, coalesce(nullif(trim(empresa),''),'(sin empresa)') as empresa, activo+0 as activa from usuarios where usuario not in ($lista) order by id"
[ "${cuantas:-0}" -gt 0 ] || { echo "No hay cuentas que borrar."; exit 0; }

# Que se borraria con ellas (solo las tablas que existan)
echo "== Datos ligados a esas cuentas"
contar() { local tabla="$1" cond="$2"; if existe_tabla "$tabla"; then printf '   %-32s %s\n' "$tabla" "$(cliente -N -e "select count(*) from $tabla where $cond")"; fi; }
contar usuario_roles              "id_usuario in ($BORRAR)"
contar password_reset_tokens      "id_usuario in ($BORRAR)"
contar registro_operaciones_v2    "id_usuario in ($BORRAR)"
contar scoring_riesgo             "id_usuario in ($BORRAR)"
contar historial_consultas        "id_usuarios in ($BORRAR)"
contar matriz_riesgo_analisis     "id_usuario in ($BORRAR)"
contar matriz_riesgo_area_proceso "id_usuario in ($BORRAR)"
contar matriz_riesgo_areas        "id_usuario in ($BORRAR)"
contar matriz_riesgo_procesos     "id_usuario in ($BORRAR)"
if existe_tabla denuncias; then
  printf '   %-32s %s (se conservan; se quita el nombre de la cuenta)\n' "denuncias" "$(cliente -N -e "select count(*) from denuncias where receptor_usuario_id in ($BORRAR) or creado_por_usuario_id in ($BORRAR)")"
fi

if [ "$APLICAR" != 1 ]; then
  echo
  echo "Simulacion: no se borro nada. Para borrar de verdad:  sudo bash $0 --aplicar"
  exit 0
fi

echo "== Respaldo de la base '$BASE' antes de borrar"
mkdir -p "$RESPALDOS"; chmod 700 "$RESPALDOS"
copia="$RESPALDOS/${BASE}_antes-de-limpiar-cuentas_$(date +%F_%H%M).sql.gz"
if ! MYSQL_PWD="$DB_PASSWORD" docker run --rm --network "$RED" -e MYSQL_PWD mysql:8.4 \
     mysqldump -h mysql -u"$DB_USER" --no-tablespaces --single-transaction "$BASE" | gzip > "$copia"; then
  rm -f "$copia"; echo "No pude respaldar la base: no borro nada." >&2; exit 1
fi
echo "   $copia ($(du -h "$copia" | cut -f1))"

# Todo en UNA transaccion; sin comprobar llaves foraneas para no depender del orden (al final se vuelven a activar).
SQL="set foreign_key_checks = 0; start transaction;"
agregar() { if existe_tabla "$1"; then SQL="$SQL $2;"; fi; }
agregar denuncia_historial         "update denuncia_historial set id_usuario = null where id_usuario in ($BORRAR)"
agregar denuncias                  "update denuncias set receptor_usuario_id = null where receptor_usuario_id in ($BORRAR)"
agregar denuncias                  "update denuncias set creado_por_usuario_id = null where creado_por_usuario_id in ($BORRAR)"
agregar registro_operaciones_v2    "update registro_operaciones_v2 set id_usuario_responsable = null where id_usuario_responsable in ($BORRAR)"
agregar beneficiarios_operacion_v2 "delete from beneficiarios_operacion_v2 where registro_id in (select id from registro_operaciones_v2 where id_usuario in ($BORRAR))"
agregar operaciones_v2             "delete from operaciones_v2 where id in (select id_operacion from registro_operaciones_v2 where id_usuario in ($BORRAR))"
agregar personas_operacion         "delete from personas_operacion where id in (select id_persona_fisica from registro_operaciones_v2 where id_usuario in ($BORRAR)) or id in (select id_persona_representada from registro_operaciones_v2 where id_usuario in ($BORRAR) and id_persona_representada is not null)"
agregar registro_operaciones_v2    "delete from registro_operaciones_v2 where id_usuario in ($BORRAR)"
agregar scoring_riesgo             "delete from scoring_riesgo where id_usuario in ($BORRAR)"
agregar historial_consultas        "delete from historial_consultas where id_usuarios in ($BORRAR)"
agregar matriz_riesgo_analisis     "delete from matriz_riesgo_analisis where id_usuario in ($BORRAR)"
agregar matriz_riesgo_area_proceso "delete from matriz_riesgo_area_proceso where id_usuario in ($BORRAR)"
agregar matriz_riesgo_procesos     "delete from matriz_riesgo_procesos where id_usuario in ($BORRAR)"
agregar matriz_riesgo_areas        "delete from matriz_riesgo_areas where id_usuario in ($BORRAR)"
agregar password_reset_tokens      "delete from password_reset_tokens where id_usuario in ($BORRAR)"
agregar usuario_roles              "delete from usuario_roles where id_usuario in ($BORRAR)"
SQL="$SQL delete from usuarios where usuario not in ($lista); commit; set foreign_key_checks = 1;"

echo "== Borrando"
printf '%s\n' "$SQL" | cliente || { echo "Fallo el borrado: la transaccion se deshizo. La base sigue como estaba (y tienes el respaldo)." >&2; exit 1; }
echo "   quedan $(cliente -N -e 'select count(*) from usuarios') cuenta(s): $(cliente -N -e 'select group_concat(usuario) from usuarios')"
echo "Listo. Ahora crea las cuentas desde la web: Administracion -> Cuentas -> Carga masiva."
