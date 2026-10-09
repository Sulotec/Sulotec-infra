#!/usr/bin/env bash
# Instala UNA vez la publicacion automatica del Buscador en el servidor Oracle:
#   sudo bash /data/apps/buscador/instalar-actualizador.sh
# 1. Crea una llave de despliegue y muestra su parte publica (no es secreta) para agregarla en GitHub
#    como "Deploy key" de SOLO LECTURA en Sulotec/buscador-interno.
# 2. Descarga el repositorio y programa una revision cada 2 minutos (systemd: buscador-actualizador.timer).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

BASE=/opt/sulotec/buscador-actualizador
APP=/data/apps/buscador
REPO_URL=git@github.com:Sulotec/buscador-interno.git
export GIT_SSH_COMMAND="ssh -i $BASE/llave -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$BASE/known_hosts"

install -d -m 700 "$BASE"
[ -f "$BASE/llave" ] || ssh-keygen -q -t ed25519 -N '' -C 'servidor-sulotec-main (solo lectura)' -f "$BASE/llave"

if [ ! -d "$BASE/repo/.git" ]; then
  echo
  echo "=== Llave publica del servidor (no es secreta) ==="
  cat "$BASE/llave.pub"
  echo
  echo "Agregala en GitHub: Sulotec/buscador-interno -> Settings -> Deploy keys -> Add deploy key"
  echo "  Title: servidor-sulotec-main | Key: la linea de arriba | Allow write access: NO (dejar sin marcar)"
  read -rp "Cuando este agregada, pulsa Enter para continuar... " _
  git clone -q --branch main "$REPO_URL" "$BASE/repo"
  echo "Repositorio descargado."
fi

cat > /etc/systemd/system/buscador-actualizador.service <<EOF
[Unit]
Description=Publica el Buscador Interno cuando hay cambios en GitHub (Sulotec/buscador-interno)
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash $APP/actualizar.sh
EOF

cat > /etc/systemd/system/buscador-actualizador.timer <<EOF
[Unit]
Description=Revisa cada 2 minutos si hay una version nueva del Buscador Interno

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now buscador-actualizador.timer >/dev/null
echo "Primera publicacion desde el repositorio nuevo (puede tardar unos minutos)..."
systemctl start buscador-actualizador.service || true
tail -n 3 /var/log/buscador-actualizador.log 2>/dev/null || true
echo
echo "Listo. Desde ahora cada cambio en main de Sulotec/buscador-interno se publica solo."
echo "  Estado:   systemctl list-timers buscador-actualizador.timer"
echo "  Registro: sudo tail -f /var/log/buscador-actualizador.log"
