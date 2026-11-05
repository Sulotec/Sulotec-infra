# Conectar un producto al servicio de licencias (guía para el responsable de cada producto)

**Para quién:** el responsable técnico de cada producto (GeoMatrix, MiRadar 360, PLAFT, Buscador Interno, Dashboard Empresarial).

**Qué es:** el servicio común `licencias` (`https://api-licencias.sulotec.com`, código en `jeliases-informaDev/Licencias-Backend`, kit
[`apps/licencias`](../../apps/licencias/README.md)) guarda la **única verdad** de cada licencia: plan, cupo de usuarios, bolsa de tokens del
mes, paquetes extra, tolerancia, avisos, vencimiento y estado. El Administrador Universal la administra en `sulotec.com/licencias`; el
Administrador General de cada empresa ve lo suyo en `sulotec.com/mi-licencia`. El diseño completo está en [`ARQUITECTURA.md`](ARQUITECTURA.md).

**La regla de oro:** el producto **no decide nada de licencias**: pregunta, consume y muestra lo que el servicio responde. Nada de bolsas
propias, porcentajes propios, correos propios ni pantallas de recarga dentro del producto. Si un día cambia una regla (por ejemplo la
tolerancia), se cambia una vez en `sulotec.com/licencias → Reglas` y aplica a todos los productos.

## 1. Reparto de responsabilidades

| | Servicio común (Sulotec) | Producto |
|---|:---:|:---:|
| Planes; alta, renovación, ampliación, cambio de plan, suspensión y cancelación de licencias | ✔ portal `/licencias` | ✘ |
| Bolsa del mes, paquetes extra y contadores de consumo | ✔ | ✘ (solo pide consumir) |
| Reglas: aviso al 80 %, tolerancia del 10 %, 7 días de aviso y 7 de solo lectura | ✔ parámetros (`/v1/admin/reglas`) | ✘ |
| Correos de aviso al titular (80 %, tolerancia, bloqueo, por vencer, vencida, suspendida) | ✔ | ✘ |
| Reporte para facturar (Excel) y bitácora | ✔ | ✘ |
| Pedido de ampliación del cliente | ✔ `/mi-licencia` | solo enlaza allí |
| Empresas y su UUID | ✔ Keycloak, grupo «Empresas» | guarda el UUID |
| **Tarifa**: cuántos tokens cuesta cada acción del producto | ✘ | ✔ (se manda como `cantidad`) |
| Pedir cupo antes de crear un usuario y reportar los activos | ✘ | ✔ |
| Consumir en el momento de la acción que cuesta, con clave idempotente | ✘ | ✔ |
| Franjas y mensajes en pantalla según `nivel` y `estado` | ✘ | ✔ (textos comunes, §5) |
| Caché de 5 minutos, seguir si Sulotec cae, cola de reintentos | ✘ | ✔ |

## 2. Credenciales y direcciones

- **Token de producto** con la forma `<producto>.<secreto>`. Lo genera el Administrador Universal en `sulotec.com/licencias → Productos →
  Generar token` o en el servidor con `sudo docker exec licencias node scripts/token-producto.js plaft`. Se muestra **una sola vez**; va al
  `.env` del producto en `/opt/sulotec/<kit>.env` (lo pone Sulotec al desplegar). Nunca al repositorio ni al chat. Rotarlo invalida el anterior:
  hay que actualizar el `.env` y reiniciar el producto.
- **Dirección:** dentro de la VM `http://licencias:3200` (red Docker `sulotec_edge`, donde ya están los backends publicados; si tu contenedor
  no está en esa red, agrégala en su compose). Desde fuera de la VM, `https://api-licencias.sulotec.com`.
- **Variables sugeridas:** `LICENCIAS_URL`, `LICENCIAS_TOKEN`, `LICENCIAS_PRODUCTO` (`geomatrix` · `miradar360` · `plaft` · `buscador` · `dashboard`).
- **Cabecera:** `Authorization: Bearer <token>`. Sin token: 401 `TOKEN_REQUERIDO`; token malo o rotado: 401 `TOKEN_INVALIDO`.
- **Errores**, siempre JSON: `{ "error": "CODIGO", "mensaje": "texto listo para mostrar" }`.

