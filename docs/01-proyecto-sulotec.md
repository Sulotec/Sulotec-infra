# 1. Proyecto Sulotec — visión general

> Índice: [Documentación](README.md) · Siguiente: [2. Oracle Cloud](02-oracle-cloud.md)

## 1.1 Qué es

Sulotec es el ecosistema SaaS de soluciones digitales de la empresa (sitio: **https://sulotec.com**).
- Toda la infraestructura vive en la nube (Oracle Cloud + Cloudflare) y no depende de ninguna PC.
- Se alinea con **ISO/IEC 27001** (ver [`SEGURIDAD-ISO27001.md`](../SEGURIDAD-ISO27001.md)).

## 1.2 Productos

| Producto | Qué hace | Estado | Visibilidad | Dirección prevista |
|---|---|---|---|---|
| **MiRadar360** (antes AFACOP) | Torre de control de equipos en campo: rutas, visitas y evidencias GPS y fotos | En producción (Render/Vercel) | Público | `miradar360.sulotec.com` |
| **Auditoría de Visitas** (Caja Huancayo) | Verifica visitas con geocerca, fotos, firma y trabajo sin conexión | En producción (Render) | Público | `auditoria.sulotec.com` |
| **Prevención de Lavado de Activos** | Cumplimiento PLAFT con trazabilidad | En implementación | Público | `plaft.sulotec.com` |
| **Buscador Interno** | Consultas internas de personas y empresas | **Nuevo front en Sulotec** | **Privado** (solo personal y sedes) | **`buscadorinterno.sulotec.com`** ✅ |

La lista de productos se edita en un solo archivo: [`apps/portal/src/data/soluciones.ts`](../apps/portal/src/data/soluciones.ts).
- `publico`: si aparece en la web.
- `url`: dirección actual mientras el producto se muda.
- `publicado`: si ya funciona en su subdominio.
- `demo`: página de demo.

## 1.3 Aplicaciones en línea

| Aplicación | Dirección | Tecnología | Código | Corre en |
|---|---|---|---|---|
| Web de Sulotec (portal + demos) | https://sulotec.com y `www` | Astro 7 (sitio estático) + nginx | [`apps/portal`](../apps/portal) | Oracle, contenedor `portal` |
| Cuentas (inicio de sesión) | https://cuenta.sulotec.com | Keycloak 26.8 + PostgreSQL | [`apps/cuenta`](../apps/cuenta) | Oracle, contenedor `cuenta` |
| Buscador Interno (front) | https://buscadorinterno.sulotec.com | Next.js 16 + React 19 + TypeScript | [Sulotec/buscador-interno `web/`](https://github.com/Sulotec/buscador-interno) | Oracle, contenedor `buscador` |
| Buscador Interno (API) | Privada | .NET 10 + SQL Server | [Sulotec/buscador-interno `api/`](https://github.com/Sulotec/buscador-interno) | Servidor de la oficina (servicio Windows `BuscadorApi`) |
| Consola del servidor | https://ssh.sulotec.com | SSH en el navegador (Cloudflare) | — | Oracle |

## 1.4 Repositorios (GitHub, organización `Sulotec`)

| Repositorio | Contenido | Acceso |
|---|---|---|
| [Sulotec/Sulotec-infra](https://github.com/Sulotec/Sulotec-infra) | Infraestructura (Terraform, scripts del servidor), web de Sulotec, cuentas, operación del Buscador y esta documentación | **Solo administradores**: quien escribe aquí controla el servidor |
| [Sulotec/buscador-interno](https://github.com/Sulotec/buscador-interno) | Código del Buscador: `web/` (React) y `api/` (.NET) | Equipo de desarrollo del Buscador |
| `jeliases-informaDev/InternalBuscador` | API vieja; el servidor de la oficina aún se actualiza desde aquí | Retirar al mover el actualizador |
| `jeliases-informaDev/internal-search-frontend` | Front Angular antiguo (Vercel) | Retirar cuando se apague Vercel |
| `jeliases-informaDev/Afacop-*`, Caja Huancayo | Productos aún en Render/Vercel | Pasar a la organización al migrar |

Estructura de `Sulotec-infra`:
```
oracle/        Terraform de Oracle Cloud (red, servidor, discos, buckets)
vm/            servicios base del servidor (túnel, PostgreSQL, MySQL) y scripts
apps/portal/   sulotec.com
apps/cuenta/   cuenta.sulotec.com (Keycloak: realm, tema, scripts)
apps/buscador/ operación del Buscador (el código está en buscador-interno)
.github/       publicación automática (runner propio en el servidor)
docs/          esta documentación
```

## 1.5 La web de Sulotec (sulotec.com)

- **Portada:** productos, metodología, pilares y contacto. Los textos se editan en [`src/data/sitio.ts`](../apps/portal/src/data/sitio.ts) y [`src/data/soluciones.ts`](../apps/portal/src/data/soluciones.ts).
- **Demos públicas:** `/demo/miradar360`, `/demo/auditoria` y `/demo/plaft`.
  - Usan **solo datos de ejemplo** ([`src/data/demos.ts`](../apps/portal/src/data/demos.ts)); los datos personales están prohibidos.
  - Sin sesión, la persona tiene **2 minutos** en total; luego una ventana obligatoria pide **Iniciar sesión** o **Solicitar acceso**.
  - Con sesión no hay límite, y al minuto se recomienda **agendar una consulta**.
- **Mis productos** (`/mis-productos`), adonde se llega al iniciar sesión:
  - **Administradores Generales:** ven los 4 productos, con botón directo al Buscador.
  - **Los demás:** ven las demos y la invitación a la consulta.
  - Todos tienen el panel "Tu cuenta".
- **Redes sociales:** se configuran en `sitio.ts` → `redes`. Solo aparecen las que tienen link.
- **Interruptor de cuentas:** la variable de GitHub `CUENTA_ACTIVA=false` apaga "Iniciar sesión" en una emergencia (ver [`portal.yml`](../.github/workflows/portal.yml)).

## 1.6 Cuentas de personas (cuenta.sulotec.com)

- **Keycloak 26.8**, realm `sulotec`, tema propio de Sulotec ([`apps/cuenta`](../apps/cuenta)).
- **SaaS, sin registro libre:** las cuentas las crea el equipo en la consola (`/admin`, protegida por Cloudflare Access).
  - La persona recibe una invitación por correo y elige su contraseña.
  - Puede recuperarla con "¿Olvidaste tu contraseña?". Requiere el correo de Oracle, pendiente.
- **Reglas:**
  - Contraseña de 10 caracteres o más, con mayúscula, minúscula y número, sin repetir las 3 últimas.
  - Bloqueo tras 5 intentos fallidos.
  - La sesión se cierra a los 30 minutos sin uso, y dura 8 horas como máximo.
- **Roles:** el grupo **Administradores Generales** (rol `administrador-general`) ve todo en Mis productos y puede administrar cuentas, pero no cambiar la configuración. El rol llega al portal en el token (claim `roles`).
- **Guía paso a paso** (crear, recuperar y quitar cuentas): [`apps/cuenta/README.md`](../apps/cuenta/README.md).

## 1.7 Buscador Interno

- **Front nuevo** en React/Next.js con las mismas funciones que el Angular:
  - login y recuperación
  - personas: DNI, RENIEC, teléfono
  - empresas: RUC, razón social
  - cargas masivas con historial
  - administración: usuarios, roles, tokens, auditoría
- **Regla de sedes:** solo se usa desde las IPs de las sedes **Lince** y **Los Olivos**. El rol **ADMIN GENERAL** puede entrar desde cualquier lugar. Se aplica en dos lugares:
  - en el servidor del front, al iniciar sesión y en cada consulta
  - en Cloudflare Access
- **Cuentas propias:** el Buscador tiene sus propios usuarios en su base SQL Server de la oficina; no son las cuentas de sulotec.com.
- **Detalle:** [README de buscador-interno](https://github.com/Sulotec/buscador-interno) y [`apps/buscador/README.md`](../apps/buscador/README.md).

## 1.8 Reglas generales

1. **Ningún secreto en GitHub ni en chats.** Los secretos van en `/opt/sulotec/*.env` (servidor) y en el gestor de contraseñas.
2. **Ningún dato real** en demos, repositorios ni documentación.
3. **Mínimo privilegio:** cada persona solo accede a lo que necesita. Por ejemplo, el CEO no tiene SSH al servidor.
4. **Todo cambio pasa por GitHub:** se edita, se sube a `main` y se publica solo. Nada se cambia a mano en el servidor sin dejarlo documentado.

## 1.9 Pendientes (consolidado)

| Prioridad | Pendiente | Dónde |
|---|---|---|
| Alta | Ruta del túnel `buscadorinterno.sulotec.com` → `http://buscador:3000`, si aún no está | [3. Cloudflare](03-cloudflare.md) |
| Alta | Publicación automática del Buscador: `sudo bash /data/apps/buscador/instalar-actualizador.sh` + *deploy key* | [`apps/buscador/README.md`](../apps/buscador/README.md) |
| Alta | `contacto@sulotec.com` con Cloudflare Email Routing (hoy los correos de "Solicitar acceso" rebotan) | [3. Cloudflare](03-cloudflare.md) |
| Alta | Correo de salida (OCI Email Delivery) para invitaciones y recuperación de contraseñas | [2. Oracle](02-oracle-cloud.md) |
| Alta | IPs de las sedes (Lince, Los Olivos) → `preparar.sh` + política *Bypass* en Access | [`apps/buscador/README.md`](../apps/buscador/README.md) |
| Alta | Rotar claves de PostgreSQL/MySQL (se vieron en un chat) antes de cargar datos reales | [`SEGURIDAD-ISO27001.md`](../SEGURIDAD-ISO27001.md) |
| Alta | Quitar los Excel con datos reales de `jeliases-informaDev/InternalBuscador` y dejarlo privado | — |
| Media | Túnel de Cloudflare en la oficina para la API; luego apagar Tailscale Funnel y Vercel | [4. Integración](04-integracion-de-proyectos.md) |
| Media | Actualizador de la API desde `Sulotec/buscador-interno` | `api/DESPLIEGUE.md` |
| Media | Direcciones actuales de MiRadar360, Auditoría y PLAFT (botón "Abrir") y links de redes sociales | `soluciones.ts`, `sitio.ts` |
| Media | 2FA en Gmail, Cloudflare, Oracle y GitHub; MFA en Access | [`SEGURIDAD-ISO27001.md`](../SEGURIDAD-ISO27001.md) |
| Media | Reemplazar `admin-temporal` de Keycloak por un administrador con nombre propio y OTP | [`apps/cuenta/README.md`](../apps/cuenta/README.md) |
| Baja | Fase 2 del Buscador: API en TypeScript | [buscador-interno](https://github.com/Sulotec/buscador-interno) |
| Baja | Migrar MiRadar360 y Auditoría de Render/Vercel a sus subdominios | [4. Integración](04-integracion-de-proyectos.md) |
| Baja | Prueba de restauración de respaldos; revisión legal Ley 29733 / SBS | [`SEGURIDAD-ISO27001.md`](../SEGURIDAD-ISO27001.md) |
