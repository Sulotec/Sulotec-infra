# Sulotec — infraestructura base (Oracle Cloud + Cloudflare)

```
Usuario → Cloudflare (DNS, SSL, WAF, Access) → Cloudflare Tunnel → VM Oracle (ARM, Ubuntu) → Docker
                                                                     ├─ cloudflared
                                                                     ├─ postgres (una BD + usuario por proyecto)
                                                                     └─ un contenedor por app (.NET / Spring Boot / React / Angular)
```

La VM **no abre ningún puerto**: todo el tráfico entra por el túnel de Cloudflare, y la administración también (`https://ssh.sulotec.com`).

## Operación diaria (plataforma ya montada)

- **Entrar al servidor:** https://ssh.sulotec.com → código al correo → usuario `informaperu2` o `serviciosdigitales`.
- **Configuración base:** `/opt/sulotec` (`docker-compose.yml`, `.env`, `scripts/`). Datos en `/data` (disco de 50 GB).
- **Nueva base para un proyecto:** `sudo /opt/sulotec/scripts/new-project-db.sh mysql miproyecto` (o `postgres`).
- **Backups:** automáticos a las 02:00 (`/var/log/sulotec-backup.log`); a mano: `sudo /opt/sulotec/scripts/backup.sh`.
- **Emergencia sin Cloudflare:** en Cloud Shell poner `ssh_enabled = true` y tu IP en `admin_cidr`, `terraform apply`, entrar con la llave de la laptop; luego volver a `false`.
- **Controles de seguridad:** ver `SEGURIDAD-ISO27001.md`.

Las fases de abajo documentan cómo se construyó (y cómo rehacerlo desde cero).

## Carpetas

| Carpeta | Qué es |
|---|---|
| `oracle/` | Terraform: red, VM, bucket de backups, permisos y alertas de costo |
| `vm/` | Lo que se copia a la VM: compose base (túnel + Postgres) y scripts |
| `templates/` | Dockerfiles y compose por tipo de app |

## Fase 1 — Cuenta Oracle (manual, tú)

1. Entra a https://cloud.oracle.com e inicia sesión.
2. **Upgrade a Pay As You Go** (Menú ☰ → Billing → Upgrade and Manage Payment). Sigue siendo gratis mientras no excedas Always Free, y reduce mucho el error "Out of capacity" al crear la VM ARM. Conserva los créditos del trial que te queden. Las alertas de presupuesto de abajo te cuidan de cobros.
3. Anota tu **región home** (arriba a la derecha). No se puede cambiar después.

## Fase 2 — Crear todo en Oracle con Terraform (Cloud Shell)

1. En tu PC (PowerShell), genera una llave SSH si no tienes:
   ```powershell
   ssh-keygen -t ed25519 -f $HOME\.ssh\sulotec_oci
   Get-Content $HOME\.ssh\sulotec_oci.pub
   ```
2. Averigua tu IP pública en https://ifconfig.me (se pone con `/32`).
3. Comprime la carpeta `oracle/` en un zip.
4. En la consola de Oracle abre **Cloud Shell** (icono `>_` arriba a la derecha) → ⚙ Upload → sube el zip.
5. En Cloud Shell:
   ```bash
   unzip -o sulotec-oracle.zip && cd oracle
   export TF_VAR_tenancy_ocid=$OCI_TENANCY TF_VAR_compartment_ocid=$OCI_TENANCY TF_VAR_region=$OCI_REGION
   echo $TF_VAR_tenancy_ocid $TF_VAR_region   # deben salir "ocid1.tenancy..." y "sa-santiago-1"
   terraform init
   terraform plan
   terraform apply
   ```
6. Si `apply` falla con **Out of host capacity**, reintenta cada minuto:
   ```bash
   until terraform apply -auto-approve; do sleep 60; done
   ```
7. Al terminar muestra `public_ip`. Espera ~3 minutos a que cloud-init instale Docker.

