#!/usr/bin/env bash
# Publica PLAFT (API y web): baja el codigo, construye las imagenes, las levanta y espera a que esten sanas.
# Si la version nueva no arranca, vuelve a la anterior. Se puede repetir las veces que haga falta:
#   sudo bash /data/apps/plaft/desplegar.sh
# La primera vez la API tarda mas (la compilacion de Kotlin tarda unos minutos). Si la base era nueva, despues del primer
# arranque sano se apaga sola la "semilla" (el usuario inicial) y se borra su clave del archivo de configuracion.
# Si existe /opt/sulotec/plaft-ml.env (preparar-ml.sh) tambien publica el servicio de IA (Security-MachineLearning).
# Variables opcionales: REPO_BACKEND, REPO_FRONTEND, REPO_ML, RAMA_BACKEND, RAMA_FRONTEND, RAMA_ML, URL_API_PUBLICA.
set -euo pipefail

REPO_BACKEND="${REPO_BACKEND:-https://github.com/jeliases-informaDev/Security-Backend.git}"
REPO_FRONTEND="${REPO_FRONTEND:-https://github.com/jeliases-informaDev/Security-FrontEnd.git}"
RAMA_BACKEND="${RAMA_BACKEND:-main}"
RAMA_FRONTEND="${RAMA_FRONTEND:-main}"
URL_API_PUBLICA="${URL_API_PUBLICA:-https://api-plaft.sulotec.com/api}"
APP="${APP:-/data/apps/plaft}"
ENVFILE="${ENVFILE:-/opt/sulotec/plaft.env}"
REPO_ML="${REPO_ML:-https://github.com/jeliases-informaDev/Security-MachineLearning.git}"
RAMA_ML="${RAMA_ML:-main}"
ENVML="${ENVML:-/opt/sulotec/plaft-ml.env}"

[ "$(id -u)" -eq 0 ] || { echo "Correlo con sudo: sudo bash $0" >&2; exit 1; }
[ -r "$ENVFILE" ] || { echo "Falta $ENVFILE: primero corre preparar.sh" >&2; exit 1; }
[ -f "$APP/docker-compose.yml" ] || { echo "Falta $APP/docker-compose.yml: primero se publica desde GitHub (apps/plaft)." >&2; exit 1; }
ML=0; IA=0; PERFIL=""
if [ -r "$ENVML" ]; then ML=1; PERFIL="--profile ml"; fi
# Con Indira activa (activar-indira.sh) tambien corre Ollama, el modelo de lenguaje local
if [ "$ML" = 1 ] && grep -q '^INDIRA_ENABLED=true' "$ENVML"; then IA=1; PERFIL="$PERFIL --profile ia"; fi
servicios="api web"; [ "$ML" = 1 ] && servicios="$servicios ml"

salud() { docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null || echo ninguno; }
espera_sano() { local c="$1" i; for i in $(seq 1 "${2:-120}"); do [ "$(salud "$c")" = healthy ] && return 0; sleep 3; done; return 1; }
poner() { local k="$1" v="$2" tmp; tmp="$(mktemp "$ENVFILE.XXXXXX")"; awk -v k="$k" -v v="$v" 'BEGIN{FS=OFS="="} $1==k {print k "=" v; next} {print}' "$ENVFILE" > "$tmp"; cat "$tmp" > "$ENVFILE"; rm -f "$tmp"; }

# Baja o actualiza un repositorio y devuelve el commit. $1 = carpeta, $2 = url, $3 = rama
bajar() {
  if [ -d "$1/.git" ]; then git -C "$1" fetch -q origin "$3"; else git clone -q "$2" "$1"; git -C "$1" fetch -q origin "$3"; fi
  git -C "$1" reset -q --hard "origin/$3"
  git -C "$1" rev-parse --short=12 HEAD
}

echo "== Codigo"
cb=$(bajar "$APP/backend"  "$REPO_BACKEND"  "$RAMA_BACKEND")
cf=$(bajar "$APP/frontend" "$REPO_FRONTEND" "$RAMA_FRONTEND")
echo "   backend $RAMA_BACKEND @ $cb   frontend $RAMA_FRONTEND @ $cf"
cm=""
if [ "$ML" = 1 ]; then
  cm=$(bajar "$APP/ml" "$REPO_ML" "$RAMA_ML")
  echo "   ia (ML) $RAMA_ML @ $cm"
  [ -f "$APP/ml/requirements.txt" ] || { echo "El repositorio del ML no tiene requirements.txt." >&2; exit 1; }
