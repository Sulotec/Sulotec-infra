#!/usr/bin/env bash
# Crea cuentas Sulotec en bloque desde un archivo CSV y manda a cada persona la invitacion para crear su contrasena.
#   sudo bash /data/apps/cuenta/cuentas.sh /ruta/cuentas.csv --revisar    # solo revisa el archivo, no crea nada
#   sudo bash /data/apps/cuenta/cuentas.sh /ruta/cuentas.csv              # crea lo que falte e invita a las nuevas
#   sudo bash /data/apps/cuenta/cuentas.sh /ruta/cuentas.csv --reinvitar  # ademas reenvia la invitacion a las que ya existian
# Formato (plantilla-cuentas.csv), separado por ";" y con esa primera fila:
#   correo;nombres;apellidos;empresa;universal
#   - correo: es el usuario con el que la persona entra (unico en todo Sulotec).
#   - empresa: slug de la empresa creada con empresa.sh (la persona pertenece a UNA sola empresa).
#   - universal: "si" solo para los administradores universales de Sulotec (ven todo; maximo 2 personas); con empresa vacia.
# Invitacion: correo de Keycloak con un enlace (7 dias) para elegir la contrasena. Si el correo de salida (SMTP) no esta
# configurado, la cuenta se crea con una clave temporal que se muestra UNA sola vez y se cambia al entrar.
# Se puede repetir: las cuentas que ya existen no se duplican; solo se comprueba su empresa.
# Variables solo para pruebas: CONTENEDOR (por defecto cuenta), PRUEBA.
set -euo pipefail

CONTENEDOR="${CONTENEDOR:-cuenta}"
if [ -z "${DENTRO:-}" ]; then
  [ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0 archivo.csv [--revisar|--reinvitar]" >&2; exit 1; }
  archivo="${1:-}"; [ -n "$archivo" ] && [ -r "$archivo" ] || { echo "Uso: cuentas.sh archivo.csv [--revisar|--reinvitar]" >&2; exit 1; }
  docker ps --format '{{.Names}}' | grep -qx "$CONTENEDOR" || { echo "El contenedor '$CONTENEDOR' no esta corriendo." >&2; exit 1; }
  shift
  exec docker exec -i -e DENTRO=1 -e CSV="$(cat "$archivo")" "$CONTENEDOR" bash -s -- "$@" < "$0"
fi

# ---------- desde aqui corre DENTRO del contenedor de Keycloak ----------
MODO="crear"
case "${1:-}" in
  "") ;;
  --revisar) MODO="revisar" ;;
  --reinvitar) MODO="reinvitar" ;;
  *) echo "Opcion no reconocida: $1 (valen --revisar y --reinvitar)" >&2; exit 1 ;;
esac

kc() { /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/cuentas.config; }
trap 'rm -f /tmp/cuentas.config' EXIT
kc config credentials --server http://127.0.0.1:8080 --realm master \
  --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null

