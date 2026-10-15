#!/usr/bin/env bash
# Pasa a la base de PRODUCCION de PLAFT ('plaft') lo valioso de la copia de la base de desarrollo (aiven_security_db, que deja importar-dev.sh):
# usuarios con sus roles, personas y empresas con sus apariciones en listas, historial de consultas, matrices de riesgo y puntajes.
# Nada se pisa ni se borra: lo que ya existe en produccion se reconoce por su clave natural (usuario, correo, tipo + numero de documento,
# nombre de la lista...) y se deja como esta; lo que falta se agrega con identificadores nuevos y las relaciones se reconectan.
# SEGURO POR DEFECTO: sin --aplicar solo SIMULA (hace todo y lo deshace) y muestra que entraria. Con --aplicar respalda 'plaft' antes.
#   sudo bash /data/apps/plaft/pasar-dev-a-produccion.sh              simula
#   sudo bash /data/apps/plaft/pasar-dev-a-produccion.sh --aplicar    escribe
# Opciones (variables, con sudo -E):
#   CON_DENUNCIAS=1       tambien pasa las denuncias de prueba (apareceran como denuncias reales y sus archivos no estan en el bucket de produccion)
#   SIN_USUARIOS=1        no pasa cuentas de usuario
#   SIN_LISTAS_NUEVAS=1   no crea listas de desarrollo que no existan en produccion (sus apariciones se omiten)
#   SIN_PERSONAS=1        no pasa las personas/empresas, las listas ni el historial de consultas de desarrollo (solo cuentas, matrices, etc.)
#   OMITIR_USUARIOS=a,b   no pasa esas cuentas (por nombre de usuario, separadas por coma)
# Para pasar opciones sin depender de la configuracion de sudo:  sudo env SIN_PERSONAS=1 OMITIR_USUARIOS=admin001 bash <este script> [--aplicar]
# Las cuentas que usan una clave publica conocida (la de la semilla del repositorio, Admin12345!) NO se pasan: serian una puerta abierta.
# Variables solo para pruebas: SULOTEC_DIR, RESPALDOS, BASE_PROD, BASE_DEV, RED_DOCKER, PRUEBA.
set -euo pipefail
[ -n "${PRUEBA:-}" ] || export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
[ "$(id -u)" -eq 0 ] || [ -n "${PRUEBA:-}" ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }

SULOTEC="${SULOTEC_DIR:-/opt/sulotec}"
RESPALDOS="${RESPALDOS:-/var/backups/sulotec}"
PROD="${BASE_PROD:-plaft}"
DEV="${BASE_DEV:-aiven_security_db}"
RED="${RED_DOCKER:-sulotec_data}"
APLICAR=0
case "${1:-}" in
  "") ;;
  --aplicar) APLICAR=1 ;;
  *) echo "uso: sudo bash $0 [--aplicar]" >&2; exit 1 ;;
esac
export DEV PROD APLICAR

cd "$SULOTEC"
set -a; . ./.env; set +a
[ -n "${MYSQL_ROOT_PASSWORD:-}" ] || { echo "No encuentro MYSQL_ROOT_PASSWORD en $SULOTEC/.env" >&2; exit 1; }
sqlr() { docker compose exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysql -uroot -N "$@"; }
sqlr -e "select 1 from information_schema.schemata where schema_name='$DEV'" | grep -x 1 >/dev/null \
  || { echo "No existe la base $DEV: primero corre  sudo bash /data/apps/plaft/importar-dev.sh" >&2; exit 1; }
sqlr -e "select 1 from information_schema.schemata where schema_name='$PROD'" | grep -x 1 >/dev/null \
  || { echo "No existe la base $PROD." >&2; exit 1; }

TMP="$(mktemp -d)"; chmod 700 "$TMP"
trap '[ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"' EXIT