## 3. La empresa es su UUID de Keycloak

- Cada empresa cliente es un subgrupo de «Empresas» en la cuenta Sulotec (`cuenta.sulotec.com`) con el atributo `empresa_uuid`. Es **el mismo
  UUID** en todos los productos y en el servicio de licencias.
- Dónde verlo: en `sulotec.com/licencias`, debajo del nombre de cada empresa, o con `apps/cuenta/empresa.sh`.
- Productos con inicio único de Sulotec (GeoMatrix, MiRadar 360, Dashboard): el token de Keycloak trae `empresa_uuid`; se usa tal cual.
- Productos con login propio (PLAFT hoy): cada empresa de PLAFT ya tiene su `uuid` desde que se crea (`Empresa.uuid`, se genera solo). Ese es el
  UUID que se registra en la cuenta Sulotec con `apps/cuenta/empresa.sh --uuid`, y PLAFT también acepta un UUID al crear o editar la empresa
  (solo el administrador universal). Sin UUID igual en los dos lados no hay licencia: el servicio responde 404 `SIN_LICENCIA`.

## 4. Las cinco llamadas (contrato v1)

Todas bajo `{LICENCIAS_URL}/v1`, con la cabecera del §2. Son las mismas para todos los productos.

### 4.1 Estado de la licencia: `GET /v1/licencias/{empresa_uuid}`

Cuándo: al iniciar sesión alguien de esa empresa y luego cada 5 minutos (caché). Respuesta `200`:

```json
{
  "id": 7,
  "empresa_uuid": "3f1c2a7e-9b1d-4c7a-8e2f-0a1b2c3d4e5f",
  "empresa_nombre": "Caja Piura",
  "producto": "plaft",
  "producto_nombre": "PLAFT",
  "plan": "Plan Impulsa",
  "plan_id": 2,
  "estado": "ACTIVA",
  "usuarios_max": 10,
  "usuarios_activos": 4,
  "puede_crear_usuarios": true,
  "periodo": "2026-11",
  "tokens": { "bolsa": 500, "extra": 0, "capacidad": 500, "usados": 120, "disponibles": 380, "porcentaje": 24, "nivel": "normal", "tolerancia": 0, "tolerancia_max": 50 },
  "inicio": "2026-11-03",
  "vencimiento": "2027-11-03",
  "dias_para_vencer": 365,
  "titular": { "email": "admin@cajapiura.pe", "nombre": "Administradora General" },
  "creado_en": "2026-11-03T15:00:00.000Z"
}
```

- `estado`: `ACTIVA` · `SOLO_LECTURA` (vencida hace menos de 7 días: se puede ver, no registrar) · `SUSPENDIDA` · `CANCELADA`. Se calcula por
  fecha en cada lectura, así que siempre es la verdad del día.
- `tokens` es `null` en los productos que se licencian solo por usuarios (GeoMatrix, Dashboard).
- `tokens.nivel`: `normal` · `aviso` (80 % o más) · `tolerancia` (bolsa agotada; se está usando el 10 % extra, que se factura aparte) · `bloqueado`.
- `tokens.bolsa` es la del mes (`periodo`); `extra`, lo que queda de paquetes adicionales; `capacidad = bolsa + extra`; `usados`, lo consumido
  del mes; `tolerancia`, lo ya usado de la tolerancia, y `tolerancia_max` su tope.
- `404 SIN_LICENCIA`: la empresa no tiene este producto contratado.

### 4.2 Cupo de usuarios: `GET /v1/licencias/{empresa_uuid}/cupo`

Cuándo: justo antes de crear o reactivar un usuario. `200`:

