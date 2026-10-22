#!/usr/bin/env bash
# Crea o actualiza una EMPRESA (un cliente de Sulotec: una caja, un negocio) en la cuenta Sulotec (Keycloak).
# La empresa es un subgrupo de "Empresas" con su UUID y sus datos en atributos, y con los roles producto-* de los
# productos que tiene contratados. Las personas de esa empresa se ponen en el grupo (cuentas.sh) y heredan todo.
#   sudo bash /data/apps/cuenta/empresa.sh "Caja Huancayo" caja-huancayo auditoria,miradar360
#   sudo bash /data/apps/cuenta/empresa.sh "Caja Piura" caja-piura auditoria --uuid 1b4e28ba-2fa1-11d2-883f-0016d3cca427
#   sudo bash /data/apps/cuenta/empresa.sh --listar
# - nombre: como se llama la empresa (entre comillas). slug: identificador corto, sin espacios (letras, numeros, guion).
# - productos: separados por coma; validos: auditoria (GeoMatrix), miradar360, plaft, dashboard. La lista es la definitiva:
#   lo que no este se quita.
# - --uuid: para usar el UUID que la empresa YA tiene en un producto. Si no se indica, se genera uno nuevo.
# Se puede repetir: si la empresa existe, actualiza nombre y productos y CONSERVA el UUID (nunca lo cambia).
# El mismo UUID se usa al crear la empresa dentro de cada producto: asi el cliente se identifica igual en todo Sulotec.
# Variables solo para pruebas: CONTENEDOR (por defecto cuenta), PRUEBA.
set -euo pipefail