# ---- 1. Con --aplicar: respaldo primero (y se comprueba)
if [ "$APLICAR" = 1 ]; then
  echo "== Respaldo de la base '$PROD' antes de escribir"
  mkdir -p "$RESPALDOS"; chmod 700 "$RESPALDOS"
  copia="$RESPALDOS/${PROD}_antes-de-pasar-dev_$(date +%F_%H%M).sql.gz"
  if ! docker compose exec -T -e MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql mysqldump -uroot --single-transaction --no-tablespaces "$PROD" | gzip > "$copia"; then
    rm -f "$copia"; echo "No pude respaldar la base: no escribo nada." >&2; exit 1
  fi
  tablas="$(zcat "$copia" | grep -c '^CREATE TABLE' || true)"
  if ! [ "${tablas:-0}" -ge 5 ] 2>/dev/null; then rm -f "$copia"; echo "El respaldo salio incompleto (${tablas:-0} tablas): no escribo nada." >&2; exit 1; fi
  echo "   OK: $copia ($(du -h "$copia" | cut -f1), $tablas tablas)"
fi

# ---- 2. La herramienta (librerias de MySQL y bcrypt en una carpeta temporal; nada queda en el servidor)
mkdir "$TMP/pkgs"
echo "== Preparando la herramienta"
docker run --rm -v "$TMP/pkgs:/pkgs" python:3.12-slim \
  pip install -q --no-cache-dir --root-user-action=ignore --target /pkgs pymysql cryptography bcrypt >/dev/null \
  || { echo "No pude instalar las librerias (¿el servidor tiene salida a internet?)." >&2; exit 1; }

if [ "$APLICAR" = 1 ]; then echo "== Pasando datos (ESCRIBE en $PROD)"; else echo "== Simulacion (no escribe nada)"; fi
docker run --rm -i --network "$RED" -v "$TMP/pkgs:/pkgs:ro" -e PYTHONPATH=/pkgs -e PYTHONDONTWRITEBYTECODE=1 \
  -e MYSQL_ROOT_PASSWORD -e DEV -e PROD -e APLICAR -e CON_DENUNCIAS -e SIN_USUARIOS -e SIN_LISTAS_NUEVAS -e SIN_PERSONAS -e OMITIR_USUARIOS \
  python:3.12-slim python - <<'PYEOF' || { echo "La herramienta fallo (arriba esta el detalle). Todo va en una sola transaccion: no se guardo nada." >&2; exit 1; }
import os
import re
import sys
import unicodedata

import bcrypt
import pymysql

DEV = os.environ["DEV"]
PROD = os.environ["PROD"]
APLICAR = os.environ.get("APLICAR") == "1"
CON_DENUNCIAS = bool(os.environ.get("CON_DENUNCIAS"))
SIN_USUARIOS = bool(os.environ.get("SIN_USUARIOS"))
SIN_LISTAS_NUEVAS = bool(os.environ.get("SIN_LISTAS_NUEVAS"))
SIN_PERSONAS = bool(os.environ.get("SIN_PERSONAS"))
OMITIR_USUARIOS = {u.strip() for u in os.environ.get("OMITIR_USUARIOS", "").split(",") if u.strip()}
CLAVES_PUBLICAS = ["Admin12345!", "Admin12345", "admin", "admin123", "12345678", "password"]

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
con = pymysql.connect(host="mysql", user="root", password=os.environ["MYSQL_ROOT_PASSWORD"], charset="utf8mb4", autocommit=False)
cur = con.cursor()


def sin_tildes(t):
    return re.sub(r"\s+", " ", unicodedata.normalize("NFD", str(t)).encode("ascii", "ignore").decode()).strip().upper()


def consulta(sql, params=()):
    cur.execute(sql, params)
    return cur.fetchall()


def columnas(bd, tabla):
    return [r[0] for r in consulta(
        "select column_name from information_schema.columns where table_schema=%s and table_name=%s order by ordinal_position", (bd, tabla))]


