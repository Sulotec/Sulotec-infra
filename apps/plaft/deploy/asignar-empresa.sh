#!/usr/bin/env bash
# Deja a los usuarios de PLAFT con una empresa para poder usar el modulo Operaciones: el listado y los registros se filtran por la
# empresa del usuario, y un usuario sin empresa no puede entrar a ese modulo.
#   sudo bash /data/apps/plaft/asignar-empresa.sh                        # a los usuarios SIN empresa les pone la del usuario de menor id
#                                                                        # (o "Empresa Demo" si ese tampoco tiene)
#   sudo bash /data/apps/plaft/asignar-empresa.sh admin001 lavado_pru    # a esos usuarios les pone esa empresa aunque ya tengan otra
# La empresa elegida es la que ve los registros DEMO (cargar-operaciones-demo.sh los deja a nombre del usuario de menor id).
# Es para las pruebas: con clientes reales cada usuario debe tener su propia empresa (no corras esto despues de crearlos).
# No hace falta volver a entrar: la web consulta la empresa en la base cada vez que abres Operaciones.
# Variables solo para pruebas: APP, ENVFILE, RED_DOCKER, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0 [usuario ...]" >&2; exit 1; }

ENVFILE="${ENVFILE:-/opt/sulotec/plaft.env}"
RED="${RED_DOCKER:-sulotec_data}"
POR_DEFECTO="Empresa Demo"

# Los nombres de usuario van dentro del SQL: solo se aceptan letras, numeros y . _ @ -
for u in "$@"; do
  [[ "$u" =~ ^[A-Za-z0-9._@-]+$ ]] || { echo "Nombre de usuario no valido: '$u' (solo letras, numeros y . _ @ -)." >&2; exit 1; }
done

[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE" >&2; exit 1; }
leer() { grep -E "^$1=" "$ENVFILE" | head -1 | cut -d= -f2- || true; }
DB_URL="$(leer DB_URL)"; DB_USER="$(leer DB_USER)"; DB_PASSWORD="$(leer DB_PASSWORD)"
{ [ -n "$DB_URL" ] && [ -n "$DB_USER" ] && [ -n "$DB_PASSWORD" ]; } || { echo "$ENVFILE no tiene DB_URL, DB_USER y DB_PASSWORD." >&2; exit 1; }
BASE="${DB_URL#*://}"; BASE="${BASE#*/}"; BASE="${BASE%%[?]*}"
[ -n "$BASE" ] || { echo "No pude sacar el nombre de la base de DB_URL." >&2; exit 1; }

# La clave viaja por entorno (no por la linea de comandos).
cliente() { MYSQL_PWD="$DB_PASSWORD" docker run --rm -i --network "$RED" -e MYSQL_PWD mysql:8.4 mysql -h mysql -u"$DB_USER" "$@" "$BASE"; }

total="$(cliente -N -e 'select count(*) from usuarios')" || { echo "No pude conectar con la base $BASE." >&2; exit 1; }
[ "${total:-0}" -ge 1 ] 2>/dev/null || { echo "No hay usuarios en la base $BASE." >&2; exit 1; }

# La empresa sale de la propia base (sin pasarla por la linea de comandos): se guarda en una variable de la conexion y despues se usa
# en el update (en dos sentencias, porque MySQL no deja leer en el mismo update la tabla que se esta actualizando).
ELEGIR_EMPRESA="set @empresa = (select coalesce(nullif(trim(empresa), ''), '$POR_DEFECTO') from usuarios order by id limit 1);"
if [ "$#" -eq 0 ]; then
  DONDE="empresa is null or trim(empresa) = ''"
  QUE="los usuarios sin empresa"
else
  lista=""; for u in "$@"; do lista="${lista:+$lista, }'$u'"; done
  DONDE="usuario in ($lista)"
  QUE="los usuarios: $*"
fi

echo "== Empresa de los usuarios en la base '$BASE' (antes)"
cliente -t -e "select coalesce(nullif(trim(empresa), ''), '(sin empresa)') as empresa, count(*) as usuarios from usuarios group by 1 order by 2 desc"

echo "== Asignando la empresa a $QUE"
cliente -e "$ELEGIR_EMPRESA update usuarios set empresa = @empresa where $DONDE" \
  || { echo "No pude actualizar los usuarios." >&2; exit 1; }

echo "== Empresa de los usuarios (despues)"
cliente -t -e "select coalesce(nullif(trim(empresa), ''), '(sin empresa)') as empresa, count(*) as usuarios from usuarios group by 1 order by 2 desc"
if [ "$#" -gt 0 ]; then
  echo "== Usuarios indicados"
  cliente -t -e "select usuario, coalesce(nullif(trim(empresa), ''), '(sin empresa)') as empresa from usuarios where $DONDE order by id"
fi
echo "== Registros DEMO de Operaciones: a nombre de quien y en que empresa se ven"
cliente -t -e "select u.usuario, coalesce(nullif(trim(u.empresa), ''), '(sin empresa)') as empresa, count(*) as registros from registro_operaciones_v2 r join usuarios u on u.id = r.id_usuario where r.numero_registro like 'DEMO-%' group by u.usuario, u.empresa" \
  || echo "(No pude consultar los registros DEMO: aun no existe la tabla de Operaciones.)" >&2
echo "Listo. Abre Registro de operaciones en la web (no hace falta volver a entrar)."
