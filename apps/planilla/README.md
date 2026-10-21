# Sistema de Planillas (Informa Perú) — kit para el servidor Sulotec

Planilla mensual peruana para el equipo de RR.HH./Contabilidad de Informa Perú: empleados, asistencias (importación del
reloj marcador), tardanzas, AFP/ONP, EsSalud, gratificación, CTS, renta de 5.ª, cierre de planilla, boletas en PDF,
PLAME, liquidaciones, auditoría de cambios y usuarios con dos roles (`ADMIN` y `GERENCIA`, solo lectura).

- **Código:** [`Jeliases/PlanillaBackend`](https://github.com/Jeliases/PlanillaBackend) (Spring Boot 3.2, Java 17, MySQL)
  y [`jeliases-informaDev/PlanillaFrontEd`](https://github.com/jeliases-informaDev/PlanillaFrontEd) (Angular 21).
- **Un solo contenedor** `planilla` (puerto 8080 interno): el `Dockerfile` de este kit compila la pantalla, la mete en el
  jar y Spring Boot la sirve en la misma dirección que la API (`/api/**`) y el WebSocket (`/ws`). No hay API aparte.
- **Base:** la MySQL 8.4 compartida de la VM, base `planilla` con su propio usuario (red `sulotec_data`).
- **Dirección:** `planilla.sulotec.com → http://planilla:8080`.
- **Secretos:** solo en `/opt/sulotec/planilla.env` (root:docker, 640; **no entra en el respaldo**). Nada en el repo.

> Maneja sueldos y datos personales. Es una herramienta interna: pon **Cloudflare Access** delante (ver §3) además del
> inicio de sesión propio del sistema.

## 1. Instalar por primera vez

Todo se hace en la VM (`https://ssh.sulotec.com`). Son 5 pasos; cada script dice cuál sigue.

**1) Copiar el kit** desde GitHub a `/data/apps/planilla` (los scripts quedan sueltos ahí, como en los otros kits):

```
sudo mkdir -p /data/apps/planilla && cd /tmp && rm -rf sulotec-infra \
 && git clone -q --depth 1 https://github.com/Sulotec/Sulotec-infra.git \
 && sudo cp sulotec-infra/apps/planilla/{Dockerfile,.dockerignore,docker-compose.yml} /data/apps/planilla/ \
 && sudo cp sulotec-infra/apps/planilla/deploy/*.sh /data/apps/planilla/ \
 && sudo chmod +x /data/apps/planilla/*.sh && ls -la /data/apps/planilla
```

**2) Crear la base y su usuario** (imprime las cadenas de conexión **una sola vez**; la de `Node` es la que pide el
siguiente paso):

```
sudo /opt/sulotec/scripts/new-project-db.sh mysql planilla
```

**3) Crear la configuración** `/opt/sulotec/planilla.env`. Pide la cadena `mysql://…` (se ve con `*`), la dirección
pública (Enter = `https://planilla.sulotec.com`) y, opcional, el correo SMTP para mandar boletas (Enter = sin correo).
Genera el `JWT_SECRET` y la **clave del usuario inicial `admin`**, que muestra **una sola vez**: guárdala en el gestor.

```
sudo bash /data/apps/planilla/preparar.sh
```

**4) Construir y levantar** (la primera vez tarda 5–10 min: compila Angular y Maven en el servidor ARM):

```
sudo bash /data/apps/planilla/desplegar.sh
```

Espera a que el contenedor esté sano; si la versión nueva no arranca, vuelve a la anterior. Cuando ve que el usuario
`admin` ya existe, **borra `ADMIN_PASSWORD` del `.env`** (solo servía para el primer arranque).

**5) Probar** (no cambia nada):

```
sudo bash /data/apps/planilla/probar.sh
```

Las pruebas de la dirección pública salen como *AVISO* hasta que exista la ruta del túnel (§3).

## 2. Primer ingreso