def existe(bd, tabla):
    return bool(consulta("select 1 from information_schema.tables where table_schema=%s and table_name=%s", (bd, tabla)))


def pk_auto(bd, tabla):
    r = consulta("select column_name from information_schema.columns where table_schema=%s and table_name=%s "
                 "and column_key='PRI' and extra like %s", (bd, tabla, "%auto_increment%"))
    return r[0][0] if r else None


def claves_foraneas_detectadas(bd, tabla):
    return {c: ref for c, ref in consulta(
        "select column_name, referenced_table_name from information_schema.key_column_usage "
        "where table_schema=%s and table_name=%s and referenced_table_name is not null", (bd, tabla))}


# Relaciones conocidas por el codigo del backend (por si la copia no trae todas las claves foraneas): columna -> tabla a la que apunta
FK_CONOCIDAS = {
    "entidades": {"id_tipo_documento": "tipo_documento", "id_pais": "pais"},
    "personas_naturales": {"id_entidades": "entidades"},
    "personas_juridicas": {"id_entidades": "entidades"},
    "historial_manchas": {"id_entidades": "entidades", "id_tipo_lista": "tipo_lista"},
    "historial_consultas": {"id_usuarios": "usuarios", "id_entidad": "entidades"},
    "tipo_lista": {"id_grupo": "lista_grupo"},
    "usuario_roles": {"id_usuario": "usuarios", "id_rol": "roles"},
    "scoring_departamento": {"id_pais": "pais"},
    "scoring_riesgo": {"id_usuario": "usuarios", "id_entidad": "entidades", "id_ocupacion": "scoring_ocupacion", "id_departamento": "scoring_departamento"},
    "matriz_riesgo_areas": {"id_usuario": "usuarios"},
    "matriz_riesgo_procesos": {"id_usuario": "usuarios"},
    "matriz_riesgo_area_proceso": {"id_area": "matriz_riesgo_areas", "id_proceso": "matriz_riesgo_procesos", "id_usuario": "usuarios"},
    "matriz_riesgo_analisis": {"id_usuario": "usuarios", "area_id": "matriz_riesgo_areas", "proceso_id": "matriz_riesgo_procesos",
                               "control_area_id": "matriz_riesgo_areas"},
    "denuncias": {"receptor_usuario_id": "usuarios"},
    "denuncia_archivos": {"denuncia_id": "denuncias"},
    "denuncia_historial": {"denuncia_id": "denuncias", "id_usuario": "usuarios"},
    "denuncia_involucrados": {"denuncia_id": "denuncias"},
}

# (tabla, columnas de la clave natural con que se reconoce lo que ya existe; None = igualdad de todas las columnas)
GRUPOS = [
    ("referencias", [("pais", ["nombre"]), ("tipo_documento", ["nombre"]), ("roles", ["codigo"]),
                     ("scoring_ocupacion", ["nombre"]), ("scoring_departamento", ["id_pais", "nombre"])]),
    ("usuarios", [("usuarios", ["usuario"]), ("usuario_roles", ["id_usuario", "id_rol"])]),
    ("listas", [("lista_grupo", ["nombre"]), ("tipo_lista", ["nombre"])]),
    ("personas", [("entidades", ["id_tipo_documento", "documento"]), ("personas_naturales", ["id_entidades"]),
                  ("personas_juridicas", ["id_entidades"]), ("historial_manchas", None), ("historial_consultas", None)]),
    ("matrices", [("matriz_riesgo_areas", ["id_usuario", "nombre"]), ("matriz_riesgo_procesos", ["id_usuario", "nombre"]),
                  ("matriz_riesgo_area_proceso", ["id_area", "id_proceso"]), ("matriz_riesgo_analisis", None),
                  ("scoring_riesgo", None)]),
    ("denuncias", [("denuncias", ["codigo_seguimiento"]), ("denuncia_archivos", None), ("denuncia_historial", None),
                   ("denuncia_involucrados", None)]),
]
if SIN_USUARIOS:
    GRUPOS = [g for g in GRUPOS if g[0] != "usuarios"]
