# cuenta.sulotec.com — cuentas Sulotec (Keycloak)

Inicio de sesión y registro de personas para sulotec.com y sus demos, y administración de las cuentas del equipo.

| Qué | Dónde |
|---|---|
| Página de cuenta de cada persona | https://cuenta.sulotec.com/realms/sulotec/account |
| Consola para administrar cuentas (equipo) | https://cuenta.sulotec.com/admin/sulotec/console/ |
| Consola maestra (solo emergencias) | https://cuenta.sulotec.com/admin/master/console/ |
| Archivos en el servidor | `/data/apps/cuenta` (los copia GitHub) |
| Claves | `/opt/sulotec/cuenta.env` (solo en el servidor, nunca en el repositorio) |
| Datos | PostgreSQL, base `keycloak` (entra en el respaldo diario) |

Reglas del realm `sulotec` (en `realm/sulotec-realm.json`):
- Cualquier correo puede crear cuenta (cuando el correo de salida esté encendido), pero debe confirmarlo antes de entrar.
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

## Parte 2 — Correo de salida con Oracle (para "Crear cuenta")

Con el correo encendido, cualquiera puede pulsar **Crear cuenta** en sulotec.com con su Gmail, Outlook o el correo que sea. Recibe un correo de Sulotec para confirmarlo y elige su contraseña. También funciona "¿Olvidaste tu contraseña?". Usa **OCI Email Delivery**, de la misma cuenta de Oracle; no necesita cuenta ni tarjeta nueva.

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
6. **Servidor SMTP:** ve a **Email Delivery → Configuration**. El "Public Endpoint" debe ser `smtp.email.sa-santiago-1.oci.oraclecloud.com`.
7. **Configurar en el servidor:** entra a https://ssh.sulotec.com y corre:
   ```bash
   sudo bash /data/apps/cuenta/preparar.sh
   ```
   Responde `s` y pega el servidor, el usuario y la contraseña SMTP; la contraseña no se ve al pegarla. El registro de Keycloak se abre solo.
8. **Encender "Crear cuenta" en el portal:**
   - En GitHub, ve a **Settings → Secrets and variables → Actions → Variables** y crea `CUENTA_REGISTRO` con el valor `true`.
   - Luego ve a **Actions → Publicar portal → Run workflow**.
9. **Probar:** en una ventana de incógnito, entra a sulotec.com y pulsa **Crear cuenta**. Pon tu correo y confirma el correo que te llega. Si no aparece, revisa la carpeta de spam.

---

## Parte 3 — Cuentas del equipo y quién ve todo

1. Cada persona crea su propia cuenta en sulotec.com con **Crear cuenta**. Elige su **Usuario** (por ejemplo `jeliases`, `sjuarez`, `AbelCEO`) y pone su correo. Keycloak guarda el usuario en minúsculas, pero al entrar se puede escribir como sea.
2. Para que alguien **vea todos los productos**, incluido el Buscador Interno (hoy, solo el CEO):
   1. En la consola de Keycloak (realm **sulotec**), ve a **Users** y busca a la persona.
   2. Abre la pestaña **Groups**, pulsa **Join Group**, elige `Administradores Generales` y pulsa **Join**.
   3. La persona cierra sesión en sulotec.com y vuelve a entrar. En **Mis productos** ahora ve todo.
3. Quien no está en el grupo solo ve las demos.

**Crear la cuenta por otra persona**:
1. En **Users → Create new user**, llena los datos y pulsa **Create**.
2. En **Credentials → Credential reset**, elige `Verify Email` y `Update Password` y pulsa **Send email**.
3. La persona recibe "Actualiza tu cuenta" y elige su propia contraseña; nadie más la conoce.

**Quitar el acceso**, cuando alguien deja la empresa:
- En **Users**, entra a la persona y apaga **Enabled**, o sácala del grupo con **Leave**.
- Si administraba cuentas, quita su correo de la política **Equipo de cuentas** en Cloudflare Access.

---

## Parte 4 — Entrar con Google y Microsoft (opcional)

Keycloak ya tiene los dos proveedores **apagados**. Se encienden pegando sus claves en **Identity providers → google / microsoft**, activando **Enabled** y pulsando **Save**. Luego, en GitHub, crea la variable `CUENTA_SOCIAL=true` y vuelve a correr *Publicar portal*.

**Google:**
1. En https://console.cloud.google.com/projectcreate crea el proyecto `Sulotec`. No hace falta activar la prueba gratuita ni poner tarjeta: cierra ese aviso.
2. En https://console.cloud.google.com/auth/overview pulsa **Comenzar**:
   - Público: **Externo**. **No subas logo**.
   - Pulsa **Publicar app**.
3. En **Clientes → Crear cliente**:
   - Tipo: **Aplicación web**.
   - Redirección: `https://cuenta.sulotec.com/realms/sulotec/broker/google/endpoint`

**Microsoft** (requiere una cuenta de trabajo de Microsoft 365):
1. En https://entra.microsoft.com, ve a **Registros de aplicaciones → Nuevo registro**:
   - Tipos de cuenta: **cualquier directorio organizativo y cuentas personales de Microsoft**.
   - Redirección **Web**: `https://cuenta.sulotec.com/realms/sulotec/broker/microsoft/endpoint`
2. En **Certificados y secretos → Nuevo secreto** (24 meses), copia el **Valor** y anota cuándo vence.

**No crees a mano** una cuenta para alguien que entrará con Google o Microsoft: si ya existe una cuenta con su correo, Keycloak le pedirá vincularla.

Para apagar el inicio de sesión en todo el portal en una emergencia: en GitHub, crea la variable `CUENTA_ACTIVA` con el valor `false` y vuelve a correr *Publicar portal*.

---

## Notas

- `ajustar-realm.sh` aplica al realm que ya existe los ajustes que el JSON no puede aplicar. Hoy son tres: el rol en el token del portal, los proveedores Google y Microsoft (apagados y sin claves si no existen), y el registro con formulario solo si hay correo. Lo corren solos el workflow y `preparar.sh`; es seguro repetirlo.
- `realm/sulotec-realm.json` solo se importa la primera vez que arranca Keycloak. Los cambios posteriores se hacen en la consola maestra. Copia también el cambio al JSON para que el repositorio refleje la configuración real.
- Los cambios del tema (`themes/sulotec`) se aplican solos: el workflow reinicia Keycloak.
- Pendiente ISO 27001: crear un administrador maestro con nombre propio y OTP, y dejar `admin-temporal` solo para emergencias.
