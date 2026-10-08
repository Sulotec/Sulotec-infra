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

# 3) El registro publico se abre solo si hay correo de salida (cada persona debe confirmar su correo)
if kc get realms/sulotec --fields 'smtpServer(host)' | grep -q '"host"'; then registro=true; else registro=false; fi
kc update realms/sulotec -s registrationAllowed=$registro
echo "Ajustes aplicados. Registro publico: $registro"
