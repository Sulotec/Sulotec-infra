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

# 3) Entrar con Google y con Microsoft. Se crean APAGADOS y sin claves: se encienden en la consola
#    (Identity providers) al pegar el Client ID y el Client Secret (ver README). No se tocan si ya existen.
#    trustEmail: Google y Microsoft ya confirmaron el correo, no hace falta otro correo de verificacion.
existentes=$(kc get identity-provider/instances -r sulotec --fields alias --format csv --noquotes)
orden=1
for idp in google:Google microsoft:Microsoft; do
  alias=${idp%%:*}; nombre=${idp##*:}
  if ! grep -qx "$alias" <<<"$existentes"; then
    kc create identity-provider/instances -r sulotec -b "{\"alias\":\"$alias\",\"providerId\":\"$alias\",\"displayName\":\"$nombre\",\"enabled\":false,\"trustEmail\":true,\"storeToken\":false,\"linkOnly\":false,\"firstBrokerLoginFlowAlias\":\"first broker login\",\"config\":{\"clientId\":\"pegar-aqui\",\"clientSecret\":\"pegar-aqui\",\"syncMode\":\"IMPORT\",\"guiOrder\":\"$orden\"}}"
    echo "Ajuste: proveedor $nombre creado (apagado hasta pegar sus claves en la consola)"
  fi
  orden=$((orden + 1))
done

# 4) El registro publico con formulario se abre solo si hay correo de salida (cada persona confirma su correo)
if kc get realms/sulotec --fields 'smtpServer(host)' | grep -q '"host"'; then registro=true; else registro=false; fi
kc update realms/sulotec -s registrationAllowed=$registro
echo "Ajustes aplicados. Registro publico: $registro"
