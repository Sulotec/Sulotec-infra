# cuenta.sulotec.com — cuentas Sulotec (Keycloak)

Inicio de sesión para sulotec.com y sus demos. Las cuentas las crea el equipo de Sulotec: no hay registro libre.

| Qué | Dónde |
|---|---|
| Página de cuenta de cada persona | https://cuenta.sulotec.com/realms/sulotec/account |
| Consola para administrar cuentas (equipo) | https://cuenta.sulotec.com/admin/sulotec/console/ |
| Consola maestra (solo emergencias) | https://cuenta.sulotec.com/admin/master/console/ |
| Archivos en el servidor | `/data/apps/cuenta` (los copia GitHub) |
| Claves | `/opt/sulotec/cuenta.env` (solo en el servidor, nunca en el repositorio) |
| Datos | PostgreSQL, base `keycloak` (entra en el respaldo diario) |

Reglas del realm `sulotec` (en `realm/sulotec-realm.json`):
- No hay registro libre: las cuentas las crea el equipo de Sulotec en la consola. Cada persona confirma su correo y elige su propia contraseña, y puede recuperarla con "¿Olvidaste tu contraseña?".
- Contraseñas de 10 o más caracteres, con mayúscula, minúscula y número, sin repetir las 3 últimas.
- 5 intentos fallidos bloquean la cuenta de 1 a 15 minutos.
- La sesión se cierra tras 30 minutos sin uso y dura 8 horas como máximo.
- El grupo **Administradores Generales**:
  - En sulotec.com/mis-productos ve **todos** los productos, incluido el Buscador Interno. El Buscador, además, está protegido por su propia política de Cloudflare Access.
  - Puede crear, editar y desactivar cuentas y ver los eventos, pero no puede cambiar la configuración ni darse más permisos (probado).
  - Quien no está en el grupo solo ve las demos.

---

## Parte 1 — Levantar cuenta.sulotec.com (una sola vez)

1. **GitHub.** Al subir esta carpeta, el workflow *Publicar cuenta* copia los archivos al servidor. La primera vez termina con un aviso amarillo, "Falta preparar el servidor": es normal.
2. **Servidor.** Entra por https://ssh.sulotec.com y corre:
   ```bash
   sudo bash /data/apps/cuenta/preparar.sh
   ```
   - Crea la base `keycloak` y levanta Keycloak (tarda alrededor de 1 minuto).
   - Muestra **una vez** la clave del `admin-temporal`. Guárdala en el gestor de contraseñas y **no la pegues en ningún chat**.
   - Si pregunta por el correo SMTP y aún no lo tienes, responde `N`. Puedes volver a correrlo cuando lo tengas.
3. **Cloudflare Zero Trust.** Haz primero el paso a, para que la consola nunca quede expuesta:

   a. **Access → Applications → Add an application → Self-hosted**:
   - Nombre: `Consola de cuentas`.
   - Dominio: `cuenta.sulotec.com`. Path: `admin`.
   - Política "Equipo de cuentas" con *Include → Emails*: los correos de quienes administran cuentas.

   b. **Networks → Tunnels → sulotec → Public hostnames → Add**:
   - Subdominio `cuenta`, dominio `sulotec.com`.
   - Tipo `HTTP`, URL `cuenta:8080`.
4. **Comprobar.** https://cuenta.sulotec.com/realms/sulotec/account debe mostrar el inicio de sesión de Sulotec. Si abres `/admin`, Cloudflare debe pedirte primero el código por correo.

---

## Parte 2 — Correo de salida con Oracle (invitaciones y recuperar contraseña)

Con el correo encendido:
- Cada cuenta nueva recibe un correo de invitación de Sulotec, y la persona elige su propia contraseña. Nadie más la conoce.
- Funciona **"¿Olvidaste tu contraseña?"** en la página de inicio de sesión.

Usa **OCI Email Delivery**, de la misma cuenta de Oracle; no necesita cuenta ni tarjeta nueva.