```json
{ "puede_crear": true, "activos": 4, "usuarios_max": 10, "estado": "ACTIVA" }
```

`puede_crear` es `false` si el cupo está lleno o la licencia no está `ACTIVA`.

### 4.3 Reportar usuarios activos: `PUT /v1/licencias/{empresa_uuid}/usuarios-activos`

Cuándo: después de crear, activar o desactivar un usuario, y una vez al arrancar la integración para alinear el conteo.
Cuerpo `{ "activos": 5 }`. Responde igual que 4.2.

### 4.4 Consumir tokens: `POST /v1/licencias/{empresa_uuid}/consumos`

Cuándo: en el momento de la acción que cuesta, **antes** de ejecutarla (si no está permitido, la acción no se ejecuta). Cuerpo:

```json
{
  "clave_idempotente": "plaft:3f1c2a7e-9b1d-4c7a-8e2f-0a1b2c3d4e5f:scoring:48213",
  "tipo": "scoring",
  "cantidad": 2,
  "usuario": "mperez",
  "hecho_por_sulotec": false,
  "detalle": { "referencia": "EXP-2026-0481" }
}
```

- `clave_idempotente` (obligatoria, hasta 200 caracteres): única por acción, `<producto>:<empresa_uuid>:<tipo>:<id de la acción>`. Repetir la
  misma clave devuelve **la misma respuesta** con `"repetido": true` y **no descuenta dos veces**: por eso reintentar es seguro.
- `tipo` (obligatorio, hasta 60): qué se consumió, en minúsculas con guion bajo. Sale en los reportes de Sulotec y en `/mi-licencia`.
- `cantidad` (1 a 1000; por defecto 1): solo se usa si Sulotec no tiene tarifa para ese `tipo` (ver «Tarifas» abajo).
- `usuario` (opcional): quién lo hizo, para el detalle por usuario.
- `hecho_por_sulotec`: `true` cuando quien actúa es el Administrador Universal (rol `administrador-general` de Keycloak o su equivalente local; en
  PLAFT, `ADMINISTRADOR`). Nunca se bloquea y se cuenta aparte.
- `detalle` (opcional, JSON): lo que el producto quiera guardar.
- **Tarifas: las pone Sulotec, no el producto.** El costo de cada acción lo decide Sulotec con una **tabla de tarifas** por producto, que el administrador universal edita en `sulotec.com/licencias`. El producto manda el `tipo` de la acción; si hay tarifa para ese tipo, Sulotec descuenta lo que diga la tarifa e ignora la `cantidad` que mande el producto. Si no hay tarifa para ese tipo, se usa la `cantidad` enviada (compatibilidad).
- La respuesta permitida trae `cobrado` (tokens descontados, puede ser 0). Una tarifa en 0 significa que la acción no descuenta.
- Una tarifa puede marcarse como «no bloquea»: si se acaban los tokens, la acción pasa igual sin descontar y la respuesta trae `sin_descuento: true` (se usa para el canal de denuncias de PLAFT).
- `GET /v1/licencias/{uuid}` trae `tarifas: [{ tipo, nombre, tokens, bloquea }]` para que el producto pueda mostrar al cliente qué descuenta tokens. El producto nunca debe escribir costos en su código.

Respuesta `200` permitido:

```json
{ "permitido": true, "nivel": "normal", "disponibles": 378, "porcentaje": 24, "capacidad": 500, "usados": 122, "periodo": "2026-11" }
```

Respuesta `200` no permitido (la acción **no** se ejecuta):

```json
{ "permitido": false, "motivo": "BOLSA_AGOTADA", "disponibles": 0, "porcentaje": 100, "capacidad": 500, "usados": 550, "periodo": "2026-11" }
```

`motivo`: `BOLSA_AGOTADA` · `SOLO_LECTURA` · `SUSPENDIDA` · `SIN_LICENCIA` (licencia cancelada). Errores: `400 DATOS_INVALIDOS` (algún campo),
`400 PRODUCTO_SIN_TOKENS` (producto que se licencia solo por usuarios), `404 SIN_LICENCIA` (la empresa no tiene el producto).
El servicio manda solo los correos de aviso al titular (80 %, tolerancia, bloqueo); el producto no manda ninguno.

