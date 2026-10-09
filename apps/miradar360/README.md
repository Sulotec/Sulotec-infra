# MiRadar360 en el servidor de Sulotec

> **Estado: preparado, NO desplegado.** Unir este PR no construye ni levanta nada, y MiRadar360 sigue funcionando en Render
> como hasta ahora. Todo lo de aquí se ejecuta **a mano**, en este orden, y el cambio real se hace **después de que Google
> Play apruebe la app** (ver "Cuándo").

## Qué se mueve

| Pieza | Hoy (Render) | Después (servidor Oracle) |
|---|---|---|
| Panel web | `afacop-frontend` (sitio estático) | contenedor `miradar360-web` (nginx) → `miradar360.sulotec.com` |
| API | `afacop-backend` (Node) | contenedor `miradar360-api` → `api-miradar360.sulotec.com` |
| Base de datos | `afacop-postgres` (PostgreSQL 18) | contenedor `miradar360-db` (PostgreSQL 18, red interna, sin puertos) |
| Fotos y firmas | Backblaze B2 privado | **no cambia** (siguen en B2; no hay archivos que mover) |

```
Usuario → Cloudflare → Tunnel ─┬→ miradar360-web  (nginx)
                               └→ miradar360-api ──(red interna)──→ miradar360-db
                                         └──→ Backblaze B2 (evidencias)
```

La base es un contenedor **aparte** con PostgreSQL 18 (la de Render es la 18; la `postgres:16` compartida del servidor no
puede recibir bien una copia de una versión más nueva).

## Archivos

| Archivo | Para qué |
|---|---|
| `docker-compose.yml` | Los 3 contenedores y sus redes |
| `backend.Dockerfile` | Imagen de la API (Node 24 + Chromium para los PDF) |
| `web.Dockerfile` / `web.nginx.conf` | Imagen del panel web |
| `.env.example` | Plantilla de la configuración (los secretos NO están aquí) |
| `scripts/preparar.sh` | Crea `/opt/sulotec/miradar360.env` con la clave de la base ya generada |
| `scripts/desplegar.sh` | Baja el código, construye las imágenes y levanta todo |
| `scripts/migrar-bd.sh` | Copia la base de Render a la nueva (solo lee de Render) y compara cantidades |
| `../../.github/workflows/miradar360.yml` | Botón manual que copia estos archivos al servidor |

## Fase 1 — Ensayo (sin tráfico real, sin riesgo para producción)

Se puede hacer ya. Render sigue siendo la fuente de verdad.

1. **Copiar los archivos al servidor:** GitHub → Actions → *Copiar MiRadar360 al servidor* → *Run workflow*.
2. **Configuración:** en el servidor,
   `sudo bash /data/apps/miradar360/scripts/preparar.sh`, y luego pegar en `sudo nano /opt/sulotec/miradar360.env` los
   valores de las líneas `PEGAR_DESDE_RENDER` (Render → `afacop-backend` → Environment).
   **Copiar TAL CUAL** `MFA_ENCRYPTION_KEY` y `JWT_SECRET` (explicación en el encabezado de `.env.example`).
3. **Levantar:** `sudo bash /data/apps/miradar360/scripts/desplegar.sh`. Termina diciendo si la API quedó sana.
4. **Copiar la base:** `sudo bash /data/apps/miradar360/scripts/migrar-bd.sh` (pide la *External Database URL* de Render).
   Debe terminar con `Todo coincide.`
5. **Revisar:** `docker logs --tail 80 miradar360-api` sin errores; `docker compose --env-file /opt/sulotec/miradar360.env ps`
   con los 3 contenedores `healthy`/`running`.

`GEOCODING_WORKER_ENABLED` queda en `false` durante el ensayo para no duplicar el trabajo de Render.

## Cambio previo en el panel web (obligatorio antes del día del cambio)

Hoy el panel **siempre** usa `https://afacop-backend.onrender.com` en producción. Está escrito a propósito en
`src/app/providers/AuthContext.jsx` del repo `Afacop-FrontEnd` (`PRODUCTION_API_URL`, con `if (import.meta.env.PROD) return PRODUCTION_API_URL;`)
para que una variable vieja de Render no desvíe el login. Por eso `VITE_API_URL` no sirve y el panel construido en
el servidor seguiría hablando con Render.

Cambio mínimo y compatible (con el mismo comportamiento si la variable no existe), en un PR de `Afacop-FrontEnd`:

```js
const PRODUCTION_API_URL = import.meta.env.VITE_PROD_API_URL || "https://afacop-backend.onrender.com";
```

