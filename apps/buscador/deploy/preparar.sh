#!/usr/bin/env bash
# Configura buscadorinterno.sulotec.com en el servidor. Se puede repetir para cambiar valores.
#   sudo bash /data/apps/buscador/preparar.sh
# Guarda la configuracion en /opt/sulotec/buscador.env (solo root y el grupo docker) y levanta el contenedor.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

ENV=/opt/sulotec/buscador.env
APP=/data/apps/buscador
[ -f "$APP/docker-compose.yml" ] || { echo "Falta $APP: primero se publica desde GitHub (workflow 'Publicar buscador')." >&2; exit 1; }
limpiar() { local v="$1"; v="${v//$'\e'\[200~/}"; v="${v//$'\e'\[201~/}"; v="${v//\[200~/}"; v="${v//\[201~/}"; printf '%s' "${v//[[:space:]]/}"; }
actual() { [ -f "$ENV" ] && grep -E "^$1=" "$ENV" | head -1 | cut -d= -f2- | sed "s/^'//; s/'\$//" || true; }

api_actual="$(actual BUSCADOR_API_URL)"
sedes_actual="$(actual SEDES_IPS)"
echo "Direccion de la API del Buscador (la de la oficina)."
read -rp "  [Enter = ${api_actual:-ninguna}]: " api
api="$(limpiar "${api:-$api_actual}")"
[[ "$api" =~ ^https:// ]] || { echo "La direccion debe empezar con https://" >&2; exit 1; }

echo "IPs publicas de las sedes (Lince, Los Olivos), separadas por comas. Ej: 200.1.2.3,190.4.5.6"
echo "  Sin sedes, solo el rol ADMIN GENERAL puede entrar."
read -rp "  [Enter = ${sedes_actual:-ninguna}]: " sedes
sedes="$(limpiar "${sedes:-$sedes_actual}")"

cf_id="$(actual CF_ACCESS_CLIENT_ID)"; cf_secreto="$(actual CF_ACCESS_CLIENT_SECRET)"
read -rp "¿Configurar el token de servicio de Cloudflare Access para la API? [s/N] " r
if [[ "$r" =~ ^[sS]$ ]]; then
  read -rp "  Client ID: " cf_id; cf_id="$(limpiar "$cf_id")"
  read -rsp "  Client Secret (no se muestra): " cf_secreto; echo; cf_secreto="$(limpiar "$cf_secreto")"
fi

install -m 640 -o root -g docker /dev/null "$ENV"
{
  echo "BUSCADOR_API_URL=$api"
  echo "SEDES_IPS=$sedes"
  [ -n "$cf_id" ] && echo "CF_ACCESS_CLIENT_ID=$cf_id"
  [ -n "$cf_secreto" ] && echo "CF_ACCESS_CLIENT_SECRET=$cf_secreto"
} > "$ENV"
echo "Configuracion guardada en $ENV"

cd "$APP"
docker compose up -d --force-recreate
echo "Listo: el Buscador queda en https://buscadorinterno.sulotec.com (cuando la ruta del tunel exista)."
