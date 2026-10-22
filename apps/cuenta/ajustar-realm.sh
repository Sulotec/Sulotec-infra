#!/usr/bin/env bash
# Ajustes del realm "sulotec" que el JSON solo aplica al crearlo (--import-realm no toca un realm existente).
# Corre DENTRO del contenedor y es seguro repetirlo:
#   docker exec -i cuenta bash -s < /data/apps/cuenta/ajustar-realm.sh
# Lo ejecutan el workflow "Publicar cuenta" y preparar.sh, con el administrador de /opt/sulotec/cuenta.env.
set -euo pipefail

kc() { /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/ajustes.config; }
trap 'rm -f /tmp/ajustes.config' EXIT
kc config credentials --server http://127.0.0.1:8080 --realm master \
  --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null

cid=$(kc get clients -r sulotec -q clientId=portal --fields id --format csv --noquotes)

# 1) El id_token del portal dice si la persona es administrador general (claim "roles"):
#    asi sulotec.com/mis-productos le muestra todos los productos.
if ! kc get "clients/$cid/protocol-mappers/models" -r sulotec --fields name --format csv --noquotes | grep -qx roles; then
  kc create "clients/$cid/protocol-mappers/models" -r sulotec -b '{"name":"roles","protocol":"openid-connect","protocolMapper":"oidc-usermodel-realm-role-mapper","config":{"claim.name":"roles","jsonType.label":"String","multivalued":"true","id.token.claim":"true","access.token.claim":"false","userinfo.token.claim":"false","introspection.token.claim":"false"}}'
  echo "Ajuste: roles en el token del portal"
fi

# 2) El portal solo puede ver ese rol (no todos los roles del realm)
rid=$(kc get roles/administrador-general -r sulotec --fields id --format csv --noquotes)
kc create "clients/$cid/scope-mappings/realm" -r sulotec -b "[{\"id\":\"$rid\",\"name\":\"administrador-general\"}]"

# 3) Sulotec es un SaaS: las cuentas las crea el equipo en la consola (no hay registro libre).
#    Las personas si pueden recuperar su acceso con "¿Olvidaste tu contraseña?" (necesita el correo de salida).
kc update realms/sulotec -s registrationAllowed=false -s resetPasswordAllowed=true

# 4) Quitar los proveedores Google/Microsoft de reserva: al primer ingreso creaban cuentas solas.
#    Solo se borran si nunca se configuraron (clientId "pegar-aqui").
for alias in google microsoft; do
  if kc get "identity-provider/instances/$alias" -r sulotec 2>/dev/null | grep -q '"clientId" : "pegar-aqui"'; then
    kc delete "identity-provider/instances/$alias" -r sulotec
    echo "Ajuste: proveedor $alias de reserva eliminado"
  fi
done
# 5) Inicio unico en los productos. Un rol `producto-<clave>` por producto (dice quien lo tiene contratado) y un grupo
#    "Clientes - <producto>" que lo da: para dar acceso a una persona basta con ponerla en el grupo.
rol_producto() {
  local rol="$1" grupo="$2" desc="$3" id
  if ! kc get "roles/$rol" -r sulotec >/dev/null 2>&1; then
    kc create roles -r sulotec -s "name=$rol" -s "description=$desc" >/dev/null
    echo "Ajuste: rol $rol creado"
  fi
  if ! kc get groups -r sulotec -q "search=$grupo" --fields name --format csv --noquotes | grep -qx "$grupo"; then
    kc create groups -r sulotec -s "name=$grupo" >/dev/null
    kc add-roles -r sulotec --gname "$grupo" --rolename "$rol" >/dev/null
    echo "Ajuste: grupo '$grupo' creado con el rol $rol"
  fi
  # El portal debe ver el rol en el id_token (claim "roles") para habilitar el boton "Abrir"
  id=$(kc get "roles/$rol" -r sulotec --fields id --format csv --noquotes)
  kc create "clients/$cid/scope-mappings/realm" -r sulotec -b "[{\"id\":\"$id\",\"name\":\"$rol\"}]" >/dev/null 2>&1 || true
}
rol_producto producto-auditoria "Clientes - Auditoria de Visitas" "Tiene contratado GeoMatrix, antes Auditoria de Visitas (auditoria.sulotec.com)"
rol_producto producto-miradar360 "Clientes - MiRadar 360" "Tiene contratado MiRadar 360"
rol_producto producto-plaft "Clientes - PLAFT" "Tiene contratado PLAFT"
rol_producto producto-dashboard "Clientes - Dashboard Empresarial" "Tiene contratado Dashboard Empresarial (dashboards.sulotec.com)"
# GeoMatrix es el nombre comercial nuevo de Auditoria de Visitas (el dominio y las claves tecnicas no cambian).
kc update roles/producto-auditoria -r sulotec -s "description=Tiene contratado GeoMatrix, antes Auditoria de Visitas (auditoria.sulotec.com)" >/dev/null

