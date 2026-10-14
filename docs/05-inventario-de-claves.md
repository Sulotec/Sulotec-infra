# Inventario de claves y secretos

Qué secretos tiene la plataforma, dónde viven, cómo recuperarlos y cómo rotarlos. **Aquí no hay ningún valor**: solo nombres y lugares
(control ISO 27001 5.17). Los valores viven en el servidor (`/opt/sulotec/*.env`) y en el gestor de contraseñas de la empresa.
Última revisión: 2026-10-14.

> **Los archivos `/opt/sulotec/*.env` NO entran en el respaldo diario** (`backup.sh` copia las bases, `/data/apps` y Object Storage).
> Si el servidor se pierde, esas claves se pierden con él: por eso lo marcado como *imprescindible* debe estar también en el gestor.

## 1. Qué guardar aparte en el gestor de contraseñas

**Imprescindible (si se pierde, no se puede recuperar):**

| Qué | Por qué | Dónde está hoy |
|---|---|---|
| `MFA_ENCRYPTION_KEY` de MiRadar | Cifra la verificación en dos pasos de cada usuario. Si cambia o se pierde, nadie puede usar su código. **No se rota.** | `/opt/sulotec/miradar.env` |
| Contraseñas de las cuentas de personas | Oracle (administradores), Cloudflare, GitHub (`jeliases-informaDev` y la organización `Sulotec`), Expo (`jeliasesinformaperu`), Google Play Console, los correos de los administradores y la cuenta de administrador de Keycloak | gestor de contraseñas |
| Códigos de recuperación de esas cuentas | Para recuperarlas si se pierde el celular. Hoy la verificación en dos pasos **no está activada** en ellas (pendiente en `SEGURIDAD-ISO27001.md`) | gestor de contraseñas |
| Clave de la RRCC-API (`RRCC_API_KEY`) | La custodia el dueño de esa API; si se pierde hay que pedir una nueva | `/opt/sulotec/miradar.env` |

**Recuperable (se vuelve a generar rotando; conviene tenerla igual en el gestor):** claves de las bases, `JWT_SECRET`, clave S3 de
`svc-miradar`, token del túnel de Cloudflare, token de servicio de Cloudflare Access del Buscador.

Para sacar todo lo del servidor en una sola pantalla: `sudo /opt/sulotec/scripts/mostrar-claves.sh` (pide confirmación, no escribe archivos).

## 2. Dónde vive cada secreto en el servidor Oracle

| Archivo | Variables secretas | Para qué | Cómo se rota |
|---|---|---|---|
| `/opt/sulotec/.env` (root:docker, 640) | `POSTGRES_PASSWORD`, `MYSQL_ROOT_PASSWORD` | Administración de las bases (los respaldos usan estas) | `sudo /opt/sulotec/scripts/rotar-claves.sh postgres mysql` |
| | `CF_TUNNEL_TOKEN` | Conecta el servidor con Cloudflare | Cloudflare One → Networks → Tunnels → `sulotec` → generar token nuevo; cambiarlo en `.env`; `docker compose up -d cloudflared` |
| `/opt/sulotec/miradar.env` | `DATABASE_URL` (lleva la clave del usuario `miradar`) | MiRadar → su base | `sudo /opt/sulotec/scripts/rotar-claves.sh miradar` |
| | `B2_KEY_ID`, `B2_APPLICATION_KEY` (nombres heredados de Backblaze; son la clave S3 de `svc-miradar`) | Fotos y firmas en Object Storage | `apps/miradar/deploy/rotar-s3.sh` (ver el README de MiRadar) |
| | `JWT_SECRET` | Firma las sesiones | Cambiar en el archivo y `desplegar.sh`; cierra todas las sesiones abiertas |
| | `MFA_ENCRYPTION_KEY` | Ver arriba | **No rotar** |
| | `RRCC_API_KEY` (y `MAPBOX_ACCESS_TOKEN` si se usa) | Servicios externos | Los entrega el dueño del servicio; `preparar.sh` los cambia |
| | `INITIAL_ADMIN_PASSWORD` | Vacía a propósito: con datos migrados, rellenarla cambiaría la clave del administrador al arrancar | — |
| `/opt/sulotec/cuenta.env` | `KC_DB_PASSWORD` (rol `keycloak`) | Keycloak → su base | `ALTER ROLE keycloak PASSWORD …` y cambiarla en el archivo; recrear el contenedor `cuenta` |
| | `KC_BOOTSTRAP_ADMIN_USERNAME` / `KC_BOOTSTRAP_ADMIN_PASSWORD` | Administrador temporal de Keycloak (pendiente reemplazarlo por uno con nombre propio) | Desde la consola de Keycloak |
| `/opt/sulotec/buscador.env` | `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` | Token de servicio de Cloudflare Access para llegar a la API de la oficina | Cloudflare One → Access → Service Auth → regenerar; `apps/buscador/deploy/preparar.sh` |
| `/opt/actions-runner` (usuario `github-runner`) | Credenciales del runner de GitHub Actions | Publicar el portal, las cuentas y el Buscador | Quitar el runner en GitHub y registrarlo con `instalar-runner.sh` |
| `/opt/sulotec/buscador-actualizador/` | Llave SSH de solo lectura | Lee `Sulotec/buscador-interno` cada 2 minutos | Deploy key en GitHub → Settings → Deploy keys |
| Base de datos de Keycloak (realm `sulotec`) | Clave SMTP de OCI Email Delivery | Correo de cuentas | Consola de Keycloak → Realm settings → Email |