### 4.5 Anular un consumo: `DELETE /v1/consumos/{clave_idempotente}`

Cuándo: si la acción falló **después** de consumir (por ejemplo el proveedor externo no respondió). `200 { "anulado": true }`
(`"repetido": true` si ya estaba anulado). `404 CONSUMO_NO_ENCONTRADO`.

### Tipos de consumo por producto

| Producto | `tipo` | `cantidad` |
|---|---|---|
| MiRadar 360 | `consulta_reniec`, `ubicar_direccion` | 1 |
| PLAFT | `busqueda_listas` (solo la primera página), `scoring`, `mensaje_indira` | 1 |
| Buscador Interno | `busqueda` | 1 |
| GeoMatrix | `ubicacion_google` (solo si se enciende Google) | 1 |
| Dashboard Empresarial | ninguno (solo usuarios) | |

## 5. Comportamiento obligatorio del cliente (igual en todas las tecnologías)

1. **Caché por empresa** de 4.1 durante 5 minutos. Si el servicio no responde, se sigue con la **última licencia conocida** y se deja un aviso
   en el log. Nunca se bloquea a un cliente por una caída de Sulotec.
2. **Cupo:** 4.2 antes de crear un usuario. Si `puede_crear` es `false`, el producto responde `409` con «Tu plan llegó al máximo de usuarios» y
   el enlace `https://sulotec.com/mi-licencia`. Después de crear, activar o desactivar: 4.3.
3. **Consumo:** llamada síncrona con espera máxima de **3 segundos**. Si `permitido` es `false`, la acción no se ejecuta: `BOLSA_AGOTADA` →
   `402` con el botón **Ampliar plan** (enlace a `/mi-licencia`); `SOLO_LECTURA`, `SUSPENDIDA` o `SIN_LICENCIA` → `403` con el mensaje del estado.
   Si el servicio **no responde** (tiempo agotado, error de red o 5xx), se **permite** la acción y el consumo entra en una **cola local de
   reintento** con la misma clave idempotente (reintento cada minuto hasta que entre). Si la acción falla después de consumir: 4.5.
   Un `401` es un error de configuración del token: se registra como ERROR y se trata como caída (permitir y encolar) para no castigar al cliente.
4. **Universal:** `hecho_por_sulotec: true`; se consume y registra, nunca se bloquea. No se omite la llamada: Sulotec quiere ver también lo que
   hace su propio equipo.
5. **Mensajes al usuario** (texto común para todos los productos):
   - `nivel = aviso`: franja amarilla «Usaste el 80 % de tu bolsa de este mes».
   - `nivel = tolerancia`: franja naranja «Bolsa agotada: estás usando la tolerancia del 10 %, se factura aparte».
   - `BOLSA_AGOTADA`: «Bolsa agotada» con el botón **Ampliar plan**.
   - `SOLO_LECTURA`: «Licencia vencida: puedes ver, no registrar».
   - `SUSPENDIDA`: pantalla de contacto con Sulotec (`contacto@sulotec.com`).
   - `dias_para_vencer` de 7 o menos: aviso discreto «Tu licencia vence en N días».
6. **Nada de reglas propias:** el producto no calcula porcentajes ni plazos; las campanas o avisos dentro del producto se derivan de `nivel`,
   `estado` y `dias_para_vencer` al refrescar la licencia, no de contadores propios.
7. **Log:** cada llamada deja una línea con empresa, llamada, resultado y milisegundos; los fallos de red, en nivel WARN.
8. **Productos sin tokens** (GeoMatrix, Dashboard): si el servicio responde `404 SIN_LICENCIA` (la empresa no tiene el producto registrado, o su UUID
   no coincide) **no se bloquea nada** ni se exige cupo; se avisa al administrador de la empresa con una franja y se deja un WARN en el log.
   El bloqueo solo aplica a los estados explícitos `SOLO_LECTURA`, `SUSPENDIDA` y `CANCELADA`. Así, poner el token antes de registrar la licencia
   de un cliente no deja a nadie fuera.

