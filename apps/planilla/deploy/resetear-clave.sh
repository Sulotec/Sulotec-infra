#!/usr/bin/env bash
# Pone una clave nueva a una cuenta del Sistema de Planillas, por ejemplo si se perdio la del administrador inicial.
#   sudo bash /data/apps/planilla/resetear-clave.sh admin
# Genera una clave al azar en este servidor, la guarda cifrada (bcrypt, igual que la app) directo en la base, activa la cuenta
# y la marca para que cambie la clave al entrar. La clave se muestra UNA sola vez aqui: no se guarda en ningun archivo.
# Nota: como escribe directo en la base, este cambio no queda en la auditoria de la app.
set -euo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0 <usuario>" >&2; exit 1; }

USUARIO="${1:-}"
[ -n "$USUARIO" ] || { echo "Uso: sudo bash $0 <usuario>      (por ejemplo: admin)" >&2; exit 1; }
[[ "$USUARIO" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Nombre de usuario no valido: '$USUARIO' (solo letras, numeros y . _ -)." >&2; exit 1; }

ENVFILE=/opt/sulotec/planilla.env
[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE" >&2; exit 1; }
leer() { grep -E "^$1=" "$ENVFILE" | head -1 | cut -d= -f2- || true; }
DB_USER="$(leer DB_USER)"; DB_PASSWORD="$(leer DB_PASSWORD)"; DB_NAME="$(leer DB_NAME)"; DB_HOST="$(leer DB_HOST)"; DB_PORT="$(leer DB_PORT)"
{ [ -n "$DB_USER" ] && [ -n "$DB_PASSWORD" ] && [ -n "$DB_NAME" ]; } || { echo "$ENVFILE no tiene los datos de la base." >&2; exit 1; }

# La clave de la base viaja por entorno (no por la linea de comandos).
cliente() { MYSQL_PWD="$DB_PASSWORD" docker run --rm -i --network sulotec_data -e MYSQL_PWD mysql:8.4 mysql -h "$DB_HOST" -P "$DB_PORT" -u"$DB_USER" "$@" "$DB_NAME"; }

existe="$(cliente -N -e "select count(*) from usuario where username = '$USUARIO'")" || { echo "No pude consultar la base $DB_NAME." >&2; exit 1; }
[ "$existe" = 1 ] || { echo "No existe la cuenta '$USUARIO'." >&2; exit 1; }

# Clave de 16 caracteres con mayuscula, minuscula y numero (lo que exige la app).
clave=""
while :; do
  clave="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 16)"
  [[ "${#clave}" -eq 16 && "$clave" =~ [a-z] && "$clave" =~ [A-Z] && "$clave" =~ [0-9] ]] && break
done
# bcrypt con el mismo costo que usa la app (10). htpasswd viene en la imagen oficial de Apache (existe para ARM).
hash="$(printf '%s' "$clave" | docker run --rm -i httpd:2.4 sh -c 'htpasswd -niBC 10 x' | cut -d: -f2 | tr -d '\r\n')"
[[ "$hash" == \$2y\$10\$* ]] || { echo "No pude generar la clave cifrada (hash inesperado)." >&2; exit 1; }

cliente -e "update usuario set password = '$hash', activo = 1, debe_cambiar_password = 1 where username = '$USUARIO'"
echo
echo "   Usuario: $USUARIO"
echo "   Clave nueva (se muestra UNA sola vez): $clave"
echo "   Al entrar, el sistema obliga a cambiarla."
