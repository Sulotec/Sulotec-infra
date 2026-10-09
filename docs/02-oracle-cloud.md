# 2. Oracle Cloud — infraestructura

> Índice: [Documentación](README.md) · Anterior: [1. Proyecto](01-proyecto-sulotec.md) · Siguiente: [3. Cloudflare](03-cloudflare.md)

## 2.1 Cuenta y costos

| Dato | Valor |
|---|---|
| Tipo de cuenta | Pay As You Go (con tarjeta), usando recursos **Always Free** |
| Región | **Chile Central (Santiago)**, `sa-santiago-1` |
| Costo actual | US$ 0/mes (todo dentro de Always Free) |
| Presupuesto aprobado | Hasta US$ 260/mes, **solo si hace falta** |
| Alertas | Presupuesto mensual `sulotec-mensual` con alertas por porcentaje al correo de la cuenta (umbral US$ 10) |
| Dueño | Cuenta de la empresa (`informaperu2@gmail.com`). Pendiente: 2FA |

## 2.2 Qué se creó (Terraform)

Toda la infraestructura está descrita como código en [`oracle/`](../oracle):
- [`main.tf`](../oracle/main.tf): los recursos.
- [`variables.tf`](../oracle/variables.tf): los parámetros.
- [`cloud-init.yaml`](../oracle/cloud-init.yaml): la preparación inicial del servidor.

El **estado de Terraform** vive en el **Cloud Shell** de Oracle (`~/oracle/terraform.tfstate`), no en una PC.

| Recurso | Nombre | Detalle |
|---|---|---|
| Red virtual | `sulotec-vcn` | Con *internet gateway* `sulotec-igw` y tabla de rutas `sulotec-public-rt` |
| Subred | `sulotec-public` | Pública; el servidor tiene IP pública, pero **sin puertos abiertos** |
| Lista de seguridad | `sulotec-ssh-only` | El puerto 22 se abre solo si `ssh_enabled = true` (hoy **cerrado**) |
| Servidor | `sulotec-main` | `VM.Standard.A1.Flex` (ARM): 4 OCPU, 24 GB de RAM, Ubuntu 24.04, disco de arranque 150 GB |
| IP | Pública `155.181.132.137` · privada `10.0.1.178` | La pública no se usa para servicios: todo entra por el túnel de Cloudflare |
| Disco de datos | `sulotec-data` | 50 GB, montado en **`/data`** (bases, apps y archivos). Se puede conectar a otra VM |
| Bucket | `sulotec-backups` | Privado, con versionado. Respaldos diarios (namespace `axkjo5bh8iys`) |
| Bucket | `sulotec-archivos` | Privado. Archivos de las aplicaciones |
| Grupo dinámico + política | `sulotec-vm`, `sulotec-vm-backups` | El servidor sube respaldos **sin llaves guardadas** (*instance principal*) |
| Presupuesto | `sulotec-mensual` | Alertas por correo |

**Cambiar algo de la infraestructura** (en el Cloud Shell de Oracle):
```bash
cd ~/oracle
# exportar las variables TF_VAR_* si la sesión es nueva (ver terraform.tfvars.example)
terraform plan     # revisar qué cambiará
terraform apply
```

## 2.3 Dentro del servidor

```
/opt/sulotec/                 (root:docker)
├── docker-compose.yml        servicios base: cloudflared, postgres:16, mysql:8.4
├── .env                      claves del túnel y de las bases. NO BORRAR. Nunca a GitHub
├── cuenta.env                claves de Keycloak (lo crea apps/cuenta/preparar.sh)
├── buscador.env              API, IPs de sedes y token de Access del Buscador (apps/buscador/deploy/preparar.sh)
└── scripts/                  backup.sh, new-project-db.sh
/data/                        disco de datos (50 GB)
├── postgres/  mysql/         datos de las bases
└── apps/                     portal/, cuenta/, buscador/  (los copia GitHub)
/opt/actions-runner/          runner de GitHub (usuario github-runner)
/opt/sulotec/buscador-actualizador/   publicador automático del Buscador (llave de solo lectura)
```

**Redes de Docker**
- `sulotec_edge`: contenedores que el túnel de Cloudflare puede alcanzar (`portal`, `cuenta`, `buscador`, `cloudflared`).
- `sulotec_data`: acceso a PostgreSQL y MySQL. **Las bases no publican puertos.**

**Contenedores**

| Contenedor | Imagen | Para qué | Memoria |
|---|---|---|---|
| `cloudflared` | `cloudflare/cloudflared` | Túnel saliente hacia Cloudflare | — |
| `postgres` | `postgres:16` | Base de Keycloak (y futuras apps) | — |
| `mysql` | `mysql:8.4` | Para apps MySQL (p. ej. Auditoría de Visitas) | — |
| `portal` | `nginx:stable-alpine` | sulotec.com (solo lectura) | 64 MB |
| `cuenta` | `quay.io/keycloak/keycloak:26.8.0` | cuenta.sulotec.com | 1,5 GB |
| `buscador` | `buscador-web` (construida aquí) | buscadorinterno.sulotec.com (solo lectura) | 512 MB |

