# Auditoría de Visitas (plantilla «Authentication Work») en el servidor de Oracle

> Esta carpeta tiene lo necesario para correr Auditoría de Visitas en `sulotec-main` y dejar Render y Aiven.
> Es para administradores: aquí se tocan claves y el servidor.
> Primer cliente: **Caja Huancayo**. El producto es una plantilla multiempresa de Sulotec (cada empresa ve solo lo suyo; hay un
> administrador universal que entra a cada una), ver §1.3 del [contexto](../../CONTEXTO-PARA-OTRO-CHAT.md).

```
App Android / navegador ──▶ Cloudflare Tunnel ──▶ auditoria-web  (nginx, solo archivos estáticos del panel)
                                             └──▶ auditoria-api  (Node 24 + Socket.IO)
                                                      ├──▶ MySQL 8.4 de la VM (base "auditoria", red sulotec_data)
                                                      └──▶ Bucket huancayo-archivos (Object Storage, llave de svc-auditoria)
```

| Dirección | Va a |
|---|---|
| `https://auditoria.sulotec.com` | `http://auditoria-web:8080` |
| `https://api-auditoria.sulotec.com` | `http://auditoria-api:4100` (con WebSockets) |

El código está en `jeliases-informaDev/Huancayo-Backend` (API), `CajaHuancayo-Web` (panel) y `CajaHuancayo-App` (app Android).
El servidor **construye** las imágenes desde GitHub (`desplegar.sh`); las bases y las claves nunca van en el repositorio.

## Archivos

| Archivo | Para qué |
|---|---|
| `docker-compose.yml` | API y panel: solo lectura, sin privilegios, sin puertos publicados |
| `deploy/preparar.sh` | Crea `/opt/sulotec/auditoria.env` (claves y reglas; solo root y docker pueden leerlo) |
| `deploy/migrar-datos.sh` | Copia la base de Aiven a la MySQL de la VM y compara tabla por tabla (`SOLO_COMPARAR=1` solo compara) |
| `deploy/desplegar.sh` | Baja el código, construye, levanta y vuelve a la versión anterior si algo falla |
| `deploy/probar.sh` | Pruebas de humo: salud, bucket, direcciones públicas y CORS |
| `deploy/rotar-s3.sh` | Cambia la clave S3 de `svc-auditoria`, prueba el bucket y vuelve a la anterior si falla |

## Puesta en marcha (en este orden)

**1. Crear el usuario de servicio para las fotos (todavía no existe; el bucket `huancayo-archivos` sí).** Lo más fácil es en **Cloud Shell**
(consola de Oracle → ícono de terminal `>_` arriba a la derecha). Crea el grupo `grp-storage-auditoria`, el usuario `svc-auditoria` dentro,
y la política que lo limita a ese bucket:

```
cd ~ && cat > pol-auditoria.json <<'EOF'
["Allow group grp-storage-auditoria to manage objects in tenancy where target.bucket.name = 'huancayo-archivos'",
 "Allow group grp-storage-auditoria to read buckets in tenancy where target.bucket.name = 'huancayo-archivos'"]
EOF
GRP=$(oci iam group create --compartment-id "$OCI_TENANCY" --name grp-storage-auditoria --description "Fotos de Auditoria de Visitas: solo el bucket huancayo-archivos" --query data.id --raw-output)
USR=$(oci iam user create --compartment-id "$OCI_TENANCY" --name svc-auditoria --email svc-auditoria@sulotec.com --description "Usuario de servicio de Auditoria de Visitas (auditoria-api)" --query data.id --raw-output)
oci iam group add-user --group-id "$GRP" --user-id "$USR" >/dev/null
oci iam policy create --compartment-id "$OCI_TENANCY" --name pol-storage-auditoria --description "svc-auditoria solo toca el bucket huancayo-archivos" --statements file://pol-auditoria.json >/dev/null
rm -f pol-auditoria.json
oci iam group list-users --group-id "$GRP" --query 'data[].name'
```

