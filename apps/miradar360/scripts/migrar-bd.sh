#!/usr/bin/env bash
# Copia la base de datos de Render a la base NUEVA del servidor y compara cantidades.
#   sudo bash /data/apps/miradar360/scripts/migrar-bd.sh
# - De Render SOLO LEE (pg_dump). Nunca escribe ni borra nada alli.
# - En la base nueva REEMPLAZA todo el contenido. Se puede repetir las veces que haga falta (ensayos).
# - La URL de Render se pide por pantalla (no queda guardada). Es la "External Database URL" de la base en Render.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }
umask 077

docker ps --format '{{.Names}}' | grep -qx miradar360-db \
  || { echo "La base nueva no esta corriendo: corre antes scripts/desplegar.sh" >&2; exit 1; }

read -rsp "URL externa de la base de Render (postgresql://...): " ORIGEN; echo
[[ "$ORIGEN" =~ ^postgres(ql)?:// ]] || { echo "No parece una URL de PostgreSQL." >&2; exit 1; }
read -rp "Esto REEMPLAZA todo lo que haya en la base nueva (miradar360-db). ¿Seguir? [s/N] " r
[[ "$r" =~ ^[sS]$ ]] || { echo "Cancelado."; exit 0; }

ARCH="/data/backups/miradar360/render-$(date +%Y%m%d-%H%M).dump"
echo "1/3 Copiando desde Render a $ARCH ..."
# pg_dump de la version 18 (la misma de Render) dentro de un contenedor.
docker run --rm -i -e ORIGEN="$ORIGEN" postgres:18 sh -c 'pg_dump "$ORIGEN" --format=custom --no-owner --no-acl' > "$ARCH"
echo "    $(du -h "$ARCH" | cut -f1) copiados."

echo "2/3 Restaurando en la base nueva ..."
docker exec -i miradar360-db pg_restore -U radar -d radar --clean --if-exists --no-owner --no-acl < "$ARCH" \
  || echo "    pg_restore dio avisos: lo que importa es la comparacion de abajo."

echo "3/3 Comparando cantidades (Render vs servidor):"
printf '    %-12s %10s %10s\n' tabla render servidor
difieren=0
for t in clientes usuarios asesores rutas visitas; do
  a="$(docker run --rm -e ORIGEN="$ORIGEN" postgres:18 sh -c "psql \"\$ORIGEN\" -Atc 'select count(*) from $t'" 2>/dev/null || echo ?)"
  b="$(docker exec miradar360-db psql -U radar -d radar -Atc "select count(*) from $t" 2>/dev/null || echo ?)"
  marca=OK; [ "$a" = "$b" ] || { marca=DIFERENTE; difieren=1; }
  printf '    %-12s %10s %10s  %s\n' "$t" "$a" "$b" "$marca"
done
echo
[ "$difieren" -eq 0 ] && echo "Todo coincide." || { echo "HAY DIFERENCIAS: no sigas con el cambio hasta entender por que." >&2; exit 1; }
echo "El respaldo queda en $ARCH (contiene datos personales: no lo copies fuera del servidor)."
