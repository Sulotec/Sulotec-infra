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
- El grupo **Administradores Generales** puede crear, editar y desactivar cuentas y ver los eventos, pero no puede cambiar la configuración ni darse más permisos (probado).

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

## Parte 2 — Crear una cuenta para alguien del equipo

**La primera vez**, entra con `admin-temporal` a la consola maestra y cambia arriba a la izquierda al realm **Sulotec**.
**Después**, cada administrador entra con su propia cuenta a https://cuenta.sulotec.com/admin/sulotec/console/.

1. Menú **Usuarios → Crear usuario**.
2. Llena el formulario:
   - **Nombre de usuario**: por ejemplo `jeliases`. Keycloak lo guarda en minúsculas: `AbelCEO` queda como `abelceo`, pero al entrar se puede escribir como sea.
   - **Correo electrónico**, **Nombre** y **Apellido**.
   - **Correo electrónico verificado**: actívalo solo si confirmaste el correo con la persona.
   - **Acciones de usuario requeridas**: elige `Configure OTP` (verificación en dos pasos). Es obligatoria para administradores.
   - **Unirse a grupos** → `Administradores Generales`, solo si esa persona también debe poder crear cuentas.
   - Pulsa **Crear**.
3. En la pestaña **Credenciales**, elige una de dos formas:
   - **Con correo SMTP configurado (recomendado).** Pulsa **Restablecimiento de credenciales**, elige `Update Password` y pulsa **Enviar correo electrónico**. La persona recibe "Actualiza tu cuenta" y elige su propia contraseña: nadie más la conoce.
   - **Sin correo todavía.** Pulsa **Establecer contraseña**, escribe una clave temporal y deja **Temporal** activado. Entrégala en persona o por llamada, nunca por chat ni por correo. Al entrar por primera vez, el sistema obliga a cambiarla.
4. La persona entra a https://cuenta.sulotec.com/realms/sulotec/account:
   - Pone su nueva contraseña.
   - Escanea el código QR con Google Authenticator o Microsoft Authenticator.
   - Desde entonces, cada inicio de sesión le pide también el código de 6 dígitos.
5. Si esa persona administra cuentas, agrega su correo a la política de **Consola de cuentas** en Cloudflare Access.

**Quitar el acceso** (cuando alguien deja la empresa): abre Usuarios, entra a la persona y apaga el interruptor **Habilitado**. Quítalo también de la política de Cloudflare.

---

## Parte 3 — Abrir las cuentas al público en sulotec.com

Hasta este paso, el portal no muestra "Iniciar sesión" ni "Crear cuenta". El registro público necesita correo de salida, porque cada persona confirma su correo.

1. **OCI Email Delivery** (consola de Oracle):
   - Crea el remitente aprobado `no-reply@sulotec.com`.
   - Agrega en Cloudflare DNS los registros SPF y DKIM que te indique.
   - Genera las credenciales SMTP en *Identity → tu usuario → SMTP credentials*.
2. En el servidor, corre `sudo bash /data/apps/cuenta/preparar.sh`, responde `s` y pega los datos SMTP.
3. Prueba el correo en la consola: **Configuración del realm → Correo electrónico → Probar conexión**.
4. En GitHub, ve a **Settings → Secrets and variables → Actions → Variables**. Crea `CUENTA_ACTIVA` con el valor `true`. Luego ve a **Actions → Publicar portal → Run workflow**.

Para apagar las cuentas en una emergencia, cambia `CUENTA_ACTIVA` a `false` y vuelve a correr *Publicar portal*.

---

## Notas

- `realm/sulotec-realm.json` solo se importa la primera vez que arranca Keycloak. Los cambios posteriores se hacen en la consola maestra. Copia también el cambio al JSON para que el repositorio refleje la configuración real.
- Los cambios del tema (`themes/sulotec`) se aplican solos: el workflow reinicia Keycloak.
- Pendiente ISO 27001: crear un administrador maestro con nombre propio y OTP, y dejar `admin-temporal` solo para emergencias.
