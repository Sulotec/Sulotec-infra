# Sulotec — contexto del ecosistema (para continuar en otro chat)

> **Actualizado: 2026-10-18.** Léelo completo antes de actuar. Si algo de aquí contradice lo que ves en el servidor o en el código, **manda lo que ves**: corrige este archivo en el mismo commit.
>
> **Para un chat nuevo:** pega o adjunta este archivo y di *"Continúa desde donde quedamos"*. Para bajarlo:
> `gh api repos/Sulotec/Sulotec-infra/contents/CONTEXTO-PARA-OTRO-CHAT.md -H "Accept: application/vnd.github.raw"`
>
> Aquí **nunca** van contraseñas, tokens ni datos personales. Los secretos viven solo en el servidor (`/opt/sulotec/*.env`) y en el gestor de contraseñas de la empresa.
> Este proyecto es de **Sulotec / Informa Perú**. No tiene relación con proyectos personales del usuario (por ejemplo, la pizzería): no mezclar.
>
> Lo que no se pudo comprobar está marcado como **(por confirmar)**. La bitácora original (decisiones y avances día a día) está en [`docs/historico/`](docs/historico/bitacora-2026-10-06-al-14.md).

## 0. En 60 segundos

- **Sulotec** es el ecosistema SaaS de soluciones digitales de Informa Perú, en `sulotec.com`: un **portal** público (demos + cuentas) y **productos** en subdominios propios.
- Todo corre en **una VM de Oracle Cloud** (ARM, Santiago de Chile) detrás de **Cloudflare** (túnel; la VM no abre ningún puerto). Nada depende de una PC.
- **Productos hoy:** MiRadar 360 (en producción, ya en Oracle), PLAFT (prevención de lavado de activos; corre en Oracle con datos de prueba, sin clientes reales todavía), Buscador Interno (privado; la web está en Oracle y la API en la oficina) y Auditoría de Visitas / Caja Huancayo (plantilla multiempresa «Authentication Work»; **en Oracle desde el 2026-10-18** en `auditoria.sulotec.com` y `api-auditoria.sulotec.com`, kit `apps/auditoria/`; falta apagar Render y Aiven) y Dashboard Empresarial (dashboards de Power BI por empresa de Informa Perú; **en Oracle desde el 2026-10-18 con los datos reales cargados** (`dashboards.sulotec.com`; al cierre solo faltaba corregir en Cloudflare el servicio de la ruta de la API), §4.6) y **Sistema de Planillas** (planilla mensual peruana de uso interno de Informa Perú; **en Oracle desde el 2026-10-21** en `planilla.sulotec.com`, kit `apps/planilla/`; falta poner Cloudflare Access delante, §4.7).
- **Cada producto = un kit en `apps/<producto>/`** de este repositorio (compose + scripts) **+ su código en repositorios de GitHub.** MiRadar, PLAFT y Auditoría se publican con `desplegar.sh` en el servidor (construye desde `main` y vuelve a la versión anterior si algo falla); el portal, las cuentas y el Buscador, por workflow o por *pull* (§5).
- **Seguridad:** buena base (túnel sin puertos, Access, respaldos con restauración probada, claves de bases rotadas el 2026-10-14), pero con **brechas conocidas** (§9): repositorios públicos, 2FA pendiente y cuentas de prueba aún activas en PLAFT (la separación entre empresas ya la hace cumplir el backend desde el 2026-10-18).
- **El usuario no es especialista en infraestructura:** pasos cortos, comandos completos y listos para copiar, español simple (§2).

## 1. Qué queremos lograr (el ecosistema SaaS)

### 1.1 Visión

Un **SaaS propio con marca Sulotec**, para ofrecer a empresas —en especial del sector financiero (Caja Huancayo, Compartamos y entidades supervisadas por la SBS)— soluciones de **trabajo en campo, cumplimiento normativo y consulta de información**, operadas desde una infraestructura **propia, segura, barata y reproducible**.

### 1.2 Principios (lo que hace que todo encaje)

1. **Una sola puerta.** `sulotec.com` es el portal: demos públicas con datos ficticios, cuentas de personas y "Mis productos" según el rol. Los productos viven en subdominios de **un solo nivel** (`plaft.sulotec.com`, no `app.plaft.sulotec.com`).
2. **Un producto = un contenedor (o un grupo pequeño), su base y su bucket.** Bases separadas en servidores compartidos (PostgreSQL 16 y MySQL 8.4); archivos en buckets privados con llave propia.
3. **Nada expuesto.** Sin puertos abiertos: todo entra por el túnel de Cloudflare. Lo privado lleva Cloudflare Access **y** su propia validación dentro de la app (defensa en profundidad).
4. **Mínimo privilegio.** Cada persona y cada servicio ve solo lo que necesita (por ejemplo, el CEO entra al Buscador pero no al servidor).
5. **Multiempresa.** Cada cliente ve solo lo suyo y cada producto es una plantilla que se adapta a otros clientes (reglas y modelo en §1.3). En PLAFT ya existe la lista de empresas y cada cuenta pertenece a una.
6. **Reproducible y sin depender de una PC.** Terraform para Oracle, scripts idempotentes para el servidor, kits por producto, despliegues con vuelta atrás, secretos solo en el servidor y en el gestor.
7. **Cumplimiento.** Alineado a ISO/IEC 27001 (Anexo A), Ley 29733 (datos personales) y requisitos de la SBS. Los datos están en Santiago de Chile: validar con legal el flujo transfronterizo antes de cargar datos reales de clientes.
8. **Costo bajo control.** Todo dentro de *Always Free* (hoy US$ 0/mes), con presupuesto aprobado de hasta US$ 260/mes **solo si hace falta**.

### 1.3 Cada producto es una plantilla multiempresa (decidido por el usuario, 2026-10-17)

**Idea:** cada producto (MiRadar, PLAFT, Buscador, Auditoría de Visitas…) es una **plantilla de Sulotec**, adaptable, que se puede **entregar a otras cajas y negocios**. Sulotec la **aloja** y la modifica para cada cliente. Los productos propios (MiRadar, PLAFT y el Buscador) se hicieron primero para un solo cliente y **no a esa escala** (multiempresa y modificables); la app de Caja Huancayo es la primera que conviene diseñar así desde el inicio. Esto **aplica a todos los productos**.

- **Jerarquía:** Sulotec (**Administrador Universal**) → producto → **cliente** (una caja o negocio: un *tenant*) → usuarios y roles de ese cliente.
- **Administrador Universal:** rol explícito de Sulotec que ve todos los productos y entra a cada cliente; cada ingreso a un cliente queda **auditado**. Los demás usuarios solo ven lo de su cliente.
- **UUID para identificar** clientes y datos (no números consecutivos): no chocan al migrar ni al crear datos sin conexión (apps móviles) y no se pueden recorrer. **Un UUID no es seguridad:** el aislamiento lo garantiza el servidor.
- **Reglas de oro (obligatorias en todo producto nuevo y en lo que se adapte):**
  1. El cliente (tenant) **sale del token verificado en el servidor, nunca de lo que mande la web o la app** (parámetros, cuerpo o cabeceras).
  2. El filtro por cliente va en **una capa central** (no consulta por consulta); en PostgreSQL, valorar *row-level security* como segunda barrera.
  3. Archivos: prefijo por cliente en el bucket y URLs firmadas de corta vida.
  4. **Pruebas automáticas de acceso cruzado:** una cuenta del cliente A intenta leer, editar y crear datos del cliente B llamando a la API directo; debe fallar siempre. (En PLAFT se comprobó que esto fallaba: §4.3.)
  5. La personalización (nombre, logo, colores, reglas como la geocerca) son **datos por cliente**, no código: una sola base de código sirve a todos.
  6. Caché, sesiones, WebSockets, exportaciones (PDF/Excel) y registros de auditoría también van **por cliente**; cuando el administrador universal cambia de cliente, la web limpia el estado.
  7. **Los clientes no saben unos de otros.** Nadie elige ni ve "qué caja es": **iniciar sesión ya identifica a la empresa** (el usuario pertenece a una sola). Sin selector de empresa para los clientes, sin listas ni nombres de otros clientes en pantallas, API, correos ni errores (solo el Administrador Universal cambia de cliente). Motivo: conflictos de interés entre empresas y reglas de negocio distintas (por ejemplo, proveedores que no comparten).
  8. **Reglas de negocio y personalización por cliente, sin bifurcar el código:** cada empresa tiene sus reglas (flujos, validaciones, catálogos, proveedores, textos, marca). Se modelan como **configuración y extensiones por cliente** (parámetros, catálogos propios, reglas activables, integraciones por cliente) sobre una sola base de código; lo que de verdad sea distinto se aísla en módulos por cliente. Meta: ser SaaS y a la vez adaptarse a cada empresa.
- **Propuesta de implementación (por confirmar con el usuario):** una **instalación compartida por producto** con `tenant_id` (UUID) en cada tabla, y la opción de una **instalación dedicada** (misma plantilla, otra base y otro subdominio) para clientes que la exijan (por ejemplo por la SBS); **Keycloak** como identidad única, con el `tenant_id` y los roles (`administrador-universal`, `administrador-cliente`…) dentro del token; y un **registro central de clientes** (UUID, nombre, productos contratados, configuración).
- **Estado a 2026-10-18:** ningún producto lo cumple del todo. PLAFT: la separación por empresa pasó a aplicarse en el backend (PR del 2026-10-17, ver §4.3) pero usa id numérico, no UUID; Caja Huancayo: **lo cumple desde el 2026-10-18** (tabla `empresas` con UUID, `empresa_id` en todas las tablas, filtro central en Prisma, rol UNIVERSAL con cambio de empresa auditado, pruebas de acceso cruzado, marca y reglas por empresa como datos; §4.5); MiRadar y el Buscador se usan hoy con un solo cliente. Es el rumbo de todos los proyectos; el orden de adaptación se decide con el usuario.

