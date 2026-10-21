# Sistema de Planillas (Informa Peru): UNA imagen con la API (Spring Boot) y la pantalla (Angular) adentro.
# El contexto de construccion es /data/apps/planilla, donde desplegar.sh deja los dos repositorios:
#   backend/   -> PlanillaBackend (Spring Boot 3, Java 17, Maven)
#   frontend/  -> PlanillaFrontEd (Angular 21)
# La pantalla se compila y se copia a src/main/resources/static del backend, que la sirve en la misma direccion
# que la API (asi el navegador nunca habla con una API aparte y el WebSocket va por el mismo dominio).
# Todas las imagenes base existen para linux/arm64 (el servidor es ARM).

FROM node:22-bookworm-slim AS web
ENV NG_CLI_ANALYTICS=false CI=true
WORKDIR /web
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY frontend/ ./
RUN npx ng build --configuration production

FROM maven:3.9-eclipse-temurin-17 AS api
WORKDIR /src
COPY backend/pom.xml ./
RUN mvn -q -B dependency:go-offline || true
COPY backend/src ./src
RUN rm -rf src/main/resources/static && mkdir -p src/main/resources/static
COPY --from=web /web/dist/planilla-frontend/browser/ src/main/resources/static/
RUN mvn -q -B -DskipTests package

FROM eclipse-temurin:17-jre-jammy
# curl solo para el chequeo de salud del contenedor
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/* \
    && useradd -r -u 10001 appuser
WORKDIR /app
COPY --from=api /src/target/*.jar app.jar
USER appuser
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-Duser.timezone=America/Lima", "-Djava.security.egd=file:/dev/./urandom", "-jar", "app.jar"]
