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
echo "Ajustes aplicados. Registro libre: apagado. Recuperar contrasena: encendido."
