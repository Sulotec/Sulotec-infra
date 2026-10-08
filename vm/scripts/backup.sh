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