1. Entra a `https://planilla.sulotec.com` con `admin` y la clave que mostró `preparar.sh`.
2. El sistema **obliga a cambiarla** (mínimo 8 caracteres con mayúscula, minúscula y número).
3. En **Usuarios** crea las cuentas reales (RR.HH. con rol `ADMIN`, gerencia con rol `GERENCIA`, solo lectura).
4. Revisa en **Conceptos** y **AFP** las tasas vigentes, y en **Feriados** el calendario del año.
5. Carga empleados con la **plantilla Excel** (Empleados → Importar) y luego asistencias y horarios.

Si se pierde la clave de una cuenta y nadie puede entrar como administrador:

```
sudo bash /data/apps/planilla/resetear-clave.sh admin
```

## 3. Cloudflare: ruta y Access

1. Cloudflare One → Networks → Tunnels → `sulotec` → **Public Hostname** → Add:
   subdominio `planilla`, dominio `sulotec.com`, servicio `HTTP`, URL `planilla:8080`.
2. Cloudflare One → Access → Applications → Add → Self-hosted: dominio `planilla.sulotec.com`, política *Allow* con los
   correos del equipo que usa el sistema (o la IP de la sede, como el Buscador). Así nadie ajeno ve ni la pantalla de
   inicio de sesión.
3. Opcional pero recomendable: regla de **límite de velocidad** en `/api/auth/login` (igual que está pendiente en PLAFT y
   Dashboard).

El WebSocket (`/ws`) y las descargas (PDF, Excel, PLAME) pasan por el mismo dominio; Cloudflare corta las peticiones
que tardan más de 100 s, que no es el caso de ninguna pantalla.

## 4. Actualizar a una versión nueva

Cuando se unan Pull Requests a `main` en cualquiera de los dos repositorios:

```
sudo bash /data/apps/planilla/desplegar.sh && sudo bash /data/apps/planilla/probar.sh
```

Para probar una rama antes de unirla:

```
RAMA_BACKEND=feature/mi-cambio RAMA_FRONTEND=main sudo -E bash /data/apps/planilla/desplegar.sh
```

Las tablas se crean/ajustan solas al arrancar (`ddl-auto=update`): antes de una versión que cambie tablas, saca una copia:

```
sudo /opt/sulotec/scripts/backup.sh
```

Volver a la versión anterior a mano: `docker images planilla` (se conservan las 3 últimas), luego
`docker tag planilla:<tag> planilla:latest && cd /data/apps/planilla && docker compose up -d --force-recreate`.

## 5. Cambiar la configuración, rotar claves

- **Cualquier valor del `.env`** (correo SMTP, dirección, RMV/UIT si cambian por ley): `sudo bash /data/apps/planilla/preparar.sh`
  (Enter conserva lo actual) y después `cd /data/apps/planilla && sudo docker compose up -d --force-recreate`.
  También puedes fijar `RMV=…` o `UIT=…` como variables al correr `preparar.sh`.
- **Clave de la base** (`rotar-claves.sh` aún no conoce este proyecto): genera una nueva, cámbiala en MySQL y vuelve a
  correr `preparar.sh` con la cadena nueva.

  ```
  NUEVA="$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 32)" \
   && sudo docker exec -i mysql mysql -uroot -p"$(sudo grep '^MYSQL_ROOT_PASSWORD=' /opt/sulotec/.env | cut -d= -f2-)" \
        -e "ALTER USER 'planilla'@'%' IDENTIFIED BY '$NUEVA'; FLUSH PRIVILEGES;" \
   && CADENA="mysql://planilla:$NUEVA@mysql:3306/planilla" SIN_CORREO=1 sudo -E bash /data/apps/planilla/preparar.sh \
   && cd /data/apps/planilla && sudo docker compose up -d --force-recreate && unset NUEVA
  ```

- **`JWT_SECRET`**: `sudo sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n')|" /opt/sulotec/planilla.env`
  y recrear el contenedor. Cierra todas las sesiones abiertas.
