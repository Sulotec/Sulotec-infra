#!/usr/bin/env bash
# Almacenamiento del servidor, en un paso (ejecutar con sudo; se puede repetir sin riesgo):
#  1. Formatea el disco de datos SOLO si esta vacio y lo monta en /data (etiqueta sulotec-data).
#  2. PostgreSQL y MySQL guardan sus datos en /data; /data/apps para archivos de los proyectos.
#  3. Instala OCI CLI y programa el backup diario (02:00) al bucket sulotec-backups.
#  4. Hace un primer backup completo para probar toda la cadena.
# Uso en la VM:  sudo bash setup-datos.sh
# En una VM nueva: primero bootstrap.sh (tunel), despues este.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
[ "$(id -u)" -eq 0 ] || { echo "Ejecuta con sudo:  sudo bash $0"; exit 1; }
[ -f /opt/sulotec/.env ] || { echo "Falta /opt/sulotec/.env: ejecuta antes bootstrap.sh"; exit 1; }

echo "== 1. Disco de datos"
if ! blkid -L sulotec-data >/dev/null 2>&1; then
  DISK=""
  for d in $(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}'); do
    [ "$(lsblk -no NAME "$d" | wc -l)" -eq 1 ] || continue        # tiene particiones: es el disco del sistema
    blkid -p "$d" >/dev/null 2>&1 && continue                       # ya tiene datos: no se toca
    [ "$(lsblk -dbno SIZE "$d")" -gt 10000000000 ] || continue
    DISK="$d"
  done
  [ -n "$DISK" ] || { echo "No encontre un disco de datos vacio. Revisa con: lsblk"; exit 1; }
  echo "Formateando $DISK ($(lsblk -dno SIZE "$DISK")) como sulotec-data..."
  mkfs.ext4 -q -L sulotec-data "$DISK"
fi
mkdir -p /data
grep -q '^LABEL=sulotec-data' /etc/fstab || echo 'LABEL=sulotec-data /data ext4 defaults,nofail 0 2' >> /etc/fstab
systemctl daemon-reload
mountpoint -q /data || mount /data
# Docker no arranca hasta que /data este montado (evita escribir datos en el disco equivocado)
mkdir -p /etc/systemd/system/docker.service.d
printf '[Unit]\nRequiresMountsFor=/data\n' > /etc/systemd/system/docker.service.d/10-data.conf
systemctl daemon-reload
install -d -m 700 /data/postgres /data/mysql
install -d -o root -g docker -m 2775 /data/apps
df -h /data

echo "== 2. Configuracion en /opt/sulotec"
cd /opt/sulotec
mkdir -p scripts

cat > docker-compose.yml <<'EOF_COMPOSE'
name: sulotec

# Servicios base de la VM. Cada proyecto va en su propio compose (ver ../templates/app-compose.yml)
# y se une a estas dos redes:
#   sulotec_edge -> contenedores que Cloudflare Tunnel puede alcanzar
#   sulotec_data -> acceso a PostgreSQL y MySQL
# Los datos viven en el disco de datos montado en /data (ver setup-datos.sh).
# Ninguna base publica puertos: solo se llega a ellas desde la red sulotec_data.

services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    restart: unless-stopped
    command: tunnel --no-autoupdate run
    environment:
      TUNNEL_TOKEN: ${CF_TUNNEL_TOKEN:?falta CF_TUNNEL_TOKEN en .env}
    networks: [edge]

  postgres:
    image: postgres:16
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?falta POSTGRES_PASSWORD en .env}
    volumes:
      - /data/postgres:/var/lib/postgresql/data
    networks: [data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  mysql:
    image: mysql:8.4
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD:?falta MYSQL_ROOT_PASSWORD en .env}
    volumes:
      - /data/mysql:/var/lib/mysql
    networks: [data]
    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -h 127.0.0.1 -uroot -p\"$$MYSQL_ROOT_PASSWORD\" --silent"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 60s

networks:
  edge:
    name: sulotec_edge
  data:
    name: sulotec_data
EOF_COMPOSE

cat > scripts/backup.sh <<'EOF_BACKUP'
#!/usr/bin/env bash
# Backup diario de todas las bases (PostgreSQL y MySQL) y de los archivos en /data/apps.
# - Copia local 14 dias en /var/backups/sulotec (disco del sistema, separado de /data).
# - Copia fuera del servidor en el bucket sulotec-backups, con el permiso propio de la VM (sin llaves).
# Lo ejecuta cron como root a las 02:00 (hora de Lima): /etc/cron.d/sulotec-backup
# Ejecutarlo a mano:  sudo /opt/sulotec/scripts/backup.sh
set -euo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

cd /opt/sulotec
set -a; . ./.env; set +a

dir=/var/backups/sulotec
ts="$(date +%F_%H%M)"
mkdir -p "$dir"; chmod 700 "$dir"

docker compose exec -T postgres pg_dumpall -U postgres | gzip > "$dir/postgres_$ts.sql.gz"
docker compose exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql \
  mysqldump -uroot --all-databases --single-transaction --routines --events --triggers \
  | gzip > "$dir/mysql_$ts.sql.gz"
tar -czf "$dir/apps_$ts.tar.gz" -C /data apps

find "$dir" -type f -mtime +14 -delete

for f in "$dir"/*_"$ts".*; do
  oci os object put --auth instance_principal --bucket-name "${BACKUP_BUCKET:-sulotec-backups}" \
    --file "$f" --name "$(date +%Y/%m)/$(basename "$f")" --force >/dev/null
done
echo "$(date -Is) backup OK y subido a ${BACKUP_BUCKET:-sulotec-backups}: $(cd "$dir" && ls *_"$ts".* | tr '\n' ' ')"
EOF_BACKUP

cat > scripts/new-project-db.sh <<'EOF_NEWDB'
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
EOF_NEWDB

rm -f scripts/backup-postgres.sh
grep -q '^MYSQL_ROOT_PASSWORD=' .env || echo "MYSQL_ROOT_PASSWORD=$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 32)" >> .env
# Solo root y los administradores (grupo docker) pueden leer la configuracion y sus secretos
chown -R root:docker /opt/sulotec
chmod 750 /opt/sulotec /opt/sulotec/scripts
chmod 640 .env docker-compose.yml
chmod 750 scripts/*.sh

echo "== 3. Bases de datos con datos en /data"
docker compose up -d --remove-orphans
for i in $(seq 1 60); do
  pg="$(docker inspect -f '{{.State.Health.Status}}' sulotec-postgres-1 2>/dev/null || true)"
  my="$(docker inspect -f '{{.State.Health.Status}}' sulotec-mysql-1 2>/dev/null || true)"
  [ "$pg" = healthy ] && [ "$my" = healthy ] && break
  sleep 5
done
docker compose ps

echo "== 4. OCI CLI y backup diario"
if [ ! -x /usr/local/bin/oci ]; then
  apt-get update -qq
  apt-get install -y -qq pipx >/dev/null
  PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install oci-cli >/dev/null
fi
/usr/local/bin/oci --version
echo '0 2 * * * root /opt/sulotec/scripts/backup.sh >> /var/log/sulotec-backup.log 2>&1' > /etc/cron.d/sulotec-backup
chmod 644 /etc/cron.d/sulotec-backup

echo "== 5. Primer backup (prueba completa, incluida la subida al bucket)"
/opt/sulotec/scripts/backup.sh

echo
echo "LISTO-DATOS"
echo "Guarda en el gestor de contrasenas la clave root de MySQL:  sudo grep MYSQL_ROOT_PASSWORD /opt/sulotec/.env"
