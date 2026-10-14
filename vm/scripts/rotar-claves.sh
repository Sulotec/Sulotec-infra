#!/usr/bin/env bash
# Rota las claves de las bases de datos de la VM. Las claves nuevas se generan aqui, se guardan solo en los archivos de
# configuracion (root:docker 640) y NO se imprimen ni pasan por ningun chat. Cada rotacion se comprueba contra la red
# interna: la clave nueva debe entrar y la vieja ya no.
#   sudo /opt/sulotec/scripts/rotar-claves.sh [postgres] [mysql] [miradar]      (sin argumentos: las tres)
#   postgres  usuario administrador "postgres"       -> POSTGRES_PASSWORD en /opt/sulotec/.env
#   mysql     usuario "root"                         -> MYSQL_ROOT_PASSWORD en /opt/sulotec/.env (recrea el contenedor mysql: unos segundos sin servicio)
#   miradar   usuario "miradar" de la base MiRadar   -> DATABASE_URL en /opt/sulotec/miradar.env (recrea miradar-api)
# Variables solo para pruebas: SULOTEC_DIR, MIRADAR_ENV, MIRADAR_DIR, RED_DATOS.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo $0" >&2; exit 1; }
BASE="${SULOTEC_DIR:-/opt/sulotec}"
MIRADAR_ENV="${MIRADAR_ENV:-$BASE/miradar.env}"
MIRADAR_DIR="${MIRADAR_DIR:-/data/apps/miradar}"
RED_DATOS="${RED_DATOS:-sulotec_data}"
cd "$BASE"
[ -r .env ] || { echo "No encuentro $BASE/.env" >&2; exit 1; }

que=("$@"); [ "${#que[@]}" -gt 0 ] || que=(postgres mysql miradar)
hacer() { local q; for q in "${que[@]}"; do [ "$q" = "$1" ] && return 0; done; return 1; }
nueva() { openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | head -c 32; }
leer() { grep -E "^$2=" "$1" | head -1 | cut -d= -f2- || true; }
poner() { grep -q "^$2=" "$1" || { echo "No encuentro $2 en $1" >&2; return 1; }; sed -i "s|^$2=.*|$2=$3|" "$1"; }
# cliente de PostgreSQL desde la red interna (el socket local y 127.0.0.1 no piden clave, esto si)
entra_pg() { [ "$(docker run --rm --network "$RED_DATOS" -e PGPASSWORD="$2" postgres:16 psql -h postgres -U "$1" -d "${3:-postgres}" -At -c 'select 1' 2>/dev/null || true)" = "1" ]; }
espera_sano() { local c="$1" t="${2:-90}" i; for i in $(seq 1 "$t"); do [ "$(docker inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null || echo none)" = healthy ] && return 0; sleep 1; done; return 1; }
borrar_copias=()

if hacer postgres; then
  echo "== PostgreSQL: usuario postgres"
  vieja="$(leer .env POSTGRES_PASSWORD)"; nuevo="$(nueva)"
  [ -n "$vieja" ] || { echo "POSTGRES_PASSWORD vacia en .env" >&2; exit 1; }
  printf "ALTER ROLE postgres PASSWORD '%s';\n" "$nuevo" | docker compose exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 -q >/dev/null
  cp -p .env .env.antes-rotacion; borrar_copias+=("$BASE/.env.antes-rotacion")
  poner .env POSTGRES_PASSWORD "$nuevo"
  entra_pg postgres "$nuevo" || { echo "FALLO: la clave nueva no entra. La anterior esta en $BASE/.env.antes-rotacion" >&2; exit 1; }
  if entra_pg postgres "$vieja"; then echo "AVISO: la clave anterior todavia entra" >&2; else echo "   OK: la clave nueva entra y la anterior ya no"; fi
fi

