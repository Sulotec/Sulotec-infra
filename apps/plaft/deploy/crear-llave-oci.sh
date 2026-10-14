#!/usr/bin/env bash
# Crea la llave de API de Oracle del usuario svc-plaft (acceso SOLO al bucket plaft-archivos) y deja lista su configuracion.
# La llave PRIVADA se genera aqui, en el servidor, y no sale de el: a Oracle solo se sube la publica.
#   sudo bash /data/apps/plaft/crear-llave-oci.sh
# Se puede repetir: si la configuracion ya existe, solo prueba el acceso al bucket.
# Variables solo para pruebas: OCI_DIR, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

DIR="${OCI_DIR:-/opt/sulotec/plaft-oci}"
NS="${OCI_NAMESPACE:-axkjo5bh8iys}"
BUCKET="${OCI_BUCKET:-plaft-archivos}"
REGION="${OCI_REGION:-sa-santiago-1}"
export OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True
TMP="$(mktemp -d)"; chmod 700 "$TMP"
trap '[ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"' EXIT
mkdir -p "$DIR"; chmod 700 "$DIR"
limpiar() { local v="$1"; v="${v//$'\e'\[200~/}"; v="${v//$'\e'\[201~/}"; v="${v//\[200~/}"; v="${v//\[201~/}"; printf '%s' "${v//[[:space:]]/}"; }

if [ ! -f "$DIR/config" ]; then
  # 1) llave privada (2048 bits) y publica; la huella se calcula igual que lo hace Oracle
  [ -f "$DIR/key.pem" ] || openssl genrsa -out "$DIR/key.pem" 2048 2>/dev/null
  chmod 644 "$DIR/key.pem"   # el contenedor la lee como usuario sin privilegios; la carpeta (700) impide que la vea otra persona del servidor
  huella="$(openssl rsa -in "$DIR/key.pem" -pubout -outform DER 2>/dev/null | openssl md5 -c | awk '{print $NF}')"
  b64="$(openssl rsa -in "$DIR/key.pem" -pubout 2>/dev/null | base64 -w0)"
  echo "== Paso 1: subir la llave PUBLICA a Oracle"
  echo "   Abre Cloud Shell de Oracle (icono >_ de la consola) y pega esta linea (es una sola linea; no lleva secretos):"
  echo
  echo "echo '$b64' | base64 -d > /tmp/plaft.pub && USR=\$(oci iam user list --all --query \"data[?name=='svc-plaft'].id | [0]\" --raw-output) && oci iam user api-key upload --user-id \"\$USR\" --key-file /tmp/plaft.pub >/dev/null && echo \"TENANCY=\$OCI_TENANCY\" && echo \"USUARIO=\$USR\""
  echo
  echo "   Al terminar muestra dos lineas: TENANCY=ocid1.tenancy... y USUARIO=ocid1.user... (no son secretas)."
  echo "   Si Oracle dice que el usuario ya tiene 3 llaves, borra una en Identity -> Users -> svc-plaft -> API keys."
  echo
  read -rp "Pega aqui el valor de TENANCY (ocid1.tenancy...): " tenancy; tenancy="$(limpiar "$tenancy")"; tenancy="${tenancy#TENANCY=}"
  read -rp "Pega aqui el valor de USUARIO (ocid1.user...): " usuario; usuario="$(limpiar "$usuario")"; usuario="${usuario#USUARIO=}"
  [[ "$tenancy" =~ ^ocid1\.tenancy\.oc1\.\.[a-z0-9]+$ ]] || { echo "TENANCY no parece un OCID de tenancy." >&2; exit 1; }
  [[ "$usuario" =~ ^ocid1\.user\.oc1\.\.[a-z0-9]+$ ]] || { echo "USUARIO no parece un OCID de usuario." >&2; exit 1; }
  printf '[DEFAULT]\nuser=%s\nfingerprint=%s\ntenancy=%s\nregion=%s\nkey_file=/run/oci/key.pem\n' "$usuario" "$huella" "$tenancy" "$REGION" > "$DIR/config"
  chmod 644 "$DIR/config"
  echo "   configuracion guardada en $DIR/config"
else
  echo "   (la configuracion ya existe en $DIR/config: solo se prueba el acceso)"
fi

# Configuracion temporal para el CLI del servidor (apunta a la llave con su ruta real)
sed "s#/run/oci/key.pem#$DIR/key.pem#" "$DIR/config" > "$TMP/config"
oci_() { oci --config-file "$TMP/config" --profile DEFAULT "$@"; }

echo "== Paso 2: probando el acceso al bucket $BUCKET (una llave nueva puede tardar unos minutos en activarse)"
listo=""
for i in $(seq 1 12); do
  if oci_ os ns get >/dev/null 2>"$TMP/err.txt"; then listo=1; break; fi
  echo "   Oracle todavia no activa la llave (intento $i de 12); espero 30 segundos..."; sleep 30
done
[ -n "$listo" ] || { echo "No se pudo autenticar con la llave. Detalle:" >&2; tail -4 "$TMP/err.txt" | sed 's/^/   /' >&2; exit 1; }

obj="pruebas/ping-$(date +%s).txt"; openssl rand -hex 16 > "$TMP/ping.txt"
oci_ os object put --namespace-name "$NS" --bucket-name "$BUCKET" --name "$obj" --file "$TMP/ping.txt" --force >/dev/null 2>"$TMP/err.txt" \
  || { echo "svc-plaft NO puede escribir en $BUCKET. Detalle de Oracle:" >&2; grep -E '"(code|message|status)"' "$TMP/err.txt" | sed 's/^ */   /' >&2
       echo "   Si el codigo es NotAuthorizedOrNotFound: falta la politica del grupo de svc-plaft ('manage objects' y 'read buckets' sobre $BUCKET) o el bucket no existe con ese nombre." >&2; exit 1; }
oci_ os object get --namespace-name "$NS" --bucket-name "$BUCKET" --name "$obj" --file "$TMP/ping.out" >/dev/null 2>&1 || { echo "No pude leer el archivo de prueba." >&2; exit 1; }
cmp -s "$TMP/ping.txt" "$TMP/ping.out" && echo "   OK: subir y leer funcionan" || { echo "El archivo leido no coincide con el subido." >&2; exit 1; }
anonimo="$(curl -s -m 15 -o /dev/null -w '%{http_code}' "https://objectstorage.$REGION.oraclecloud.com/n/$NS/b/$BUCKET/o/$obj" || true)"
if [ "$anonimo" = 200 ]; then echo "ALERTA: el bucket entrega archivos SIN firma (publico). Hay que dejarlo privado." >&2; oci_ os object delete --namespace-name "$NS" --bucket-name "$BUCKET" --name "$obj" --force >/dev/null 2>&1 || true; exit 1; fi
echo "   OK: sin firma el bucket no entrega nada (HTTP $anonimo)"
oci_ os object delete --namespace-name "$NS" --bucket-name "$BUCKET" --name "$obj" --force >/dev/null 2>&1 && echo "   OK: borrar funciona"

echo
echo "Listo: svc-plaft puede guardar archivos en $BUCKET. La llave privada queda en $DIR/key.pem (solo este servidor)."
echo "Siguiente: sudo bash /data/apps/plaft/preparar.sh"