### 1.4 Cómo se ve "terminado" (camino propuesto; no todo está decidido por el usuario)

- **Orden acordado el 2026-10-22 (reunión sobre el esquema del ecosistema):** 1) capa de cuentas en Sulotec (Keycloak con un grupo por cliente con su UUID y roles `producto-*` para todos los productos; portal "Mis productos" con el catálogo completo: "Abrir" si está contratado, "Solicitar" si no); 2) enchufar los productos al inicio único copiando el patrón de Auditoría (`/api/auth/sso`), primero PLAFT y Dashboard; 3) MiRadar pasa a multiempresa antes de enchufarlo. Indira queda fuera de este plan (es parte de PLAFT; ver §4.3).

- Todos los productos en Oracle, bajo sus subdominios, con **Render, Vercel, Aiven y Backblaze apagados**.
- **Cuentas con inicio de sesión único** (Keycloak) también dentro de los productos (hoy el portal usa Keycloak y cada producto tiene sus propias cuentas).
- Cada backend **hace cumplir** la separación por empresa (no solo la web), con el modelo multiempresa de §1.3 (clientes con UUID y Administrador Universal).
- 2FA/MFA en todo, repositorios privados, claves rotadas y guardadas, monitoreo y alertas, migraciones de base versionadas, pruebas separadas de producción y, con clientes reales, una VM de pago con SLA.

## 2. Cómo se trabaja con el usuario (reglas para cualquier chat)

**Estilo**
- **Español simple y coloquial.** Respuestas **cortas**: qué cambió, qué tiene que hacer él, comandos listos. Sin resúmenes técnicos largos.
- No es especialista en infraestructura: explica el porqué de cada paso. Suele pedir algo grande en una frase y espera que lo resuelvas con criterio.
- **Verifica de verdad y di con franqueza lo que no pudiste probar.** Pero **no gastes tokens en rondas de pruebas** ("no entres en bucle"): una comprobación proporcional por cambio; pregunta antes de una tanda larga. Sugiérele un chat nuevo cuando el actual sea muy largo (este archivo y la memoria conservan el contexto).
- Si dice **"espera"** o pregunta por otra alternativa: **para y contesta la pregunta** (comparación corta, recomendación, y si seguimos) antes de ejecutar nada más.

**Comandos y scripts**
- Da **archivos y scripts completos con valores reales**, no marcadores ("pégalo tú"): él pega literalmente lo que se le da y no es técnico en PowerShell/JSON. Con cada paso, un comando de verificación que **falle a la vista**.
- Los comandos **del servidor** van en bloques **sin etiqueta de lenguaje** (así no aparece un botón de ejecutar en su PC); los de su PC, con `bash`/`powershell`.
- Los scripts que piden claves muestran un `*` por carácter y "recibido: N caracteres" (un prompt mudo le parece un terminal congelado).
- Antes de tocar archivos de producción, copia `.bak`.

**Git y entregas**
- **Commits sin ninguna atribución a Claude** (ni `Co-Authored-By` ni "Generated with…"), con la cuenta git del usuario, mensajes en español **sin tildes**, añadiendo archivos **por nombre** (nunca `git add -A`).
- `Sulotec-infra`: directo a `main` (se publica solo lo que corresponda). **Repositorios de las aplicaciones** (`Security-*`, `Afacop-*`, etc.): **rama + Pull Request que el usuario une**; no unir ni desplegar sin decirlo.
- Nada de configuración que dependa de su PC. Trabaja desde la **laptop de trabajo**; la PC personal solo sirve de navegador.

**Seguridad**
- **Nunca secretos ni datos personales en chats, repositorios ni documentos.** Si el usuario pega uno, avísale y recuérdale rotarlo (ya lo ha hecho varias veces: está en los pendientes).
- **RENIEC:** no llamar al proveedor real en pruebas (cuota limitada; se usan servidores simulados).
- Las reglas de seguridad impiden que un asistente ponga tokens o integre código ajeno por su cuenta: esos pasos los corre el usuario.

## 3. Mapa de la plataforma

```
                   ┌──────────────────────── Cloudflare ────────────────────────┐
Personas ─HTTPS──▶ │ DNS · HTTPS · WAF · Access (quién entra) · Túnel "sulotec"  │
                   └───────────────┬────────────────────────────────────────────┘
                                   │ conexión SALIENTE desde la VM (sin puertos abiertos)
        ┌────────────── VM Oracle "sulotec-main" (ARM · Ubuntu · Docker) ───────────────┐
        │ red sulotec_edge:  cloudflared · portal · cuenta(Keycloak) · buscador          │
        │                    miradar-web/api · plaft-web/api · auditoria-web/api         │
        │ red sulotec_data:  postgres 16 · mysql 8.4   (sin puertos publicados)          │
        │ red ia (PLAFT):    plaft-ml ◀──▶ plaft-ollama   (sin ruta pública)             │
        └──────────────┬───────────────────────────────────────────────┬────────────────┘
                       │ Object Storage (privado): backups, archivos    │ API del Buscador
                       ▼                                                ▼ (por ahora Tailscale Funnel)
              buckets de Oracle                          Servidor de la oficina (Windows): API .NET + SQL Server
```

### 3.1 Oracle Cloud (detalle en [`docs/02-oracle-cloud.md`](docs/02-oracle-cloud.md))

| Dato | Valor |
|---|---|
| Cuenta | Pay As You Go (con tarjeta) usando solo recursos **Always Free**; costo actual US$ 0 |
| Región | Chile Central (Santiago), `sa-santiago-1` |
| Servidor | `sulotec-main`: `VM.Standard.A1.Flex` (**ARM**), 4 OCPU, 24 GB, Ubuntu 24.04; disco de arranque 150 GB |
| Datos | Disco `sulotec-data` de 50 GB montado en **`/data`** (bases, apps, respaldos); se puede conectar a otra VM |
| Red | VCN `sulotec-vcn`; **puerto 22 cerrado** (`ssh_enabled = false`); la IP pública no sirve servicios |
| Infraestructura como código | `oracle/` (Terraform). **El estado vive en el Cloud Shell de Oracle**, no en una PC |
| Acceso al servidor | Solo por **https://ssh.sulotec.com** (SSH en el navegador, Cloudflare Access, certificados cortos); un usuario Linux por persona, sin contraseña, con `sudo` y `docker` |
| Emergencia (si falla Cloudflare) | En Cloud Shell: `ssh_enabled = true` + `admin_cidr` = tu IP, `terraform apply`; volver a `false` al terminar |
| Correo de salida | OCI Email Delivery con el dominio `sulotec.com` (DKIM y SPF activos), remitente `no-reply@sulotec.com`. Funciona para el Buscador; para las invitaciones de Keycloak **(por confirmar)** |

### 3.2 Cloudflare (detalle en [`docs/03-cloudflare.md`](docs/03-cloudflare.md))

- DNS de `sulotec.com`, **HTTPS obligatorio**, TLS ≥ 1.2, plan Free. Cloudflare **corta las peticiones que pasan de 100 s**.
- **Túnel `sulotec`:** conector `cloudflared` (contenedor). Cada subdominio se enruta a un contenedor por nombre (`http://<contenedor>:<puerto>`).
- **Zero Trust / Access** (Free): ingreso con código al correo. Aplicaciones protegidas: el servidor SSH (`Administradores`), el Buscador (`Administradores Generales`; sedes por IP) y `/admin` de cuentas (`Equipo de cuentas`).
- Subdominios de **un solo nivel**: el certificado gratuito solo cubre ese nivel.

### 3.3 El servidor por dentro (detalle en [`docs/02-oracle-cloud.md`](docs/02-oracle-cloud.md) §2.3)

| Ruta | Qué hay |
|---|---|
| `/opt/sulotec/` (root:docker) | `docker-compose.yml` base (cloudflared, postgres, mysql), `.env` (**no borrar**), `scripts/`; un `<producto>.env` por producto (`cuenta.env`, `buscador.env`, `miradar.env`, `plaft.env`, `plaft-ml.env`, `auditoria.env`, `dashboard.env`, `planilla.env`) |
| `/data/` | `postgres/`, `mysql/` (datos de las bases), `apps/<producto>/` (kits y compose), `backups/` |
| `/var/backups/sulotec/` | Respaldos locales de 14 días y los que hacen los scripts antes de escribir datos |
| `/opt/actions-runner/` | Runner de GitHub Actions (usuario `github-runner`); atiende **solo** a `Sulotec-infra` |

**Contenedores**

| Contenedor | Para qué | Notas |
|---|---|---|
| `cloudflared` | Túnel a Cloudflare | token en `/opt/sulotec/.env` |
| `postgres` (16) · `mysql` (8.4) | Bases compartidas | solo red `sulotec_data` |
| `portal` | sulotec.com (nginx, Astro estático) | |
| `cuenta` | Keycloak 26.8 (cuenta.sulotec.com) | 1,5 GB |
| `buscador` | Web del Buscador Interno (Next.js) | solo lectura, 512 MB |
| `miradar-api` · `miradar-web` | MiRadar 360 (Node 24 + Socket.IO · nginx) | |
| `auditoria-api` · `auditoria-web` | Auditoría de Visitas (Node 24 + Socket.IO · nginx) | plantilla multiempresa; en producción desde el 2026-10-18 (§4.5) |
| `dashboard-api` · `dashboard-web` | Dashboard Empresarial (NestJS · Next.js) | corriendo desde el 2026-10-18, con los datos reales (§4.6) |
| `planilla` | Sistema de Planillas de Informa Perú (Spring Boot 17 + Angular 21 en **un solo** contenedor) | corriendo desde el 2026-10-21 (§4.7); solo lectura, 1 GB, sin privilegios |
| `plaft-api` · `plaft-web` | PLAFT (Spring Boot · Next.js) | memoria limitada, solo lectura, sin privilegios |
| `plaft-ml` · `plaft-ollama` | IA de PLAFT (FastAPI · Ollama con `qwen2.5:7b`) | opcionales, red `ia`, sin ruta pública |

