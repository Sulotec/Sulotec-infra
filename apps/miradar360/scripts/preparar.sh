#!/usr/bin/env bash
# Paso 1 (una sola vez): crea la configuracion de MiRadar360 en el servidor.
#   sudo bash /data/apps/miradar360/scripts/preparar.sh
# Genera la clave de la base de datos y deja /opt/sulotec/miradar360.env listo para pegar los valores de Render.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

APP="$(cd "$(dirname "$0")/.." && pwd)"
ENV=/opt/sulotec/miradar360.env

if [ -f "$ENV" ]; then
  echo "Ya existe $ENV. No lo sobrescribo."
  echo "Para cambiar valores:  sudo nano $ENV"
  exit 0
fi

clave="$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 28)"
install -m 640 -o root -g docker /dev/null "$ENV"
sed "s/CLAVE_DB/$clave/g" "$APP/.env.example" > "$ENV"
mkdir -p /data/miradar360/postgres /data/backups/miradar360
chmod 700 /data/backups/miradar360

echo
echo "Listo: $ENV creado (solo root y el grupo docker pueden leerlo)."
echo "La clave de la base de datos ya quedo puesta; no hace falta guardarla aparte."
echo
echo "Siguiente paso: pegar los valores de Render en las lineas con PEGAR_DESDE_RENDER:"
echo "    sudo nano $ENV"
echo "(copiar TAL CUAL MFA_ENCRYPTION_KEY y JWT_SECRET; ver el encabezado del archivo)."
echo "Despues:  sudo bash $APP/scripts/desplegar.sh"