fi
[ -f "$APP/backend/build.gradle.kts" ] || { echo "El backend de esa rama no parece el proyecto Gradle esperado." >&2; exit 1; }
[ -f "$APP/frontend/Dockerfile" ] || { echo "El frontend de esa rama no tiene Dockerfile." >&2; exit 1; }

# El servidor es ARM y la imagen de ejecucion del repo (eclipse-temurin alpine) no existe para ARM: se usa una propia.
# La compilacion es la misma del repo; solo cambia la base de ejecucion (multi-arquitectura) y el usuario sin privilegios.
cat > "$APP/Dockerfile.api" <<'DOCKERFILE'
FROM eclipse-temurin:17-jdk AS build
WORKDIR /app
ENV GRADLE_OPTS="-Xmx1g"
COPY gradlew settings.gradle.kts build.gradle.kts ./
COPY gradle gradle
RUN sed -i 's/\r$//' gradlew && chmod +x gradlew
COPY src src
RUN --mount=type=cache,target=/root/.gradle \
    ./gradlew --no-daemon -Pkotlin.compiler.execution.strategy=in-process bootJar -x test \
    && cp "$(ls build/libs/*.jar | grep -v -- '-plain' | head -n 1)" /app/app.jar

FROM eclipse-temurin:17-jre
RUN groupadd --system app && useradd --system --gid app --no-create-home app
WORKDIR /app
COPY --from=build /app/app.jar app.jar
USER app
EXPOSE 8081
ENV JAVA_OPTS="-XX:MaxRAMPercentage=60"
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
DOCKERFILE

# Servicio de IA: misma imagen de Python del repo, pero con usuario sin privilegios (el repo corre como root)
if [ "$ML" = 1 ]; then
cat > "$APP/Dockerfile.ml" <<'DOCKERFILE'
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN groupadd --system app && useradd --system --gid app --no-create-home app
USER app
EXPOSE 8000
CMD ["sh", "-c", "alembic upgrade head && uvicorn main:app --host 0.0.0.0 --port 8000"]
DOCKERFILE
fi

echo "== Construyendo imagenes (la primera vez tarda varios minutos)"
docker build -q -f "$APP/Dockerfile.api" -t "plaft-api:$cb" "$APP/backend" >/dev/null
docker build -q --build-arg NEXT_PUBLIC_API_URL="$URL_API_PUBLICA" -t "plaft-web:$cf" "$APP/frontend" >/dev/null
if [ "$ML" = 1 ]; then docker build -q -f "$APP/Dockerfile.ml" -t "plaft-ml:$cm" "$APP/ml" >/dev/null; fi

anterior_api=$(docker image inspect -f '{{.Id}}' plaft-api:latest 2>/dev/null || true)
anterior_web=$(docker image inspect -f '{{.Id}}' plaft-web:latest 2>/dev/null || true)
docker tag "plaft-api:$cb" plaft-api:latest
docker tag "plaft-web:$cf" plaft-web:latest
anterior_ml=""
if [ "$ML" = 1 ]; then anterior_ml=$(docker image inspect -f '{{.Id}}' plaft-ml:latest 2>/dev/null || true); docker tag "plaft-ml:$cm" plaft-ml:latest; fi

echo "== Levantando"
(cd "$APP" && docker compose $PERFIL up -d --force-recreate $servicios)
# Ollama se levanta sin recrearlo: asi no se descarga de memoria el modelo en cada despliegue
if [ "$IA" = 1 ]; then (cd "$APP" && docker compose $PERFIL up -d ollama); fi

ok=1
for contenedor in plaft-api plaft-web; do
  if espera_sano "$contenedor" 120; then echo "   $contenedor: sano"; else echo "   $contenedor: NO arranco bien" >&2; ok=0; fi
done