CONTENEDOR="${CONTENEDOR:-cuenta}"
if [ -z "${DENTRO:-}" ]; then
  [ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0 ..." >&2; exit 1; }
  docker ps --format '{{.Names}}' | grep -qx "$CONTENEDOR" || { echo "El contenedor '$CONTENEDOR' no esta corriendo." >&2; exit 1; }
  exec docker exec -i -e DENTRO=1 "$CONTENEDOR" bash -s -- "$@" < "$0"
fi

# ---------- desde aqui corre DENTRO del contenedor de Keycloak ----------
kc() { /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/empresa.config; }
trap 'rm -f /tmp/empresa.config' EXIT
kc config credentials --server http://127.0.0.1:8080 --realm master \
  --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null

PRODUCTOS_VALIDOS="auditoria miradar360 plaft dashboard"
PADRE="Empresas"

# (la imagen de Keycloak no trae awk: se usa grep/cut; el "|| true" evita que "no encontrado" corte el script con set -e)
padre_id() {
  kc get groups -r sulotec -q search="$PADRE" -q exact=true --fields id,name --format csv --noquotes \
    | grep -E "^[^,]+,$PADRE\$" | head -1 | cut -d, -f1 || true
}
hijo_id() { # slug -> id del subgrupo de Empresas
  kc get "groups/$pid/children" -r sulotec -q max=500 --fields id,name --format csv --noquotes \
    | grep -E "^[^,]+,$1\$" | head -1 | cut -d, -f1 || true
}
atributo() { # id-del-grupo nombre-del-atributo -> valor (kcadm solo expande el atributo si se pide por nombre)
  kc get "groups/$1" -r sulotec --fields "attributes($2)" --format csv --noquotes | head -1 || true
}
roles_de() { kc get "groups/$1/role-mappings/realm" -r sulotec --fields name --format csv --noquotes | grep '^producto-' || true; }

pid=$(padre_id)
[ -n "$pid" ] || { echo "No existe el grupo '$PADRE'. Corre primero ajustar-realm.sh (lo crea)." >&2; exit 1; }

if [ "${1:-}" = "--listar" ]; then
  echo "Empresas registradas en la cuenta Sulotec:"
  kc get "groups/$pid/children" -r sulotec -q max=500 --fields id,name --format csv --noquotes | while IFS=, read -r gid gname; do
    [ -n "$gid" ] || continue
    printf '  %-24s %-36s %-30s %s\n' "$gname" "$(atributo "$gid" empresa_uuid)" "$(atributo "$gid" empresa_nombre)" "$(roles_de "$gid" | sed 's/^producto-//' | paste -sd, -)"
  done
  exit 0
fi

nombre="${1:-}"; slug="${2:-}"; productos="${3:-}"; uuid=""
shift $(( $# >= 3 ? 3 : $# ))
while [ $# -gt 0 ]; do
  case "$1" in
    --uuid) uuid="${2:-}"; shift 2 ;;
    *) echo "Opcion no reconocida: $1" >&2; exit 1 ;;
  esac
done
[ -n "$nombre" ] && [ -n "$slug" ] && [ -n "$productos" ] || { echo "Uso: empresa.sh \"Nombre\" slug producto1,producto2 [--uuid UUID]   |   empresa.sh --listar" >&2; exit 1; }
[[ "$slug" =~ ^[a-z0-9][a-z0-9-]{1,38}$ ]] || { echo "El slug '$slug' no vale: solo minusculas, numeros y guion (ej. caja-huancayo)." >&2; exit 1; }
[ -z "$uuid" ] || [[ "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || { echo "El UUID '$uuid' no tiene el formato correcto." >&2; exit 1; }
uuid=$(echo "$uuid" | tr 'A-F' 'a-f')

deseados=""
for p in $(echo "$productos" | tr ',' ' '); do
  echo " $PRODUCTOS_VALIDOS " | grep -q " $p " || { echo "Producto '$p' no existe. Validos: $PRODUCTOS_VALIDOS" >&2; exit 1; }
  kc get "roles/producto-$p" -r sulotec >/dev/null 2>&1 || { echo "Falta el rol producto-$p en Keycloak: corre ajustar-realm.sh." >&2; exit 1; }
  deseados="$deseados producto-$p"
done

gid=$(hijo_id "$slug")
if [ -z "$gid" ]; then
  [ -n "$uuid" ] || uuid=$(cat /proc/sys/kernel/random/uuid)
  # Un UUID identifica a UNA empresa: no se admite repetirlo
  while IFS=, read -r oid oname; do
    [ -n "$oid" ] || continue
    if [ "$(atributo "$oid" empresa_uuid)" = "$uuid" ]; then
      echo "El UUID $uuid ya es de la empresa '$oname'. Cada empresa tiene su propio UUID." >&2; exit 1
    fi
  done <<< "$(kc get "groups/$pid/children" -r sulotec -q max=500 --fields id,name --format csv --noquotes)"
  kc create "groups/$pid/children" -r sulotec -b "{\"name\":\"$slug\",\"attributes\":{\"empresa_uuid\":[\"$uuid\"],\"empresa_nombre\":[\"$nombre\"],\"empresa_slug\":[\"$slug\"]}}" >/dev/null
  gid=$(hijo_id "$slug")
  [ -n "$gid" ] || { echo "No pude crear el grupo de la empresa." >&2; exit 1; }
  accion="creada"
else
  actual=$(atributo "$gid" empresa_uuid)
  if [ -n "$uuid" ] && [ -n "$actual" ] && [ "$uuid" != "$actual" ]; then
    echo "La empresa '$slug' ya existe con el UUID $actual y no se cambia (el UUID identifica al cliente en todos los productos)." >&2; exit 1
  fi
  uuid="${actual:-$uuid}"; [ -n "$uuid" ] || uuid=$(cat /proc/sys/kernel/random/uuid)
  # (kcadm manda el cuerpo tal cual: hay que repetir el nombre del grupo)
  kc update "groups/$gid" -r sulotec -b "{\"name\":\"$slug\",\"attributes\":{\"empresa_uuid\":[\"$uuid\"],\"empresa_nombre\":[\"$nombre\"],\"empresa_slug\":[\"$slug\"]}}" >/dev/null
  accion="actualizada"
fi

# Roles de producto: deja exactamente los pedidos
actuales=$(roles_de "$gid")
for r in $deseados; do
  echo "$actuales" | grep -qx "$r" || kc add-roles -r sulotec --gid "$gid" --rolename "$r" >/dev/null
done
for r in $actuales; do
  echo " $deseados " | grep -q " $r " || kc remove-roles -r sulotec --gid "$gid" --rolename "$r" >/dev/null
done

echo "Empresa '$nombre' ($slug) $accion."
echo "   UUID:      $uuid"
echo "   Productos: $(echo "$deseados" | sed 's/producto-//g' | xargs | tr ' ' ',')"
echo "Usa ese mismo UUID al crear la empresa dentro de cada producto. Para sus cuentas: cuentas.sh con empresa=$slug."
