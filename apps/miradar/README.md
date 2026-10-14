# MiRadar 360 (antes AFACOP) en el servidor de Oracle

> Esta carpeta tiene lo necesario para correr MiRadar en `sulotec-main` y dejar Aiven, Render y Backblaze.
> Es para administradores: aquí se tocan claves y el servidor.

```
App móvil / navegador ──▶ Cloudflare Tunnel ──▶ miradar-web  (nginx, solo archivos estáticos)
                                           └──▶ miradar-api  (Node + Socket.IO)
                                                    ├──▶ PostgreSQL de la VM (base "miradar", red sulotec_data)
                                                    └──▶ Bucket miradar-archivos (Object Storage, llave key-miradar)
```

| Dirección | Va a |
|---|---|
| `https://miradar360.sulotec.com` | `http://miradar-web:8080` |
| `https://api-miradar360.sulotec.com` | `http://miradar-api:4000` (con WebSockets) |

El código está en `jeliases-informaDev/Afacop-Backend`, `Afacop-FrontEnd` y `App-Afacop`. El servidor **construye** las imágenes
desde GitHub (`desplegar.sh`); las bases y las claves nunca van en el repositorio.

## Archivos

| Archivo | Para qué |
|---|---|
| `docker-compose.yml` | API y web: solo lectura, sin privilegios, sin puertos publicados |
| `deploy/preparar.sh` | Crea `/opt/sulotec/miradar.env` (claves; solo root y docker pueden leerlo) |
| `deploy/migrar-datos.sh` | Copia la base de Aiven a la PostgreSQL de la VM y compara tabla por tabla |
| `deploy/migrar-archivos.sh` | Copia fotos y firmas de Backblaze B2 al bucket de Oracle, con las mismas rutas |
| `deploy/desplegar.sh` | Baja el código, construye, levanta y vuelve a la versión anterior si algo falla |
| `deploy/probar.sh` | Pruebas de humo: salud, almacenamiento, direcciones públicas y CORS |

## Puesta en marcha (en este orden)

**1. Usuario de servicio para los archivos (consola de Oracle o Cloud Shell).**
En Domains → Default: grupo `grp-storage-miradar` (vacío), usuario `svc-miradar` dentro de ese grupo, y en su pestaña
**Customer secret keys → Generate secret key** (el secreto se ve una sola vez; guárdalo en el gestor). Política:

```
Allow group grp-storage-miradar to manage objects in tenancy where target.bucket.name = 'miradar-archivos'
Allow group grp-storage-miradar to read buckets in tenancy where target.bucket.name = 'miradar-archivos'
```

**2. Copiar este kit al servidor** (desde `ssh.sulotec.com`):

```bash
sudo mkdir -p /data/apps/miradar
sudo git clone --depth 1 https://github.com/Sulotec/Sulotec-infra.git /tmp/sulotec-infra
sudo cp /tmp/sulotec-infra/apps/miradar/docker-compose.yml /tmp/sulotec-infra/apps/miradar/deploy/*.sh /data/apps/miradar/
sudo rm -rf /tmp/sulotec-infra
```

**3. Crear la base** y guardar la cadena que muestra (la clave no se vuelve a ver):

```bash
sudo /opt/sulotec/scripts/new-project-db.sh postgres miradar
```

**4. Configuración:** `sudo bash /data/apps/miradar/preparar.sh`.
Pide la cadena de la base, la `MFA_ENCRYPTION_KEY` **de Render** (debe ser la misma: si cambia, nadie podrá usar su verificación en dos pasos),
y las claves de `svc-miradar`. Al decir que la base ya tiene datos, deja vacía la clave del administrador inicial a propósito:
con un administrador existente que nunca inició sesión, el arranque le **cambiaría la contraseña y le borraría la verificación en dos pasos**.

**5. Datos de la base actual, Render o Aiven (antes de levantar la API):** `sudo bash /data/apps/miradar/migrar-datos.sh`.
Pide la direccion **externa** de la base (en Render: la base PostgreSQL -> Connections -> *External Database URL*; en Aiven: *Service URI*; la interna de Render no sirve desde fuera). Saldran asteriscos. Solo lee del origen, guarda el volcado en `/data/backups/miradar` y compara cada tabla.
Si el origen es de una versión de PostgreSQL más nueva que la de la VM (16), se detiene y lo explica.

**6. Archivos de Backblaze:** `sudo bash /data/apps/miradar/migrar-archivos.sh` (repetible: copia solo lo que falte).

**7. Publicar:** `sudo bash /data/apps/miradar/desplegar.sh`.
Mientras los cambios de Docker no estén unidos a `main`, usar las ramas:
`RAMA_BACKEND=feat/oracle-docker RAMA_FRONTEND=feat/oracle-docker sudo -E bash /data/apps/miradar/desplegar.sh`.

**8. Cloudflare.** En DNS, **borrar el CNAME `miradar360` que apunta a Render**. Luego en Networks → Tunnels → `sulotec` → Add route,
las dos direcciones de la tabla de arriba.

**9. Comprobar:** `sudo bash /data/apps/miradar/probar.sh`.

**10. App móvil:** compilar con la dirección nueva (ya está en `eas.json`) y publicar. Actualizar en Play Console la URL de la política de privacidad:
`https://api-miradar360.sulotec.com/privacidad/radar360`.

**11. Cerrar lo viejo,** solo cuando todo lo anterior esté en verde: último respaldo de Aiven (queda en `/data/backups/miradar`),
apagar Aiven, Render y el bucket de Backblaze, y borrar sus claves.

## Operación

| Qué | Cómo |
|---|---|
| Ver registros | `docker logs -f miradar-api` |
| Versión publicada | `docker images miradar-api` (la etiqueta es el commit) |
| Volver a una versión anterior | `docker tag miradar-api:<commit> miradar-api:latest && cd /data/apps/miradar && docker compose up -d --force-recreate` |
| Cambiar una clave | `sudo bash /data/apps/miradar/preparar.sh` (Enter conserva) y luego `desplegar.sh` |
| Respaldo | La base entra en el respaldo diario de la VM (`pg_dumpall`); los archivos tienen versionado y llave propia en Oracle |

## Reglas de seguridad de este producto

- La base y la API no publican puertos: todo entra por el túnel.
- Las fotos y firmas nunca son públicas: la app sube con una URL firmada de 5 minutos y la API entrega URLs firmadas de 10 minutos.
- `RESET_INITIAL_ADMIN` queda en `false`; solo se activa durante un despliegue de emergencia y se vuelve a apagar.
- El ajuste de checksums del cliente S3 (`requestChecksumCalculation: WHEN_REQUIRED`) es necesario para Oracle; no quitarlo.