## 6. Cómo probar sin tocar producción

1. Levanta el servicio en tu PC (README de `Licencias-Backend`): PostgreSQL en Docker y `npm run dev` (puerto 3200).
2. Crea una licencia de prueba y el token del producto **sin Keycloak**:

   ```bash
   node --env-file=.env scripts/licencia-prueba.js plaft --tokens 20 --usuarios 2
   ```

   Imprime la licencia (con un `empresa_uuid` de prueba) y el token para `LICENCIAS_TOKEN`.
3. Apunta tu producto a `LICENCIAS_URL=http://localhost:3200` y comprueba, con 20 tokens: `nivel: "aviso"` al llegar a 16 usados, `tolerancia` en
   los consumos 21 y 22, `permitido: false` en el 23. Repite una llamada con la misma clave: no descuenta. Apaga el servicio: el producto sigue
   trabajando con la última licencia y encola los consumos; al volver, los manda sin duplicar.
4. En producción, el Administrador Universal crea la licencia real en `sulotec.com/licencias`, genera el token del producto y lo pone en
   `/opt/sulotec/<kit>.env`.

## Cuentas y acceso: lo decide Sulotec

Todo el manejo de licencias, cuentas, accesos y tokens es exclusivo de Sulotec. El producto solo avisa qué acción se hizo.

- Al crear una licencia con titular en `sulotec.com/licencias`, Sulotec crea la cuenta Sulotec del titular (si no existe) y le manda la invitación para crear su contraseña. No hay que correr scripts en el servidor. En licencias que ya existían, la acción «Invitar al titular» hace lo mismo.
- Todo producto debe ofrecer el inicio único con la cuenta Sulotec (OpenID Connect + PKCE contra `cuenta.sulotec.com`, un cliente público por producto) además de su login propio.
- Regla del titular: la primera vez que el titular de la licencia entra por inicio único, el producto crea solo su empresa (con el UUID que da Sulotec) y su usuario administrador de empresa. El producto sabe quién es el titular porque `GET /v1/licencias/{uuid}` trae `titular: { email, nombre }`. El titular nunca queda fuera por falta de cupo.
- Los demás usuarios de la empresa los crea el titular dentro del producto, y Sulotec solo controla cuántos caben (cupo). Si un usuario tiene cuenta Sulotec con el mismo correo, entra también por inicio único.
- Los administradores universales de Sulotec (rol `administrador-general` en el token) entran a cualquier producto.
- **Estado:** implementado en PLAFT (PRs en curso el 2026-11-05); **pendiente en GeoMatrix** (hoy GeoMatrix exige que ya exista un usuario local con ese correo).

## 7. PLAFT (conectado: mismo criterio que GeoMatrix, más tokens)

PLAFT se licencia por usuarios y por tokens. Se conecta con el mismo criterio que GeoMatrix (§8) y suma diez acciones que consumen tokens.
Sulotec es la única verdad: PLAFT no guarda saldos ni decide bolsas.

**Qué se retiró:** el módulo propio de créditos de prueba (Security-Backend `modules/creditos` y Security-FrontEnd `modules/licencias`): el descuento
local, el endpoint que recibía la bolsa (`/api/licencias/sincronizar`), los endpoints `/api/licencias/*` (mi-bolsa, empresas/{id}, movimientos,
avisos), los correos de 80 % y de exceso, el cron de vencimientos y las pantallas de saldo, banner, historial, campana y recarga. Las tablas
`licencias_empresa`, `movimientos_credito`, `tarifas_credito` y `avisos_licencia` se quitan de la base con `apps/plaft/deploy/quitar-creditos-prueba.sh`
(respalda antes).

