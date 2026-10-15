#!/usr/bin/env bash
# Muestra ejemplos REALES de lo que hay cargado en la base de PLAFT para probar cada modulo de la web: que escribir en el buscador de
# listas negativas, que cuentas hay, que denuncias, operaciones y matrices. Solo lee; no cambia nada ni muestra claves.
#   sudo bash /data/apps/plaft/ejemplos-para-probar.sh
# Variables solo para pruebas: ENVFILE, RED_DOCKER, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

ENVFILE="${ENVFILE:-/opt/sulotec/plaft.env}"
RED="${RED_DOCKER:-sulotec_data}"
[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE" >&2; exit 1; }
leer() { grep -E "^$1=" "$ENVFILE" | head -1 | cut -d= -f2- || true; }
DB_URL="$(leer DB_URL)"; DB_USER="$(leer DB_USER)"; DB_PASSWORD="$(leer DB_PASSWORD)"
{ [ -n "$DB_URL" ] && [ -n "$DB_USER" ] && [ -n "$DB_PASSWORD" ]; } || { echo "$ENVFILE no tiene DB_URL, DB_USER y DB_PASSWORD." >&2; exit 1; }
BASE="${DB_URL#*://}"; BASE="${BASE#*/}"; BASE="${BASE%%[?]*}"

consulta() { MYSQL_PWD="$DB_PASSWORD" docker run --rm --network "$RED" -e MYSQL_PWD mysql:8.4 mysql -h mysql -u"$DB_USER" --default-character-set=utf8mb4 -t -e "$1" "$BASE"; }
NOMBRE="coalesce(pj.razon_social, concat_ws(' ', pn.nombre, pn.ape_pat, pn.ape_mat))"
UNIONES="join tipo_documento td on td.id = e.id_tipo_documento left join personas_juridicas pj on pj.id_entidades = e.id left join personas_naturales pn on pn.id_entidades = e.id"

echo "== LISTAS NEGATIVAS - buscar por NOMBRE (figuras politicas con sus noticias; escribe los nombres y apellidos en el buscador)"
consulta "select left(pn.nombre, 28) as nombres, left(pn.ape_pat, 32) as apellidos from personas_naturales pn join entidades e on e.id = pn.id_entidades where e.documento like 'SIN-DOC-%' order by e.id limit 6"

echo "== LISTAS NEGATIVAS - buscar por DOCUMENTO (sancionadas por la SBS: elige el tipo RUC)"
consulta "select td.nombre as tipo, e.documento, left($NOMBRE, 44) as nombre from historial_manchas hm join tipo_lista tl on tl.id = hm.id_tipo_lista join entidades e on e.id = hm.id_entidades $UNIONES where tl.nombre like 'Peru - Personas sancionadas por la Superintendencia%' order by e.id limit 4"

echo "== LISTAS NEGATIVAS - personas y empresas de demostracion (base de desarrollo)"
consulta "select td.nombre as tipo, e.documento, left($NOMBRE, 36) as nombre, left(tl.nombre, 32) as lista from historial_manchas hm join tipo_lista tl on tl.id = hm.id_tipo_lista join entidades e on e.id = hm.id_entidades $UNIONES where tl.nombre in ('Personas Expuestas Politicamente', 'Actos Ilicitos', 'Listas Internacionales') order by tl.nombre, e.id limit 9"

echo "== CUENTAS (usuario, rol, estado; las claves son las de desarrollo, no se muestran)"
consulta "select u.usuario, r.codigo as rol, if(u.activo, 'activo', 'inactivo') as estado from usuarios u left join usuario_roles ur on ur.id_usuario = u.id left join roles r on r.id = ur.id_rol order by u.id"

echo "== DENUNCIAS (el seguimiento publico pide codigo y PIN; el PIN no se puede ver)"
consulta "select id, codigo_seguimiento, causa, if(anonima, 'si', 'no') as anonima from denuncias order by id"

echo "== OPERACIONES (registros de demostracion)"
consulta "select numero_registro, empresa, oficina, fecha_registro from registro_operaciones_v2 order by id limit 4"

echo "== MATRIZ DE RIESGOS (areas y procesos cargados)"
consulta "select 'area' as tipo, nombre from matriz_riesgo_areas union all select 'proceso', nombre from matriz_riesgo_procesos"

echo
echo "SCORING: no hay nada que escribir; elige una ocupacion y un departamento de las listas y una persona de la base (por ejemplo una de LISTAS NEGATIVAS)."
