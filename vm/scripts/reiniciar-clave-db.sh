#!/usr/bin/env bash
# Pone una clave NUEVA al usuario de una base creada con new-project-db.sh (por ejemplo si no se guardo la clave que mostro).
# La base y sus datos no se tocan. Si el usuario no existe, lo crea con permiso solo sobre su base.
#   sudo /opt/sulotec/scripts/reiniciar-clave-db.sh <postgres|mysql> <proyecto>
#   ej: sudo /opt/sulotec/scripts/reiniciar-clave-db.sh mysql plaft
# La clave nueva se muestra UNA vez (igual que new-project-db.sh) y se comprueba por la red interna.
# Variables solo para pruebas: SULOTEC_DIR, RED_DATOS, PRUEBA, FORZAR.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo $0 <postgres|mysql> <proyecto>" >&2; exit 1; }

motor="${1:-}"; name="${2:-}"
case "$motor" in postgres|mysql) ;; *) echo "uso: $0 <postgres|mysql> <proyecto>" >&2; exit 1;; esac
[[ "$name" =~ ^[a-z][a-z0-9_]{1,30}$ ]] || { echo "nombre invalido: '$name' (minusculas, numeros y _)" >&2; exit 1; }
# Estas bases ya las usan aplicaciones en marcha: cambiarles la clave sin actualizar su configuracion las dejaria sin servicio
case "$name" in keycloak|miradar) [ -n "${FORZAR:-}" ] || { echo "'$name' lo usa una aplicacion en marcha. Para cambiarle la clave usa rotar-claves.sh (actualiza su configuracion)." >&2; exit 1; };; esac

BASE="${SULOTEC_DIR:-/opt/sulotec}"
RED_DATOS="${RED_DATOS:-sulotec_data}"
cd "$BASE"
set -a; . ./.env; set +a
pass="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 28)"

if [ "$motor" = mysql ]; then
  docker compose exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot -N -e "select 1 from information_schema.schemata where schema_name='$name'" | grep -q 1 \
    || { echo "La base '$name' no existe en MySQL. Crea primero: sudo /opt/sulotec/scripts/new-project-db.sh mysql $name" >&2; exit 1; }
  printf "CREATE USER IF NOT EXISTS '%s'@'%%' IDENTIFIED BY '%s';\nALTER USER '%s'@'%%' IDENTIFIED BY '%s';\nGRANT ALL PRIVILEGES ON \`%s\`.* TO '%s'@'%%';\nFLUSH PRIVILEGES;\n" \
    "$name" "$pass" "$name" "$pass" "$name" "$name" | docker compose exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot
  comprobar() { docker run --rm --network "$RED_DATOS" -e MYSQL_PWD="$pass" mysql:8.4 mysql -h mysql -u"$name" -N -e 'select 1' "$name" 2>/dev/null | grep -q 1; }
else
  docker compose exec -T postgres psql -U postgres -At -c "select 1 from pg_database where datname='$name'" | grep -q 1 \
    || { echo "La base '$name' no existe en PostgreSQL. Crea primero: sudo /opt/sulotec/scripts/new-project-db.sh postgres $name" >&2; exit 1; }
  docker compose exec -T postgres psql -U postgres -At -c "select 1 from pg_roles where rolname='$name'" | grep -q 1 \
    || { echo "El rol '$name' no existe en PostgreSQL: revisa con el responsable antes de crearlo a mano." >&2; exit 1; }
  printf "ALTER ROLE \"%s\" PASSWORD '%s';\n" "$name" "$pass" | docker compose exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 -q >/dev/null
  comprobar() { [ "$(docker run --rm --network "$RED_DATOS" -e PGPASSWORD="$pass" postgres:16 psql -h postgres -U "$name" -d "$name" -At -c 'select 1' 2>/dev/null || true)" = 1 ]; }
fi

comprobar || { echo "FALLO: la clave nueva no entra. Revisa el usuario '$name'." >&2; exit 1; }
echo "   OK: la clave nueva entra a la base '$name'"
echo
if [ "$motor" = mysql ]; then
  echo "  .NET : Server=mysql;Port=3306;Database=$name;Uid=$name;Pwd=$pass"
  echo "  Java : jdbc:mysql://mysql:3306/$name   usuario=$name   clave=$pass"
  echo "  Node : mysql://$name:$pass@mysql:3306/$name"
else
  echo "  .NET : Host=postgres;Port=5432;Database=$name;Username=$name;Password=$pass"
  echo "  Java : jdbc:postgresql://postgres:5432/$name   usuario=$name   clave=$pass"
  echo "  Node : postgresql://$name:$pass@postgres:5432/$name"
fi
echo
echo "Clave nueva de '$name' ($motor). Guardala en el gestor de contrasenas: no se vuelve a mostrar."
echo "La clave anterior ya no vale: si alguna aplicacion la usaba, hay que actualizarla."