**Las diez acciones que consumen tokens**, pidiendo permiso **antes** de ejecutar cada acción. El costo vive en Sulotec y se cambia desde el portal `sulotec.com/licencias`; los números de la tabla son los iniciales:

| tipo | Acción | Tokens (inicial) | Si se acaban |
|---|---|:---:|---|
| `busqueda_listas` | Búsqueda en listas negativas (solo la primera página) | 1 | se bloquea |
| `lista_pdf` | PDF de una coincidencia de listas | 1 | se bloquea |
| `scoring` | Evaluación de scoring | 2 | se bloquea |
| `matriz_registrar` | Registrar una matriz de riesgo (los borradores no) | 3 | se bloquea |
| `matriz_pdf` | PDF de una matriz | 1 | se bloquea |
| `denuncia_crear` | Registrar una denuncia | 2 | pasa sin descontar |
| `denuncia_documentos` | Archivos de una denuncia (por lote) | 1 | pasa sin descontar |
| `operacion_registrar` | Registrar una operación | 2 | se bloquea |
| `operacion_pdf` | PDF de una operación | 1 | se bloquea |
| `mensaje_indira` | Mensaje a Indira | 1 | se bloquea |

Esta tabla es la que definió el equipo de PLAFT (Henry) para sus cinco módulos, más el mensaje a Indira. PLAFT entra además con la cuenta Sulotec (variables `SSO_ISSUER`, `SSO_CLIENT_ID`, `SSO_REDIRECT_URI` del kit `apps/plaft`).

**Clave idempotente (4.4).** Scoring e Indira: `plaft:<empresa_uuid>:<tipo>:<UUID aleatorio>`. La búsqueda es determinista para que una misma
búsqueda no cobre dos veces: `plaft:<empresa_uuid>:busqueda_listas:<SHA-256 en hex (32 primeros) de usuario y criterios normalizados>:<ventana de
dos minutos>`. Un doble clic o recargar la misma búsqueda dentro de la ventana repite la clave y el servicio responde lo mismo con `"repetido": true`.

**Sin el servicio (§5.3).** Si no responde (tiempo agotado, red o 5xx), PLAFT permite la acción y encola el consumo con la **misma** clave para
reintentarlo cada minuto. Si la última licencia conocida está en `SOLO_LECTURA`, `SUSPENDIDA` o `CANCELADA`, responde el 403 que corresponda; si su
`tokens.nivel` es `bloqueado`, responde 402. Si nunca se conoció una licencia, se trata como activa. Si la acción falla después de consumir, se anula
con 4.5; si la anulación tampoco responde, se encola. Un `401` se registra como error de configuración (token mal puesto).

**Guard de escrituras (§8 D1 a D5), con las excepciones de PLAFT.** Solo se revisan POST, PUT, PATCH y DELETE. Siempre pasan: las lecturas (GET,
HEAD, OPTIONS), las peticiones sin autenticar, el rol `ADMINISTRADOR` de Sulotec, `/api/auth/**`, `/api/public/**`, `/api/licencia`, `/api/empresas/**`,
el canal de denuncias (crear denuncia, consultarla por su código y subir archivos: la licencia nunca lo corta) y los cálculos sin guardar
(`calcular-inherente` y `calcular-residual`). Con `SOLO_LECTURA` se bloquea el resto con `403 LICENCIA_SOLO_LECTURA`, salvo desactivar usuarios e
invitar. Con `SUSPENDIDA` (`403 LICENCIA_SUSPENDIDA`) o `CANCELADA` (`403 LICENCIA_CANCELADA`) se bloquea el resto, salvo desactivar usuarios.
Sin licencia registrada o con licencias apagadas, todo pasa. La búsqueda en listas es un GET: la bloquea el propio consumo (403 si no está permitido).

