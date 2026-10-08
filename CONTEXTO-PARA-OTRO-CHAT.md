# Contexto del proyecto Sulotec (para continuar en otro chat / otra PC)

Pega o adjunta este archivo en el chat nuevo y di: "Continúa desde donde quedamos".
Este proyecto es de **Sulotec** y NO tiene relación con la pizzería (esa es personal, no mezclar).

## Objetivo
Montar un ecosistema de aplicaciones web SaaS en subdominios de `sulotec.com`: Caja Huancayo, Compartamos, lavado de activos (security backend) y AFACOP.
Stack mixto: React, Angular, TypeScript/JavaScript, C# .NET, Java Spring Boot, APIs. Nada estaba configurado al empezar (2026-10-06).

## Arquitectura elegida
```
Usuario → Cloudflare (DNS, SSL, WAF, Access) → Cloudflare Tunnel → VM Oracle ARM (Ubuntu) → Docker
                                                                   ├─ cloudflared
                                                                   ├─ postgres (una BD + usuario por proyecto)
                                                                   └─ un contenedor por app
```
- La VM no abre puertos web; solo SSH desde la IP del administrador.
- Subdominios de **un solo nivel** (`api-afacop.sulotec.com`, no `api.afacop.sulotec.com`) por el SSL gratis de Cloudflare.
- Todo está en la carpeta `sulotec-infra/`: `README.md` (fases paso a paso), `oracle/` (Terraform), `vm/` (compose base + scripts), `templates/` (Dockerfiles .NET, Spring Boot, SPA).

## >>> ESTADO ACTUAL (2026-10-07, 23:40 Lima) — leer esto primero <<<
**Plataforma base terminada y funcionando.** Lo de más abajo es historial.
- **Oracle (Pay As You Go, todo en Always Free = US$0):** VM `sulotec-main` A1 4 OCPU/24 GB, Ubuntu 24.04 ARM, IP pública 155.181.132.137 (IP privada 10.0.1.178). Boot 150 GB + **disco de datos 50 GB montado en `/data`** (etiqueta `sulotec-data`). Buckets privados `sulotec-backups` y `sulotec-archivos` (namespace `axkjo5bh8iys`). **Puerto 22 cerrado** (`ssh_enabled = false` en tfvars). Presupuesto real: US$260/mes, gastar solo si hace falta; alerta en US$10.
- **Cloudflare:** `sulotec.com` con HTTPS obligatorio y TLS ≥1.2. Túnel **`sulotec`** (ID 2bb087e4-…) Healthy. Zero Trust Free (team `round-butterfly-3ee7`, se puede renombrar). App de Access **`ssh.sulotec.com`** (SSH en el navegador) con política `Administradores` = `informaperu2@gmail.com`, `serviciosdigitales@informaperu.com`; certificados SSH cortos (CA en `/etc/ssh/ca.pub`). Ruta del túnel: `ssh.sulotec.com → ssh://10.0.1.178:22`.
- **Cómo entrar al servidor:** abrir **https://ssh.sulotec.com** desde cualquier navegador → código al correo → usuario `informaperu2` (o `serviciosdigitales`). Cada persona tiene su usuario Linux, sin contraseña, con sudo y docker. El usuario `ubuntu` + llave de la laptop solo sirve si se reabre el puerto 22 (emergencia).
- **Emergencia (si Cloudflare falla):** Cloud Shell → `cd ~/oracle`, exportar `TF_VAR_*`, poner `ssh_enabled = true` y `admin_cidr = "<IP actual>/32"` en `terraform.tfvars`, `terraform apply`; entrar con la llave de la laptop (`ubuntu@155.181.132.137`). Volver a `false` al terminar.
- **En la VM (`/opt/sulotec`, root:docker):** `docker-compose.yml` con `cloudflared`, `postgres:16` (`/data/postgres`) y `mysql:8.4` (`/data/mysql`), redes `sulotec_edge` y `sulotec_data`. `.env` con `CF_TUNNEL_TOKEN`, `POSTGRES_PASSWORD`, `MYSQL_ROOT_PASSWORD`, `BACKUP_BUCKET` (**no borrar `.env`**). Scripts: `scripts/backup.sh` (cron diario 02:00 → `/var/log/sulotec-backup.log`, copia local en `/var/backups/sulotec` 14 días + bucket con instance principal; primer backup OK 23:36) y `scripts/new-project-db.sh <postgres|mysql> <proyecto>`. OCI CLI en `/usr/local/bin/oci`. Volumen Docker viejo `sulotec_pgdata` quedó sin uso (vacío; se puede borrar).
- **Archivos de referencia:** `vm/bootstrap.sh` (túnel, VM nueva) → `vm/setup-datos.sh` (disco, bases, backups). `SEGURIDAD-ISO27001.md` con el mapeo de controles y pendientes.
- **Pendientes:** las claves de `POSTGRES_PASSWORD` y `MYSQL_ROOT_PASSWORD` se mostraron en el chat el 2026-10-07 y el usuario decidió no rotarlas aún → **rotarlas antes de cargar datos reales** (ALTER USER en ambas bases + actualizar `.env` + `docker compose up -d` + `backup.sh`); guardar claves de Postgres/MySQL en el gestor de la empresa; 2FA en Gmail/Cloudflare/Oracle y MFA en la política de Access; prueba de restauración; repo Git privado de la empresa; repos de Caja Huancayo a privado; validar Ley 29733/SBS con legal; limpiar la PC personal (llave `C:\Users\Jorge\.ssh\sulotec_oci` nunca autorizada, zips en Descargas). **Siguiente gran paso: subir los 3 proyectos** (Caja Huancayo usa Node + MySQL; su código está en GitHub `jeliases-informaDev/*`).