MAX_UNIVERSALES=2
limpiar() { echo "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

# Grupos: empresas (slug -> id) y administradores universales
# (la imagen de Keycloak no trae awk: se usa grep/cut; el "|| true" evita que "no encontrado" corte el script con set -e)
pid=$(kc get groups -r sulotec -q search=Empresas -q exact=true --fields id,name --format csv --noquotes | grep -E '^[^,]+,Empresas$' | head -1 | cut -d, -f1 || true)
[ -n "$pid" ] || { echo "No existe el grupo 'Empresas': corre ajustar-realm.sh y crea las empresas con empresa.sh." >&2; exit 1; }
empresas=$(kc get "groups/$pid/children" -r sulotec -q max=500 --fields id,name --format csv --noquotes)
gid_de() { echo "$empresas" | grep -E "^[^,]+,$1\$" | head -1 | cut -d, -f1 || true; }
gid_adm=$(kc get groups -r sulotec -q search="Administradores Generales" -q exact=true --fields id --format csv --noquotes | head -1)
[ -n "$gid_adm" ] || { echo "No existe el grupo 'Administradores Generales'." >&2; exit 1; }
n_adm=$(kc get "groups/$gid_adm/members" -r sulotec -q max=100 --fields id --format csv --noquotes | grep -c . || true)

# 1) Revision de todo el archivo (no se crea nada si hay una fila mala)
errores=0; filas=0; nuevos_universales=0; declare -A vistos=()
while IFS= read -r linea || [ -n "$linea" ]; do
  linea=$(printf '%s' "$linea" | tr -d '\r')
  filas=$((filas+1))
  [ "$filas" -gt 1 ] || continue                      # primera fila: encabezado
  [ -n "$(limpiar "$linea")" ] || continue            # filas vacias
  IFS=';' read -r correo nombres apellidos empresa universal <<< "$linea"
  correo=$(limpiar "${correo:-}" | tr 'A-Z' 'a-z'); nombres=$(limpiar "${nombres:-}"); apellidos=$(limpiar "${apellidos:-}")
  empresa=$(limpiar "${empresa:-}" | tr 'A-Z' 'a-z'); universal=$(limpiar "${universal:-}" | tr 'A-Z' 'a-z')
  f="fila $filas ($correo)"
  [[ "$correo" =~ ^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$ ]] || { echo "  $f: correo no valido"; errores=$((errores+1)); }
  [ -n "$nombres" ] && [ -n "$apellidos" ] || { echo "  $f: faltan nombres o apellidos"; errores=$((errores+1)); }
  [ -z "${vistos[$correo]:-}" ] || { echo "  $f: correo repetido en el archivo"; errores=$((errores+1)); }
  vistos[$correo]=1
  if [ "$universal" = "si" ]; then
    [ -z "$empresa" ] || { echo "  $f: un administrador universal no lleva empresa"; errores=$((errores+1)); }
    # Solo cuenta como nuevo si la persona no es ya miembro del grupo (asi el archivo puede repetir a los que ya estan)
    uid_u=$(kc get users -r sulotec -q email="$correo" -q exact=true --fields id --format csv --noquotes | head -1 || true)
    if [ -z "$uid_u" ] || ! kc get "users/$uid_u/groups" -r sulotec --fields id --format csv --noquotes | grep -qx "$gid_adm"; then
      nuevos_universales=$((nuevos_universales+1))
    fi
  else
    [ -z "$universal" ] || { echo "  $f: la columna universal solo admite 'si' o vacio"; errores=$((errores+1)); }
    [ -n "$empresa" ] || { echo "  $f: falta la empresa (slug) o universal=si"; errores=$((errores+1)); }
    [ -z "$empresa" ] || [ -n "$(gid_de "$empresa")" ] || { echo "  $f: la empresa '$empresa' no existe (crea con empresa.sh)"; errores=$((errores+1)); }
  fi
done <<< "$CSV"
[ "$filas" -gt 1 ] || { echo "El archivo no tiene filas de datos (la primera fila es el encabezado)." >&2; exit 1; }
if [ $((n_adm + nuevos_universales)) -gt "$MAX_UNIVERSALES" ]; then
  echo "  administradores universales: hay $n_adm y el archivo agrega $nuevos_universales; el maximo es $MAX_UNIVERSALES"; errores=$((errores+1))
fi
if [ "$errores" -gt 0 ]; then echo "Revisa el archivo: $errores error(es). No se creo nada." >&2; exit 1; fi
echo "Archivo correcto: $((filas-1)) fila(s)."
[ "$MODO" != "revisar" ] || exit 0

# 2) Creacion
clave_temporal() { echo "Sulotec-$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 10)A1"; }
invitar() { # id -> 0 si se envio el correo
  kc update "users/$1/execute-actions-email?client_id=portal&redirect_uri=https%3A%2F%2Fsulotec.com%2Fmis-productos&lifespan=604800" \
    -r sulotec -n -b '["UPDATE_PASSWORD","VERIFY_EMAIL"]' >/dev/null 2>&1 \
  || kc update "users/$1/execute-actions-email?lifespan=604800" -r sulotec -n -b '["UPDATE_PASSWORD","VERIFY_EMAIL"]' >/dev/null 2>&1
}
creadas=0; existentes=0; invitadas=0; temporales=""
filas=0
while IFS= read -r linea || [ -n "$linea" ]; do
  linea=$(printf '%s' "$linea" | tr -d '\r')
  filas=$((filas+1)); [ "$filas" -gt 1 ] || continue; [ -n "$(limpiar "$linea")" ] || continue
  IFS=';' read -r correo nombres apellidos empresa universal <<< "$linea"
  correo=$(limpiar "$correo" | tr 'A-Z' 'a-z'); nombres=$(limpiar "$nombres"); apellidos=$(limpiar "$apellidos")
  empresa=$(limpiar "${empresa:-}" | tr 'A-Z' 'a-z'); universal=$(limpiar "${universal:-}" | tr 'A-Z' 'a-z')

  uid=$(kc get users -r sulotec -q email="$correo" -q exact=true --fields id --format csv --noquotes | head -1)
  nueva=0
  if [ -z "$uid" ]; then
    kc create users -r sulotec -s "username=$correo" -s "email=$correo" -s "firstName=$nombres" -s "lastName=$apellidos" -s enabled=true -s emailVerified=false >/dev/null
    uid=$(kc get users -r sulotec -q email="$correo" -q exact=true --fields id --format csv --noquotes | head -1)
    [ -n "$uid" ] || { echo "  $correo: no se pudo crear" >&2; continue; }
    nueva=1; creadas=$((creadas+1))
  else
    existentes=$((existentes+1))
  fi

  # Grupo: su empresa (una sola) o administradores universales
  grupos=$(kc get "users/$uid/groups" -r sulotec --fields id,name,path --format csv --noquotes)
  if [ "$universal" = "si" ]; then
    echo "$grupos" | cut -d, -f1 | grep -qx "$gid_adm" || { kc update "users/$uid/groups/$gid_adm" -r sulotec -s realm=sulotec -s userId="$uid" -s groupId="$gid_adm" -n >/dev/null; n_adm=$((n_adm+1)); }
    destino="administrador universal"
  else
    gid=$(gid_de "$empresa")
    otra=""
    while IFS=, read -r g n p; do
      [[ "${p:-}" == /Empresas/* ]] && [ "$g" != "$gid" ] && { otra="$n"; break; }
    done <<< "$grupos"
    if [ -n "$otra" ]; then echo "  $correo: ya pertenece a la empresa '$otra'; no se mueve (hazlo a mano en la consola si corresponde)" >&2; continue; fi
    echo "$grupos" | cut -d, -f1 | grep -qx "$gid" || kc update "users/$uid/groups/$gid" -r sulotec -s realm=sulotec -s userId="$uid" -s groupId="$gid" -n >/dev/null
    destino="empresa $empresa"
  fi

  # Invitacion (o clave temporal si no hay correo de salida)
  if [ "$nueva" = 1 ] || [ "$MODO" = "reinvitar" ]; then
    if invitar "$uid"; then
      invitadas=$((invitadas+1)); echo "  $correo: $([ "$nueva" = 1 ] && echo creada || echo existente), $destino, invitacion enviada"
    else
      clave=$(clave_temporal)
      kc set-password -r sulotec --userid "$uid" --new-password "$clave" --temporary >/dev/null
      temporales="$temporales\n  $correo   $clave"
      echo "  $correo: $([ "$nueva" = 1 ] && echo creada || echo existente), $destino, sin correo de salida: clave temporal"
    fi
  else
    echo "  $correo: ya existia, $destino (sin cambios)"
  fi
done <<< "$CSV"

echo "Listo: $creadas creada(s), $existentes ya existia(n), $invitadas invitacion(es) enviada(s)."
if [ -n "$temporales" ]; then
  echo "Claves temporales (se muestran UNA sola vez; entregalas por un canal seguro; se cambian al entrar):"
  printf '%b\n' "$temporales"
fi