## 3. Fuera del servidor

| Sistema | Qué secretos hay | Dónde |
|---|---|---|
| **Oracle Cloud** | Usuarios y administradores; usuario de servicio `svc-miradar` con su clave S3 (`miradar-api-2`); claves de API del CLI y de Terraform (`~/.oci`, `terraform.tfvars`); credenciales SMTP (Mi perfil → Tokens y claves) | Consola de Oracle / Cloud Shell |
| **Cloudflare** | Cuenta, políticas de Access, tokens de servicio | Cloudflare One |
| **GitHub** | Cuentas, secretos de Actions (token de Vercel para el front del Buscador), llaves de despliegue | GitHub → Settings |
| **Expo (EAS)** y **Google Play** | Cuenta Expo; la llave de subida de Android la administra EAS | expo.dev / Play Console |
| **API del Buscador (servidor Windows de la oficina)** | `appsettings.Production.json`: `Jwt:Key`, SMTP, clave de la base `irubio`, token de RENIEC | Servidor Windows de la oficina |
| **RRCC-API** | Su clave `x-api-key` y el token de ngrok del equipo donde corre | Equipo del dueño de esa API |
| **Render, Aiven, Backblaze** | A cerrar. Sus claves se borran al eliminar los servicios | Sus paneles |

## 4. Estado de rotación

| Secreto | Última rotación | Pendiente |
|---|---|---|
| `postgres`, `root` de MySQL, rol `miradar` | 2026-10-14 | — |
| Clave S3 de `svc-miradar` | 2026-10-14 | — |
| `JWT_SECRET`, `MFA_ENCRYPTION_KEY` de MiRadar | Generadas en el servidor, nunca salieron de él | `MFA_ENCRYPTION_KEY` no se rota |
| `RRCC_API_KEY` | — | Pasó por un chat; pedir una nueva al dueño de la API |
| Claves de Render y Backblaze | — | Se anulan al borrar esos servicios |
| SMTP, `Jwt:Key`, `irubio`, token de RENIEC, token de Vercel, administrador temporal de Keycloak | — | Pasaron por chats; rotar |

Política: rotar de inmediato cualquier secreto que se haya compartido por un chat o un correo, y revisar el resto cada 90 días.

## 5. Si se pierde o se expone una clave

| Situación | Qué hacer |
|---|---|
| Se expuso una clave de base de datos | `sudo /opt/sulotec/scripts/rotar-claves.sh` |
| Se expuso la clave S3 de `svc-miradar` | Crear una nueva en Cloud Shell, `rotar-s3.sh`, y borrar la anterior en Oracle |
| Se expuso `JWT_SECRET` | Cambiarlo y volver a publicar: se cierran todas las sesiones |
| Se perdió `MFA_ENCRYPTION_KEY` | No hay forma de recuperarla: hay que reiniciar la verificación en dos pasos de todos los usuarios de MiRadar |
| Se perdió el servidor | Terraform + `bootstrap.sh` recrean la infraestructura; las bases vuelven del respaldo; los `.env` hay que reconstruirlos desde el gestor de contraseñas |
