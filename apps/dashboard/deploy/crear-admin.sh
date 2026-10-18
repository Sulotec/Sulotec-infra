#!/usr/bin/env bash
# Crea (o, con --resetear, le da clave nueva a) una cuenta de ADMINISTRADOR GENERAL de Dashboard Empresarial.
# La clave es aleatoria, se muestra UNA sola vez en pantalla y no queda guardada en ningun archivo del servidor.
#   sudo bash /data/apps/dashboard/crear-admin.sh                      crea 'admin.sulotec'
#   sudo bash /data/apps/dashboard/crear-admin.sh otro.usuario         crea con otro nombre
#   sudo bash /data/apps/dashboard/crear-admin.sh admin.sulotec --resetear      clave nueva para una cuenta que ya existe
# Necesita la API corriendo (desplegar.sh) y las tablas cargadas (importar-datos.sh).
set -euo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }
[ "$(docker inspect -f '{{.State.Running}}' dashboard-api 2>/dev/null || echo false)" = true ] || { echo "dashboard-api no esta corriendo: primero desplegar.sh" >&2; exit 1; }
exec docker exec dashboard-api node scripts/crear-admin.js "$@"