Debe terminar mostrando `svc-auditoria` (Identity Domains exige un correo al crear el usuario; uno del dominio propio basta, no necesita buzón). Luego la clave S3 (el SECRETO se ve **una sola vez**: guárdalo en el gestor, nunca en un chat):

```
USR=$(oci iam user list --all --query "data[?name=='svc-auditoria'].id | [0]" --raw-output); oci iam customer-secret-key create --user-id "$USR" --display-name auditoria-api-1 --query 'data.{ACCESO:id,SECRETO:key}' --output table
```

Por consola, si prefieres: Identity & Security → Domains → Default → **Groups → Create group** (`grp-storage-auditoria`); **Users → Create user**
(`svc-auditoria`) y en el usuario, pestaña Groups → Add to group; Identity → **Policies** (compartimento raíz) → Create policy → *Show manual editor*
y pegar las dos líneas de arriba; por último, en el usuario, **Customer secret keys → Generate secret key**. Oracle tarda unos minutos en activar la
clave: si `probar.sh` falla en el bucket justo después de crearla, espera 2-3 minutos y repite.

**2. Copiar este kit al servidor** (desde `ssh.sulotec.com`):

```
sudo mkdir -p /data/apps/auditoria && sudo rm -rf /tmp/sulotec-infra && sudo git clone --depth 1 https://github.com/Sulotec/Sulotec-infra.git /tmp/sulotec-infra && sudo cp /tmp/sulotec-infra/apps/auditoria/docker-compose.yml /tmp/sulotec-infra/apps/auditoria/deploy/*.sh /data/apps/auditoria/ && sudo rm -rf /tmp/sulotec-infra && ls /data/apps/auditoria
```

**3. Crear la base** y guardar la cadena `Node` que muestra (la clave no se vuelve a ver):

```
sudo /opt/sulotec/scripts/new-project-db.sh mysql auditoria
```

**4. Configuración:** `sudo bash /data/apps/auditoria/preparar.sh`.
Pide la cadena de la base (y comprueba que entra), la `MFA_ENCRYPTION_KEY` **de Render** (debe ser la misma: si cambia, nadie podrá usar
su verificación en dos pasos), el nombre de la primera empresa, el administrador universal (opcional) y las claves de `svc-auditoria`.
Al decir que la base ya tiene datos, deja vacía la clave del administrador inicial a propósito: con un administrador existente que nunca
inició sesión, el arranque le **cambiaría la contraseña y le borraría la verificación en dos pasos**.

**5. Datos de la base actual (Aiven), antes de levantar la API:** `sudo bash /data/apps/auditoria/migrar-datos.sh`.
Pide la *Service URI* de Aiven (o la `DATABASE_URL` del servicio en Render). Saldrán asteriscos. Solo lee del origen, guarda el volcado en
`/data/backups/auditoria` y compara cada tabla. Trae también la tabla `_prisma_migrations`, así la API no vuelve a aplicar migraciones ya hechas.

**6. Fotos.** En Render (plan gratis, sin disco) las fotos se perdían en cada reinicio, así que **no hay archivos que copiar**: las evidencias
nuevas van directo al bucket con prefijo `empresa/<id>/…`. Si alguna visita de la demo apunta a una foto que ya no existe, el panel muestra
«no encontrada»; es lo mismo que pasaba en Render.

**7. Publicar:** `sudo bash /data/apps/auditoria/desplegar.sh` (construye desde `main`; para probar otra rama:
`RAMA_BACKEND=mi-rama RAMA_FRONTEND=mi-rama sudo -E bash /data/apps/auditoria/desplegar.sh`).

**8. Cloudflare.** Networks → Tunnels → `sulotec` → Public hostnames → Add, las dos direcciones de la tabla de arriba (no hay CNAME viejo
que borrar: Render usaba `onrender.com`).

**9. Comprobar:** `sudo bash /data/apps/auditoria/probar.sh`.