# 6) Cliente "auditoria": el panel de Auditoria de Visitas entra con la cuenta Sulotec (OpenID Connect + PKCE, cliente publico).
#    Su id_token lleva el correo (con el que el panel ubica al usuario) y los roles de producto/administrador general.
if ! kc get clients -r sulotec -q clientId=auditoria --fields id --format csv --noquotes | grep -q .; then
  kc create clients -r sulotec -b '{"clientId":"auditoria","name":"Auditoria de Visitas","description":"Panel web de Auditoria de Visitas (inicio unico con la cuenta Sulotec)","enabled":true,"publicClient":true,"standardFlowEnabled":true,"implicitFlowEnabled":false,"directAccessGrantsEnabled":false,"serviceAccountsEnabled":false,"fullScopeAllowed":false,"rootUrl":"https://auditoria.sulotec.com","baseUrl":"https://auditoria.sulotec.com","redirectUris":["https://auditoria.sulotec.com/sso","http://localhost:5173/sso"],"webOrigins":["https://auditoria.sulotec.com","http://localhost:5173"],"attributes":{"pkce.code.challenge.method":"S256","post.logout.redirect.uris":"https://auditoria.sulotec.com/*"}}' >/dev/null
  echo "Ajuste: cliente auditoria creado"
fi
aid=$(kc get clients -r sulotec -q clientId=auditoria --fields id --format csv --noquotes)
if ! kc get "clients/$aid/protocol-mappers/models" -r sulotec --fields name --format csv --noquotes | grep -qx roles; then
  kc create "clients/$aid/protocol-mappers/models" -r sulotec -b '{"name":"roles","protocol":"openid-connect","protocolMapper":"oidc-usermodel-realm-role-mapper","config":{"claim.name":"roles","jsonType.label":"String","multivalued":"true","id.token.claim":"true","access.token.claim":"false","userinfo.token.claim":"false","introspection.token.claim":"false"}}' >/dev/null
  echo "Ajuste: roles en el token de auditoria"
fi
for rol in administrador-general producto-auditoria; do
  id=$(kc get "roles/$rol" -r sulotec --fields id --format csv --noquotes)
  kc create "clients/$aid/scope-mappings/realm" -r sulotec -b "[{\"id\":\"$id\",\"name\":\"$rol\"}]" >/dev/null 2>&1 || true
done

# 7) Empresas (clientes de Sulotec). Cada cliente es un subgrupo de "Empresas" con su UUID y sus datos en atributos
#    (empresa_uuid, empresa_nombre, empresa_slug) y con los roles producto-* que tiene contratados. Los crea y actualiza
#    empresa.sh (en el servidor); aqui solo se asegura el grupo padre.
if ! kc get groups -r sulotec -q search=Empresas -q exact=true --fields name --format csv --noquotes | grep -qx Empresas; then
  kc create groups -r sulotec -s name=Empresas >/dev/null
  echo "Ajuste: grupo padre 'Empresas' creado"
fi

# 8) Los tokens del portal y de los productos llevan la empresa de la persona, tomada de los atributos de su grupo
#    ("aggregate.attrs"): claims empresa_uuid, empresa_nombre y empresa_slug. Un administrador universal no tiene empresa.
mapper_empresa() {
  local cliente_id="$1" attr="$2"
  if ! kc get "clients/$cliente_id/protocol-mappers/models" -r sulotec --fields name --format csv --noquotes | grep -qx "$attr"; then
    kc create "clients/$cliente_id/protocol-mappers/models" -r sulotec -b "{\"name\":\"$attr\",\"protocol\":\"openid-connect\",\"protocolMapper\":\"oidc-usermodel-attribute-mapper\",\"config\":{\"user.attribute\":\"$attr\",\"claim.name\":\"$attr\",\"jsonType.label\":\"String\",\"id.token.claim\":\"true\",\"access.token.claim\":\"true\",\"userinfo.token.claim\":\"true\",\"aggregate.attrs\":\"true\",\"multivalued\":\"false\"}}" >/dev/null
    echo "Ajuste: claim $attr en el token del cliente $cliente_id"
  fi
}
for c in "$cid" "$aid"; do
  for a in empresa_uuid empresa_nombre empresa_slug; do mapper_empresa "$c" "$a"; done
done

# 9) Administradores universales: el acuerdo (2026-10-22) es un maximo de 2 personas en "Administradores Generales".
gid_adm=$(kc get groups -r sulotec -q search="Administradores Generales" -q exact=true --fields id --format csv --noquotes | head -1)
if [ -n "$gid_adm" ]; then
  n_adm=$(kc get "groups/$gid_adm/members" -r sulotec --fields id --format csv --noquotes | grep -c . || true)
  [ "${n_adm:-0}" -le 2 ] || echo "AVISO: 'Administradores Generales' tiene $n_adm miembros; el acuerdo es un maximo de 2 administradores universales." >&2
fi

echo "Ajustes aplicados. Registro libre: apagado. Recuperar contrasena: encendido. Inicio unico: cliente auditoria, roles producto-*, grupo Empresas y claims empresa_*."
