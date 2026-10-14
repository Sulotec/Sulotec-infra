#!/usr/bin/env bash
# Muestra EN PANTALLA las claves guardadas en el servidor, para copiarlas al gestor de contrasenas de la empresa.
# No escribe archivos ni las manda a ningun lado. Ver docs/05-inventario-de-claves.md.
#   sudo /opt/sulotec/scripts/mostrar-claves.sh
# Variables solo para pruebas: ARCHIVOS (lista separada por espacios) y PRUEBA.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo $0" >&2; exit 1; }

echo "Esto muestra claves REALES en pantalla."
echo "Hazlo donde nadie mas vea tu pantalla y, al terminar, limpia la pantalla con:  clear"
read -rp "¿Continuar? [s/N] " r
[[ "$r" =~ ^[sS]$ ]] || { echo "No se mostro nada."; exit 0; }

archivos="${ARCHIVOS:-/opt/sulotec/.env /opt/sulotec/miradar.env /opt/sulotec/cuenta.env /opt/sulotec/buscador.env}"
for f in $archivos; do
  [ -r "$f" ] || { echo; echo "=== $f: no existe o no se puede leer"; continue; }
  echo; echo "=== $f ==="
  # solo variables que parecen secretos (o su usuario) y que tengan valor
  grep -E '^[A-Za-z0-9_]*(PASSWORD|SECRET|TOKEN|KEY|DATABASE_URL|CLIENT_ID|USERNAME)[A-Za-z0-9_]*=.+' "$f" || echo "   (nada que mostrar)"
done
echo
echo "Fin. Copia lo que necesites al gestor y limpia la pantalla:  clear"
echo "Recuerda: lo marcado como imprescindible en docs/05-inventario-de-claves.md (sobre todo MFA_ENCRYPTION_KEY) debe quedar en el gestor."
