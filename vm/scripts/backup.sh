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
# No se respalda lo que se vuelve a bajar: los clones de MiRadar salen de GitHub y el modelo de IA de PLAFT
# (apps/plaft/ollama, ~9 GB, no se comprime) se baja con: sudo bash /data/apps/plaft/activar-indira.sh
# Incluirlo llenó el disco el 2026-10-27 (8,9 GB por noche durante 14 noches = 102 GB).
tar -czf "$dir/apps_$ts.tar.gz" --exclude='apps/miradar/backend' --exclude='apps/miradar/frontend' --exclude='apps/plaft/ollama' -C /data apps

find "$dir" -type f -mtime +14 -delete

for f in "$dir"/*_"$ts".*; do
  oci os object put --auth instance_principal --bucket-name "${BACKUP_BUCKET:-sulotec-backups}" \
    --file "$f" --name "$(date +%Y/%m)/$(basename "$f")" --force >/dev/null
done
# Mantenimiento del disco: cada despliegue deja cache de construccion de Docker (llego a 19 GB en 12 dias).
# Se borra la de mas de 3 dias y las imagenes sin etiqueta; no toca imagenes con nombre ni volumenes.
docker builder prune -f --filter 'until=72h' >/dev/null 2>&1 || true
docker image prune -f >/dev/null 2>&1 || true
uso="$(df --output=pcent / | tail -1 | tr -dc '0-9')"
[ "${uso:-0}" -lt 80 ] || echo "$(date -Is) ALERTA: el disco esta al ${uso}%. Ver /var/backups/sulotec y: sudo docker system df"

echo "$(date -Is) backup OK y subido a ${BACKUP_BUCKET:-sulotec-backups}: $(cd "$dir" && ls *_"$ts".* | tr '\n' ' ') | disco al ${uso:-?}%"