## Fase 3 — Entrar a la VM y subir los archivos

```powershell
ssh -i $HOME\.ssh\sulotec_oci ubuntu@<IP>
# dentro de la VM:
cloud-init status --wait ; ls /opt/sulotec/.cloud-init-ok ; docker --version
```

**Forma recomendada (sin copiar archivos):** pega el contenido de `vm/bootstrap.sh` en la VM como `~/bootstrap.sh` y ejecuta `bash ~/bootstrap.sh`. Escribe el compose y los scripts en `/opt/sulotec`, te pide el token del túnel (Fase 4) sin mostrarlo, genera la clave de Postgres y levanta todo. Con eso te saltas el resto de esta fase y el paso 4 de la Fase 4.

Alternativa manual: desde tu PC copia la carpeta `vm/`:
```powershell
scp -i $HOME\.ssh\sulotec_oci -r .\vm\* ubuntu@<IP>:/opt/sulotec/
```

## Fase 4 — Cloudflare Tunnel

1. Cloudflare → **Zero Trust** (te pide elegir un nombre de equipo y plan Free; puede pedir tarjeta solo para verificar).
2. **Networks → Tunnels → Create a tunnel → Cloudflared**. Nombre: `sulotec-oci`.
3. Elige la pestaña **Docker** y copia solo el token (el texto largo que empieza con `eyJ`).
4. En la VM:
   ```bash
   cd /opt/sulotec
   cp .env.example .env
   chmod +x scripts/*.sh
   nano .env        # pega CF_TUNNEL_TOKEN y genera POSTGRES_PASSWORD con: openssl rand -base64 24 | tr -dc 'A-Za-z0-9'
   docker compose up -d
   ```
5. El túnel debe quedar **HEALTHY** en Cloudflare.

## Fase 5 — Primer proyecto (ejemplo: AFACOP)

1. Base de datos propia:
   ```bash
   ./scripts/new-project-db.sh afacop      # guarda la cadena de conexión que imprime
   ```
2. Copia el código del proyecto a `/opt/apps/afacop/{web,api}`, pon el Dockerfile de `templates/` que corresponda y `templates/app-compose.yml` como `docker-compose.yml`. Crea `.env` con `DB_CONN=...`.
3. `docker compose up -d --build`
4. En el túnel → **Public Hostname** → Add:
   - `afacop.sulotec.com` → `http://afacop-web:80`
   - `api-afacop.sulotec.com` → `http://afacop-api:8080`

   Cloudflare crea el DNS solo. Usa nombres de **un solo nivel** (`api-afacop.sulotec.com`, no `api.afacop.sulotec.com`): el SSL gratis solo cubre un nivel.
5. Repite para Caja Huancayo, Compartamos y lavado de activos.

## Fase 6 — Seguridad y respaldo

- **Cloudflare Access:** Zero Trust → Access → Applications → protege paneles admin y entornos de prueba con login por correo + 2FA.
- **Backups:** `crontab -e` y agrega
  `0 2 * * * /opt/sulotec/scripts/backup-postgres.sh >> /opt/backups/backup.log 2>&1`
  Para subirlos al bucket, instala OCI CLI en la VM (`bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"`). Usa permisos de la propia VM, sin llaves.
- **Probar la restauración** una vez antes de tener clientes reales.

## Notas

- **SQL Server no corre en ARM.** Si alguna app .NET usa SQL Server, hay que migrarla a PostgreSQL (Npgsql) o usar una VM x86 de pago.
- Para clientes financieros (Caja Huancayo, Compartamos, lavado de activos) la capa gratuita no tiene SLA: sirve para desarrollo y pilotos; para producción con datos reales conviene VM de pago, backups probados y revisar los requisitos del cliente y la Ley 29733.
- Todos los proyectos comparten las redes `sulotec_edge` y `sulotec_data`. Si algún cliente exige aislamiento fuerte, se crea una red por proyecto.
