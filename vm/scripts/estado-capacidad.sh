#!/usr/bin/env bash
# Informe de capacidad del servidor: memoria, discos, bases de datos, Docker, respaldos y buckets de Object Storage.
# Solo lee: no cambia nada ni imprime claves.
#   sudo /opt/sulotec/scripts/estado-capacidad.sh
# Variables solo para pruebas: SULOTEC_DIR, PRUEBA.
set -uo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo $0" >&2; exit 1; }
BASE="${SULOTEC_DIR:-/opt/sulotec}"
BUCKETS="${BUCKETS:-sulotec-backups sulotec-archivos miradar-archivos}"
cd "$BASE" 2>/dev/null || true
bytes() { numfmt --to=iec --suffix=B "${1:-0}" 2>/dev/null || echo "${1:-0} B"; }

echo "== Servidor"
echo "   encendido: $(uptime -p 2>/dev/null || true)"
echo "   carga (1/5/15 min): $(cut -d' ' -f1-3 /proc/loadavg) | nucleos: $(nproc)"
free -m 2>/dev/null | awk 'NR==2{printf "   memoria: %d MB en uso de %d MB (%d%%)\n", $3, $2, ($3*100)/$2}'

echo "== Discos"
df -h --output=target,size,used,avail,pcent / /data 2>/dev/null | sed 's/^/   /' || true

echo "== Que ocupa /data"
du -sh /data/* 2>/dev/null | sort -rh | head -8 | sed 's/^/   /' || true

echo "== Bases de datos PostgreSQL (tamano de cada una)"
docker compose exec -T postgres psql -U postgres -At -F '  ' \
  -c "select datname, pg_size_pretty(pg_database_size(datname)) from pg_database where not datistemplate order by pg_database_size(datname) desc" 2>/dev/null | sed 's/^/   /' || echo "   (no se pudo leer)"

echo "== MySQL (tamano por base, sin las del sistema)"
if [ -r .env ]; then
  clave="$(grep -E '^MYSQL_ROOT_PASSWORD=' .env | head -1 | cut -d= -f2- || true)"
  docker compose exec -T -e MYSQL_PWD="$clave" mysql mysql -uroot -N \
    -e "select table_schema, concat(round(sum(data_length+index_length)/1024/1024,1),' MB') from information_schema.tables where table_schema not in ('mysql','sys','performance_schema','information_schema') group by table_schema" 2>/dev/null \
    | awk 'BEGIN{n=0} {print "   " $0; n++} END{if (n==0) print "   (sin bases de usuario)"}' || echo "   (no se pudo leer)"
fi

echo "== Docker (imagenes, contenedores y volumenes)"
docker system df 2>/dev/null | sed 's/^/   /' || true

echo "== Respaldos en este servidor (14 dias)"
if [ -d /var/backups/sulotec ]; then
  echo "   $(ls /var/backups/sulotec | wc -l) archivos, $(du -sh /var/backups/sulotec | cut -f1) en total; el ultimo: $(ls -1t /var/backups/sulotec | head -1)"
fi

echo "== Object Storage (buckets de Oracle)"
ns="$(oci os ns get --auth instance_principal --query data --raw-output 2>/dev/null || true)"
if [ -z "$ns" ]; then
  echo "   (no se pudo consultar Oracle desde el servidor)"
else
  total=0
  for b in $BUCKETS; do
    tam="$(oci os bucket get --auth instance_principal --namespace-name "$ns" --bucket-name "$b" --fields approximateSize --query 'data."approximate-size"' --raw-output 2>/dev/null || true)"
    num="$(oci os bucket get --auth instance_principal --namespace-name "$ns" --bucket-name "$b" --fields approximateCount --query 'data."approximate-count"' --raw-output 2>/dev/null || true)"
    if [ -n "$tam" ] && [ "$tam" != "null" ]; then
      printf '   %-20s %10s en %s objetos\n' "$b" "$(bytes "$tam")" "${num:-?}"
      total=$((total + tam))
    else
      printf '   %-20s (no se pudo leer o no existe)\n' "$b"
    fi
  done
  echo "   TOTAL de los buckets: $(bytes "$total")   (el gratis de Oracle: 20 GB entre Standard e Infrequent Access)"
fi
echo
echo "Fin del informe. Pegalo completo en el chat: no lleva claves."