## Portal sulotec.com y subdominios (2026-10-08, madrugada)
- Portal en `apps/portal/` (Astro + componentes; datos en `src/data/sitio.ts` y `src/data/soluciones.ts`). Marca **Sulotec**, estilo tomado como **referencia** del manual de marca de Informa Perú (azul `#1B4589`, rojo `#ED1C24` solo acento, Leelawadee UI/Arial, corte curvo con filete rojo, íconos lineales) y estructura inspirada en experian.com.pe (sin copiar diseño ni imágenes). Animaciones solo CSS (respeta "reducir movimiento").
- Productos: **MiRadar360** (antes AFACOP; repos `jeliases-informaDev/Afacop-*`, "torre de control" de asesores en campo, web + Android/iOS, en producción), **Auditoría de Visitas** (Caja Huancayo; Node + MySQL), **Prevención de Lavado de Activos** (web + app), **Buscador Interno** (repos `InternalBuscador` (T-SQL → SQL Server) e `internal-search-frontend`).
- Despliegue: nginx `stable-alpine` en `/data/apps/portal` (red `sulotec_edge`, contenedor `portal`); rutas del túnel `sulotec.com` y `www.sulotec.com` → `http://portal:80`. El build (`npm run build`) se hace en una PC por ahora; luego CI/CD desde GitHub.
- Subdominios propuestos (un solo nivel): `miradar360`/`api-miradar360`, `auditoria`/`api-auditoria`, `plaft`/`api-plaft`, `buscador` (con Cloudflare Access). Por confirmar con el usuario.
- **GitHub:** organización **`Sulotec`** (creada desde la cuenta de empresa `informaperu2-cmyk`, como "business"), repo **privado `Sulotec/Sulotec-infra`** con todo este proyecto. Es la fuente oficial: editar → push a `main` → se publica solo.
- **CI/CD:** `.github/workflows/portal.yml` corre en un **runner propio** `sulotec-main` (servicio `actions.runner.Sulotec-Sulotec-infra.sulotec-main`, usuario `github-runner` en grupo docker, `/opt/actions-runner`, etiqueta `sulotec`), instalado con `vm/scripts/instalar-runner.sh`. Conexión saliente, sin puertos. Compila Astro en `node:24-alpine` y publica en `/data/apps/portal/sitio` (dueño `github-runner:docker`). Primera publicación OK (2026-10-08 ~01:20).
- **Rutas del túnel:** `ssh.sulotec.com → ssh://10.0.1.178:22`, `sulotec.com → http://portal:80`, `www.sulotec.com → http://portal:80`. **https://sulotec.com en línea** (HTTP 200, encabezados de seguridad del nginx).
- **Productos públicos vs privados:** MiRadar360, Auditoría de Visitas y Lavado de Activos son **públicos** (aparecen en el portal). **Buscador Interno es privado** de la empresa: `publico: false` en `soluciones.ts` (no aparece en el portal) y `buscadorinterno.sulotec.com` se protege con Cloudflare Access (app "buscadorinterno", creada 2026-10-08), política reutilizable **"Administradores generales"**: `abel.chavez@informaperu.com` (CEO), `serviciosdigitales@informaperu.com`, `informaperu2@gmail.com`. El CEO NO tiene acceso al servidor SSH (mínimo privilegio). **Requisito del usuario: el Buscador solo debe abrirse desde la red de la sede** (no desde casa ni datos móviles): agregar a la política un "Require → IP ranges" con la IP pública fija de la oficina (pendiente: obtenerla el viernes en https://ifconfig.me y confirmar que es fija; si no lo es, usar WARP con equipos registrados). Dentro de la app: CEO acceso total, demás usuarios con permisos limitados (roles por correo). La app Buscador debe leer la identidad verificada por Cloudflare (`Cf-Access-Jwt-Assertion`, validar contra el team domain y el AUD de la app) para sus roles (inicio de sesión único). Ojo: `InternalBuscador` es T-SQL → SQL Server (no corre en ARM).
- Portal: cada producto tiene `url` opcional (dirección actual mientras se muda) y `publicado` (subdominio propio). Pendiente: que el usuario pase las URLs actuales de MiRadar360, Auditoría y Lavado de Activos.
- En el terminal web de Cloudflare el pegado agrega `^[[200~ … ~`: antes de pegar comandos, ejecutar `bind 'set enable-bracketed-paste off'`.

## Estado actual (2026-10-06, noche)
- **Cloudflare:** `sulotec.com` activo, plan Free. Túnel `sulotec-oci` ya creado (ver "Avance" más abajo). **Para el estado más reciente y el plan de mañana, ir a "Plan para mañana".**
- **Oracle Cloud:** tenancy `InformaPeru`, región home Chile Central (Santiago) = `sa-santiago-1`. Cuenta en **Free Trial** (sin método de pago). El usuario solo tiene tarjeta de débito y no la tenía a mano; se decidió **seguir sin upgrade** y hacerlo luego si hace falta (Billing → Change Payment Method → Upgrade your account).
- **Cloud Shell de Oracle:** `terraform plan` y `terraform apply` ya corrieron. Se crearon **12 de 13 recursos** (VCN, subred, internet gateway, ruta, security list solo-SSH, bucket `sulotec-backups`, presupuesto US$10 y sus 3 alertas). **Falta la VM** (`oci_core_instance.main`) y, como dependen de ella, el dynamic group y la policy. Oracle responde `500 Out of host capacity` (la capa gratuita ARM no tiene hueco en Santiago). Es esperable; se reintenta en bucle. A las 03:16 UTC (22:16 Lima) del 2026-10-07 llevaba ~20 min reintentando sin éxito.
- **Siguiente paso inmediato:** conseguir que se cree la VM (ver "Retomar en Cloud Shell"). Si tras ~1 hora no sale: bajar a 2 OCPU / 12 GB. Si tampoco: upgrade a Pay As You Go con **tarjeta de crédito** (Billing → Change Payment Method → Upgrade your account; el usuario solo tiene débito, que puede no ser aceptada), o usar otro proveedor de VPS (los compose/scripts sirven en cualquier Ubuntu).

## Retomar en Cloud Shell (cada sesión nueva pierde las variables)
```bash
cd ~/oracle
export TF_VAR_tenancy_ocid=$OCI_TENANCY TF_VAR_compartment_ocid=$OCI_TENANCY TF_VAR_region=$OCI_REGION
# opcional, si hay que bajar el tamaño:  printf 'ocpus = 2\nmemory_gb = 12\n' >> terraform.tfvars
while true; do terraform apply -auto-approve -input=false > /tmp/tf.log 2>&1 && break; grep -q "Out of host capacity" /tmp/tf.log || break; echo "$(date +%H:%M) sin capacidad, reintento en 60 s"; sleep 60; done; tail -20 /tmp/tf.log
```
Éxito = `Apply complete!` con `public_ip` y `ssh`. Mantener la pestaña de Oracle abierta, o el bucle se corta.

## Regla: la configuración NO depende de ninguna PC personal
- La PC personal de Jorge (escritorio, 2 pantallas) se usa **solo por comodidad**, como navegador para Cloud Shell y Cloudflare. Nada de la configuración vive ni depende de ella.
- La VM se crea **solo con la llave de la laptop de trabajo** (la que ya está en `terraform.tfvars`). La llave de la PC personal NO va en Terraform.
- Si algún día se quiere SSH desde la PC personal, se agrega temporalmente en `~/.ssh/authorized_keys` de la VM y se quita después. (Hay una llave generada en `C:\Users\Jorge\.ssh\sulotec_oci`, no autorizada en ningún lado.)
- Misma IP pública en ambas PCs (`38.253.149.94`, misma red), así que `admin_cidr` no cambia.
- En `main.tf` se añadió `metadata` a `ignore_changes`: Oracle no permite cambiar las llaves de una VM ya creada, y sin esto un cambio en `ssh_public_key` podría hacer que Terraform intente recrear la VM.
- El estado de Terraform está en el Cloud Shell de Oracle (`~/oracle/terraform.tfstate`), no en una PC: se ve igual desde cualquier navegador con la misma cuenta. No correr dos bucles a la vez (uno por pestaña/PC): el segundo falla por el lock del estado.
- Pendiente para no depender de nadie: repo Git privado de Sulotec para `sulotec-infra/`, secretos en gestor de contraseñas de la empresa, estado de Terraform al bucket.

## Qué crea Terraform (oracle/main.tf)
VCN + subred pública + security list (solo SSH desde `admin_cidr`), VM `VM.Standard.A1.Flex` (4 OCPU, 24 GB, 150 GB, Ubuntu 24.04) con cloud-init que instala Docker/fail2ban, bucket privado `sulotec-backups`, dynamic group + policy para que la VM suba backups, y presupuesto de US$10/mes con alertas al 50/80/100 % al correo serviciosdigitales@informaperu.com.

## Si cambias de PC (importante)
- `admin_cidr` está fijado a la IP pública de la PC original (`38.253.149.94/32`). Desde otra PC/red el SSH será bloqueado: edita `admin_cidr` en `oracle/terraform.tfvars` (Cloud Shell) y ejecuta `terraform apply` otra vez (solo cambia la security list).
- La llave SSH privada autorizada está en la laptop de trabajo: `C:\Users\INFORMA PERU\.ssh\sulotec_oci` (sin passphrase, pendiente ponerle una con `ssh-keygen -p -f`). La pública está en `terraform.tfvars`. **No pegues ni subas la privada a ningún chat.** Para otra PC, genera otra llave allí y agrégala a `~/.ssh/authorized_keys` en la VM (no en Terraform).
- Copia la carpeta `sulotec-infra/` completa a la PC nueva (o súbela al Cloud Shell si solo vas a trabajar ahí).

## Avance 2026-10-06 noche (PC personal)
- Cloudflare: túnel `sulotec-oci` creado (Networking → Tunnels, sin pasar por Zero Trust), estado Inactive, sin rutas. Token guardado por el usuario (NO está en estos archivos).
- Cloud Shell: bucle de `terraform apply` relanzado ~22:40 Lima con `metadata` en `ignore_changes`; solo la llave de la laptop en tfvars. Cloud Shell se cerró por inactividad (~20 min sin teclado) y mató el bucle.
- 23:05 Lima: bucle relanzado **en segundo plano** (`nohup`), con **2 OCPU / 12 GB** (`ocpus`/`memory_gb` agregados a tfvars). Avance en `~/tf-loop.log` (horas en UTC), detalle en `~/tf.log`. Cada intento tarda ~1 min. Hay que presionar Enter en Cloud Shell cada ~10 min para que no se cierre. Ver avance: `tail -5 ~/tf-loop.log`.
- `vm/bootstrap.sh`: un solo script que se pega en la VM y escribe compose + scripts, pide el token del túnel (oculto), genera la clave de Postgres, crea `.env` y levanta todo. Evita copiar archivos desde una PC.
- Decisión del usuario: **Caja Huancayo y demás apps se ven después**. Prioridad: dejar funcionando la arquitectura base de Oracle + Cloudflare.
- Cloudflare SSL/TLS → Edge Certificates: certificado universal `*.sulotec.com, sulotec.com` activo; **Always Use HTTPS = On**, **Minimum TLS = 1.2**, Automatic HTTPS Rewrites = On. Cloudflare base queda lista; falta solo conectar el túnel (necesita la VM).
- 23:15 Lima: a 2 OCPU / 12 GB seguía "Out of host capacity". **Decisión: mañana 2026-10-07 hacer upgrade a Pay As You Go** (Menú ☰ → Billing & Cost Management → Upgrade and Manage Payment → Upgrade; probar débito, si no, crédito de la empresa) y relanzar el bucle.
- Pendientes del usuario: 2FA en Gmail `informaperu2`, Cloudflare y Oracle; poner **privados** los 3 repos de Caja Huancayo (son públicos; antes confirmar que Render está conectado a GitHub en Account Settings → Git Providers); copiar esta carpeta a la laptop.

## 2026-10-07: VM CREADA
- Upgrade a **Pay As You Go** hecho. Con eso la VM salió **al primer intento** con **4 OCPU / 24 GB** (02:48 UTC del 2026-10-08 = 21:48 Lima del 07).
- `terraform apply` completo (13/13 + dynamic group + policy). Salidas: `public_ip = 155.181.132.137`, `backup_bucket = sulotec-backups`, `object_storage_namespace = axkjo5bh8iys`.
- SSH desde la laptop OK (desde casa: la IP de casa `38.253.149.94` es la de `admin_cidr`; desde la oficina NO entra hasta resolver acceso por Cloudflare). `bootstrap.sh` OK: `/opt/sulotec/.env` creado, `cloudflared` y `postgres` (healthy) corriendo.
- **NO borrar `/opt/sulotec/.env`**: Postgres ya se inicializó con esa clave. Para cambiar solo el token del túnel: `sed -i "s|^CF_TUNNEL_TOKEN=.*|CF_TUNNEL_TOKEN=<nuevo>|" .env && docker compose up -d`.
- El token del primer túnel se pegó en el chat, así que se creó un túnel nuevo **`sulotec`** (ID `2bb087e4-1629-4778-beff-a94899412754`), **Healthy**, conectado desde 155.181.132.137 (linux_arm64, bordes scl04/gru07/gru11). El viejo `sulotec-oci` (8a3fcbf5…) fue **borrado**. La página del túnel tiene botón **Rotate token** para futuras rotaciones.
- Siguiente: reiniciar la VM (`sudo reboot`) y comprobar que todo vuelve solo; guardar la clave de Postgres en el gestor de la empresa; luego acceso SSH por Cloudflare Access y cerrar el puerto 22.

- 22:30 Lima: reinicio de la VM probado; `cloudflared` y `postgres` vuelven solos. **Arquitectura base funcionando.**

## Decisiones del 2026-10-07 noche (lo siguiente a construir)
- **Trabajo desde la laptop de trabajo.** La PC personal (usuario Windows `Jorge`) NO se autoriza en el servidor y no debe quedar configuración en ella. Ahí hay una llave `C:\Users\Jorge\.ssh\sulotec_oci` que nunca se autorizó: el usuario la borrará.
- Sugerido: abrir Claude Code **en la laptop** con esta carpeta; así Claude ejecuta los comandos del servidor directamente con `ssh -i "$HOME\.ssh\sulotec_oci" ubuntu@155.181.132.137` (huella ED25519 `SHA256:U+Svw53XtB9utDhGXVMS2EMJLUpxll3h7bf4p0g5Lyo`) y el usuario solo hace clics en Cloudflare/Oracle.
- **Presupuesto: US$260/mes**, gastar solo si es necesario. Esta etapa debe quedar en $0 (Always Free). Alertas siguen en US$10 como alarma de "algo empezó a cobrar".
- **3 proyectos** a alojar (por confirmar cuáles; Caja Huancayo usa MySQL). Motores en uso: MySQL, SQL Server, PostgreSQL. SQL Server no corre en ARM: se decide con su proyecto (dejar en data center con conexión privada / migrar a PostgreSQL / VM x86 de pago ~US$55/mes, Express gratis hasta 10 GB).
- **ISO/IEC 27001**: diseñar alineado al Anexo A y dejar `SEGURIDAD-ISO27001.md` con el mapeo de controles (acceso 5.15/8.5, redes 8.20/8.22, cripto 8.24, backup 8.13, logging 8.15/8.16, vulnerabilidades 8.8, cambios 8.32, nube 5.23). Advertir: datos en Santiago = flujo transfronterizo (Ley 29733) y clientes supervisados por SBS → que lo valide legal/cumplimiento.
- **Correos con acceso al servidor (Cloudflare Access):** `informaperu2@gmail.com` (usuario/principal `informaperu2`) y `serviciosdigitales@informaperu.com` (principal `serviciosdigitales`).

### Paso 1 — Acceso SSH por Cloudflare (y luego cerrar el puerto 22)
1. Servidor: agregar a `cloudflared` `extra_hosts: ["host.docker.internal:host-gateway"]` (ya está en `vm/docker-compose.yml` local; en el servidor):
   `cd /opt/sulotec && (grep -q host-gateway docker-compose.yml || sed -i '/command: tunnel --no-autoupdate run/a\    extra_hosts: ["host.docker.internal:host-gateway"]' docker-compose.yml) && docker compose up -d`
2. Cloudflare → Zero Trust: onboarding con team name `sulotec`, plan Free.
3. Access → Applications → Self-hosted `ssh.sulotec.com`, política Allow con los 2 correos (login por código al correo; 2FA), y **Browser rendering = SSH**.
4. Túnel `sulotec` → Add route → published application `ssh.sulotec.com` → tipo **SSH** → `host.docker.internal:22`.
5. Access → Service credentials / Service Auth → **SSH** → generar certificado (CA de certificados cortos) para esa app → copiar la llave pública (no es secreta).
6. Servidor: `/etc/ssh/ca.pub` con esa llave; `/etc/ssh/auth_principals/ubuntu` con `informaperu2` y `serviciosdigitales`; `/etc/ssh/sshd_config.d/60-cloudflare-access.conf` con `PubkeyAuthentication yes`, `TrustedUserCAKeys /etc/ssh/ca.pub`, `AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u`; `sudo sshd -t && sudo systemctl restart ssh`.
7. Probar `https://ssh.sulotec.com` desde cualquier navegador → usuario `ubuntu`.

### Paso 2 — Oracle (Terraform, Cloud Shell): almacenamiento y cierre de SSH
- Volumen de bloque **50 GB** `sulotec-data` (paravirtualized) adjunto a la VM → total 150+50 = 200 GB, dentro de Always Free.
- Bucket privado **`sulotec-archivos`** (Object Storage, API compatible S3) para fotos/documentos de las apps.
- Variable `ssh_enabled` (bool) con `dynamic "ingress_security_rules"` para el puerto 22; poner `false` **solo después** de probar el paso 1.7. Plan de emergencia: `ssh_enabled = true` + `admin_cidr` = IP actual y `terraform apply` desde Cloud Shell.

### Paso 3 — Servidor: datos y backups
- Montar el volumen en **`/data`** (UUID en fstab con `_netdev,nofail`). Todo lo importante vive ahí: `/data/postgres`, `/data/mysql`, `/data/apps/<proyecto>`.
- Pasar Postgres del volumen Docker `sulotec_pgdata` (vacío) a `/data/postgres` (misma `POSTGRES_PASSWORD` del `.env`; NO borrar `.env`). Agregar **MySQL 8.4** al compose base con `/data/mysql`, y soporte MySQL en `new-project-db.sh`.
- OCI CLI con `pipx` (`sudo apt install -y pipx && pipx install oci-cli`); en `backup-postgres.sh` agregar `export PATH="$HOME/.local/bin:$PATH"` para cron. Backup diario: `pg_dumpall` + `mysqldump --all-databases` + `tar` de `/data/apps` → bucket `sulotec-backups` con `--auth instance_principal`. Correr uno a mano, verlo en el bucket y **probar una restauración**.

### Paso 4 — Cierre
- `SEGURIDAD-ISO27001.md`, repo Git privado de la empresa para `sulotec-infra`, 2FA en Gmail/Cloudflare/Oracle, repos de Caja Huancayo en privado.

## Plan para mañana (en orden) — HISTÓRICO, ya cumplido
1. Upgrade a Pay As You Go en Oracle.
2. Cloud Shell: pegar el bloque de "Relanzar el bucle" de abajo y presionar Enter cada ~10 min.
3. Cuando salga `>>> LISTO, VM CREADA` con `public_ip`: desde la **laptop** `ssh -i $HOME\.ssh\sulotec_oci ubuntu@<IP>`, pegar `vm/bootstrap.sh` como `~/bootstrap.sh` y ejecutar `bash ~/bootstrap.sh` (pide el token del túnel).
4. Verificar túnel **Healthy** en Cloudflare → Networking → Tunnels. Guardar la clave de Postgres en el gestor de la empresa.
5. Después: acceso admin por Cloudflare Access (y cerrar SSH), backups, repo Git de la empresa, y recién ahí las apps.

### Relanzar el bucle (Cloud Shell; seguro de repetir)
```bash
cd ~/oracle
export TF_VAR_tenancy_ocid=$OCI_TENANCY TF_VAR_compartment_ocid=$OCI_TENANCY TF_VAR_region=$OCI_REGION
if terraform state list | grep -q '^oci_core_instance.main$'; then echo ">>> LA VM YA EXISTE"; terraform output; else
grep -q '^ocpus' terraform.tfvars || printf 'ocpus = 2\nmemory_gb = 12\n' >> terraform.tfvars
nohup bash -c 'while true; do echo "$(date +%H:%M) intentando..."; terraform apply -auto-approve -input=false > ~/tf.log 2>&1 && { echo ">>> LISTO, VM CREADA"; terraform output; break; }; grep -q "Out of host capacity" ~/tf.log || { echo ">>> ERROR DISTINTO:"; tail -20 ~/tf.log; break; }; echo "$(date +%H:%M) sin capacidad, reintento en 60 s"; sleep 60; done' > ~/tf-loop.log 2>&1 &
sleep 2; tail -f ~/tf-loop.log; fi
```
Con Pay As You Go se puede volver a 4 OCPU / 24 GB (borrar las líneas `ocpus`/`memory_gb` de `terraform.tfvars`), pero 2/12 basta para empezar y se agranda después.
- La cuenta de Oracle y la de Cloudflare están a nombre de `informaperu2@gmail.com`: asegurar 2FA y que la empresa controle ese Gmail.

## Situación actual de las apps (dicho por el usuario)
- Todo el código está en **GitHub**.
- Algunas apps ya desplegadas en **Vercel** y **Render**; ya tienen **imágenes Docker**.
- Algunas bases de datos están en el **data center propio** de la empresa. Motores en uso: **SQL Server, MySQL y PostgreSQL**.
  - PostgreSQL y MySQL corren bien en la VM ARM (MySQL aún no está en `vm/docker-compose.yml`; agregarlo cuando un proyecto lo necesite).
  - SQL Server NO corre en ARM: esas BDs se quedan en el data center (la app en la VM se conecta remoto) o se migran a PostgreSQL.
- Implicancias: imágenes deben ser `linux/arm64` (la VM es ARM); despliegue por GitHub Actions; si una app en la VM usa una BD del data center, hay que resolver la conexión segura (no abrir la BD a internet) y la latencia Santiago↔Lima. Una app .NET puede seguir usando SQL Server remoto: lo que no corre en ARM es el servidor SQL Server, no el cliente.

## Pendiente (en orden)
1. `terraform plan` / `apply` en Cloud Shell → obtener `public_ip`.
2. SSH a la VM, copiar `vm/` a `/opt/sulotec/`, crear `.env`.
3. Crear el túnel de Cloudflare, poner el token en `.env`, `docker compose up -d`.
4. Primer proyecto (AFACOP o el más simple): `scripts/new-project-db.sh`, plantillas de `templates/`, hostnames públicos en el túnel.
5. Cloudflare Access para paneles admin, cron de backups, probar restauración, ponerle passphrase a la llave SSH.

## Advertencias
- **SQL Server no corre en ARM.** Preguntar qué base de datos usan hoy las apps .NET; si es SQL Server, migrar a PostgreSQL o usar VM x86 de pago.
- La capa gratuita no tiene SLA: sirve para desarrollo y pilotos. Para producción con datos reales de clientes financieros (Caja Huancayo, Compartamos, lavado de activos) conviene VM de pago, backups probados y revisar requisitos del cliente y la Ley 29733.
- Estos archivos de Terraform no se validaron localmente (no hay `terraform` en la PC); `terraform plan` en Cloud Shell es la primera validación real.
