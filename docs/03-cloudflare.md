# 3. Cloudflare — dominio, túnel y control de acceso

> Índice: [Documentación](README.md) · Anterior: [2. Oracle Cloud](02-oracle-cloud.md) · Siguiente: [4. Integración](04-integracion-de-proyectos.md)

## 3.1 Qué hace Cloudflare aquí

1. **DNS del dominio** `sulotec.com`.
2. **HTTPS:** certificado, HTTPS obligatorio y TLS 1.2 como mínimo.
3. **Túnel:** el servidor de Oracle se conecta **hacia afuera** con Cloudflare, sin abrir puertos. Cada subdominio se enruta a un contenedor.
4. **Zero Trust / Access:** decide **quién** puede entrar a las partes privadas (correo verificado con código, IP de la sede).

Cuenta: `informaperu2@gmail.com` (pendiente: 2FA). Plan **Free**; Zero Trust Free admite hasta 50 usuarios.

## 3.2 Túnel `sulotec`

- **ID:** `2bb087e4-1629-4778-beff-a94899412754`.
- **Conector:** el contenedor `cloudflared` de `/opt/sulotec/docker-compose.yml`. Su token está en `/opt/sulotec/.env` (`CF_TUNNEL_TOKEN`) y nunca va a GitHub.
- **Dónde se ve:** Cloudflare → **Zero Trust → Networks → Tunnels → sulotec → Routes** (o *Published application routes*).

| Dirección | Destino (dentro del servidor) | Aplicación |
|---|---|---|
| `ssh.sulotec.com` | `ssh://10.0.1.178:22` | Consola del servidor |
| `sulotec.com` | `http://portal:80` | Web de Sulotec |
| `www.sulotec.com` | `http://portal:80` | Web de Sulotec |
| `cuenta.sulotec.com` | `http://cuenta:8080` | Cuentas (Keycloak) |
| `buscadorinterno.sulotec.com` | `http://buscador:3000` | Buscador Interno (**agregar si aún no está**) |

**Agregar una aplicación nueva:**
1. Su contenedor debe estar en la red `sulotec_edge`, con un `container_name`.
2. En el túnel, ve a **Add route**: subdominio, dominio `sulotec.com`, Service URL `http://<contenedor>:<puerto>`.
3. Si es privada, crea **antes** su aplicación de Access (3.4).

> Usa subdominios de **un solo nivel** (`api-miradar360.sulotec.com`, no `api.miradar360.sulotec.com`): el certificado gratuito de Cloudflare solo cubre ese nivel.

## 3.3 Zero Trust

- **Equipo:** `round-butterfly-3ee7` (se puede renombrar en *Settings*).
- **Método de ingreso:** *One-time PIN*, un código que llega al correo.
- **Certificados SSH de corta duración:** la CA pública está en el servidor (`/etc/ssh/ca.pub`). El usuario Linux se deduce del correo: `serviciosdigitales@…` → `serviciosdigitales`.

## 3.4 Aplicaciones de Access (quién entra a qué)

| Aplicación | Protege | Política | Quiénes |
|---|---|---|---|
| **Servidor SSH** | `ssh.sulotec.com` (SSH en el navegador) | `Administradores` | `informaperu2@gmail.com`, `serviciosdigitales@informaperu.com` |
| **buscadorinterno** | `buscadorinterno.sulotec.com` | `Administradores Generales` | `abel.chavez@informaperu.com` (CEO), `serviciosdigitales@informaperu.com`, `informaperu2@gmail.com` |
| **cuenta** (Consola de cuentas) | `cuenta.sulotec.com/admin` | `Equipo de cuentas` | Correos de quienes administran cuentas |

**Reglas**
- **Mínimo privilegio:** el CEO entra al Buscador pero no al servidor SSH.
- **Sedes:** al tener las IPs públicas fijas de Lince y Los Olivos, agrega a la app `buscadorinterno` una política **Sedes** con acción **Bypass** e *Include → IP ranges*. Desde las sedes se entra sin código de Cloudflare, y desde fuera solo los Administradores Generales. La app del Buscador vuelve a validar lo mismo.
- **Quitar el acceso de una persona:** sácala de la política correspondiente (*Access controls → Policies*).

## 3.5 Pendientes en Cloudflare

| Pendiente | Cómo |
|---|---|
| **`contacto@sulotec.com`** (hoy no recibe) | Panel normal → `sulotec.com` → **Email → Email Routing** → *Get started* → dirección de destino (p. ej. `serviciosdigitales@informaperu.com`), confirmar → regla `contacto` → *Send to an email* → aceptar los registros DNS |
| **DNS del correo de Oracle** | **CNAME** de DKIM y **TXT** de SPF que da Oracle. Si Email Routing ya creó un SPF, **un solo** TXT con ambos `include:` (ver [2. Oracle](02-oracle-cloud.md)) |
| **Túnel en la oficina para la API** | Nuevo túnel (p. ej. `oficina`) con `cloudflared` como servicio de Windows en el servidor de la API. Ruta `api-buscadorinterno.sulotec.com` → `http://localhost:8090`. App de Access con política **Service Auth** y un *service token*, que se pega con `apps/buscador/deploy/preparar.sh`. Luego se apaga Tailscale Funnel |
| **MFA** | Exigir un segundo factor en las políticas de Access y 2FA en la cuenta de Cloudflare |
