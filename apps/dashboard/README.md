# Dashboard Empresarial (Informa Perú) en el servidor de Oracle

> Esta carpeta tiene lo necesario para correr **Dashboard Empresarial** en `sulotec-main` (Oracle Cloud, detrás de Cloudflare) y dejar atrás el SQL Server de la oficina.
> Es para administradores: aquí se tocan claves y el servidor.
> Qué es: portal donde las empresas clientes de Informa Perú ven sus dashboards de Power BI por periodo (mes). Un administrador de Informa asigna dashboards a cada empresa; cada usuario de empresa ve solo lo suyo.

```
Navegador ──▶ Cloudflare Tunnel ──▶ dashboard-web  (Next.js 16, puerto 3000)
                                └──▶ dashboard-api  (NestJS 12, puerto 3100)
                                         └──▶ PostgreSQL 16 de la VM (base "dashboard", red sulotec_data)
```

| Dirección | Va a |
|---|---|
| `https://dashboards.sulotec.com` | `http://dashboard-web:3000` |
| `https://api-dashboards.sulotec.com` | `http://dashboard-api:3100` |

El código está en `Henry-InformaPeru/dashboard-empresarial-backend` y `dashboard-empresarial-frontend`. El servidor **construye** las imágenes desde GitHub (`desplegar.sh`); las bases y las claves nunca van en el repositorio.

## Por qué PostgreSQL y no SQL Server

El servidor de Oracle es ARM y **SQL Server no corre en ARM**. El backend se pasó a PostgreSQL (rama `feature/oracle-postgres`): mismas tablas, mismos nombres de esquemas, tablas y columnas, y los mismos ids. Los usuarios entran con **las mismas claves de siempre** (se copia la clave cifrada con bcrypt, que sirve igual). El esquema vive en `db/schema.sql` del repositorio del backend.

Una diferencia a propósito: SQL Server no distinguía mayúsculas en el nombre de usuario (`Admin` = `admin`); la API y el índice único de PostgreSQL tampoco las distinguen, así nadie se queda fuera.

## Archivos

| Archivo | Para qué |
|---|---|
| `docker-compose.yml` | API y web: solo lectura, sin privilegios, sin puertos publicados |
| `herramientas/exportar-sqlserver.ps1` | **Se corre en Windows (la oficina).** Lee SQL Server (solo `SELECT`) y genera un `.sql` con todos los datos para PostgreSQL |
| `deploy/instalar.sh` | Atajo: revisa el servidor y hace de una vez copiar kit, crear base, configurar, publicar y crear tablas vacías (`revisar` solo mira) |
| `deploy/preparar.sh` | Crea `/opt/sulotec/dashboard.env` (base, clave de sesiones, web permitida) |
| `deploy/desplegar.sh` | Baja el código, construye, **aplica el esquema de la base** (solo agrega lo que falta; si falla, no publica nada), levanta y vuelve a la versión anterior si algo falla |
| `deploy/importar-datos.sh` | Crea las tablas y carga el `.sql` en **una sola transacción**; comprueba fila por fila los totales |
| `deploy/crear-admin.sh` | Crea (o da clave nueva a) un administrador general; clave aleatoria que se ve **una sola vez** |
| `deploy/probar.sh` | Pruebas de humo: contenedores, base, login, direcciones públicas y CORS |

## Puesta en marcha (en este orden)

**0. Unir los dos Pull Requests** en GitHub (backend: `feature/oracle-postgres`, web: `feature/oracle-docker`). Mientras no estén en `main`, `desplegar.sh` puede probar las ramas con `RAMA_BACKEND=feature/oracle-postgres RAMA_FRONTEND=feature/oracle-docker sudo -E bash /data/apps/dashboard/desplegar.sh`.

