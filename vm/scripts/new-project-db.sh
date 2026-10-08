#!/usr/bin/env bash
# Crea una base de datos + usuario propio para un proyecto, en PostgreSQL o MySQL.
# Uso:  sudo /opt/sulotec/scripts/new-project-db.sh <postgres|mysql> <proyecto>
#   ej: sudo /opt/sulotec/scripts/new-project-db.sh mysql cajahuancayo
set -euo pipefail

motor="${1:-}"; name="${2:-}"
case "$motor" in postgres|mysql) ;; *) echo "uso: $0 <postgres|mysql> <proyecto>" >&2; exit 1;; esac
[[ "$name" =~ ^[a-z][a-z0-9_]{1,30}$ ]] || { echo "nombre invalido: '$name' (minusculas, numeros y _)" >&2; exit 1; }

cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
pass="$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 28)"

if [ "$motor" = postgres ]; then
  docker compose exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 <<SQL
CREATE ROLE "$name" LOGIN PASSWORD '$pass';
CREATE DATABASE "$name" OWNER "$name";
REVOKE ALL ON DATABASE "$name" FROM PUBLIC;
SQL
  echo
  echo "  .NET : Host=postgres;Port=5432;Database=$name;Username=$name;Password=$pass"
  echo "  Java : jdbc:postgresql://postgres:5432/$name   usuario=$name   clave=$pass"
  echo "  Node : postgresql://$name:$pass@postgres:5432/$name"
else
  docker compose exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot <<SQL
CREATE DATABASE \`$name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER '$name'@'%' IDENTIFIED BY '$pass';
GRANT ALL PRIVILEGES ON \`$name\`.* TO '$name'@'%';
SQL
  echo
  echo "  .NET : Server=mysql;Port=3306;Database=$name;Uid=$name;Pwd=$pass"
  echo "  Java : jdbc:mysql://mysql:3306/$name   usuario=$name   clave=$pass"
  echo "  Node : mysql://$name:$pass@mysql:3306/$name"
fi
echo
echo "Base '$name' ($motor) creada. Guarda estos datos en el gestor de contrasenas: la clave no se vuelve a mostrar."
echo "El contenedor de la app debe unirse a la red 'sulotec_data' para llegar a '$motor'."
