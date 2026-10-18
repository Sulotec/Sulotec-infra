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
rol_producto producto-auditoria "Clientes - Auditoria de Visitas" "Tiene contratado Auditoria de Visitas (auditoria.sulotec.com)"
rol_producto producto-miradar360 "Clientes - MiRadar 360" "Tiene contratado MiRadar 360"
rol_producto producto-plaft "Clientes - PLAFT" "Tiene contratado PLAFT"

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

echo "Ajustes aplicados. Registro libre: apagado. Recuperar contrasena: encendido. Inicio unico: cliente auditoria y roles producto-*."
