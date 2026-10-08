#!/usr/bin/env bash
# Instala en el servidor un runner propio de GitHub Actions para desplegar automaticamente.
# El runner se conecta SALIENDO hacia GitHub (no se abre ningun puerto).
# Uso:  sudo bash instalar-runner.sh https://github.com/ORGANIZACION/REPO
#       (pide el token de registro sin mostrarlo; se obtiene en GitHub -> Settings -> Actions -> Runners -> New self-hosted runner)
# IMPORTANTE: usar solo con repositorios PRIVADOS.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
[ "$(id -u)" -eq 0 ] || { echo "Ejecuta con sudo"; exit 1; }
URL="${1:?uso: sudo bash $0 https://github.com/ORGANIZACION/REPO}"
read -rsp "Pega el token de registro del runner y Enter (no se mostrara): " TOKEN; echo
[ -n "$TOKEN" ] || { echo "Token vacio"; exit 1; }

apt-get update -qq && apt-get install -y -qq rsync jq >/dev/null

id -u github-runner >/dev/null 2>&1 || useradd -m -s /bin/bash -G docker github-runner
install -d -o github-runner -g docker -m 2775 /data/apps/portal
chown -R github-runner:docker /data/apps/portal

DIR=/opt/actions-runner
VER="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/^v//')"
if [ ! -x "$DIR/config.sh" ]; then
  install -d -o github-runner -g github-runner "$DIR"
  curl -fsSL "https://github.com/actions/runner/releases/download/v${VER}/actions-runner-linux-arm64-${VER}.tar.gz" | tar xz -C "$DIR"
  chown -R github-runner:github-runner "$DIR"
fi

cd "$DIR"
sudo -u github-runner ./config.sh --unattended --replace --url "$URL" --token "$TOKEN" \
  --name sulotec-main --labels sulotec --work _work
./svc.sh install github-runner
./svc.sh start
echo
echo "LISTO-RUNNER: en GitHub -> Settings -> Actions -> Runners debe aparecer 'sulotec-main' como Idle."