**1. Exportar los datos reales (en la oficina, en una PC o servidor Windows que llegue al SQL Server).** Abre **Windows PowerShell** (el que trae Windows, no PowerShell 7) y pega:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/Sulotec/Sulotec-infra/main/apps/dashboard/herramientas/exportar-sqlserver.ps1 -OutFile exportar-sqlserver.ps1
powershell -ExecutionPolicy Bypass -File .\exportar-sqlserver.ps1
```

Pregunta el servidor, la base y cómo entrar (Enter = con tu cuenta de Windows; o un usuario de SQL Server, con la clave oculta). **Solo lee.** Antes de escribir el archivo muestra todas las tablas de la base y avisa:

- qué tablas **no** se copian porque el sistema no las usa;
- si alguna tabla tiene columnas que el sistema no usa (no se copian);
- si hay datos raros (usuarios repetidos, asignaciones sin empresa, roles distintos de 1 y 2…). Los repetidos impedirían la carga: si salen, avísame antes de seguir.

Al terminar deja `dashboard-datos-AAAAMMDD-HHMM.sql` y su huella **SHA256**. Ese archivo **contiene correos, nombres y claves cifradas**: es sensible.

**2. Subir el archivo al bucket privado de Oracle.** Consola de Oracle → *Storage → Buckets → `sulotec-backups` → Upload* y, en **Prefix**, escribe `externos/dashboard/`. Sube el `.sql`. Después bórralo de la PC.

**3. En el servidor** (https://ssh.sulotec.com). **Atajo:** `instalar.sh` hace todo el resto de este paso (copiar el kit, crear la base, configurar, publicar y crear las tablas vacías) sin preguntas y sin mostrar ninguna clave. Primero solo mira el servidor:

```
cd /tmp && sudo rm -rf si && git clone -q --depth 1 https://github.com/Sulotec/Sulotec-infra.git si && sudo bash si/apps/dashboard/deploy/instalar.sh revisar
```

y luego instala con `sudo bash si/apps/dashboard/deploy/instalar.sh`. Lo que sigue es lo mismo, paso a paso y a mano. Copiar el kit:

```
sudo mkdir -p /data/apps/dashboard && sudo rm -rf /tmp/sulotec-infra && sudo git clone --depth 1 https://github.com/Sulotec/Sulotec-infra.git /tmp/sulotec-infra && sudo cp /tmp/sulotec-infra/apps/dashboard/docker-compose.yml /tmp/sulotec-infra/apps/dashboard/deploy/*.sh /data/apps/dashboard/ && sudo rm -rf /tmp/sulotec-infra && ls /data/apps/dashboard
```

Crear la base y **guardar la cadena `Node`** que muestra (la clave no se vuelve a ver; va al gestor de contraseñas):

```
sudo /opt/sulotec/scripts/new-project-db.sh postgres dashboard
```

Configuración (pide la cadena de arriba y la dirección de la web; la clave de sesiones la genera sola):

```
sudo bash /data/apps/dashboard/preparar.sh
```

Publicar (construye API y web; la primera vez tarda unos minutos):

```
sudo bash /data/apps/dashboard/desplegar.sh
```

Cargar los datos reales (toma el `.sql` más nuevo del bucket; con `SHA256=<huella>` exige que sea el mismo archivo que exportaste):

```
SHA256=PEGA_AQUI_LA_HUELLA sudo -E bash /data/apps/dashboard/importar-datos.sh
```

Si algo no cuadra (una sola fila de más o de menos), **no queda nada cargado**. Si la base ya tenía datos, el script se niega y no toca nada. Para cargar de nuevo todo (ojo: borra también las cuentas creadas aquí, como el administrador) usa `REEMPLAZAR=1 sudo -E bash /data/apps/dashboard/importar-datos.sh`; antes guarda un respaldo en `/data/backups/dashboard/`.

Crear el administrador general para revisar (la clave sale **una vez** en pantalla: cópiala al gestor y luego escribe `clear`):

```
sudo bash /data/apps/dashboard/crear-admin.sh
```

**4. Cloudflare.** Cloudflare One → *Networks → Tunnels* → `sulotec` → *Public hostnames* → *Add a public hostname*, dos veces (Cloudflare crea el DNS solo):

| Subdominio | Dominio | Tipo | URL |
|---|---|---|---|
| `dashboards` | `sulotec.com` | HTTP | `dashboard-web:3000` |
| `api-dashboards` | `sulotec.com` | HTTP | `dashboard-api:3100` |

**5. Comprobar:**

```
sudo bash /data/apps/dashboard/probar.sh
```

**6. Entrar** en `https://dashboards.sulotec.com` con el administrador del paso 3 y revisar. Las cuentas de siempre entran con sus claves de siempre.

**7. Recomendado:** en Cloudflare → *Security → WAF → Rate limiting rules*, una regla para `api-dashboards.sulotec.com/auth/login` (por ejemplo 10 intentos por minuto por IP): el login de la API no limita intentos por sí solo.

**8. Cierre** (cuando todo esté probado y la gente ya use la dirección nueva): último respaldo del SQL Server de la oficina, apagar lo viejo, y borrar el `.sql` del bucket (`sulotec-backups/externos/dashboard/`).

## Operación

| Qué | Cómo |
|---|---|
| Ver registros | `docker logs -f dashboard-api` · `docker logs -f dashboard-web` |
| Versión publicada | `docker images dashboard-api` (la etiqueta es el commit) |
| Volver a una versión anterior | `docker tag dashboard-api:<commit> dashboard-api:latest && cd /data/apps/dashboard && docker compose up -d --force-recreate` (igual con `dashboard-web`) |
| Cambiar la dirección de la API | Hay que reconstruir la web (`desplegar.sh`): `NEXT_PUBLIC_API_URL` se incrusta al compilar |
| Cambiar una clave o la web permitida | `sudo bash /data/apps/dashboard/preparar.sh` y luego `desplegar.sh` |
| Recuperar el acceso del administrador | `sudo bash /data/apps/dashboard/crear-admin.sh admin.sulotec --resetear` |
| Respaldo | La base `dashboard` entra en el respaldo diario de la VM (`pg_dumpall`) |