**Cupo de usuarios (4.2 y 4.3, §8 D6 y D7).** Se exige a todos, también al `ADMINISTRADOR`. Antes de crear una cuenta, reactivar una inactiva,
mover una cuenta activa a otra empresa y en la carga masiva (las cuentas válidas del lote no pueden pasar del cupo libre). Sin cupo: `409
LICENCIA_SIN_CUPO` con `activos`, `usuarios_max` y `enlace`. Después de crear, activar, desactivar, mover o cargar en lote, reporta los activos de
cada empresa afectada (después de guardar y sin demorar la respuesta), y al arrancar, de todas las empresas activas con UUID. Usuario activo =
fila de `usuarios` con `activo = true` de esa empresa, de cualquier rol.

**Licencia pública (C1).** `GET /api/licencia` (cualquier rol; `?refrescar=1` fuerza leer) devuelve `exento`, `empresa` y `licencia`. Si `licencia`
es `null`, las licencias están apagadas o no hay información y el front no muestra nada.

**Errores (C2).** El JSON de siempre (`timestamp`, `status`, `error`, `message`, `path`) más, cuando aplica, `code`, `enlace`, `estado`, `activos` y
`usuarios_max`: `402 LICENCIA_BOLSA_AGOTADA`; `403 LICENCIA_SOLO_LECTURA`, `LICENCIA_SUSPENDIDA` o `LICENCIA_CANCELADA`; `409 LICENCIA_SIN_CUPO`. El
`enlace` (`https://sulotec.com/mi-licencia`, o `https://sulotec.com/licencias` si quien actúa es el administrador de Sulotec) va en los tres.

**UUID de la empresa (§3).** Se toma de `Empresa.uuid` de PLAFT, buscando la empresa por su nombre (la cuenta del usuario lleva la empresa como
texto). Sin UUID no se consulta ni se consume nada. El administrador de Sulotec sin empresa no consulta ni consume nada tampoco. Sus consumos
(cuando tiene empresa) van con `hecho_por_sulotec = true` y nunca se bloquean. `POST /api/empresas` y `PUT /api/empresas/{id}` aceptan un `uuid`
opcional (solo administrador universal) para igualarlo al de la cuenta Sulotec.