if [ "$ok" -eq 0 ]; then
  echo "== La version nueva fallo. Ultimas lineas de la API:" >&2
  docker logs --tail 30 plaft-api >&2 || true
  if [ -n "$anterior_api" ] || [ -n "$anterior_web" ]; then
    echo "== Volviendo a la version anterior" >&2
    [ -n "$anterior_api" ] && docker tag "$anterior_api" plaft-api:latest
    [ -n "$anterior_web" ] && docker tag "$anterior_web" plaft-web:latest
    [ -n "$anterior_ml" ] && docker tag "$anterior_ml" plaft-ml:latest
    (cd "$APP" && docker compose $PERFIL up -d --force-recreate $servicios)
  fi
  exit 1
fi

# El servicio de IA es opcional: si falla, la API y la web (que ya estan sanas) se quedan como estan
final=0
if [ "$ML" = 1 ]; then
  echo "== Servicio de IA"
  if espera_sano plaft-ml 120; then
    echo "   plaft-ml: sano"
  else
    final=1
    echo "   plaft-ml: NO arranco bien. Ultimas lineas:" >&2
    docker logs --tail 30 plaft-ml >&2 || true
    if [ -n "$anterior_ml" ]; then
      echo "   Volviendo el servicio de IA a su version anterior (la API y la web quedan como estan)" >&2
      docker tag "$anterior_ml" plaft-ml:latest
      (cd "$APP" && docker compose $PERFIL up -d --force-recreate ml >/dev/null 2>&1) || true
    else
      echo "   No habia version anterior: se apaga el servicio de IA. PLAFT sigue funcionando sin el (esas pantallas dicen 'servicio no disponible')." >&2
      (cd "$APP" && docker compose $PERFIL rm -sf ml >/dev/null 2>&1) || true
    fi
  fi
fi

if [ "$IA" = 1 ]; then
  if espera_sano plaft-ollama 60; then echo "   plaft-ollama: sano (Indira activa)"; else final=1; echo "   plaft-ollama: NO esta sano: Indira no respondera. Revisa: docker logs plaft-ollama" >&2; fi
fi

# Primer arranque con base nueva: la semilla ya se aplico; se apaga y se borra la clave inicial del archivo
if grep -q '^APP_SEED_ENABLED=true' "$ENVFILE"; then
  echo "== Esperando a que la semilla termine (roles, catalogos y usuario superadmin)"
  dbpass="$(grep -E '^DB_PASSWORD=' "$ENVFILE" | head -1 | cut -d= -f2-)"
  usuarios=0
  for _ in $(seq 1 30); do
    usuarios="$(docker run --rm --network sulotec_data -e MYSQL_PWD="$dbpass" mysql:8.4 mysql -h mysql -uplaft -N -e 'select count(*) from usuarios' plaft 2>/dev/null || echo 0)"
    [ "${usuarios:-0}" -ge 1 ] 2>/dev/null && break
    sleep 3
  done
  if ! [ "${usuarios:-0}" -ge 1 ] 2>/dev/null; then
    echo "AVISO: no vi usuarios en la base despues de esperar: dejo la semilla encendida. Revisa: docker logs plaft-api" >&2
    echo "Listo (con aviso): PLAFT publicado (backend $cb, frontend $cf)."; exit "$final"
  fi
  echo "   usuarios creados: $usuarios. Apagando la semilla"
  poner APP_SEED_ENABLED false
  poner APP_SEED_ADMIN_PASSWORD ""
  (cd "$APP" && docker compose up -d --force-recreate api >/dev/null 2>&1)
  espera_sano plaft-api 120 || { echo "La API no volvio a arrancar tras apagar la semilla. Revisa: docker logs plaft-api" >&2; exit 1; }
  echo "   semilla apagada; la clave inicial ya no esta en $ENVFILE"
fi

# Conserva las 3 ultimas versiones de cada imagen por si hay que volver atras a mano
for img in plaft-api plaft-web plaft-ml; do
  docker images "$img" --format '{{.Tag}}' | grep -v '^latest$' | tail -n +4 | xargs -r -I{} docker rmi -f "$img:{}" >/dev/null 2>&1 || true
done
if [ "$final" -ne 0 ]; then
  echo "PLAFT quedo publicado (backend $cb, frontend $cf) pero SIN el servicio de IA: revisa las lineas de arriba." >&2
  exit 1
fi
echo "Listo: PLAFT publicado (backend $cb, frontend $cf${cm:+, IA $cm})."
echo "Siguiente: en Cloudflare crea las dos rutas del tunel (ver README) y corre: sudo bash /data/apps/plaft/probar.sh"