if not CON_DENUNCIAS:
    GRUPOS = [g for g in GRUPOS if g[0] != "denuncias"]
if SIN_PERSONAS:
    GRUPOS = [g for g in GRUPOS if g[0] not in ("listas", "personas")]

# tablas que se reconocen por su nombre sin importar tildes ni mayusculas
POR_NOMBRE = {"pais", "tipo_documento", "lista_grupo", "tipo_lista", "scoring_ocupacion"}

PK = {}
mapas = {}            # tabla -> {id en desarrollo: id en produccion}
resumen = []
avisos = []
usuarios_nuevos = []
usuarios_omitidos = []
listas_nuevas = []


def enmascarar(correo):
    usuario, _, dominio = (correo or "").partition("@")
    return f"{usuario[:2]}***@{dominio}" if dominio else "(sin correo)"


def buscar_existente(tabla, d, clave, cols):
    """(id, True) si la fila ya esta en produccion; (None, False) si falta."""
    if tabla in POR_NOMBRE:
        objetivo = sin_tildes(d.get("nombre") or "")
        extra = ", codigo" if tabla == "tipo_lista" else ""
        for fila in consulta(f"select id, nombre{extra} from `{PROD}`.`{tabla}`"):
            if objetivo and sin_tildes(fila[1] or "") == objetivo:
                return fila[0], True
            if tabla == "tipo_lista" and d.get("codigo") and fila[2] == d["codigo"]:
                return fila[0], True
        return None, False
    if tabla == "usuarios":
        r = consulta(f"select id from `{PROD}`.usuarios where usuario=%s or correo=%s", (d["usuario"], d["correo"]))
        return (r[0][0], True) if r else (None, False)
    busqueda = clave if clave else [c for c in cols if c != PK.get(tabla)]
    condicion = " and ".join(f"`{c}` <=> %s" for c in busqueda)
    sel = PK.get(tabla) or busqueda[0]
    r = consulta(f"select `{sel}` from `{PROD}`.`{tabla}` where {condicion} limit 1", [d[c] for c in busqueda])
    return (r[0][0], True) if r else (None, False)


def clave_debil(hash_guardado):
    h = (hash_guardado or "").encode()
    if not h.startswith(b"$2"):
        return None
    for candidata in CLAVES_PUBLICAS:
        try:
            if bcrypt.checkpw(candidata.encode(), h):
                return candidata
        except ValueError:
            return None
    return None