**Configuración** (la pone `apps/plaft/deploy/preparar.sh` en `/opt/sulotec/plaft.env`): `LICENCIAS_URL=http://licencias:3200`,
`LICENCIAS_PRODUCTO=plaft` y `LICENCIAS_TOKEN=plaft.<secreto>` (vacío = apagado). La puesta en marcha está en
[`apps/plaft/README.md`](../../apps/plaft/README.md#licencias-de-sulotec-usuarios-y-tokens).

## 8. Los demás productos

Dónde se engancha cada uno (tecnología, tenant, cupo y tipos) está en la tabla de [`ARQUITECTURA.md` §5](ARQUITECTURA.md#5-el-cliente-que-lleva-cada-producto-mismo-comportamiento-en-todas-las-tecnologías).
GeoMatrix y MiRadar 360 comparten un cliente Node (ya escrito en Huancayo-Backend, ver abajo; se reutiliza en Afacop-Backend); Dashboard lo
adapta a NestJS; el Buscador lo pone en su proxy Next.js. Todos cumplen el §5 y la lista del §9.

### GeoMatrix (conectado: PRs Huancayo-Backend#45, CajaHuancayo-Web#50 y CajaHuancayo-App#21)

Es la referencia para MiRadar 360 y Dashboard: el mismo cliente Node y el mismo criterio. GeoMatrix se licencia solo por usuarios (`tokens: null`).
Kit `apps/auditoria`: `LICENCIAS_URL`, `LICENCIAS_PRODUCTO`, `LICENCIAS_TOKEN`; con el token vacío las licencias están apagadas y nada se consulta.
Decisiones tomadas (D1 a D9), para que MiRadar 360 y Dashboard copien el criterio:

| Decisión | Cómo quedó en GeoMatrix |
|---|---|
| D1 Dónde corre el guard | Al final de la autenticación, ya con el usuario verificado y la empresa que sale del token del servidor (nunca de lo que mande el cliente) |
| D2 Exentos siempre | `GET`; el rol `UNIVERSAL` (Sulotec nunca se bloquea); las rutas `/api/auth`, `/api/terminos`, `/api/empresas` y `/api/licencia`; la telemetría GPS (`PATCH /api/visitas/ubicacion`: bloquearla apagaría el seguimiento de la app); `POST /api/rutas/trazar` (no escribe); cerrar la jornada (`TERMINAR`); `PUT /api/limpieza/modo-pruebas` |
| `ACTIVA` | Todo pasa; solo se exige el cupo al crear o reactivar usuarios |
| D3 `SOLO_LECTURA` → `403 LICENCIA_SOLO_LECTURA` | Se bloquean las escrituras de trabajo. Se permiten editar, desactivar y eliminar usuarios y los ajustes de asignación (el cliente puede ordenar su cuenta); crear o reactivar usuarios, no |
| D4 `SUSPENDIDA` → `403 LICENCIA_SUSPENDIDA`; `CANCELADA` → `403 LICENCIA_CANCELADA` | Se bloquea todo lo no exento salvo las bajas de usuarios (para que el cliente pueda reducir su consumo). Las lecturas siempre pasan |
| D5 `404 SIN_LICENCIA` o licencia desconocida | **No se bloquea nada** ni se exige cupo: solo un WARN en el log y una franja para los administradores. Protege el despliegue: el token puede ponerse antes de registrar la licencia |
| Servicio caído | Caché de 5 minutos por empresa; se sigue con la última licencia conocida (§5.1); tras un fallo se espera 30 s antes de volver a preguntar. Un `401` (token mal puesto) se registra como error y se trata como caída |
| D8 Formato del bloqueo | `403 { error: <texto para la persona>, code: LICENCIA_*, estado, enlace: https://sulotec.com/mi-licencia, requestId }`; el registro de seguridad lo clasifica como `LICENCIA_BLOQUEO` (aviso), no como intento sin permiso |
| D6 Cupo (4.2) | Se exige a todos, incluido el `UNIVERSAL` (el cupo es del plan; él lo amplía en `sulotec.com/licencias`). Sin cupo: `409` con `code: LICENCIA_SIN_CUPO` y `enlace` = `https://sulotec.com/mi-licencia` (`https://sulotec.com/licencias` si quien crea es el universal) |
| D7 Usuario activo (4.3) | Fila de `usuarios` con `estado = 'ACTIVO'` de la empresa, de cualquier rol; se reporta tras crear, activar, desactivar o eliminar |
| D9 Licencia pública (lo que ven panel y app) | `GET /api/licencia` y el campo `licencia` en `GET /api/auth/me`, `GET /api/empresas/actual`, `GET /api/visitas/config` y `GET /api/asignaciones/mias` (la app la recibe con la muestra, que consulta cada 20 s); `null` = licencias apagadas, sin franja |

## 9. Lista de verificación antes de dar por conectado un producto

- [ ] El producto guarda el UUID de Keycloak de cada empresa y lo usa en todas las llamadas.
- [ ] Con el servicio apagado el producto sigue funcionando con la última licencia y encola los consumos; al volver los manda y no duplica.
- [ ] Con 20 tokens de prueba: `aviso` al llegar a 16, `tolerancia` en los consumos 21 y 22, bloqueo (402) en el 23.
- [ ] Repetir una llamada con la misma clave no descuenta dos veces.
- [ ] El Administrador Universal nunca es bloqueado y sus consumos van con `hecho_por_sulotec`.
- [ ] Crear un usuario con el cupo lleno da 409 con el enlace a `/mi-licencia`; crear o desactivar reporta los activos.
- [ ] No queda ninguna pantalla de recarga o configuración de licencias dentro del producto, ni correos propios de licencias.
- [ ] Ningún token en el repositorio: solo en `/opt/sulotec/<kit>.env`.