`web.Dockerfile` ya pasa `VITE_PROD_API_URL` al construir y `desplegar.sh` avisa si el panel no quedó apuntando a la API nueva.
Ese PR se puede unir antes del cambio sin efecto alguno: en Render la variable no existe y todo sigue igual.

## Fase 2 — Día del cambio

Antes de empezar, que se cumpla todo esto:

- [ ] Google Play ya aprobó la app (producción).
- [ ] El cambio previo del panel web (sección anterior) está unido y publicado.
- [ ] Ensayo de la Fase 1 hecho y repetido por segunda vez sin diferencias.
- [ ] La base `miradar360-db` está en el respaldo diario (`vm/scripts/backup.sh`; **hoy no está incluida**).
- [ ] Decididos los puntos de "Decisiones pendientes".
- [ ] Horario de poco uso y aviso a los asesores.

Pasos:

1. Render → `afacop-backend` → **Suspend** (para que nadie escriba datos nuevos mientras se copia).
2. `sudo bash /data/apps/miradar360/scripts/migrar-bd.sh` (copia final; debe decir `Todo coincide.`).
3. En `/opt/sulotec/miradar360.env`: `GEOCODING_WORKER_ENABLED=true`, y
   `cd /data/apps/miradar360 && docker compose --env-file /opt/sulotec/miradar360.env up -d --force-recreate api`.
4. Cloudflare → DNS: **borrar** el CNAME `miradar360` (apunta a Render).
5. Cloudflare Zero Trust → Networks → Tunnels → `sulotec` → *Public Hostname*: agregar
   `miradar360.sulotec.com → http://miradar360-web:80` y `api-miradar360.sulotec.com → http://miradar360-api:4000`.
6. Probar: iniciar sesión (con MFA), mapa, subir foto y firma, generar un PDF de admisión, y la app móvil.
7. Si algo falla **antes de que entren datos nuevos**: borrar las 2 rutas, volver a crear el CNAME
   `miradar360 → afacop-frontend.onrender.com` y *Resume* en Render. Si ya hubo datos nuevos, no volver sin antes
   copiar esos datos de vuelta.

## Decisiones pendientes (no las decide este PR)

1. **App móvil:** la URL de la API está dentro de la app (`afacop-backend.onrender.com`). Hay que sacar una versión
   (o actualización OTA, solo para versiones con `expo-updates`) que apunte a `https://api-miradar360.sulotec.com`.
   Mientras tanto Render tiene que seguir vivo para las versiones viejas, y esas versiones verían una base congelada.
2. **Política de privacidad:** la sirve la API (`/privacidad/radar360`) y la URL de Render ya está pegada en Play. La
   nueva API la servirá en `https://api-miradar360.sulotec.com/privacidad/radar360`; cambiarla en Play es un trámite aparte.
3. **Repositorios privados:** `desplegar.sh` clona los repos por HTTPS. Si pasan a privados, hace falta una llave de
   despliegue o token de solo lectura.
4. **Respaldo:** agregar `miradar360-db` a `vm/scripts/backup.sh` y hacer una prueba de restauración.
5. **Content-Security-Policy** del panel web: agregarla después del ensayo, midiendo que no rompa los mapas.

## Qué se probó y qué no (9-oct-2026)

Probado en una PC con Docker (Linux x86_64), con una base **de mentira** y sin tocar Render:

- Las dos imágenes se construyen (`backend.Dockerfile`, `web.Dockerfile`) y `docker compose config` valida el compose.
- La API arranca con PostgreSQL 18 vacío: aplica las 14 tablas de migraciones, crea el administrador inicial,
  responde `/health/live` y `/health/ready` con 200, corre como usuario `node` (sin privilegios) y con `cap_drop: ALL`.
- CORS: acepta `https://miradar360.sulotec.com` y rechaza un origen ajeno (403).
- Chromium arranca dentro de la imagen (lo usan los PDF de admisión).
- nginx: las rutas del panel vuelven a `index.html`, un archivo inexistente de `/assets/` da 404 y salen los encabezados de seguridad.
- Descubierto: el panel NO apunta a la API nueva (ver "Cambio previo en el panel web").

**No probado:** que corra en ARM (el servidor es ARM; las imágenes base `node:24-bookworm-slim` y `postgres:18` tienen versión
ARM, pero no se ejecutó), el `healthcheck` de la API dentro de compose, `migrar-bd.sh` con una base real y los PDF de
admisión de punta a punta. Para eso es el ensayo de la Fase 1: si algo falla, se corrige aquí antes del día del cambio.