**Scripts de referencia** (en [`vm/`](../vm))

| Script | Uso |
|---|---|
| [`bootstrap.sh`](../vm/bootstrap.sh) | Servidor nuevo: Docker, túnel y PostgreSQL |
| [`setup-datos.sh`](../vm/setup-datos.sh) | Disco `/data`, MySQL, OCI CLI y cron de respaldos |
| [`scripts/backup.sh`](../vm/scripts/backup.sh) | Respaldo diario |
| [`scripts/new-project-db.sh`](../vm/scripts/new-project-db.sh) | Crea base + usuario para un proyecto: `sudo /opt/sulotec/scripts/new-project-db.sh <postgres\|mysql> <proyecto>` |
| [`scripts/instalar-runner.sh`](../vm/scripts/instalar-runner.sh) | Instala el runner de GitHub |
| [`templates/`](../templates) | Dockerfiles base para .NET, Spring Boot y SPA |

## 2.4 Acceso al servidor

- **Solo por https://ssh.sulotec.com:** SSH en el navegador, protegido por Cloudflare Access con código al correo y certificados de corta duración. Ver [3. Cloudflare](03-cloudflare.md).
- **Usuarios Linux:** uno por persona (`informaperu2`, `serviciosdigitales`), sin contraseña, con `sudo` y `docker`. No se comparten cuentas.
- **El puerto 22 está cerrado.** El servidor confía en la CA de Cloudflare (`/etc/ssh/ca.pub`, `/etc/ssh/sshd_config.d/60-cloudflare-access.conf`).
- **Emergencia (si Cloudflare falla):**
  1. En Cloud Shell, abre `~/oracle/terraform.tfvars` y pon `ssh_enabled = true` y `admin_cidr = "<tu IP>/32"`.
  2. Corre `terraform apply`.
  3. Entra con la llave de emergencia.
  4. **Vuelve a `false`** al terminar.

## 2.5 Respaldos

- **Cada día a las 02:00** (cron), `backup.sh` hace `pg_dumpall` (PostgreSQL), `mysqldump` (MySQL) y un comprimido de `/data/apps`.
- **Dónde quedan:** 14 días en `/var/backups/sulotec`, y una copia fuera del servidor en el bucket `sulotec-backups`, con versionado.
- **Registro:** `/var/log/sulotec-backup.log`.
- **Pendiente:** prueba de restauración documentada.

## 2.6 Publicación automática (GitHub → servidor)

- **Runner propio** `sulotec-main`:
  - Servicio `actions.runner.Sulotec-Sulotec-infra.sulotec-main`, usuario `github-runner`, etiqueta `sulotec`.
  - Conexión saliente, sin puertos abiertos.
  - Atiende **solo** a `Sulotec/Sulotec-infra`.
- **Workflows:**
  - `portal.yml`: compila Astro y publica en `/data/apps/portal/sitio`.
  - `cuenta.yml`: copia Keycloak, lo reinicia y aplica `ajustar-realm.sh`.
  - `buscador.yml`: copia la operación del Buscador.
- **Buscador:** el servidor **lee** `Sulotec/buscador-interno` cada 2 minutos con una llave de solo lectura (`buscador-actualizador.timer`), construye y publica. Los desarrolladores no tienen acceso al servidor.

## 2.7 Pendiente: correo de salida (OCI Email Delivery)

Hace falta para las invitaciones y la recuperación de contraseñas de cuenta.sulotec.com. Pasos detallados en [`apps/cuenta/README.md`](../apps/cuenta/README.md), Parte 2:
1. Crea el dominio de correo `sulotec.com`.
2. Agrega el **DKIM** (CNAME en Cloudflare) y el **SPF** (TXT en Cloudflare).
3. Crea el remitente aprobado `no-reply@sulotec.com`.
4. Genera las credenciales SMTP (Mi perfil → Tokens y claves).
5. Corre `sudo bash /data/apps/cuenta/preparar.sh` y responde `s`.

Servidor SMTP: `smtp.email.sa-santiago-1.oci.oraclecloud.com:587`.

## 2.8 Operación diaria (comandos útiles)

```bash
docker ps                                   # qué contenedores corren y su salud
docker logs --tail 50 <contenedor>          # registro de una app
cd /opt/sulotec && docker compose ps        # servicios base
sudo tail -f /var/log/sulotec-backup.log    # respaldos
sudo tail -f /var/log/buscador-actualizador.log   # publicaciones del Buscador
df -h /data                                 # espacio del disco de datos
```
