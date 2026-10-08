#!/usr/bin/env bash
# Deja lista la VM en un solo paso: compose base (tunel Cloudflare + Postgres), scripts y .env.
# No hace falta copiar archivos desde ninguna PC: todo va dentro de este script.
# Uso en la VM:  bash bootstrap.sh     (se puede repetir; no pisa un .env existente)
set -euo pipefail

echo "Esperando a que cloud-init termine (Docker, fail2ban)..."
sudo cloud-init status --wait >/dev/null || true
[ -f /opt/sulotec/.cloud-init-ok ] || { echo "cloud-init no termino bien: revisa 'sudo cloud-init status --long'"; exit 1; }

cd /opt/sulotec
mkdir -p scripts

cat > docker-compose.yml <<'EOF_COMPOSE'
name: sulotec

# Servicios base de la VM. Cada proyecto va en su propio compose (ver ../templates/app-compose.yml)
# y se une a estas dos redes:
#   sulotec_edge -> contenedores que Cloudflare Tunnel puede alcanzar
#   sulotec_data -> acceso a Postgres

services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    restart: unless-stopped
    command: tunnel --no-autoupdate run
    environment:
      TUNNEL_TOKEN: ${CF_TUNNEL_TOKEN:?falta CF_TUNNEL_TOKEN en .env}
    networks: [edge]

  postgres:
    image: postgres:16
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?falta POSTGRES_PASSWORD en .env}
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks: [data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  edge:
    name: sulotec_edge
  data:
    name: sulotec_data

volumes:
  pgdata:
EOF_COMPOSE

cat > scripts/backup-postgres.sh <<'EOF_BACKUP'
#!/usr/bin/env bash
# Backup diario de todas las bases. Guarda 14 dias en /opt/backups y,
# si hay OCI CLI + BACKUP_BUCKET, tambien lo sube a Object Storage.
# Cron sugerido (crontab -e):
#   0 2 * * * /opt/sulotec/scripts/backup-postgres.sh >> /opt/backups/backup.log 2>&1
set -euo pipefail

cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a

dir=/opt/backups
mkdir -p "$dir"
file="$dir/pg_$(date +%F_%H%M).sql.gz"

docker compose exec -T postgres pg_dumpall -U postgres | gzip > "$file"
find "$dir" -name 'pg_*.sql.gz' -mtime +14 -delete
echo "$(date -Is) backup local: $file"

if command -v oci >/dev/null 2>&1 && [ -n "${BACKUP_BUCKET:-}" ]; then
  oci os object put --auth instance_principal --bucket-name "$BACKUP_BUCKET" \
    --file "$file" --name "postgres/$(basename "$file")" --force >/dev/null
  echo "$(date -Is) backup subido a $BACKUP_BUCKET"
fi
EOF_BACKUP

cat > scripts/new-project-db.sh <<'EOF_NEWDB'
#!/usr/bin/env bash
# Crea una base de datos + usuario propio para un proyecto nuevo.
# Uso:  ./scripts/new-project-db.sh afacop
set -euo pipefail

name="${1:?uso: $0 <proyecto>  (minusculas, numeros y _)}"
[[ "$name" =~ ^[a-z][a-z0-9_]*$ ]] || { echo "nombre invalido: $name" >&2; exit 1; }

cd "$(dirname "$0")/.."
pass="$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 28)"

docker compose exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 <<SQL
CREATE ROLE "$name" LOGIN PASSWORD '$pass';
CREATE DATABASE "$name" OWNER "$name";
REVOKE ALL ON DATABASE "$name" FROM PUBLIC;
SQL

echo
echo "Base '$name' creada. Guarda estos datos ahora (la clave no se vuelve a mostrar):"
echo "  .NET : Host=postgres;Port=5432;Database=$name;Username=$name;Password=$pass"
echo "  Java : jdbc:postgresql://postgres:5432/$name   usuario=$name   clave=$pass"
EOF_NEWDB

chmod +x scripts/*.sh

if [ ! -f .env ]; then
  read -rsp "Pega el token del tunel de Cloudflare (no se mostrara en pantalla) y Enter: " token; echo
  case "$token" in eyJ*) ;; *) echo "Eso no parece el token (debe empezar con eyJ). Vuelve a ejecutar: bash bootstrap.sh"; exit 1;; esac
  pg="$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 32)"
  ( umask 077; printf 'CF_TUNNEL_TOKEN=%s\nPOSTGRES_PASSWORD=%s\nBACKUP_BUCKET=sulotec-backups\n' "$token" "$pg" > .env )
  echo ".env creado (solo lo puede leer el usuario ubuntu)."
fi

# 'sg docker' evita tener que cerrar y abrir la sesion SSH para estrenar el grupo docker.
sg docker -c "docker compose up -d && docker compose ps"
echo
echo "Listo. En Cloudflare -> Networking -> Tunnels, el tunel 'sulotec' debe pasar a Healthy en ~1 minuto."
echo "Guarda la clave de Postgres en el gestor de contrasenas de la empresa:  grep POSTGRES_PASSWORD /opt/sulotec/.env"
