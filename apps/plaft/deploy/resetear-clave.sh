#!/usr/bin/env bash
# Pone una clave nueva a una cuenta de PLAFT, por ejemplo si se perdio la del administrador inicial (superadmin).
#   sudo bash /data/apps/plaft/resetear-clave.sh superadmin
# Como funciona: genera una clave al azar en este servidor, crea el enlace de recuperacion de un solo uso que la API ya sabe canjear
# y lo canjea contra la propia API, que guarda la clave cifrada como siempre. La clave nueva se muestra UNA sola vez en esta pantalla:
# no pasa por el correo, no se guarda en ningun archivo y no queda en el historial de comandos.
# Variables solo para pruebas: ENVFILE, RED_DOCKER, API_CONTENEDOR, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0 <usuario>" >&2; exit 1; }

USUARIO="${1:-}"
[ -n "$USUARIO" ] || { echo "Uso: sudo bash $0 <usuario>      (por ejemplo: superadmin)" >&2; exit 1; }
# El nombre va dentro del SQL: solo se aceptan letras, numeros y . _ @ -
[[ "$USUARIO" =~ ^[A-Za-z0-9._@-]+$ ]] || { echo "Nombre de usuario no valido: '$USUARIO' (solo letras, numeros y . _ @ -)." >&2; exit 1; }

ENVFILE="${ENVFILE:-/opt/sulotec/plaft.env}"
RED="${RED_DOCKER:-sulotec_data}"
API="${API_CONTENEDOR:-plaft-api}"

[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE" >&2; exit 1; }
leer() { grep -E "^$1=" "$ENVFILE" | head -1 | cut -d= -f2- || true; }
DB_URL="$(leer DB_URL)"; DB_USER="$(leer DB_USER)"; DB_PASSWORD="$(leer DB_PASSWORD)"
{ [ -n "$DB_URL" ] && [ -n "$DB_USER" ] && [ -n "$DB_PASSWORD" ]; } || { echo "$ENVFILE no tiene DB_URL, DB_USER y DB_PASSWORD." >&2; exit 1; }
BASE="${DB_URL#*://}"; BASE="${BASE#*/}"; BASE="${BASE%%[?]*}"
[ -n "$BASE" ] || { echo "No pude sacar el nombre de la base de DB_URL." >&2; exit 1; }

# La clave de la base viaja por entorno (no por la linea de comandos).
cliente() { MYSQL_PWD="$DB_PASSWORD" docker run --rm -i --network "$RED" -e MYSQL_PWD mysql:8.4 mysql -h mysql -u"$DB_USER" "$@" "$BASE"; }

# Llama a la API desde adentro de su contenedor (no hace falta abrir ningun puerto). El cuerpo entra por la entrada estandar:
# asi la clave no aparece en la lista de procesos de este servidor.
llamar_api() {
  printf '%s' "$2" | docker exec -i "$API" sh -c 'if command -v wget >/dev/null 2>&1; then wget -qO- --header="Content-Type: application/json" --post-data="$(cat)" "$0"; else curl -fsS -H "Content-Type: application/json" -d "$(cat)" "$0"; fi' "http://127.0.0.1:8081$1"
}

docker inspect "$API" >/dev/null 2>&1 || { echo "No encuentro el contenedor $API: ¿esta corriendo la API de PLAFT? (docker ps)" >&2; exit 1; }

fila="$(cliente -N -e "select id, activo + 0 from usuarios where usuario = '$USUARIO'")" || { echo "No pude consultar la base $BASE." >&2; exit 1; }
[ -n "$fila" ] || { echo "No existe la cuenta '$USUARIO'." >&2; exit 1; }
activo="$(printf '%s' "$fila" | cut -f2)"

# Clave de 16 caracteres con mayuscula, minuscula y numero.
clave=""
while :; do
  clave="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 16)"
  [[ "${#clave}" -eq 16 && "$clave" =~ [a-z] && "$clave" =~ [A-Z] && "$clave" =~ [0-9] ]] && break
done
token="$(openssl rand -hex 24)"

# Enlace de recuperacion de un solo uso, a nombre de la cuenta (vale un dia por si la hora del servidor y la de la base difieren; se canjea enseguida).
cliente -e "insert into password_reset_tokens (id_usuario, token, fecha_expiracion, usado, fecha_creacion) select id, '$token', now(6) + interval 1 day, 0, now(6) from usuarios where usuario = '$USUARIO'" \
  || { echo "No pude preparar el enlace de recuperacion (¿existe la tabla password_reset_tokens? la crea la API al arrancar)." >&2; exit 1; }
limpiar() { cliente -e "delete from password_reset_tokens where token = '$token'" >/dev/null 2>&1 || true; }

if ! respuesta="$(llamar_api /api/auth/reset-password "$(printf '{"token":"%s","nuevaClave":"%s"}' "$token" "$clave")" 2>&1)"; then
  limpiar
  echo "La API no acepto el cambio de clave: $(printf '%s' "$respuesta" | head -c 300)" >&2
  exit 1
fi
limpiar

# Comprobacion: entrar con la clave nueva
if llamar_api /api/auth/login "$(printf '{"usuario":"%s","clave":"%s"}' "$USUARIO" "$clave")" 2>/dev/null | grep -q accessToken; then
  verificado="si"
else
  verificado="no"
fi

echo
echo "Cuenta:       $USUARIO"
echo "Clave nueva:  $clave"
echo "(Se muestra UNA sola vez: guardala en el gestor de contrasenas.)"
if [ "$verificado" = "si" ]; then
  echo "Comprobado: la clave nueva entra."
elif [ "${activo:-1}" = "0" ]; then
  echo "AVISO: la cuenta esta DESACTIVADA, por eso no puede entrar todavia: activala en Administracion (Cuentas) con otra cuenta de administrador." >&2
else
  echo "AVISO: cambie la clave pero no pude comprobar el ingreso desde aqui. Prueba entrar en la web." >&2
fi