if hacer mysql; then
  echo "== MySQL: usuario root (el contenedor mysql se recrea: unos segundos sin servicio)"
  vieja="$(leer .env MYSQL_ROOT_PASSWORD)"; nuevo="$(nueva)"
  [ -n "$vieja" ] || { echo "MYSQL_ROOT_PASSWORD vacia en .env" >&2; exit 1; }
  printf "ALTER USER IF EXISTS 'root'@'%%' IDENTIFIED BY '%s';\nALTER USER IF EXISTS 'root'@'localhost' IDENTIFIED BY '%s';\nFLUSH PRIVILEGES;\n" "$nuevo" "$nuevo" \
    | docker compose exec -T -e MYSQL_PWD="$vieja" mysql mysql -uroot
  [ -e .env.antes-rotacion ] || { cp -p .env .env.antes-rotacion; borrar_copias+=("$BASE/.env.antes-rotacion"); }
  poner .env MYSQL_ROOT_PASSWORD "$nuevo"
  # el healthcheck del contenedor usa la clave de su entorno: hay que recrearlo para que lea la nueva
  docker compose up -d mysql >/dev/null 2>&1
  id="$(docker compose ps -q mysql)"
  espera_sano "$id" 120 || { echo "FALLO: mysql no volvio a estar sano. La clave anterior esta en $BASE/.env.antes-rotacion" >&2; exit 1; }
  docker compose exec -T -e MYSQL_PWD="$nuevo" mysql mysql -uroot -e 'select 1' >/dev/null || { echo "FALLO: la clave nueva de root no entra" >&2; exit 1; }
  if docker compose exec -T -e MYSQL_PWD="$vieja" mysql mysql -uroot -e 'select 1' >/dev/null 2>&1; then echo "AVISO: la clave anterior todavia entra" >&2; else echo "   OK: la clave nueva entra y la anterior ya no"; fi
fi

if hacer miradar; then
  echo "== MiRadar: usuario miradar de la base miradar (la API se recrea)"
  [ -r "$MIRADAR_ENV" ] || { echo "No encuentro $MIRADAR_ENV" >&2; exit 1; }
  url="$(leer "$MIRADAR_ENV" DATABASE_URL)"
  vieja="$(printf '%s' "$url" | sed -E 's#^postgres(ql)?://[^:]+:([^@]*)@.*#\2#')"; nuevo="$(nueva)"
  [ -n "$vieja" ] && [ "$vieja" != "$url" ] || { echo "No pude leer la clave actual de DATABASE_URL" >&2; exit 1; }
  printf "ALTER ROLE miradar PASSWORD '%s';\n" "$nuevo" | docker compose exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 -q >/dev/null
  cp -p "$MIRADAR_ENV" "$MIRADAR_ENV.antes-rotacion"; borrar_copias+=("$MIRADAR_ENV.antes-rotacion")
  sed -i -E "s#^(DATABASE_URL=postgres(ql)?://miradar:)[^@]*@#\1$nuevo@#" "$MIRADAR_ENV"
  entra_pg miradar "$nuevo" miradar || { echo "FALLO: la clave nueva no entra a la base miradar" >&2; exit 1; }
  if entra_pg miradar "$vieja" miradar; then echo "AVISO: la clave anterior todavia entra" >&2; fi
  ( cd "$MIRADAR_DIR" && docker compose up -d --force-recreate api >/dev/null 2>&1 )
  if espera_sano miradar-api 90; then
    echo "   OK: la API arranco con la clave nueva"
  else
    echo "FALLO: miradar-api no arranco. Vuelvo a la clave anterior..." >&2
    printf "ALTER ROLE miradar PASSWORD '%s';\n" "$vieja" | docker compose exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 -q >/dev/null
    cp -p "$MIRADAR_ENV.antes-rotacion" "$MIRADAR_ENV"
    ( cd "$MIRADAR_DIR" && docker compose up -d --force-recreate api >/dev/null 2>&1 ) || true
    exit 1
  fi
fi

# solo si todo salio bien se borran las copias con las claves anteriores
for f in "${borrar_copias[@]:-}"; do [ -n "$f" ] && rm -f "$f"; done
echo
echo "Listo. Las claves nuevas estan solo en $BASE/.env y $MIRADAR_ENV (no se imprimieron)."
echo "Pasalas a tu gestor de contrasenas con:  sudo grep -E '^(POSTGRES_PASSWORD|MYSQL_ROOT_PASSWORD)=' $BASE/.env"