**Bases de datos**

| Motor | Base | De quién |
|---|---|---|
| PostgreSQL 16 | `keycloak` · `miradar` · `plaft_ml` · `dashboard` | cuentas del portal · MiRadar · IA de PLAFT · Dashboard Empresarial (por crear) |
| MySQL 8.4 | `plaft` · `aiven_*` · `auditoria` · `planilla` | PLAFT · copias **temporales** de la base de desarrollo de PLAFT (restauradas el 2026-10-15) · Auditoría de Visitas · Sistema de Planillas (creada el 2026-10-21) |
| SQL Server | (en la oficina) | Buscador Interno; **no corre en ARM** |

**Buckets de Object Storage** (privados, con versionado; los de producto con llave propia en el Vault): `sulotec-backups` (respaldos diarios y `externos/…`), `sulotec-archivos`, `miradar-archivos`, `plaft-archivos` y `huancayo-archivos`. Cada servicio usa **su propia identidad** (p. ej. `svc-miradar`, `svc-plaft`, `svc-auditoria`) con permiso solo sobre su bucket.

### 3.4 Dominios y rutas del túnel

| Dirección | Va a | Quién entra |
|---|---|---|
| `sulotec.com`, `www` | `portal:80` | público |
| `ssh.sulotec.com` | SSH de la VM | Access: administradores |
| `cuenta.sulotec.com` | `cuenta:8080` | público (la consola `/admin` tras Access) |
| `buscadorinterno.sulotec.com` | `buscador:3000` | Access + regla de sedes |
| `miradar360.sulotec.com` · `api-miradar360.sulotec.com` | `miradar-web:8080` · `miradar-api:4000` | público (cuentas propias de MiRadar) |
| `plaft.sulotec.com` · `api-plaft.sulotec.com` | `plaft-web:3000` · `plaft-api:8081` | público (cuentas propias de PLAFT) |
| `auditoria.sulotec.com` · `api-auditoria.sulotec.com` | `auditoria-web:8080` · `auditoria-api:4100` | público (cuentas propias de Auditoría; cada una pertenece a una empresa) |
| `dashboards.sulotec.com` · `api-dashboards.sulotec.com` | `dashboard-web:3000` · `dashboard-api:3100` | público (cuentas propias de Dashboard Empresarial) |
| `planilla.sulotec.com` | `planilla:8080` (pantalla, API y WebSocket en la misma dirección) | cuentas propias del sistema; **Access pendiente** (recomendado: son sueldos; equipo de RR.HH./Contabilidad) |

### 3.5 Identidad: quién es quién

| Capa | Dónde | Para qué |
|---|---|---|
| **Cloudflare Access** | Delante de lo sensible (SSH, `/admin`, Buscador) | Primera puerta: correo verificado con código, o IP de sede |
| **Keycloak** (`cuenta.sulotec.com`) | Portal: demos y "Mis productos" | **SaaS sin registro libre:** el equipo crea las cuentas; recuperación de contraseña sí. Rol `administrador-general` |
| **Cuentas propias de cada producto** | MiRadar (PostgreSQL), PLAFT (MySQL), Buscador (SQL Server de la oficina), Auditoría (MySQL) | Hoy no comparten identidad con Keycloak (el inicio único es un objetivo, §1.3). **Auditoría de Visitas ya acepta la cuenta Sulotec** (2026-10-18): desde `/mis-productos`, «Abrir» lleva a `auditoria.sulotec.com/sso`; el panel canjea el código con Keycloak (cliente `auditoria`, PKCE) y ubica al usuario local **por correo** (el rol y la empresa salen de la base de Auditoría, nunca del token). Quién tiene contratado qué: rol `producto-<clave>` de Keycloak (grupos «Clientes - …»); sin el rol, el portal muestra el producto en gris. Lo crea `apps/cuenta/ajustar-realm.sh` |

### 3.6 Respaldos y secretos (resumen)

- **Respaldos:** diarios a las 02:00 (`pg_dumpall` + `mysqldump` + `/data/apps`), 14 días en el servidor y copia en el bucket `sulotec-backups`. **Restauración probada el 2026-10-14** (`vm/scripts/probar-restauracion.sh --desde-bucket`; repetir cada trimestre).
- **Los `*.env` de `/opt/sulotec` NO entran en el respaldo.** Lo imprescindible (p. ej. `MFA_ENCRYPTION_KEY` de MiRadar, que **no se rota**) debe estar también en el gestor. Inventario **sin valores**: [`docs/05-inventario-de-claves.md`](docs/05-inventario-de-claves.md).
- **Rotación:** `sudo /opt/sulotec/scripts/rotar-claves.sh` (bases) y `apps/miradar/deploy/rotar-s3.sh` (clave S3). Rotadas el 2026-10-14.
- Controles ISO 27001 y brechas: [`SEGURIDAD-ISO27001.md`](SEGURIDAD-ISO27001.md).

## 4. Productos (estado a 2026-10-17)

### 4.1 Portal y cuentas (`apps/portal`, `apps/cuenta`)
- **Portal** (Astro): textos en `apps/portal/src/data/` (`sitio.ts`, `soluciones.ts`, `demos.ts`). **Demos públicas** (`/demo/miradar360`, `/demo/auditoria`, `/demo/plaft`) **solo con datos ficticios** (los datos personales están prohibidos): sin sesión hay 2 minutos y luego se pide iniciar sesión o solicitar acceso. **"Mis productos"** (`/mis-productos`): los *Administradores Generales* ven todo (incluido el Buscador); los demás, las demos.
- **Cuentas** (Keycloak, realm `sulotec`): sin registro libre; contraseña de 10+ caracteres, bloqueo tras 5 intentos, sesión de 30 min sin uso (máx. 8 h); OTP al crear cada cuenta. Se publica con el workflow `cuenta.yml`.
- **Pendiente:** reemplazar el administrador temporal de Keycloak por uno con nombre propio + OTP; confirmar el correo de invitaciones/recuperación; Email Routing de `contacto@sulotec.com` (hoy los correos de "Solicitar acceso" rebotan).