**10. App Android:** compilar con la dirección nueva. El workflow `Compilar APK (Android)` del repo `CajaHuancayo-App` ya trae
`https://api-auditoria.sulotec.com` por defecto (y `eas.json` para EAS). Desinstalar la app vieja del celular (apunta a Render) e instalar la nueva.

**11. Cerrar lo viejo,** solo cuando todo lo anterior esté en verde y la app nueva esté en los celulares: último respaldo de Aiven (queda en
`/data/backups/auditoria`), apagar Aiven y los dos servicios de Render, borrar sus claves del gestor, y en el portal poner `publicado: true` a
«Auditoría de Visitas» en `apps/portal/src/data/soluciones.ts`.

## Operación

| Qué | Cómo |
|---|---|
| Ver registros | `docker logs -f auditoria-api` |
| Versión publicada | `docker images auditoria-api` (la etiqueta es el commit) |
| Volver a una versión anterior | `docker tag auditoria-api:<commit> auditoria-api:latest && cd /data/apps/auditoria && docker compose up -d --force-recreate` |
| Cambiar una clave o una regla | `sudo bash /data/apps/auditoria/preparar.sh` (Enter conserva) y luego `desplegar.sh` |
| Comparar con Aiven antes de apagarlo | `SOLO_COMPARAR=1 sudo -E bash /data/apps/auditoria/migrar-datos.sh` |
| Respaldo | La base entra en el respaldo diario de la VM (`mysqldump`); el bucket tiene versionado y llave propia en Oracle |

## Rotar claves

| Clave | Cómo |
|---|---|
| Base de datos (`auditoria`) | `sudo /opt/sulotec/scripts/rotar-claves.sh`. Las genera en el servidor, no se imprimen, y comprueba que la nueva entra y la anterior ya no. |
| Clave S3 de `svc-auditoria` (cada 90 días o si se expone) | 1) Cloud Shell: `USR=$(oci iam user list --all --query "data[?name=='svc-auditoria'].id \| [0]" --raw-output); oci iam customer-secret-key create --user-id "$USR" --display-name auditoria-api-2 --query 'data.{ACCESO:id,SECRETO:key}' --output table` (Oracle permite 2 claves por usuario). 2) Servidor: `sudo bash /data/apps/auditoria/rotar-s3.sh` (pide ACCESO y SECRETO, prueba el bucket y vuelve a la anterior si falla). 3) Cloud Shell: borrar la clave anterior (el script imprime el comando exacto). |
| `MFA_ENCRYPTION_KEY` | **No rotar**: si cambia, nadie puede usar su verificación en dos pasos. Guardarla en el gestor de contraseñas. |
| `JWT_SECRET` | Se puede cambiar en `/opt/sulotec/auditoria.env` y `desplegar.sh`; cierra todas las sesiones abiertas (los auditores vuelven a entrar). |

## Reglas de seguridad de este producto

- La base y la API no publican puertos: todo entra por el túnel.
- Las fotos nunca son públicas: la app sube por la API con una clave firmada (15 minutos) y el panel las recibe por la API, con sesión;
  cada clave lleva el prefijo de su empresa y la API rechaza claves de otra empresa.
- Cada empresa (cliente) ve solo lo suyo: el filtro va en el servidor (Prisma), no en la web. El administrador universal elige empresa
  con la cabecera `X-Empresa-Id` y cada acción queda en la auditoría.
- `RESET_INITIAL_ADMIN` queda en `false`; solo se activa durante un despliegue de emergencia y se vuelve a apagar.
- `ENFORCE_DEVICE_BINDING=true` (un celular por cuenta de campo) no se puede apagar en producción.
- El ajuste de checksums del cliente S3 (`requestChecksumCalculation: WHEN_REQUIRED`) y `S3_FORCE_PATH_STYLE=true` son necesarios para Oracle; no quitarlos.
- La geocodificación externa (`GEOCODING_WORKER_ENABLED`) queda apagada salvo autorización del banco: manda direcciones de clientes a un proveedor externo.
