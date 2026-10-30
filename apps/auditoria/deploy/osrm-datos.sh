#!/usr/bin/env bash
# Prepara (o renueva) el mapa de Peru del motor de rutas por calles (OSRM) de GeoMatrix: baja el extracto de OpenStreetMap de Geofabrik, lo convierte
# al formato del motor (10-20 min la primera vez; necesita 2-3 GB de RAM libres y unos 2 GB de disco) y levanta el contenedor auditoria-osrm.
#   sudo bash /data/apps/auditoria/osrm-datos.sh
# Se puede repetir (por ejemplo una vez al mes, para traer calles nuevas): construye en una carpeta aparte y recien al final reemplaza la anterior;
# si algo falla, el mapa que estaba sigue en uso.
set -euo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

APP=/data/apps/auditoria
DATOS="$APP/osrm"
NUEVO="$DATOS.nuevo"
IMAGEN="${OSRM_IMAGEN:-ghcr.io/project-osrm/osrm-backend:v5.27.1}"
EXTRACTO="${OSRM_EXTRACTO:-https://download.geofabrik.de/south-america/peru-latest.osm.pbf}"
RED_DOCKER="${RED_DOCKER:-sulotec_edge}"

[ -f "$APP/docker-compose.yml" ] && grep -q 'container_name: auditoria-osrm' "$APP/docker-compose.yml" \
  || { echo "El docker-compose.yml de $APP no tiene el servicio osrm: copia el kit nuevo desde GitHub (README, paso 2) y vuelve a correr esto." >&2; exit 1; }

rm -rf "$NUEVO"; mkdir -p "$NUEVO"
echo "== Bajando el mapa de Peru (OpenStreetMap via Geofabrik; unos 250 MB)"
curl -fL --retry 3 --progress-bar -o "$NUEVO/peru-latest.osm.pbf" "$EXTRACTO"
echo "   $(du -h "$NUEVO/peru-latest.osm.pbf" | cut -f1) bajados"

echo "== Convirtiendo al formato del motor (perfil de carro; tarda varios minutos, no lo cortes)"
paso() { # paso <nombre> <comando osrm...>
  local nombre="$1"; shift
  if docker run --rm -v "$NUEVO:/data" "$IMAGEN" "$@" > "$NUEVO/$nombre.log" 2>&1; then echo "   $nombre: listo"; else echo "   $nombre: FALLO. Ultimas lineas:" >&2; tail -15 "$NUEVO/$nombre.log" >&2; exit 1; fi
}
paso extract   osrm-extract -p /opt/car.lua /data/peru-latest.osm.pbf
paso partition osrm-partition /data/peru-latest.osrm
paso customize osrm-customize /data/peru-latest.osrm
rm -f "$NUEVO/peru-latest.osm.pbf"   # el extracto ya no hace falta; en la proxima renovacion se baja de nuevo
date -u +%Y-%m-%dT%H:%M:%SZ > "$NUEVO/FECHA"

echo "== Poniendo el mapa nuevo y levantando el motor"
(cd "$APP" && docker compose stop osrm >/dev/null 2>&1 || true)
rm -rf "$DATOS.anterior"
[ -e "$DATOS" ] && mv "$DATOS" "$DATOS.anterior"
mv "$NUEVO" "$DATOS"
(cd "$APP" && docker compose up -d osrm >/dev/null)

echo "== Probando una ruta en Lima"
for _ in $(seq 1 30); do
  if docker run --rm --network "$RED_DOCKER" curlimages/curl:8.10.1 -sf "http://auditoria-osrm:5000/route/v1/driving/-77.0428,-12.0464;-77.0300,-12.0600?overview=false" >/dev/null 2>&1; then
    rm -rf "$DATOS.anterior"
    echo "   el motor responde. Mapa del $(cat "$DATOS/FECHA")."
    echo "Listo. Si OSRM_URL todavia no esta en /opt/sulotec/auditoria.env: sudo bash $APP/preparar.sh (Enter en todo, acepta http://auditoria-osrm:5000) y luego desplegar.sh."
    exit 0
  fi
  sleep 3
done
echo "El motor no respondio. Mira: docker logs auditoria-osrm. El mapa anterior quedo en $DATOS.anterior (para volver: docker compose stop osrm; mv)." >&2
exit 1