## Cómo se trabaja: el reporte de cada empresa

Cada empresa tiene su reporte de Power BI (por ejemplo «Huancayo», o «Portfolio» de Qapaq); al registrar la empresa el portal le crea su dashboard. El vínculo de Power BI **es del reporte, no del mes**, y los periodos son **opcionales**: sirven para dar la descarga de MEGA de cada mes. Es la misma lógica del login anterior de Informa.

1. En Power BI, quien publica el reporte abre **Publicar en la web → Código para insertar** y copia el **«HTML para pegar en un sitio web»** (empieza con `<iframe …>`; también sirve el «Vínculo»).
2. El administrador entra a `dashboards.sulotec.com` → **Gestión de Empresas** → la empresa → **Periodos y Enlaces** y pega ese HTML en «Vínculo de Power BI del reporte». La pantalla muestra el vínculo detectado y el nombre del reporte; se guarda **solo el vínculo**, nunca el HTML. El cliente ya ve su reporte, aunque no haya ningún periodo. Para cambiarlo (por ejemplo si se vuelve a publicar el reporte) está «Cambiar vínculo»: lo cambia en todos los periodos y no toca las descargas.
3. Opcional, cada mes: en «Periodos y descargas» escribe el periodo (la pantalla propone el mes siguiente) y pega el vínculo de **MEGA** del mes. Solo eso: ya no se vuelve a pegar el de Power BI.
4. El cliente entra con su cuenta y ve el reporte; si hay periodos aparecen el desplegable de periodo y el botón **Descargar**, que abre el vínculo de MEGA en otra pestaña.

Se rechaza, con un mensaje claro: dos reportes distintos en el mismo texto, un vínculo que no sea `https` de Power BI, el vínculo de MEGA en el campo de Power BI y el de Power BI en el campo de la descarga.

Por la API, un periodo puede llevar un vínculo de Power BI propio si ese mes usa otro reporte (la pantalla no lo ofrece). Los periodos cargados antes de este cambio conservan su vínculo propio: no se pierde nada.

**Base de datos:** `db/schema.sql` del backend agrega la columna `Dashboards.url_powerbi` y rellena los reportes con el vínculo de su periodo más reciente. `desplegar.sh` lo aplica solo antes de levantar la versión nueva (se puede repetir). Si cambia `desplegar.sh`, hay que copiar el kit de nuevo al servidor con el comando de «Copiar el kit» (paso 3, arriba).

**Los vínculos de «Publicar en la web» son públicos:** cualquiera que los tenga ve el reporte sin pasar por el portal. No van en repositorios, documentos ni chats; si se exponen, se borra el código en Power BI («Administrar códigos para insertar»), se vuelve a publicar y se pega el nuevo con «Cambiar vínculo».

## Rotar claves

| Clave | Cómo |
|---|---|
| Base de datos (`dashboard`) | Manual (el script `rotar-claves.sh` todavía no conoce este proyecto): ver abajo |
| `JWT_SECRET` | Se puede cambiar en `/opt/sulotec/dashboard.env` y correr `desplegar.sh`; cierra todas las sesiones abiertas |

**Rotar la clave de la base** (genera la clave nueva, la cambia en PostgreSQL y muestra la cadena nueva: guárdala en el gestor):

```
cd /opt/sulotec && NUEVA="$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 28)" && echo "ALTER ROLE dashboard PASSWORD '$NUEVA';" | sudo docker compose exec -T postgres psql -U postgres -v ON_ERROR_STOP=1 && echo "postgresql://dashboard:$NUEVA@postgres:5432/dashboard"
```

Luego pega esa cadena en `sudo bash /data/apps/dashboard/preparar.sh`, aplica con `cd /data/apps/dashboard && sudo docker compose up -d --force-recreate api` y comprueba con `sudo bash /data/apps/dashboard/probar.sh`.

## Reglas de seguridad de este producto

- La base y la API no publican puertos: todo entra por el túnel de Cloudflare.
- La API solo acepta llamadas desde `https://dashboards.sulotec.com` (CORS).
- Cada usuario de empresa ve solo los dashboards **asignados y activos** de **su** empresa; la empresa sale del token firmado por el servidor, nunca de lo que mande la web.
- Las claves de los usuarios se guardan con bcrypt (costo 12); la API nunca las devuelve.
- El administrador creado con `crear-admin.sh` tiene clave aleatoria de 20 caracteres que no queda guardada en el servidor.
- Los enlaces de Power BI/MEGA se ven en la web de quien tiene el dashboard asignado (así funciona el producto): quien los copie podría compartirlos. Si Power BI está en modo «publicar en la web», cualquiera con el enlace lo ve; conviene revisarlo.
