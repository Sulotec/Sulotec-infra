#!/usr/bin/env bash
# Renombra el grupo de los administradores universales de Sulotec: "Administradores Generales" -> "Administradores Universales".
# Por que: desde el modelo de licencias (2026-11-02) "Administrador General" es el administrador de cada empresa cliente
# (el titular de la licencia), asi que el grupo de Sulotec no puede llamarse igual. El rol tecnico `administrador-general`
# NO cambia de nombre: lo leen el portal (cuenta.js, mis-productos.astro) y GeoMatrix (sso.service.js).
# Corre DENTRO del contenedor, una sola vez (repetirlo no hace nada):
#   sudo docker exec -i cuenta bash -s < /data/apps/cuenta/renombrar-universales.sh
set -euo pipefail

VIEJO="Administradores Generales"
NUEVO="Administradores Universales"
kc() { /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/renombrar.config; }
trap 'rm -f /tmp/renombrar.config' EXIT
kc config credentials --server http://127.0.0.1:8080 --realm master \
  --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null

buscar() { kc get groups -r sulotec -q "search=$1" -q exact=true --fields id --format csv --noquotes | head -1; }
gid_nuevo=$(buscar "$NUEVO")
gid_viejo=$(buscar "$VIEJO")
if [ -n "$gid_nuevo" ]; then
  echo "El grupo ya se llama '$NUEVO'. Nada que hacer."
elif [ -n "$gid_viejo" ]; then
  kc update "groups/$gid_viejo" -r sulotec -s "name=$NUEVO"
  echo "Grupo renombrado: '$VIEJO' -> '$NUEVO' (mismos miembros, mismo rol administrador-general y mismos permisos)."
else
  echo "No existe ni '$VIEJO' ni '$NUEVO' en el realm sulotec: revisalo en la consola." >&2
  exit 1
fi
# La descripcion del rol explica el nombre heredado para que nadie lo confunda con el administrador de una empresa.
kc update roles/administrador-general -r sulotec -s "description=Administrador universal de Sulotec (grupo Administradores Universales): administra las cuentas y ve todo el ecosistema. Nombre tecnico heredado; no es el Administrador General de una empresa cliente." >/dev/null
gid="${gid_nuevo:-$gid_viejo}"
n=$(kc get "groups/$gid/members" -r sulotec -q max=100 --fields username --format csv --noquotes | grep -c . || true)
echo "Miembros de '$NUEVO': ${n:-0} (el acuerdo es un maximo de 2)."