for grupo, tablas in GRUPOS:
    for tabla, clave in tablas:
        if not existe(DEV, tabla) or not existe(PROD, tabla):
            continue
        cols_prod = columnas(PROD, tabla)
        cols = [c for c in columnas(DEV, tabla) if c in cols_prod]
        PK[tabla] = pk_auto(PROD, tabla)
        fks = {**claves_foraneas_detectadas(DEV, tabla), **FK_CONOCIDAS.get(tabla, {})}
        mapas.setdefault(tabla, {})
        nuevas = ya = omitidas = 0
        for fila in consulta(f"select {', '.join('`' + c + '`' for c in cols)} from `{DEV}`.`{tabla}`"):
            d = dict(zip(cols, fila))
            id_dev = d.get(PK[tabla]) if PK[tabla] else None
            # 1) reconectar las relaciones con los identificadores de produccion
            motivo = None
            for col, ref in fks.items():
                if col in d and d[col] is not None:
                    nuevo = mapas.get(ref, {}).get(d[col])
                    if nuevo is None:
                        motivo = f"{col} -> {ref} sin equivalente en produccion"
                        break
                    d[col] = nuevo
            if motivo:
                omitidas += 1
                avisos.append(f"{tabla}: fila omitida ({motivo})")
                continue
            # 2) ya esta en produccion? entonces solo se anota su equivalencia
            existente, hay = buscar_existente(tabla, d, clave, cols)
            if hay:
                ya += 1
                if PK[tabla] and id_dev is not None:
                    mapas[tabla][id_dev] = existente
                continue
            # 3) cuentas omitidas a pedido, o con una clave publica conocida, no se pasan
            if tabla == "usuarios" and d["usuario"] in OMITIR_USUARIOS:
                omitidas += 1
                usuarios_omitidos.append((d["usuario"], "omitida a pedido (OMITIR_USUARIOS)"))
                continue
            if tabla == "usuarios":
                debil = clave_debil(d.get("clave"))
                if debil:
                    omitidas += 1
                    usuarios_omitidos.append((d["usuario"], "usa una clave publica conocida (la de la semilla del repositorio)"))
                    continue
            if tabla == "tipo_lista" and SIN_LISTAS_NUEVAS:
                omitidas += 1
                avisos.append(f"tipo_lista: '{d.get('nombre')}' no existe en produccion y se pidio no crearla")
                continue
            # 4) insertar con identificador nuevo
            ins = {c: v for c, v in d.items() if c != PK[tabla]}
            cur.execute(f"insert into `{PROD}`.`{tabla}` ({', '.join('`' + c + '`' for c in ins)}) values ({', '.join(['%s'] * len(ins))})",
                        list(ins.values()))
            nuevas += 1
            if PK[tabla] and id_dev is not None:
                mapas[tabla][id_dev] = cur.lastrowid
            if tabla == "usuarios":
                roles = consulta(f"select r.codigo from `{DEV}`.usuario_roles ur join `{DEV}`.roles r on r.id = ur.id_rol where ur.id_usuario=%s", (id_dev,))
                usuarios_nuevos.append((d["usuario"], enmascarar(d["correo"]), ", ".join(x[0] for x in roles), "activo" if d.get("activo") else "inactivo"))
            if tabla == "tipo_lista":
                listas_nuevas.append(d.get("nombre"))
        resumen.append((tabla, nuevas, ya, omitidas))

print(f"\n   {'tabla':<28} {'nuevas':>7} {'ya estaban':>11} {'omitidas':>9}")
for tabla, n, y, o in resumen:
    print(f"   {tabla:<28} {n:>7} {y:>11} {o:>9}")
if usuarios_nuevos:
    print("\n   Cuentas que entrarian (usuario | correo | roles | estado):")
    for u in usuarios_nuevos:
        print(f"      {u[0]} | {u[1]} | {u[2] or '(sin rol)'} | {u[3]}")
if usuarios_omitidos:
    print("\n   Cuentas NO pasadas:")
    for u, m in usuarios_omitidos:
        print(f"      {u}: {m}")
if listas_nuevas:
    print("\n   Listas de desarrollo que no existen en produccion (se crearian):")
    for n in listas_nuevas:
        print(f"      {n}")
for a in sorted(set(avisos))[:15]:
    print(f"   AVISO: {a}")
if not CON_DENUNCIAS and existe(DEV, "denuncias"):
    n = consulta(f"select count(*) from `{DEV}`.denuncias")[0][0]
    if n:
        print(f"\n   Las {n} denuncias de la base de desarrollo NO se pasan (parecen de prueba y sus archivos no estan en produccion). Siguen en la copia {DEV}.")
        print("   Si de verdad las quieres:  CON_DENUNCIAS=1 sudo -E bash <este script>")

if APLICAR:
    con.commit()
    print("\nAPLICADO: cambios guardados.")
else:
    con.rollback()
    print("\nSIMULACION: no se guardo nada.")
con.close()
PYEOF

echo
if [ "$APLICAR" = 1 ]; then
  echo "LISTO. Las cuentas que entraron conservan SUS claves de desarrollo: si alguna es debil, cambiala desde el sistema. La copia completa sigue en $DEV."
else
  echo "Eso fue una SIMULACION: no se escribio nada. Si el resumen se ve bien:  sudo bash $0 --aplicar"
fi