- **Clave de un usuario**: desde la pantalla *Usuarios* (administrador) o `resetear-clave.sh <usuario>`.

## 6. Respaldos y datos

- El respaldo diario de la VM (02:00) ya incluye la base `planilla` (`mysqldump` de todas las bases) y `/data/apps`.
  **No incluye `/opt/sulotec/planilla.env`**: guarda en el gestor la clave de la base y el `JWT_SECRET`
  (ver [`docs/05-inventario-de-claves.md`](../../docs/05-inventario-de-claves.md)).
- Restaurar una tabla o la base: `vm/scripts/probar-restauracion.sh` describe el procedimiento general.
- Los datos son reales (sueldos, DNI): aplica la Ley 29733 (datos personales); el servidor está en Santiago de Chile.

## 7. Variables de `/opt/sulotec/planilla.env`

| Variable | Qué es | La pone |
|---|---|---|
| `PORT` | Puerto interno (8080) | `preparar.sh` |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_URL` | Conexión a MySQL (de la cadena de `new-project-db.sh`) | `preparar.sh` |
| `JWT_SECRET`, `JWT_EXPIRATION_MS` | Firma y duración (8 h) de las sesiones | `preparar.sh` |
| `ADMIN_USER`, `ADMIN_PASSWORD` | Usuario inicial; la clave solo existe hasta el primer arranque | `preparar.sh` / `desplegar.sh` la borra |
| `SEED_ENABLED` | Carga regímenes, conceptos PLAME, AFP, feriados y tabla de tardanzas si faltan (`true`) | `preparar.sh` |
| `WEB_URL`, `CORS_ORIGINS` | Dirección pública (una sola, mismo origen) | `preparar.sh` |
| `RMV`, `UIT`, `EMPRESA_RUC`, `EMPRESA_RAZON_SOCIAL`, `EMPRESA_DIRECCION`, `EMPRESA_LUGAR` | Parámetros legales y de la empresa; si faltan, la app usa los de 2026 (RMV 1230, UIT 5500) y los datos de Informa Perú | opcional |
| `EMPRESA_REPRESENTANTE`, `EMPRESA_REPRESENTANTE_DOC` | Nombre y DNI del gerente que firma las constancias de gratificación y CTS (dato personal: solo aquí, nunca en el repositorio). Vacíos = línea para firmar a mano. Se fijan como variables al correr `preparar.sh` | opcional |
| `MAIL_HOST`, `MAIL_PORT`, `MAIL_USER`, `MAIL_PASSWORD`, `MAIL_FROM`, `MAIL_HABILITADO` | Correo saliente para boletas (OCI Email Delivery) | `preparar.sh` |
| `SHOW_SQL` | `false` en producción | `preparar.sh` |

## 8. Problemas comunes

| Síntoma | Qué mirar |
|---|---|
| `desplegar.sh` falla en la construcción | `docker build` sin `-q` para ver el error: `cd /data/apps/planilla && sudo docker build -t planilla:prueba .`. Si falla Angular por presupuesto de tamaño (*budget*), es un cambio en la pantalla; si falla Maven, suele ser una prueba o una dependencia |
| El contenedor no llega a *healthy* | `docker logs planilla`: casi siempre es la base (clave o red `sulotec_data`) |
| 502 en `planilla.sulotec.com` | La ruta del túnel debe apuntar a `http://planilla:8080` (nombre exacto del contenedor) |
| La pantalla carga pero el login dice error de red | `CORS_ORIGINS` debe ser exactamente la dirección pública (sin barra final); recrear el contenedor |
| "Tiempo real" no actualiza | El WebSocket va por `wss://planilla.sulotec.com/ws`; Cloudflare lo soporta de fábrica. Revisar que Access no tenga una política distinta para `/ws` |
| Sin usuarios y nadie puede entrar | `resetear-clave.sh admin`; si la tabla `usuario` está vacía, pon `ADMIN_PASSWORD` en el `.env` y recrea el contenedor (el seed crea `admin`) |