### 4.2 MiRadar 360 — antes AFACOP (`apps/miradar`)
- **Qué es:** "torre de control" de asesores en campo: rutas, clientes, visitas con GPS, fotos y firmas, mapa y MFA. **En producción.**
- **Código:** `jeliases-informaDev/Afacop-Backend` (Node 24, Socket.IO), `Afacop-FrontEnd` (React) y `App-Afacop` (Expo; se compila con EAS).
- **Corre en Oracle desde el 2026-10-14:** base `miradar` (se copió de la PostgreSQL 18 de Render a la 16 de la VM como SQL en una transacción), fotos y firmas en `miradar-archivos` (copiadas desde Backblaze con las mismas rutas). Las fotos nunca son públicas (URL firmadas de 5 y 10 minutos).
- **Publicar:** `sudo bash /data/apps/miradar/desplegar.sh`. Comprobar: `probar.sh`. Detalle: [`apps/miradar/README.md`](apps/miradar/README.md). **Desarrollo en local** (clonar y levantar backend, web y app; probado el 2026-10-20): [`apps/miradar/DESARROLLO-LOCAL.md`](apps/miradar/DESARROLLO-LOCAL.md).
- **Datos útiles:** en Rutas se asignan **asesores** (no usuarios); el rol ASESOR solo entra por la app móvil; el planificador necesita latitud/longitud del asesor. Las 13 cuentas de testers son MiRadar (ASESOR), no PLAFT.
- **Hecho (2026-10-15/16):** corregida la paginación de asesores (PR #21, desplegado) y selector de ubicación con mapa para el asesor (PR #22, unido; **falta confirmar que corrió `desplegar.sh`**).
- **Trampas:** con datos migrados `INITIAL_ADMIN_PASSWORD` va **vacía** (si no, el arranque cambia la clave del administrador y borra su MFA); `MFA_ENCRYPTION_KEY` debe ser la misma que tenía Render y no se rota; el cliente S3 necesita `forcePathStyle` y `requestChecksumCalculation: WHEN_REQUIRED`.
- **App móvil (a 2026-10-14):** `main` en 1.0.6 (código 9) con la dirección de Oracle; Play Console: prueba interna 1.0.5 y alpha cerrada 1.0.6 en revisión; falta cambiar la URL de privacidad a `https://api-miradar360.sulotec.com/privacidad/radar360`.
- **Pendiente:** que todos los celulares usen la app nueva → apagar **Render y Backblaze** (antes, comparar con `SOLO_COMPARAR=1`); mover la **RRCC-API** fuera de un túnel ngrok gratuito; asesor duplicado "Santos Juarez" (ids 31 y 42).

### 4.3 PLAFT — prevención de lavado de activos (`apps/plaft`)
- **Qué es:** plataforma de cumplimiento PLAFT. Módulos de la web: **Listas Negativas / PEP**, **Canal de Denuncias** (con archivos en `plaft-archivos`), **Scoring de Riesgo**, **Matrices de Riesgo**, **Registro de Operaciones**, **Administración** (empresas y cuentas; solo administradores), Cursos (*próximamente*) e **Indira** (chat de IA acoplado a la derecha).
- **Código** (`jeliases-informaDev`): `Security-Backend` (Kotlin sobre Java 17, Spring Boot 4, MySQL), `Security-FrontEnd` (Next.js 16, React 19, Tailwind 4), `Security-MachineLearning` (FastAPI: casos en prensa, scoring de personas, Indira) y `Security-App` (Expo). El módulo de Operaciones del backend lo desarrolla un compañero (`irubio06dev`).
- **Corre en Oracle:** `plaft-api` → base MySQL `plaft`; `plaft-ml` → base PostgreSQL `plaft_ml`; Indira con **Ollama local (`qwen2.5:7b`)** por privacidad. Rutas: `plaft.sulotec.com` y `api-plaft.sulotec.com`. **Publicado en el portal desde el 2026-10-18** (`publicado: true` en `soluciones.ts`: el botón «Ingresar»/«Abrir» lleva a plaft.sulotec.com).
- **Publicar:** `sudo bash /data/apps/plaft/desplegar.sh` (construye desde `main`; al primer arranque con base nueva apaga solo la "semilla" y borra la clave inicial del archivo). Probar: `probar.sh`. Guía completa de 13 pasos: [`apps/plaft/README.md`](apps/plaft/README.md).
- **Cuentas:** el administrador inicial es `superadmin`; su clave fue **aleatoria**, se mostró **una sola vez** y no se guarda en el servidor: si se perdió, `sudo bash /data/apps/plaft/resetear-clave.sh superadmin`. También pasaron cuentas de desarrollo (`admin001`, `lavado_pru*`, con claves que conoce el equipo de desarrollo).
- **Datos cargados:** listas (colorimetría) y sancionadas SBS desde Excel, figuras políticas con sus casos en prensa, y **toda la base de desarrollo** (decisión del usuario para probar todos los módulos: personas y listas de demostración, consultas, matrices, scoring, denuncias de prueba, 10 operaciones DEMO). **No hay clientes reales todavía;** antes de tenerlos hay que desactivar las cuentas de prueba.
- **Empresas y cuentas (2026-10-16):** `usuarios.empresa` era texto libre; ahora hay una **lista de empresas** (`/api/empresas`), la empresa es **obligatoria** y se elige de la lista al crear una cuenta, y la web trae **Administración** para crear cuentas (con clave generada) y administrar empresas. Operaciones **filtra por la empresa de la cuenta**; sin empresa no se puede usar. (PRs `Security-Backend#25` y `Security-FrontEnd#20`, desplegados.) Documentado en `Security-Backend/docs/EMPRESAS-Y-CUENTAS.md`.
- **Rediseño de la web (2026-10-16):** la raíz va directo al login; estructura común (`PageShell`/`PageHeader`/`Panel`), tipografía IBM Plex, Indira como panel acoplado, módulo de Operaciones (lista, alta/edición, PDF, responsable).
- **Verificado el 2026-10-16** con la web de producción y MySQL 8.4 reales en local: todo lo anterior funciona. **Hallazgo crítico:** el backend del módulo de Operaciones toma la empresa y el usuario de lo que manda la web, así que **la separación por empresa hoy solo la aplica la web, no el servidor** (otra cuenta común podría leer/editar datos de otra empresa llamando a la API directo); `GET /api/usuarios` además devuelve las cuentas de todas las empresas a cualquier cuenta. **Arreglo hecho el 2026-10-17** (PR `Security-Backend` `fix/aislamiento-por-empresa`): `AccesoEmpresaService` toma la empresa y la cuenta del token; una cuenta común siempre trabaja con lo suyo, los registros ajenos responden 404, los registros nuevos quedan a nombre de quien los crea y `GET /api/usuarios` se filtra por empresa; un ADMINISTRADOR puede indicar cualquier empresa. Verificado con MySQL real: 20/20 (los 10 accesos cruzados bloqueados y la cuenta sigue trabajando con lo suyo). **Unido y desplegado el 2026-10-18** (junto con #27 y #28). Sigue pendiente pasar los ids a UUID.
- **Modelo de privacidad completo (2026-10-18, decisión del usuario):** cada cuenta ve lo suyo; el **administrador de la empresa** (rol nuevo `ADMINISTRADOR_EMPRESA`) ve todo lo de su empresa (búsquedas, scoring, matrices, denuncias, operaciones); el **administrador universal** (`ADMINISTRADOR`, Sulotec) ve absolutamente todo. Lo ajeno responde 404. Hecho en el PR `fix/denuncias-por-empresa` de `Security-Backend` (sale del PR #26): `VisibilidadEmpresaService`, `RolesInicializador`, consultas por empresa en scoring/historial/matrices, receptores de denuncias solo de la propia empresa y denuncia no dirigible a otra empresa. Verificado con MySQL real: 17/17 con cuentas de dos empresas. Scoring, matrices e historial ya eran privados por usuario (no filtraban entre empresas); las listas negativas/PEP/sancionadas son referencia común. PLAFT **no** lleva personalización de marca por empresa (el usuario la quiere solo en Huancayo): lo único es el campo empresa y la privacidad.
- **Gestión de cuentas (PR 2, hecho el 2026-10-18; PRs `Security-Backend#28` y `Security-FrontEnd#22`, **unidos y desplegados el 2026-10-18**, backend `48fdd53`, web `9177655`):** empresa con **UUID y sigla** única (propuesta desde el nombre; relleno al arrancar para las existentes); el **usuario interno lleva la sigla delante** (`hcyo.jperez`, único entre empresas; en pantalla se ve el nombre); **inicio de sesión con el correo o el usuario**; **carga masiva** desde Excel/CSV por empresa (revisión fila por fila, creación todo o nada, usuario `sigla.parte-local-del-correo`); **invitaciones por correo** (enlace de 72 h para crear la clave) cuando hay SMTP configurado (`preparar.sh` ya lo pregunta: OCI Email Delivery) y, si no, **claves temporales**; pantallas web de recuperar y crear contraseña; `limpiar-cuentas-prueba.sh` en el kit (simula; `--aplicar` respalda y borra las cuentas de prueba con sus registros, deja `superadmin`). Verificado con MySQL real y la web: 29/30 (la restante fue un falso negativo de la prueba). **No se probó el envío SMTP real** (sin credenciales en local).
- **Para poner en marcha PR 2:** unir #26, #27 y #28 del backend y #22 de la web; actualizar el kit; `preparar.sh` (Enter en todo; opcional: SMTP de OCI); `desplegar.sh`; luego `limpiar-cuentas-prueba.sh --aplicar` si se quiere empezar limpio y cargar las cuentas desde Administración → Cuentas → Carga masiva.
- **Otros hallazgos del código:** `ddl-auto: update` (Hibernate cambia las tablas al arrancar, sin migraciones; conviene Flyway/Liquibase); el login no limita intentos (poner regla de velocidad en Cloudflare); Swagger y `/actuator` (salvo `health`) quedan cerrados por variables.
- **Indira es parte de PLAFT y por ahora solo de PLAFT** (decisión del usuario, 2026-10-22): no se extiende a los demás productos hasta tener resuelta la capa de cuentas y el modelo de clientes; la idea de "un agente por producto" queda anotada para más adelante.
- **IA lenta:** una respuesta de Indira puede tardar ~160 s en CPU y Cloudflare corta a los 100 s. Arreglo de fondo propuesto: chat **asíncrono** (el POST devuelve un id y la web consulta); mientras tanto, un modelo más liviano (`qwen2.5:3b`). Sin responder aún.
- **Cómo compilar y probar el backend desde la laptop de trabajo:** Java directo **no funciona** en el entorno de Claude Code (Gradle falla al abrir sockets locales); se usa **Docker** con la imagen `eclipse-temurin:17-jdk` y un volumen de caché de Gradle. Para pruebas de punta a punta: contenedor `mysql:8.4` + backend (`bootRun`) + la web compilada, manejados con Playwright.

### 4.4 Buscador Interno (`apps/buscador` + repo `Sulotec/buscador-interno`)
- **Qué es:** consulta interna de personas (DNI, RENIEC, teléfono) y empresas (RUC), cargas masivas con historial, y administración de usuarios/roles/tokens/auditoría. **Privado**: no aparece en el portal.
- **Partes:** web nueva (Next.js 16) en un contenedor de Oracle; **API .NET 10** en un **servidor Windows de la oficina** (servicio `BuscadorApi`) con **SQL Server** en la red interna. Hoy la API se alcanza por **Tailscale Funnel**.
- **Publicación:** el servidor **lee** `Sulotec/buscador-interno` cada 2 minutos con una llave de solo lectura y construye (si falla, vuelve a la anterior). Es *pull* a propósito: los desarrolladores externos no tienen acceso al servidor.
- **Acceso:** Cloudflare Access (`Administradores Generales`) + **regla de sedes** (solo desde las IP de Lince y Los Olivos; `ADMIN GENERAL` entra desde cualquier lugar; soporta IPv4/IPv6/CIDR). Cuentas propias del Buscador. Correo con OCI Email Delivery vía MailKit (OCI solo ofrece AUTH PLAIN y `SmtpClient` no lo soporta).
- **Pendiente:** hoy la política temporal `Presentación` de Access deja pasar a todos → cambiarla a las sedes; túnel de Cloudflare en la oficina para la API (y apagar Tailscale Funnel y Vercel); mover el actualizador de la API a `Sulotec/buscador-interno` y replicar allí el MailKit; prefijos IPv6 de las sedes; script `004_menu_operador.sql`; fase 2 (API en TypeScript).

### 4.5 Auditoría de Visitas / Caja Huancayo, Compartamos y otros
- **Auditoría de Visitas** (Caja Huancayo): verifica visitas con geocerca, fotos, firma y trabajo sin conexión. Es la **plantilla multiempresa «Authentication Work»** de Sulotec (§1.3), para entregarla a otras cajas y negocios. Repos `jeliases-informaDev/Huancayo-Backend` (Node 24 `engines` 24.19.x, Express + Prisma 7 + Socket.IO sobre **MySQL 8**; `npm start` = `prisma migrate deploy` + alta de empresa/administrador + servidor; puerto `PORT`, 4100), `CajaHuancayo-Web` (Vite/React; la URL de la API se fija al compilar con `VITE_API_URL`) y `CajaHuancayo-App` (Expo; URL incrustada con `EXPO_PUBLIC_API_URL`; APK con GitHub Actions `apk.yml`, firma de depuración; la de producción en EAS). Tiempo real por Socket.IO (WebSockets por el túnel; con varios procesos haría falta un adaptador compartido). Geocodificación externa apagada por defecto (requiere autorización del banco).
  - **Hecho (2026-10-18, PRs unidos en `main`):** tabla `empresas` (UUID, slug, estado, reglas y marca como datos), `empresa_id` en todas las tablas de datos, filtro central en Prisma (sin contexto de empresa la consulta **falla**, no devuelve todo), empresa tomada del usuario verificado en la base (nunca de la petición), rol `UNIVERSAL` de Sulotec (sin empresa; elige con la cabecera `X-Empresa-Id`, validada y auditada), pruebas automáticas de acceso cruzado (15/15), fotos con prefijo `empresa/<id>/` y **adaptador S3 para Oracle** (`EVIDENCIAS_BACKEND=s3`, `forcePathStyle`, checksums `WHEN_REQUIRED`; probado de punta a punta contra un S3 local con autenticación, no todavía contra el bucket real), ficha Word y política de privacidad por empresa, formatos de importación por empresa (CORE_262 de Caja Huancayo / SIMPLE). Panel: página `/empresas` para el universal, marca por empresa, login genérico «Sulotec · Authentication Work». Además: seguimiento tipo Life360 (llegadas/salidas, batería, movimiento, recorrido), mapas rediseñados y listas paginadas (preparado para escalar).
  - **Kit en Oracle (listo, 2026-10-18):** [`apps/auditoria/`](apps/auditoria/README.md): `docker-compose.yml` (`auditoria-api` :4100 + `auditoria-web` :8080, solo lectura, redes `sulotec_edge`/`sulotec_data`), `preparar.sh` (crea `/opt/sulotec/auditoria.env` y comprueba que entra a la base; variables solo por nombre: `DATABASE_URL JWT_SECRET MFA_ENCRYPTION_KEY INITIAL_ADMIN_USERNAME INITIAL_ADMIN_PASSWORD RESET_INITIAL_ADMIN EMPRESA_INICIAL_NOMBRE INITIAL_UNIVERSAL_USERNAME INITIAL_UNIVERSAL_PASSWORD REQUIRE_MFA MFA_EXEMPT_USERNAMES JWT_* MAX_LOGIN_FAILURES ACCOUNT_LOCK_MINUTES ENFORCE_DEVICE_BINDING FRONTEND_URL CORS_ALLOW_ALL TRUST_PROXY LOG_LEVEL EVIDENCIAS_BACKEND=s3 EVIDENCIAS_BASE_URL S3_ENDPOINT S3_REGION S3_BUCKET S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY S3_FORCE_PATH_STYLE GEOFENCE_RADIO_METROS GEOFENCE_PRECISION_MAXIMA_METROS PERMITIR_AUTOASIGNACION TRACKING_RETENCION_DIAS GEOCODING_WORKER_ENABLED GEOCODING_PROVIDER` + `MAPBOX_ACCESS_TOKEN` opcional), `migrar-datos.sh` (Aiven → MySQL de la VM con `mysqldump`, compara tabla por tabla; `SOLO_COMPARAR=1`), `desplegar.sh` (construye desde `main` con los `Dockerfile` de los repos; el panel con `VITE_API_URL=https://api-auditoria.sulotec.com`; vuelve atrás si falla), `probar.sh` (salud, bucket con `scripts/probar-almacenamiento.js`, rutas públicas, CORS) y `rotar-s3.sh`. Imágenes probadas en la laptop (x64): la API arranca en modo solo lectura y aplica migraciones; el panel lleva la URL nueva.
  - **Corte hecho (2026-10-18, lo corrió el usuario con el README del kit):** usuario de servicio `svc-auditoria` (grupo `grp-storage-auditoria`, política solo sobre `huancayo-archivos`, clave S3 `auditoria-api-1`), base `auditoria`, `/opt/sulotec/auditoria.env`, datos copiados de Aiven (14 tablas iguales; volcado en `/data/backups/auditoria/`), `desplegar.sh` y `probar.sh` **todo en verde** (incluido el bucket real de Oracle), rutas del túnel, portal con `publicado: true`, APK v8 compilado con la API nueva, administrador universal `sulotec.admin` creado (verificación en dos pasos obligatoria). Las fotos de Render no se copiaron (plan gratis sin disco; la tabla `evidencias` estaba vacía). **Falta:** apagar Render (2 servicios) y Aiven tras un `SOLO_COMPARAR=1`, instalar el APK v8 en los celulares y probar en un celular real.
  - **Cierre del 2026-10-18 (todo unido en `main`):** QA completa en verde (todas las suites `api_*` de `C:\CajaHuancayo-QA`; la de geocodificación necesita un segundo servidor en 4102 con el trabajador encendido). **Ficha al 100 %:** medidos los 205 datos que salen de las 262 columnas; el panel y la app («Ver base») muestran todos (antes 172 y 130), el Word reproduce el formato del banco sección por sección (comparado con los tres `muestra.docx`). Limpieza: fuera `render.yaml` de backend y panel y los scripts de arreglo de la demo vieja. La abreviatura sugerida se hace única sola (`pru`, `pru2`…). APK **v9** compilado desde `main` con la API de Sulotec. Nombre de la plantilla confirmado: **«Authentication Work»**.
  - **Inicio único con Sulotec y carga de datos (2026-10-18, PRs #6 de backend y web, unidos y desplegados):** `POST /api/auth/sso` + página `/sso` del panel (ver §3.5; variables `SSO_ISSUER`/`SSO_CLIENT_ID` en `auditoria.env`; el portal y Keycloak se ajustan con `ajustar-realm.sh` y `soluciones.ts` → `acceso`). Carga de expedientes: **plantillas descargables** desde «Cargar expedientes» (`GET /api/expedientes/plantilla?formato=CORE_262|SIMPLE`, con 3 ejemplos y hoja de instrucciones) y `scripts/generar-muestra-completa.mjs` (100 filas inventadas con las 262 columnas completas, Lima y Huancayo con coordenadas; el usuario la carga en el panel).
  - **Abreviatura por empresa (PRs Huancayo-Backend#5 y CajaHuancayo-Web#5, 2026-10-18, unidos):** cada empresa tiene una abreviatura única (`empresas.prefijo`, p. ej. `arq`) que va fija delante de sus nombres de usuario (`arq.jorge`): así no chocan entre empresas y el login sigue identificando a la empresa; se sugiere desde el nombre y el universal la edita; las cuentas existentes no se renombran. En el mismo PR web, el color de la marca por fin tiñe el panel (antes se guardaba pero no se usaba). Idea del usuario; descartada la alternativa de identificar por correo (queda para cuando entre Keycloak).
  - **Trampas:** `MFA_ENCRYPTION_KEY` debe ser la de Render; con datos migrados `INITIAL_ADMIN_PASSWORD` va vacía (si no, el arranque cambia la clave del administrador que nunca entró y le borra el MFA); `ENFORCE_DEVICE_BINDING` no puede ser `false` en producción; `EVIDENCIAS_BACKEND=s3` exige las cinco `S3_*`; Cloudflare corta a los 100 s (la importación de Excel ya corre en segundo plano). `render.yaml` queda en los repos solo como referencia hasta apagar Render.
  - **Personalización por empresa (2026-10-18, reportado por el chat de ese proyecto):** el usuario decidió que entra **después de entregar a Huancayo** (no se empieza hasta que lo pida). Lo que **ya existe**: `Empresa.marca` (JSON: nombre, producto, color, `logo_url` solo https) y `Empresa.configuracion` (radio de geocerca, precisión máxima, formatos de importación), saneados en el servicio; `/api/auth/me` devuelve `empresa.marca` y `empresa.reglas`; solo el rol UNIVERSAL edita la marca. En la web, al entrar `marca.color` tiñe el panel (variables CSS en runtime) y la cabecera muestra nombre y producto; el catálogo de empresas edita color, nombre, prefijo y reglas. El **logo no se muestra ni se sube** (solo URL por API) y la **app Expo no lee la marca** (paleta fija). Plan acordado en concepto, por tandas: 1) logo subible al bucket con prefijo de empresa y versión, color de acento con contraste validado, logo en cabecera, tema dinámico en la app desde `me`, el administrador de cada empresa edita su marca y UNIVERSAL todo, login neutro, prueba cruzada A/B; 2) catálogos propios y plantilla de Excel guardada; 3) extensiones por empresa solo con lógica distinta. Lo "de Huancayo" pasa a ser la configuración del primer tenant.
- **Compartamos:** repo `AppCompartamos`; estado **(por confirmar)**.
- **Fuera del ecosistema por ahora** (no tocar sin que el usuario lo pida): `Sistema-Tickets-TI`, `PlanillaFrontEd` y otros proyectos de Informa Perú de su PC.

### 4.6 Dashboard Empresarial (Informa Perú) (`apps/dashboard`)
- **Qué es:** portal donde las empresas clientes de Informa Perú ven sus dashboards de **Power BI** (y un enlace MEGA) por periodo (mes). Un administrador de Informa crea usuarios, asigna dashboards a cada empresa y agrega periodos; cada usuario de empresa ve solo los dashboards **asignados y activos** de **su** empresa (empresa tomada del token firmado en el servidor). Roles: `1` = administrador, `2` = cliente (con empresa).
- **Código:** `Henry-InformaPeru/dashboard-empresarial-backend` (NestJS 12, TypeORM, arquitectura hexagonal) y `dashboard-empresarial-frontend` (Next.js 16, React 19, Tailwind 4). La web llama a la API con `NEXT_PUBLIC_API_URL`, que se fija **al compilar**.
- **Cambio de base (decisión del usuario, 2026-10-18):** la base original es **SQL Server en el servidor de la oficina** y SQL Server no corre en ARM, así que el backend se pasó a **PostgreSQL 16** de la VM (base `dashboard`, esquemas `seguridad`, `reportes` y `comercial`, mismos nombres y ids; `db/schema.sql` en el repo del backend). Las claves de los usuarios (bcrypt) pasan tal cual: entran con las de siempre. El nombre de usuario sigue sin distinguir mayúsculas.
- **Kit (listo, probado en local con datos ficticios):** [`apps/dashboard/`](apps/dashboard/README.md) con `docker-compose.yml` (`dashboard-api` :3100 y `dashboard-web` :3000), `preparar.sh`, `desplegar.sh`, `importar-datos.sh`, `crear-admin.sh`, `probar.sh` y `herramientas/exportar-sqlserver.ps1`. Direcciones: `dashboards.sulotec.com` y `api-dashboards.sulotec.com`.
- **Migración de datos:** un script de PowerShell (solo `SELECT`, sin dependencias) se corre en la oficina, genera un `.sql` con todo y su huella SHA256; se sube a `sulotec-backups/externos/dashboard/` y `importar-datos.sh` lo carga en una sola transacción comprobando los totales fila por fila. El `.sql` tiene datos personales: se borra del bucket y de la PC al terminar.
- **En el servidor (2026-10-18):** instalado con `apps/dashboard/deploy/instalar.sh` desde las ramas `feature/oracle-postgres` y `feature/oracle-docker`; los PR (`dashboard-empresarial-backend#5` y `dashboard-empresarial-frontend#3`) se unieron el mismo día y **hoy el backend corre desde `main` y la web desde un código que ya está en `main`** (PR `dashboard-empresarial-frontend#4` y `#5`, unidos: módulo «Reportes y Periodos» del administrador con el Power BI embebido, página 404 con la marca y **web responsive para celular**: menú cajón, tarjetas en vez de tablas). **PR `#6` unido (2026-10-19)**: visor de reportes que se ajusta entero y centrado (Power BI «Publicar en la web» se ajusta al tamaño que tiene al cargar y no se reajusta solo, por eso el visor recarga el reporte cuando cambia el tamaño), pantalla completa que funciona y menú lateral ocultable en escritorio. **Unidos en `main` pero SIN publicar en el servidor (2026-10-19; hace falta correr `desplegar.sh`):** web `#7` (periodos en un listado desplegable), web `#8` + backend `#6` (gestión de usuarios del administrador: cambiar contraseña con generador de clave segura —`PATCH /usuarios/:id/password`—, eliminar —`DELETE /usuarios/:id`— y crear; un administrador no puede desactivarse ni eliminarse a sí mismo; probado con PostgreSQL real, 19 comprobaciones); y web `#9` (pendiente de unir: botón Descargar junto al periodo y cambiar de periodo sin recargar el reporte; muchos periodos comparten el mismo enlace de Power BI y solo cambia la descarga); después `sudo bash /data/apps/dashboard/desplegar.sh` (`desplegar.sh`; incluye lo nuevo de Henry: crear empresas y usuarios, pantalla de usuarios y de periodos; probado en local con PostgreSQL); base `dashboard` creada, contenedores `dashboard-api` y `dashboard-web` sanos, tablas vacías, `probar.sh` en verde salvo las direcciones públicas. **Datos cargados el 2026-10-18** desde `DashboardDB` (SQL Server de la oficina, 192.168.1.17): 9 empresas, 15 usuarios (+ el administrador `admin.sulotec` creado con `crear-admin.sh`), 10 dashboards, 18 periodos, 9 asignaciones; los 3 usuarios con rol vacío están inactivos. Rutas del túnel creadas por el usuario; **la ruta de la API debe apuntar a `http://dashboard-api:3100`** (al cierre tenía un typo `dashboards-api` y daba 502). Quedan datos de prueba copiados (`EMPRESA_TEST_DESARROLLO`, `Prueba1`, `Prueba2`, `usuario_test_desarrollo`, `henry`).
- **Probado (2026-10-18, en la laptop, base y datos ficticios, contra SQL Server Express real):** exportador, carga, 29 comprobaciones de la API (login sin distinguir mayúsculas, usuario inactivo, un cliente no ve lo de otra empresa, escrituras, CORS) y la web en modo solo lectura. **No probado:** el bucket, la ruta de Cloudflare ni el SQL Server real de la oficina.
- **Pendiente:** revisar con el administrador; página 404 con la marca (la de Next sale negra); **cambiar las claves de SQL Server (`jeliases` y `Userapi`) que se pegaron en un chat**, borrar el `.sql` del bucket `sulotec-backups/externos/dashboard/` y de las PC, y apagar el origen cuando se confirme todo; regla de límite de velocidad en Cloudflare para `/auth/login`; desactivar las cuentas de prueba; `rotar-claves.sh` aún no conoce este proyecto; los datos son reales: validar con legal el flujo transfronterizo (Santiago de Chile, §1.2).

### 4.7 Sistema de Planillas (Informa Perú) (`apps/planilla`)
- **Qué es:** planilla mensual peruana para uso interno de Informa Perú (RR.HH./Contabilidad): empleados (DNI/CE, carga masiva por Excel), asistencias importadas del reloj marcador y tareo semanal de horarios, tardanzas según el comunicado de la empresa, AFP/ONP (comisión por flujo o mixta), EsSalud, asignación familiar, gratificación, CTS, renta de 5.ª (procedimiento SUNAT), horas extra, bonos, vacaciones, cierre y reapertura de planilla, boletas en PDF con el formato de la boleta de la empresa (y envío por correo opcional), PLAME (Tabla 22), liquidaciones por cese, reportes (bancos y AFPnet provisionales), auditoría de cambios (Envers) y **tiempo real** (WebSocket STOMP). Roles: `ADMIN` (RR.HH.) y `GERENCIA` (solo lectura). Parámetros 2026: RMV S/ 1 230 (D.S. 015-2026-TR), UIT 5 500.
- **Código:** `Jeliases/PlanillaBackend` (Spring Boot 3.2, Java 17, MySQL, JPA `ddl-auto=update`) y `jeliases-informaDev/PlanillaFrontEd` (Angular 21, build estático; en producción llama a la API por ruta relativa, mismo origen). Pruebas unitarias: 49 (cálculos, asistencia, importación, liquidación).
- **Hoy es monoempresa** (RUC y razón social por variables de entorno): no cumple aún el modelo multiempresa de §1.3; si se ofrece a otras empresas hay que añadir el *tenant* en el servidor.
- **En el servidor (2026-10-21):** instalado siguiendo el README del kit (base `planilla` creada con `new-project-db.sh`, `preparar.sh`, `desplegar.sh` desde `main` tras unir `PlanillaBackend#1`/`#2` y `PlanillaFrontEd#1`, `probar.sh` en verde, ruta `planilla.sulotec.com → http://planilla:8080` creada por el usuario). Primer tropiezo: sin SMTP el indicador de salud del correo tumbaba `/actuator/health` (arreglado en `#2`: la salud depende solo de la base). El mismo día se revisaron fórmula por fórmula los Excel reales de la contadora (CTS, gratificación, planilla mensual y quinta 2026) y se implementó lo que faltaba (jornada parcial, pensión «NINGUNO», tardanzas que reducen la base afecta, ingresos no remunerativos, feriado laborado, descuentos varios, promedio de variables en gratificación/CTS, adelanto de quincena y constancias PDF de gratificación y CTS); 56 pruebas, 7 con los números de sus hojas.
- **Kit (instalado el 2026-10-21):** [`apps/planilla/`](apps/planilla/README.md). A diferencia de los otros kits, el `Dockerfile` vive en el kit y construye **una sola imagen** clonando ambos repos (`/data/apps/planilla/backend` y `frontend`): compila Angular, lo copia a `static/` del backend y arma el jar (temurin 17, imágenes multi-arquitectura). Scripts: `preparar.sh` (crea `/opt/sulotec/planilla.env` a partir de la cadena de `new-project-db.sh`, genera `JWT_SECRET` y la clave inicial de `admin`, que muestra una sola vez), `desplegar.sh` (construye, levanta, espera sano, vuelve atrás si falla y borra `ADMIN_PASSWORD` del `.env` cuando ya existe el usuario), `probar.sh` y `resetear-clave.sh` (bcrypt directo en la base). Chequeo de salud: `/actuator/health` (único endpoint de Actuator, sin detalles).
- **Pendiente:** **Cloudflare Access** delante de `planilla.sulotec.com` (datos de sueldos), guardar en el gestor la clave de la base y el `JWT_SECRET` (`mostrar-claves.sh`), crear los usuarios reales, regla de límite de velocidad al login, añadir el proyecto a `rotar-claves.sh`; confirmar con la contadora la **lista B** del README del backend («Pendiente de confirmar con la contadora»: faltas en la gratificación 1/180 vs su promedio en soles, quiénes van a la mitad en gratificación/CTS, horas extras 25/35 vs 25 plano, asignación familiar con faltas, renta de 5ta SUNAT vs 12 cuotas, regla de 3 meses, tardanzas después de las 10:40, códigos PLAME, formatos de banco/AFPnet). La «planilla extra» (sueldo real distinto al declarado) de sus hojas no se implementa.

## 5. Repositorios y cómo se publica cada cosa

> **Hoy todos los repositorios son PÚBLICOS** (los documentos antiguos decían que `Sulotec-infra` era privado; ya no lo es). El servidor clona por HTTPS sin credenciales: pasarlos a privados exige antes **llaves de despliegue de solo lectura** en el servidor (§9).

| Repositorio | Contenido | Cómo se publica |
|---|---|---|
| `Sulotec/Sulotec-infra` | Terraform, scripts del servidor, kits `apps/*`, portal, cuentas y estos documentos | Push a `main`: los workflows (`portal`, `cuenta`, `buscador`) corren en el **runner propio** del servidor. Los kits de MiRadar y PLAFT se copian a mano al servidor (ver §6) |
| `Sulotec/buscador-interno` | Buscador: `web/` y `api/` | El servidor lo **lee** cada 2 min (web). La API de la oficina aún se actualiza desde `jeliases-informaDev/InternalBuscador` |
| `jeliases-informaDev/Afacop-*`, `App-Afacop` | MiRadar 360 | `desplegar.sh` construye desde `main`; la app se compila con EAS |
| `jeliases-informaDev/Security-*` | PLAFT | `desplegar.sh` construye desde `main` |
| `jeliases-informaDev/Huancayo-Backend`, `CajaHuancayo-*` | Auditoría de Visitas | Kit `apps/auditoria`: `desplegar.sh` construye desde `main` (Dockerfiles en los repos); Render hasta el corte. La app Android con el workflow `apk.yml` (o EAS) |
| `Henry-InformaPeru/dashboard-empresarial-backend`, `dashboard-empresarial-frontend` | Dashboard Empresarial | Kit `apps/dashboard`: `desplegar.sh` construye desde `main` (Dockerfiles en los repos); cambios por rama + Pull Request |
| `Jeliases/PlanillaBackend`, `jeliases-informaDev/PlanillaFrontEd` | Sistema de Planillas | Kit `apps/planilla`: `desplegar.sh` clona ambos desde `main` y construye **una** imagen con el `Dockerfile` del kit; cambios por rama + Pull Request |
| `jeliases-informaDev/InternalBuscador`, `internal-search-frontend` | Buscador anterior | Se retiran al mover el actualizador y apagar Vercel |

**Cuentas de GitHub:** `jeliases-informaDev` (cuenta de desarrollo del usuario; es solo lectura en `buscador-interno`), `informaperu2-cmyk` (cuenta de la empresa, dueña de la organización `Sulotec`) y `irubio06dev` (compañero de desarrollo). Los programadores del Buscador tienen rol *Write* en su repositorio; los programadores externos **no** tienen acceso a `Sulotec-infra` (quien escribe ahí controla el servidor).

## 6. Recetas (lo que más se usa)

Los comandos del servidor se corren desde **https://ssh.sulotec.com**.

**Actualizar el kit de un producto en el servidor** (cambia `plaft` por `miradar` o el producto que sea):

```
sudo rm -rf /tmp/sulotec-infra && sudo git clone --depth 1 https://github.com/Sulotec/Sulotec-infra.git /tmp/sulotec-infra && sudo cp /tmp/sulotec-infra/apps/plaft/docker-compose.yml /tmp/sulotec-infra/apps/plaft/deploy/*.sh /data/apps/plaft/
```

| Quiero… | Comando (en el servidor) |
|---|---|
| Publicar PLAFT / MiRadar / Auditoría | `sudo bash /data/apps/plaft/desplegar.sh` · `sudo bash /data/apps/miradar/desplegar.sh` · `sudo bash /data/apps/auditoria/desplegar.sh` |
| Probar un producto | `sudo bash /data/apps/<producto>/probar.sh` |
| Ver registros | `docker logs --tail 50 <contenedor>` (p. ej. `plaft-api`, `miradar-api`) |
| Qué hay corriendo y su salud | `docker ps` |
| Crear base y usuario para un proyecto | `sudo /opt/sulotec/scripts/new-project-db.sh <postgres\|mysql> <proyecto>` |
| Respaldo a mano / probar restauración | `sudo /opt/sulotec/scripts/backup.sh` · `probar-restauracion.sh --desde-bucket` (script de `vm/scripts/` del repositorio) |
| Informe de capacidad (memoria, discos, bases, respaldos) | `estado-capacidad.sh` (script de `vm/scripts/` del repositorio; solo lee) |
| Rotar claves de las bases | `sudo /opt/sulotec/scripts/rotar-claves.sh` |
| Recuperar el acceso de una cuenta de PLAFT | `sudo bash /data/apps/plaft/resetear-clave.sh <usuario>` |
| Dejar empresa a cuentas viejas de PLAFT | `sudo bash /data/apps/plaft/asignar-empresa.sh` |
| Volver a una versión anterior | `docker tag <imagen>:<commit> <imagen>:latest && cd /data/apps/<producto> && docker compose up -d --force-recreate` |

**Sumar un producto nuevo** (receta completa en [`docs/04-integracion-de-proyectos.md`](docs/04-integracion-de-proyectos.md) §4.5): repositorio → base con `new-project-db.sh` → Dockerfile de `templates/` + compose (redes `sulotec_edge` y, si usa base, `sulotec_data`; `container_name`; secretos en `/opt/sulotec/<producto>.env`) → publicación (kit con `desplegar.sh`, o *pull* si hay un equipo externo) → ruta en el túnel (y Access si es privado) → `soluciones.ts` con `publicado: true` → corte (apagar Render/Vercel) → documentar aquí.

## 7. Cronología (resumen)

| Fecha | Qué pasó |
|---|---|
| 2026-10-05/06 | Buscador: la API pasa de la laptop del usuario a un servidor de la oficina (servicio Windows, Funnel). Cloudflare con `sulotec.com`; Terraform en Oracle (la VM da *Out of host capacity*). |
| 2026-10-07 | Upgrade a Pay As You Go: la VM sale al primer intento (4 OCPU/24 GB). Túnel `sulotec`, SSH por Cloudflare Access (puerto 22 cerrado), disco `/data`, PostgreSQL + MySQL, respaldos y Object Storage. |
| 2026-10-08 | Portal sulotec.com con runner propio, demos, Keycloak (cuenta.sulotec.com), Buscador nuevo en Oracle, botón de MiRadar. Decisión: SaaS **sin registro libre**. |
| 2026-10-09 | Buscador separado en `Sulotec/buscador-interno` con publicación *pull*; documentación completa en `docs/`. |
| 2026-10-13 | Correo OCI + MailKit para el Buscador; regla de sedes con IPv6; buckets de producto con llaves en el Vault. |
| 2026-10-14 | **MiRadar migrado a Oracle** (datos de Render, archivos de Backblaze). Ronda de seguridad: claves de bases y S3 rotadas, restauración probada, inventario de claves. **Primer despliegue de PLAFT.** |
| 2026-10-15 | PLAFT: servicio de IA (ML + Ollama/Indira), carga de listas y sancionadas, importación de la base de desarrollo (Aiven) y paso a producción para pruebas. MiRadar: arreglo de asesores y ubicación. |
| 2026-10-16 | PLAFT: raíz directo al login, rediseño, módulo de Operaciones, lista de empresas y pantalla de Administración; prueba de punta a punta con MySQL real y hallazgo de aislamiento entre empresas; `resetear-clave.sh`. Se une el arreglo del límite de largo del login (PR #24). MiRadar: selector de ubicación con mapa (PR #22). |
| 2026-10-17/18 | Caja Huancayo: seguimiento tipo Life360, mapas y listas a escala, **modelo multiempresa** (plantilla «Authentication Work»: empresas con UUID, filtro central en el servidor, administrador universal, pruebas de acceso cruzado), fotos a bucket S3 y **kit `apps/auditoria`** con Dockerfiles. **Auditoría de Visitas migrada a Oracle** (datos de Aiven, bucket `huancayo-archivos`, `auditoria.sulotec.com`), portal publicado, APK v8. |

| 2026-10-18 | **Dashboard Empresarial:** backend pasado de SQL Server a PostgreSQL (SQL Server no corre en ARM), Dockerfiles de API y web, kit `apps/dashboard` con exportador de SQL Server (PowerShell) e importador transaccional; probado en local con datos ficticios. Falta correrlo en Oracle con los datos reales. |

## 8. Decisiones tomadas (y por qué)

1. **Oracle con Pay As You Go dentro de Always Free:** el upgrade era necesario para conseguir capacidad ARM; el costo real es US$ 0 y se fija un tope de US$ 260/mes.
2. **Túnel de Cloudflare y cero puertos abiertos;** SSH por el navegador con certificados cortos: reduce la superficie de ataque y evita llaves permanentes en PCs.
3. **Una base y un usuario por proyecto en servidores compartidos:** ahorra memoria y facilita respaldos y rotaciones.
4. **SaaS sin registro libre, Keycloak, cuentas creadas por el equipo:** control de quién entra; la recuperación de contraseña sí está permitida. Las demos usan solo datos ficticios.
5. **Buscador privado con *pull*:** el runner ejecuta lo que diga un workflow; si los desarrolladores externos tuvieran uno, ejecutarían comandos en el servidor.
6. **Kits `apps/<producto>` con `desplegar.sh` y vuelta atrás;** secretos solo en `/opt/sulotec/*.env`.
7. **PLAFT directo a producción (sin clientes todavía):** base nueva `plaft`, IA en una segunda etapa, archivos de denuncias en un bucket propio con la llave de `svc-plaft` visible **solo** para `plaft-api` (no la identidad de todo el servidor), y la IA sin ruta pública.
8. **PLAFT con toda la base de desarrollo en producción para probar** todos los módulos (riesgo aceptado: desactivar las cuentas de prueba antes de clientes reales).
9. **Indira con modelo local:** privacidad de los datos a cambio de lentitud (CPU).
10. **Empresas como lista administrable** (en vez de texto libre) y empresa obligatoria al crear una cuenta, para que todo funcione desde el inicio.
11. **Entrega de cambios:** commits sin atribución, `Sulotec-infra` a `main`, repos de aplicaciones por Pull Request que une el usuario.

## 9. Pendientes (priorizados)

| Prioridad | Pendiente | Producto |
|---|---|---|
| **Alta** | **Aplicar el modelo multiempresa de §1.3** al resto de productos: Caja Huancayo ya lo cumple (2026-10-18); reforzar PLAFT (ids UUID), luego MiRadar y el Buscador; Keycloak con `tenant_id` sigue como objetivo | Todos |
| **Alta** | Auditoría ya corre en Oracle (2026-10-18): **apagar Render (2 servicios) y Aiven** tras `SOLO_COMPARAR=1 sudo -E bash /data/apps/auditoria/migrar-datos.sh`, borrar sus claves del gestor, instalar el APK v8 en los celulares; unir y desplegar los PRs #5 (abreviatura por empresa y color de marca) | Caja Huancayo |
| **Alta** | PLAFT: configurar el **correo de salida** (SMTP de OCI en `preparar.sh`) y probar el envío real; si se quiere empezar limpio, `limpiar-cuentas-prueba.sh --aplicar` y cargar las cuentas con la carga masiva | PLAFT |
| **Alta** | Pasar los repositorios a **privados** (requiere llaves de despliegue de solo lectura en el servidor) | Todos |
| **Alta** | **2FA** en Gmail, Cloudflare, Oracle y GitHub; **MFA** en las políticas de Access; cambiar la política temporal `Presentación` del Buscador a solo sedes | Plataforma |
| **Alta** | **Rotar** lo que pasó por chats: SMTP, `Jwt:Key` y clave `irubio` del Buscador, tokens de RENIEC y de Vercel, `RRCC_API_KEY`; revisar el resto cada 90 días | Varios |
| **Alta** | Antes de clientes: **desactivar cuentas de prueba** (`admin001`, `lavado_pru*`…), regla de **límite de velocidad** en Cloudflare para el login, política de privacidad y términos, ficha de datos personales (Ley 29733), validar con legal/SBS | PLAFT |
| **Alta** | Indira **asíncrona** (Cloudflare corta a 100 s) | PLAFT |
| **Alta** | **Correr el kit `apps/dashboard`** con los datos reales (exportar el SQL Server de la oficina, subir al bucket, importar, rutas del túnel), unir los PR `feature/oracle-postgres` y `feature/oracle-docker`, regla de límite de velocidad al login y añadir el proyecto a `rotar-claves.sh` | Dashboard Empresarial |
| **Alta** | Planillas ya corre en Oracle (2026-10-21): poner **Cloudflare Access** delante de `planilla.sulotec.com`, guardar en el gestor la clave de la base y el `JWT_SECRET`, crear los usuarios reales y confirmar con la contadora la lista B del README del backend antes de pagar con el sistema | Planillas |
| Media | La prueba gratis de **Aiven vence ~2026-10-18**: ya hay copia como `aiven_*`; apagar y borrar sus claves | PLAFT / MiRadar |
| Media | MiRadar: confirmar el despliegue del selector de mapa; publicar la app 1.0.6; apagar Render y Backblaze; sacar la RRCC-API de ngrok | MiRadar |
| Media | Buscador: túnel de Cloudflare en la oficina (apagar Funnel y Vercel), API desde el repo nuevo, IPv6 de sedes | Buscador |
| Media | Auditoría de Visitas: probar la app en un celular real (ubicación en segundo plano) y el bucket real de Oracle (`probar.sh`); confirmar Compartamos | Caja Huancayo |
| Media | Keycloak: administrador con nombre propio + OTP; correo de invitaciones; `contacto@sulotec.com` | Cuentas |
| Media | Operación: monitoreo externo y alertas; Flyway/Liquibase; CI con pruebas en los repos de aplicaciones; separar pruebas de producción; VM de pago (SLA) con clientes reales | Plataforma |
| Baja | Inicio único (Keycloak) dentro de los productos; Buscador fase 2 (API en TypeScript); prueba de restauración trimestral | Varios |

## 10. Trampas conocidas (lecciones aprendidas)

- **El servidor es ARM:** las imágenes deben ser `linux/arm64` (`eclipse-temurin:*-alpine` no existe para ARM). **SQL Server no corre en ARM.**
- **Next.js:** `NEXT_PUBLIC_*` se fija al **compilar**: si cambia la URL de la API hay que reconstruir la web.
- **bash 5.1 del servidor:** un heredoc dentro de `$(...)` falla aunque `bash -n` pase; con `pipefail`, `grep -q` en una tubería da falsos negativos (redirige a `/dev/null`).
- **Terminal web de Cloudflare:** pegar agrega `^[[200~ … ~`; antes de pegar: `bind 'set enable-bracketed-paste off'`.
- **Oracle S3:** cada usuario admite 2 llaves "customer secret"; tardan en activarse (`rotar-s3.sh` reintenta). El cliente necesita `forcePathStyle` y checksums `WHEN_REQUIRED`.
- **OCI Email Delivery** solo ofrece `AUTH PLAIN`: en .NET usar MailKit.
- **MiRadar:** ver §4.2 (clave del administrador inicial vacía y `MFA_ENCRYPTION_KEY` intocable).
- **Auditoría de Visitas:** las mismas dos trampas de MiRadar (§4.5); `EVIDENCIAS_BACKEND=s3` exige las cinco `S3_*`; en la laptop, `MSYS_NO_PATHCONV=1` también para `--tmpfs /tmp` de Docker.
- **Spring (PLAFT):** `ddl-auto: update` crea tablas nuevas al arrancar; las pruebas de PDF del backend reescriben archivos versionados (`git checkout -- output tmp` antes de commitear); `contextLoads` necesita una MySQL y falla sin ella.
- **En la laptop de trabajo (Windows):** `MSYS_NO_PATHCONV=1` con Docker y rutas en Git Bash; usar `./node_modules/.bin/tsc` y no `npx`; Java directo falla en el entorno de Claude Code (usar Docker).
- **Cloudflare corta a los 100 s:** cualquier endpoint más lento (chat de IA) necesita ser asíncrono.
- **Los `*.env` no se respaldan** y las claves que pasan por un chat se consideran expuestas.

## 11. Documentos relacionados y cómo mantener esto al día

| Documento | Para qué |
|---|---|
| [`docs/README.md`](docs/README.md) | Índice de la documentación técnica |
| [`docs/01-proyecto-sulotec.md`](docs/01-proyecto-sulotec.md) | Visión, productos, repositorios, reglas |
| [`docs/02-oracle-cloud.md`](docs/02-oracle-cloud.md) | Infraestructura: servidor, discos, buckets, respaldos, operación |
| [`docs/03-cloudflare.md`](docs/03-cloudflare.md) | Dominio, túnel, Zero Trust y Access |
| [`docs/04-integracion-de-proyectos.md`](docs/04-integracion-de-proyectos.md) | Identidad, publicación, datos y receta para sumar un producto |
| [`docs/05-inventario-de-claves.md`](docs/05-inventario-de-claves.md) | Qué secretos hay y dónde viven (sin valores) |
| [`SEGURIDAD-ISO27001.md`](SEGURIDAD-ISO27001.md) | Controles del Anexo A y brechas |
| `apps/<producto>/README.md` | Operación de cada producto (portal, cuenta, buscador, miradar, plaft) |
| [`docs/historico/`](docs/historico/bitacora-2026-10-06-al-14.md) | Bitácora original (puede estar desactualizada) |

**Mantenimiento:** cuando cambie la infraestructura o un producto, actualiza **este archivo y el documento correspondiente en el mismo commit**. Lo que se resuelva sale de §9; lo nuevo entra con su fecha. Este archivo es la **fuente de verdad** para retomar trabajo; no guardes aquí valores secretos.

**Resumen global en la laptop de trabajo:** en la carpeta `.claude` del usuario de Windows hay un `CLAUDE.md` corto (reglas de trabajo, resumen del ecosistema y el comando para bajar este documento) que **todos los chats de Claude Code de esa PC cargan al empezar**, sea cual sea la carpeta. Si cambia algo grande (productos, dominios, reglas o infraestructura), actualiza también ese resumen. Los chats de claude.ai en el navegador no lo ven: ahí se sube este documento a un Proyecto.
