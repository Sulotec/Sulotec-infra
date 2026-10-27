#!/usr/bin/env bash
# Backup diario de todas las bases (PostgreSQL y MySQL) y de los archivos en /data/apps.
# - Copia local de los ultimos RETENCION_DIAS (por defecto 2) en /var/backups/sulotec (disco del sistema, separado de /data).
# - Copia fuera del servidor en el bucket sulotec-backups, con el permiso propio de la VM (sin llaves).
# Lo ejecuta cron como root a las 02:00 (hora de Lima): /etc/cron.d/sulotec-backup
# Ejecutarlo a mano:  sudo /opt/sulotec/scripts/backup.sh
# Solo limpiar imagenes de Docker (con vista previa):  sudo /opt/sulotec/scripts/backup.sh --solo-imagenes --simular
set -euo pipefail
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

cd /opt/sulotec
set -a; . ./.env; set +a

# --- Limpieza INTELIGENTE de imagenes propias de Docker (las que construyen los desplegar.sh) ---
# Conserva la imagen que corre y IMAGENES_ANTERIORES versiones anteriores por producto (por defecto 1, maximo 2); nunca toca
# lo que usa un contenedor, ni :latest, ni imagenes de terceros, ni lo creado en las ultimas 24 h. Detalle de las reglas abajo.
# Variables opcionales en /opt/sulotec/.env: IMAGENES_ANTERIORES, IMAGENES_EDAD_MINIMA_HORAS, IMAGENES_PROPIAS.
podar_imagenes() {
  command -v python3 >/dev/null 2>&1 || { echo "Imagenes propias: falta python3, no se limpian."; return 0; }
  python3 - "$@" <<'PY_IMAGENES'
import json, os, re, subprocess, sys
from datetime import datetime, timedelta, timezone

# Limpieza INTELIGENTE de imagenes propias de Docker. Reglas (pensadas para no borrar nada importante):
#  1. Solo toca la lista IMAGENES_PROPIAS (las que construyen los desplegar.sh). Las de terceros no se tocan.
#  2. NUNCA borra una imagen que use algun contenedor (corriendo o detenido) ni la etiquetada :latest.
#  3. De cada producto conserva, ademas de la que corre, IMAGENES_ANTERIORES versiones inmediatamente anteriores
#     (por defecto 1, maximo 2) para poder volver atras. Una imagen mas NUEVA que la que corre (una construccion que
#     fallo y se revirtio) no sirve de respaldo: se borra.
#  4. No borra nada creado en las ultimas IMAGENES_EDAD_MINIMA_HORAS (24): protege un despliegue en curso.
#  5. Usa "docker rmi" sin -f: si Docker ve la imagen en uso, se niega. Fallar es seguro.
# Con --simular solo muestra lo que haria.


def entero(nombre, defecto, minimo, maximo):
    v = os.environ.get(nombre, '').strip()
    return min(max(int(v), minimo), maximo) if v.isdigit() else defecto


SIMULAR = '--simular' in sys.argv[1:]
PROPIAS = set(os.environ.get(
    'IMAGENES_PROPIAS',
    'auditoria-api auditoria-web buscador-web dashboard-api dashboard-web miradar-api miradar-web plaft-api plaft-ml plaft-web planilla',
).split())
ANTERIORES = entero('IMAGENES_ANTERIORES', 1, 1, 2)
HORAS = entero('IMAGENES_EDAD_MINIMA_HORAS', 24, 0, 720)


def docker(*args):
    r = subprocess.run(('docker',) + args, capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def fecha(texto):
    texto = re.sub(r'(\.\d{6})\d+', r'\1', texto)
    return datetime.fromisoformat(texto.replace('Z', '+00:00'))


def gb(n):
    return f'{n / 1e9:.1f} GB'


def referencia_completa(ref):
    ultimo = ref.split('/')[-1]
    return ref if ':' in ultimo or '@' in ultimo else ref + ':latest'


# Imagenes que usa algun contenedor (corriendo o detenido), por ID y por referencia
rc, out, _ = docker('ps', '-aq')
cids = out.split() if rc == 0 else []
en_uso_ids, en_uso_refs = set(), set()
if cids:
    rc, out, _ = docker('inspect', '--format', '{{.Image}}|{{.Config.Image}}', *cids)
    for linea in out.splitlines():
        a, _, b = linea.partition('|')
        if a.strip():
            en_uso_ids.add(a.strip())
        if b.strip():
            en_uso_refs.add(referencia_completa(b.strip()))

rc, out, err = docker('images', '-q', '--no-trunc')
ids = sorted(set(out.split()))
if rc != 0:
    print('No pude leer las imagenes de Docker:', err.strip())
    sys.exit(1)
if not ids:
    print('Imagenes propias: no hay imagenes.')
    sys.exit(0)
rc, out, err = docker('image', 'inspect', *ids)
if rc != 0:
    print('No pude inspeccionar las imagenes:', err.strip())
    sys.exit(1)
imagenes = json.loads(out)

# repo -> {id: {creada, tags, bytes}}
por_repo = {}
sin_fecha = 0
for im in imagenes:
    for rt in im.get('RepoTags') or []:
        repo, _, _tag = rt.rpartition(':')
        if repo not in PROPIAS:
            continue
        # Sin fecha de creacion fiable no se puede saber si es mas nueva o mas vieja: NO SE TOCA nunca.
        try:
            creada = fecha(im['Created']) if im.get('Created') and not im['Created'].startswith('0001-01-01') else None
        except ValueError:
            creada = None
        if creada is None:
            sin_fecha += 1
            continue
        d = por_repo.setdefault(repo, {}).setdefault(
            im['Id'], {'creada': creada, 'tags': [], 'bytes': im.get('Size', 0)})
        d['tags'].append(rt)
        if rt in en_uso_refs:
            en_uso_ids.add(im['Id'])

ahora = datetime.now(timezone.utc)
limite_edad = ahora - timedelta(hours=HORAS)
plan = []          # (repo, id, accion, datos)
a_borrar = []      # (repo, id)
for repo in sorted(por_repo):
    imgs = por_repo[repo]
    protegidas = {i for i, d in imgs.items() if i in en_uso_ids or any(t.endswith(':latest') for t in d['tags'])}
    if not protegidas:  # producto sin contenedor ni :latest: se considera la mas nueva como la actual
        protegidas = {max(imgs, key=lambda i: imgs[i]['creada'])}
    ref = max(imgs[i]['creada'] for i in protegidas)
    anteriores = sorted((i for i in imgs if i not in protegidas and imgs[i]['creada'] < ref),
                        key=lambda i: imgs[i]['creada'], reverse=True)[:ANTERIORES]
    for i in sorted(imgs, key=lambda x: imgs[x]['creada'], reverse=True):
        if i in protegidas:
            accion = 'corre'
        elif i in anteriores:
            accion = 'anterior'
        elif imgs[i]['creada'] >= limite_edad:
            accion = 'reciente'
        else:
            accion = 'borra'
            a_borrar.append((repo, i))
        plan.append((repo, i, accion, imgs[i]))

etiquetas = {'corre': 'CONSERVA (corre)', 'anterior': 'CONSERVA (respaldo)', 'reciente': 'espera (menos de %dh)' % HORAS, 'borra': 'BORRA'}
if SIMULAR or a_borrar:
    print('== Imagenes propias: se conserva la que corre y %d anterior(es) por producto ==' % ANTERIORES)
    ultimo = None
    for repo, i, accion, d in plan:
        if repo != ultimo:
            print(repo)
            ultimo = repo
        print('   %-24s %s  %s  %s  %s' % (etiquetas[accion], i.replace('sha256:', '')[:12],
                                         d['creada'].astimezone().strftime('%Y-%m-%d %H:%M'), gb(d['bytes']),
                                         ', '.join(t.split(':', 1)[1] for t in d['tags'] if t.rsplit(':', 1)[0] == repo)))

borradas, liberados = 0, 0
for repo, i in a_borrar:
    d = por_repo[repo][i]
    if SIMULAR:
        borradas += 1
        liberados += d['bytes']
        continue
    ok = True
    for t in d['tags']:
        if t.rsplit(':', 1)[0] != repo:
            continue
        rc, _, err = docker('rmi', t)
        if rc != 0:
            ok = False
            print('   no se borro %s: %s' % (t, (err.strip().splitlines() or ['?'])[-1][:120]))
    if ok:
        borradas += 1
        liberados += d['bytes']

conservadas = sum(1 for _, _, a, _ in plan if a != 'borra')
verbo = 'se borrarian' if SIMULAR else 'borradas'
print('Imagenes propias: %s %d (%s); se conservan %d%s.' % (verbo, borradas, gb(liberados), conservadas, ' y %d sin fecha (no se tocan)' % sin_fecha if sin_fecha else ''))
PY_IMAGENES
}

# A mano:  sudo /opt/sulotec/scripts/backup.sh --solo-imagenes --simular   (solo muestra lo que borraria)
#          sudo /opt/sulotec/scripts/backup.sh --solo-imagenes             (borra de verdad, solo lo que muestra la simulacion)
if [ "${1:-}" = "--solo-imagenes" ]; then
  shift
  podar_imagenes "$@"
  exit 0
fi

dir=/var/backups/sulotec
ts="$(date +%F_%H%M)"
mkdir -p "$dir"; chmod 700 "$dir"

docker compose exec -T postgres pg_dumpall -U postgres | gzip > "$dir/postgres_$ts.sql.gz"
docker compose exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql \
  mysqldump -uroot --all-databases --single-transaction --routines --events --triggers \
  | gzip > "$dir/mysql_$ts.sql.gz"
# No se respalda lo que se vuelve a bajar: los clones de MiRadar salen de GitHub y el modelo de IA de PLAFT
# (apps/plaft/ollama, ~9 GB, no se comprime) se baja con: sudo bash /data/apps/plaft/activar-indira.sh
# Incluirlo llenó el disco el 2026-10-27 (8,9 GB por noche durante 14 noches = 102 GB).
tar -czf "$dir/apps_$ts.tar.gz" --exclude='apps/miradar/backend' --exclude='apps/miradar/frontend' --exclude='apps/plaft/ollama' -C /data apps

# Cuantos respaldos diarios se guardan EN EL SERVIDOR, contando el de hoy. Decision del usuario (2026-10-27): 2, hoy y el anterior.
# Para guardar mas, poner RETENCION_DIAS=7 en /opt/sulotec/.env. La copia del bucket tiene su propia regla de ciclo de vida
# (vm/ciclo-de-vida-backups.json) y se cambia aparte.
retencion="${RETENCION_DIAS:-2}"
[[ "$retencion" =~ ^[0-9]+$ ]] && [ "$retencion" -ge 1 ] || retencion=2
find "$dir" -type f -mtime +$((retencion - 1)) -delete

for f in "$dir"/*_"$ts".*; do
  oci os object put --auth instance_principal --bucket-name "${BACKUP_BUCKET:-sulotec-backups}" \
    --file "$f" --name "$(date +%Y/%m)/$(basename "$f")" --force >/dev/null
done
# Mantenimiento del disco: cada despliegue deja cache de construccion de Docker (llego a 19 GB en 12 dias).
# Se borra la de mas de 3 dias y las imagenes sin etiqueta; no toca imagenes con nombre ni volumenes.
docker builder prune -f --filter 'until=72h' >/dev/null 2>&1 || true
docker image prune -f >/dev/null 2>&1 || true
podar_imagenes 2>&1 || true
uso="$(df --output=pcent / | tail -1 | tr -dc '0-9')"
[ "${uso:-0}" -lt 80 ] || echo "$(date -Is) ALERTA: el disco esta al ${uso}%. Ver /var/backups/sulotec y: sudo docker system df"

echo "$(date -Is) backup OK y subido a ${BACKUP_BUCKET:-sulotec-backups}: $(cd "$dir" && ls *_"$ts".* | tr '\n' ' ') | disco al ${uso:-?}%"