En la consola de Oracle (https://cloud.oracle.com, región **Chile Central (Santiago)**):

1. **Dominio de correo:** en el buscador de arriba escribe **Email Delivery** y entra. Ve a **Email Domains → Create Email Domain**, escribe `sulotec.com` y pulsa **Create**.
2. **DKIM** (firma que prueba que el correo es de verdad de sulotec.com):
   - Dentro del dominio, ve a **DKIM → Add DKIM** con el selector `sulotec-2026`.
   - Oracle muestra un registro **CNAME** (nombre y valor).
   - En Cloudflare, ve a **sulotec.com → DNS → Add record**, elige **CNAME**, pega el nombre y el valor y deja **Proxy status: DNS only** (nube gris).
3. **SPF:**
   - En el mismo dominio, Oracle muestra el texto SPF que debes usar.
   - En Cloudflare, agrega un registro **TXT** con nombre `@` y ese valor (por ejemplo `v=spf1 include:rp.oracleemaildelivery.com ~all`).
   - Si ya existe un TXT que empieza con `v=spf1`, no crees otro: agrégale el `include:` de Oracle al mismo.
4. **Remitente:** ve a **Email Delivery → Approved Senders → Create Approved Sender** con `no-reply@sulotec.com`.
5. **Credenciales SMTP:**
   - Arriba a la derecha, abre el ícono de perfil → **Mi perfil** (o **Configuración de usuario**) → **Tokens y claves** → **Credenciales SMTP** → **Generar credenciales**.
   - Copia el **usuario** y la **contraseña** al gestor de contraseñas. La contraseña solo se muestra una vez. **No la pegues en chats.**
6. **Configurar en el servidor:** entra a https://ssh.sulotec.com y corre:
   ```bash
   sudo bash /data/apps/cuenta/preparar.sh
   ```
   Responde `s` y pega, cuando te los pida:
   - el servidor: `smtp.email.sa-santiago-1.oci.oraclecloud.com`
   - el usuario SMTP
   - la contraseña SMTP (no se ve al pegarla)
7. **Probar:** crea una cuenta para ti con la Parte 3 y revisa que llegue la invitación. Si no aparece, revisa la carpeta de spam.

---

## Parte 3 — Levantar cuentas (lo hace el equipo de Sulotec)

Sulotec es un SaaS: **nadie se crea su cuenta solo**. Quien no tiene cuenta pulsa **Solicitar acceso** en la demo, y esa solicitud llega por correo a `contacto@sulotec.com`. El equipo decide y crea la cuenta.

**Dónde:**
- **La primera vez**, entra con `admin-temporal` a https://cuenta.sulotec.com/admin/master/console/ y cambia arriba a la izquierda al realm **sulotec**.
- **Después**, quien esté en *Administradores Generales* entra con su propia cuenta a https://cuenta.sulotec.com/admin/sulotec/console/.

**Crear una cuenta:**
1. Ve a **Usuarios (Users) → Crear usuario (Create new user)**:
   - **Nombre de usuario:** por ejemplo `jeliases`. Keycloak lo guarda en minúsculas: `AbelCEO` queda `abelceo`, pero al entrar se puede escribir como sea.
   - **Correo electrónico**, **Nombre** y **Apellido**. El correo puede ser Gmail, Outlook o el de su empresa.
   - **Correo electrónico verificado:** déjalo **apagado**; la persona lo confirma con la invitación.
   - **Unirse a grupos:** `Administradores Generales`, **solo** si debe ver todos los productos (incluido el Buscador) y poder crear cuentas. Hoy: el CEO y quien administre cuentas. Clientes y demás: sin grupo, ven las demos.
   - Pulsa **Crear**.
2. Ve a la pestaña **Credenciales → Restablecimiento de credenciales (Credential reset)**:
   - Elige `Verify Email` y `Update Password`.
   - En **Expira en**, pon 3 días.
   - Pulsa **Enviar correo electrónico**.
3. La persona recibe "Actualiza tu cuenta":
   1. Confirma su correo.
   2. Elige su contraseña: 10 caracteres o más, con mayúscula, minúscula y número.
   3. Ya puede entrar a sulotec.com con **Iniciar sesión** y llega a **Mis productos**.

**Sin correo de Oracle todavía:**
1. Al crear la cuenta, activa **Correo electrónico verificado**.
2. En **Credenciales → Establecer contraseña**, pon una clave temporal con **Temporal** activado.
3. Entrégala en persona o por llamada, nunca por chat. Al entrar, el sistema obliga a cambiarla.

**Recuperar el acceso:**
- La persona pulsa **¿Olvidaste tu contraseña?** en la página de inicio de sesión y recibe un enlace por correo.
- También puedes enviárselo tú: **Credenciales → Restablecimiento de credenciales → `Update Password`**.
- Tras 5 intentos fallidos, la cuenta se bloquea de 1 a 15 minutos y luego se desbloquea sola.

**Quitar el acceso** (cliente que termina contrato o persona que deja la empresa):
- En **Usuarios**, entra a la persona y apaga **Habilitado**.
- Si administraba cuentas, quita también su correo de la política **Equipo de cuentas** en Cloudflare Access.

Para apagar el inicio de sesión en todo el portal en una emergencia: en GitHub, crea la variable `CUENTA_ACTIVA` con el valor `false` y vuelve a correr *Publicar portal*.

---

## Notas

- `ajustar-realm.sh` aplica al realm que ya existe los ajustes que el JSON no puede aplicar. Hoy: el rol en el token del portal, registro libre siempre apagado con recuperación de contraseña encendida, y el borrado de los proveedores Google/Microsoft de reserva que nunca se configuraron. Lo corren solos el workflow y `preparar.sh`; es seguro repetirlo.
- `realm/sulotec-realm.json` solo se importa la primera vez que arranca Keycloak. Los cambios posteriores se hacen en la consola maestra. Copia también el cambio al JSON para que el repositorio refleje la configuración real.
- Los cambios del tema (`themes/sulotec`) se aplican solos: el workflow reinicia Keycloak.
- Pendiente ISO 27001: crear un administrador maestro con nombre propio y OTP, y dejar `admin-temporal` solo para emergencias.

---

## Inicio único en los productos (desde 2026-10-18)

`ajustar-realm.sh` crea, además, lo necesario para que los productos acepten la cuenta Sulotec:
- Un rol `producto-<clave>` por producto (`producto-auditoria`, `producto-miradar360`, `producto-plaft`) y un grupo **Clientes - <producto>** que lo
  otorga. El portal (`/mis-productos`) habilita el botón «Abrir» solo a quien tiene el rol; los demás ven el producto en gris con su demo.
- El cliente público `auditoria` (PKCE, redirect `https://auditoria.sulotec.com/sso`), con el correo y los roles en su id_token.

**Para dar acceso a Auditoría de Visitas a una persona:** en la consola, abre (o crea) su cuenta con el **mismo correo** que tiene su usuario en el
panel de Auditoría, y agrégala al grupo **Clientes - Auditoria de Visitas**. Desde ese momento entra desde sulotec.com → Mis productos → Abrir, sin
otra contraseña. Si su cuenta no está vinculada, el panel se lo dice y le ofrece entrar con usuario y contraseña.

---

## Modelo de cuentas (acordado el 2026-10-22)

| Quién | En Keycloak | Qué ve |
|---|---|---|
| **Administrador universal** (Sulotec; **máximo 2 personas**) | grupo **Administradores Generales** (rol `administrador-general`) | Todos los productos y todos los clientes. |
| **Empresa** (un cliente de Sulotec: una caja, un negocio) | subgrupo de **Empresas** con los atributos `empresa_uuid`, `empresa_nombre` y `empresa_slug`, y con los roles `producto-*` que tiene contratados | — |
| **Persona de una empresa** | miembro del subgrupo de su empresa (de **una sola**) | Los productos que su empresa contrató: hereda los roles del grupo. Su rol dentro de cada producto (administrador de la empresa, supervisor, usuario) lo define el producto, no Keycloak. |

- El **UUID de la empresa nace aquí** y es el mismo en todos los productos: al crear la empresa dentro de GeoMatrix, PLAFT o MiRadar se usa este UUID. Así el cliente se identifica igual en todo Sulotec.
- Los tokens del portal y de los productos llevan `empresa_uuid`, `empresa_nombre` y `empresa_slug` (además de `email` y `roles`). Un administrador universal no lleva empresa.
- **Sub-productos** (una plantilla con clientes debajo, cada uno con su marca y sus reglas): solo **GeoMatrix** (antes Auditoría de Visitas) y **MiRadar 360**. PLAFT y Dashboard Empresarial separan por empresa sin marca propia; el Buscador es interno.
- El portal (`/mis-productos`) muestra **todo el catálogo**: «Abrir» si la empresa tiene el rol del producto, «Solicitar» si no; los productos privados (`publico: false`) solo aparecen a quien los tiene contratados.

### Dar de alta una empresa y sus cuentas (en el servidor, por `ssh.sulotec.com`)

1. **Crear la empresa** (o cambiar sus productos; se puede repetir, conserva el UUID):
   ```bash
   sudo bash /data/apps/cuenta/empresa.sh "Caja Huancayo" caja-huancayo auditoria,miradar360
   ```
   Productos válidos: `auditoria` (GeoMatrix), `miradar360`, `plaft`, `dashboard`. Con `--uuid <uuid>` se reutiliza el UUID que la empresa ya tiene en un producto. `sudo bash /data/apps/cuenta/empresa.sh --listar` muestra todas.
2. **Preparar el CSV** copiando `plantilla-cuentas.csv` (`correo;nombres;apellidos;empresa;universal`; `empresa` es el slug del paso 1; `universal=si` solo para los 2 administradores de Sulotec, con empresa vacía) y revisarlo:
   ```bash
   sudo bash /data/apps/cuenta/cuentas.sh /ruta/cuentas.csv --revisar
   ```
3. **Crear e invitar:**
   ```bash
   sudo bash /data/apps/cuenta/cuentas.sh /ruta/cuentas.csv
   ```
   Cada persona recibe un correo de Sulotec con el enlace (7 días) para crear su contraseña. Si el correo de salida no está configurado, el script muestra una **clave temporal** por cuenta (una sola vez; se cambia al entrar). `--reinvitar` reenvía la invitación también a las cuentas que ya existían. Las cuentas que ya existen no se duplican ni se mueven de empresa.
4. **En cada producto contratado**, crear la misma empresa con el **mismo UUID** y sus usuarios con el **mismo correo**: así el inicio único los reconoce (hoy lo hace GeoMatrix; PLAFT y Dashboard se enchufan a continuación).

Los scripts corren dentro del contenedor `cuenta` con el administrador de `/opt/sulotec/cuenta.env`; se prueban en local con un Keycloak de prueba (variables `CONTENEDOR` y `PRUEBA`).
