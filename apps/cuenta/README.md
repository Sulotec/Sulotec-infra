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
- Cualquier correo puede crear cuenta, pero debe confirmarlo antes de entrar.
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

## Parte 2 — Entrar con Google y Microsoft

Cada persona entra con el Gmail u Outlook que ya tiene; no se crean contraseñas nuevas. La primera vez, su cuenta Sulotec se crea sola, y Google o Microsoft ya confirmaron que el correo es suyo.

Keycloak ya tiene los dos proveedores, **apagados** hasta pegar sus claves. Las claves se guardan en el gestor de contraseñas de la empresa, **nunca en un chat**.

### Google (unos 10 minutos)

1. Entra a https://console.cloud.google.com. Arriba, en **Seleccionar proyecto**, pulsa **Proyecto nuevo**, ponle de nombre `Sulotec` y pulsa **Crear**.
2. Menú **APIs y servicios → Pantalla de consentimiento de OAuth** (o **Google Auth Platform**) → **Comenzar**:
   - Nombre de la app: `Sulotec`; correo de asistencia: el tuyo.
   - Público: **Externo**. Información de contacto: tu correo. Pulsa **Crear**.
   - **No subas logo**: obliga a una revisión de Google que tarda días.
   - En **Público**, pulsa **Publicar app**. Si queda "En prueba", solo podrán entrar los correos de prueba.
3. Ve a **Clientes → Crear cliente**:
   - Tipo: **Aplicación web**; nombre: `cuenta.sulotec.com`.
   - **URIs de redireccionamiento autorizados**: `https://cuenta.sulotec.com/realms/sulotec/broker/google/endpoint`
   - Pulsa **Crear** y copia el **ID de cliente** y el **Secreto del cliente** al gestor de contraseñas.
4. En la consola de Keycloak (realm **Sulotec**), abre **Identity providers → google**:
   - Pega el **Client ID** y el **Client Secret**.
   - Activa **Enabled** y pulsa **Save**.

### Microsoft (unos 10 minutos)

Se necesita una cuenta Microsoft de trabajo (Microsoft 365) que pueda registrar aplicaciones.

1. Entra a https://entra.microsoft.com → **Aplicaciones → Registros de aplicaciones → Nuevo registro**:
   - Nombre: `Sulotec`.
   - Tipos de cuenta: **Cuentas en cualquier directorio organizativo y cuentas personales de Microsoft**, para que también entren Outlook y Hotmail.
   - URI de redirección: **Web**, con `https://cuenta.sulotec.com/realms/sulotec/broker/microsoft/endpoint`.
   - Pulsa **Registrar**.
2. Copia el **Id. de aplicación (cliente)**.
3. Ve a **Certificados y secretos → Nuevo secreto de cliente**:
   - Vencimiento: 24 meses.
   - Copia el **Valor**, no el "Id. de secreto"; solo se muestra una vez.
   - **Anota la fecha de vencimiento**: ese día hay que generar otro secreto y pegarlo de nuevo en Keycloak.
4. En Keycloak, abre **Identity providers → microsoft**:
   - Pega el **Client ID** (el Id. de aplicación) y el **Client Secret** (el Valor).
   - Activa **Enabled** y pulsa **Save**.

### Después

1. Prueba en una ventana de incógnito: entra a sulotec.com, pulsa **Iniciar sesión** y luego **Continuar con Google** (o Microsoft). Debes volver a sulotec.com, a **Mis productos**.
2. Enciende los botones en la ventana de las demos:
   - En GitHub, ve a **Settings → Secrets and variables → Actions → Variables** y crea `CUENTA_REGISTRO` con el valor `true`.
   - Luego ve a **Actions → Publicar portal → Run workflow**.

---

## Parte 3 — Quién ve todo (Administradores Generales)

Las cuentas no se crean a mano. **No crees en la consola una cuenta para alguien que entrará con Google o Microsoft**: si ya existe una cuenta con su correo, Keycloak le pide "vincularla" y se complica.

1. La persona entra **una vez** a sulotec.com con su Google o Microsoft.
2. En la consola de Keycloak (realm **Sulotec**), ve a **Users** y busca su correo.
3. Entra a la persona, abre la pestaña **Groups**, pulsa **Join Group**, elige `Administradores Generales` y pulsa **Join**.
4. La persona cierra sesión en sulotec.com y vuelve a entrar. En **Mis productos** ahora ve todo, incluido el Buscador Interno.

Hoy solo el CEO va en ese grupo. Quien no está en el grupo solo ve las demos.

**Quitar el acceso**, cuando alguien deja la empresa:
- En **Users**, entra a la persona y apaga **Enabled**, o sácala del grupo con **Leave**.
- Si administraba cuentas, quita su correo de la política **Equipo de cuentas** en Cloudflare Access.

**Para quien no use Google ni Microsoft** (opcional):
1. En **Users → Create new user**, llena los datos y pulsa **Create**.
2. En **Credentials → Set password**, pon una clave temporal con **Temporary** activado.
3. Entrega esa clave en persona, nunca por chat. Al entrar, el sistema obliga a cambiarla.

---

## Parte 4 — Correo de salida (opcional, más adelante)

Sirve para "¿Olvidaste tu contraseña?" y para el registro con formulario. Con Google y Microsoft no hace falta.

1. En **OCI Email Delivery** (consola de Oracle):
   - Crea el remitente aprobado `no-reply@sulotec.com`.
   - Agrega en Cloudflare DNS los registros SPF y DKIM que te indique.
   - Genera las credenciales SMTP en *Identity → tu usuario → SMTP credentials*.
2. En el servidor, corre `sudo bash /data/apps/cuenta/preparar.sh`, responde `s` y pega los datos SMTP.
3. Prueba el correo en la consola: **Realm settings → Email → Test connection**.

Para apagar el inicio de sesión en todo el portal en una emergencia: en GitHub, crea la variable `CUENTA_ACTIVA` con el valor `false` y vuelve a correr *Publicar portal*.

---

## Notas

- `ajustar-realm.sh` aplica al realm que ya existe los ajustes que el JSON no puede aplicar. Hoy son tres: el rol en el token del portal, los proveedores Google y Microsoft (apagados y sin claves si no existen), y el registro con formulario solo si hay correo. Lo corren solos el workflow y `preparar.sh`; es seguro repetirlo.
- `realm/sulotec-realm.json` solo se importa la primera vez que arranca Keycloak. Los cambios posteriores se hacen en la consola maestra. Copia también el cambio al JSON para que el repositorio refleje la configuración real.
- Los cambios del tema (`themes/sulotec`) se aplican solos: el workflow reinicia Keycloak.
- Pendiente ISO 27001: crear un administrador maestro con nombre propio y OTP, y dejar `admin-temporal` solo para emergencias.
