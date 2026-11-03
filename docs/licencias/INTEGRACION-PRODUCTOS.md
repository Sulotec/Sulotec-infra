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
- Productos con login propio (PLAFT hoy): la tabla de empresas del producto necesita una columna `uuid` que el administrador llena una vez por
  cliente (PLAFT ya la tiene: `Empresa.uuid`, vacía). Sin UUID no hay licencia: el servicio responde 404 `SIN_LICENCIA`.

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
  "clave_idempotente": "plaft:3f1c2a7e-9b1d-4c7a-8e2f-0a1b2c3d4e5f:scoring_evaluar:48213",
  "tipo": "scoring_evaluar",
  "cantidad": 2,
  "usuario": "mperez",
  "hecho_por_sulotec": false,
  "detalle": { "referencia": "EXP-2026-0481" }
}
```

- `clave_idempotente` (obligatoria, hasta 200 caracteres): única por acción, `<producto>:<empresa_uuid>:<tipo>:<id de la acción>`. Repetir la
  misma clave devuelve **la misma respuesta** con `"repetido": true` y **no descuenta dos veces**: por eso reintentar es seguro.
- `tipo` (obligatorio, hasta 60): qué se consumió, en minúsculas con guion bajo. Sale en los reportes de Sulotec y en `/mi-licencia`.
- `cantidad` (1 a 1000; por defecto 1): la tarifa del producto para esa acción.
- `usuario` (opcional): quién lo hizo, para el detalle por usuario.
- `hecho_por_sulotec`: `true` cuando quien actúa es el Administrador Universal (rol `administrador-general` de Keycloak o su equivalente local; en
  PLAFT, `ADMINISTRADOR`). Nunca se bloquea y se cuenta aparte.
- `detalle` (opcional, JSON): lo que el producto quiera guardar.

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
| PLAFT | `lista_busqueda` (solo la primera página), `scoring_evaluar`, `matriz_registrar`, `matriz_pdf`, `denuncia_crear`, `denuncia_documentos`, `operacion_registrar`, `operacion_pdf`, `mensaje_indira` | la tarifa del producto (hoy de 1 a 3) |
| Buscador Interno | `busqueda` | 1 |
| GeoMatrix | `ubicacion_google` (solo si se enciende Google) | 1 |
| Dashboard Empresarial | ninguno (solo usuarios) | |

## 5. Comportamiento obligatorio del cliente (igual en todas las tecnologías)

1. **Caché por empresa** de 4.1 durante 5 minutos. Si el servicio no responde, se sigue con la **última licencia conocida** y se deja un aviso
   en el log. Nunca se bloquea a un cliente por una caída de Sulotec.
2. **Cupo:** 4.2 antes de crear un usuario. Si `puede_crear` es `false`, el producto responde `409` con «Tu plan llegó al máximo de usuarios» y
   el enlace `https://sulotec.com/mi-licencia`. Después de crear, activar o desactivar: 4.3.
3. **Consumo:** llamada síncrona con espera máxima de **2 segundos**. Si `permitido` es `false`, la acción no se ejecuta: `BOLSA_AGOTADA` →
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

## 7. Caso PLAFT: qué cambia en `modules/creditos` (Security-Backend) y `modules/licencias` (Security-FrontEnd)

**Se queda tal cual:** las tarifas por acción (`AccionCredito`, `tarifas_credito`), el punto donde cada módulo llama a `consumir(...)`, las
excepciones `SaldoInsuficienteException` (402), `LicenciaVencidaException` (403) y `CupoUsuariosExcedidoException` (409), y las pantallas
`CreditosWidget`, `LicenciaBanner`, `HistorialConsumosModal`, `NotificacionesBell` y `SaldoInsuficienteModal`.

**Cambia:**

| Hoy | Debe quedar |
|---|---|
| `CreditoService.consumir` descuenta en `licencias_empresa` y decide el 80 % y el exceso | Llama a 4.4 con `cantidad = costo`, `tipo = accion.name.lowercase()`, `clave_idempotente = "plaft:" + uuid + ":" + tipo + ":" + referencia` (la referencia debe ser única por acción: id de la operación, del scoring, de la matriz o de la denuncia; si no hay, un UUID aleatorio generado una sola vez por intento). `permitido = false` → `SaldoInsuficienteException` si `BOLSA_AGOTADA`, `LicenciaVencidaException` en los demás motivos. Sin respuesta en 2 s → permite y encola (tabla `consumos_pendientes` o la misma `movimientos_credito` con estado `PENDIENTE` y un `@Scheduled` cada minuto que reintenta con la misma clave) |
| El `ADMINISTRADOR` (Sulotec) está exento y no se registra nada | Se llama igual, con `hecho_por_sulotec = true` |
| La empresa se busca por nombre (`findByNombreIgnoreCase`) | Por `Empresa.uuid` (el UUID de Keycloak, que el administrador llena en Administración → Empresas; sin él no hay licencia) |
| `POST /api/licencias/sincronizar` recibe la bolsa que Sulotec «empuja» | Se elimina. En su lugar, 4.1 cada 5 minutos (caché en memoria o `licencias_empresa` como copia: `creditos_totales ← tokens.capacidad`, `creditos_consumidos ← tokens.usados`, `cupo_usuarios ← usuarios_max`, `fecha_vencimiento ← vencimiento`, estado ← `estado`) |
| `GET /api/licencias/mi-bolsa` y `/empresas/{id}` leen `licencias_empresa` | Devuelven la copia de 4.1 con los campos de hoy: `creditosTotales = capacidad`, `creditosConsumidos = usados`, `creditosDisponibles = disponibles`, `porcentajeConsumo = porcentaje`, `enExceso = (nivel == "tolerancia")`, `exceso = tokens.tolerancia`, `toleranciaCreditos = tolerancia_max`, `cupoUsuarios = usuarios_max`, `usuariosActivos = usuarios_activos`, `fechaVencimiento = vencimiento`, `diasParaVencer = dias_para_vencer`, `estado` |
| `verificarVencimientosProgramados` y los avisos del 80 % y del exceso con correo | Se eliminan: los decide y manda el servicio. La campana (`avisos_licencia`) se alimenta de los cambios de `nivel`, `estado` y `dias_para_vencer` al refrescar, sin correos |
| `validarCupoUsuarios` cuenta usuarios locales contra `cupo_usuarios` | 4.2 antes de crear; 4.3 después de crear, activar o desactivar |
| Frontend: `recargarCreditos`, `configurarLicencia` y sus pantallas para el `ADMINISTRADOR` dentro de PLAFT | Se quitan: eso vive en `sulotec.com/licencias`. Las tarifas pueden seguir editables por el `ADMINISTRADOR` porque son del producto. El banner y la campana usan los textos del §5 y el botón «Ampliar plan» abre `https://sulotec.com/mi-licencia` |
| `docs/CREDITOS-Y-LICENCIAS.md`, tabla 1: «Sulotec Central envía asignación» | Sulotec no envía nada: PLAFT consulta al servicio |

Configuración en producción (la pone Sulotec en `/opt/sulotec/plaft.env`): `LICENCIAS_URL=http://licencias:3200`, `LICENCIAS_TOKEN=<token>`,
`LICENCIAS_PRODUCTO=plaft`. Esqueleto del cliente en Kotlin, sin dependencias nuevas (orientativo):

```kotlin
class LicenciasClient(private val url: String, private val token: String) {
    private val http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build()
    private val json = jacksonObjectMapper()

    /** null = el servicio no respondió bien: el que llama permite la acción y encola el consumo. */
    fun consumir(empresaUuid: String, cuerpo: Map<String, Any?>): JsonNode? = try {
        val req = HttpRequest.newBuilder(URI("$url/v1/licencias/$empresaUuid/consumos"))
            .timeout(Duration.ofSeconds(2))
            .header("Authorization", "Bearer $token")
            .header("Content-Type", "application/json")
            .POST(HttpRequest.BodyPublishers.ofString(json.writeValueAsString(cuerpo)))
            .build()
        val res = http.send(req, HttpResponse.BodyHandlers.ofString())
        when (res.statusCode()) {
            200 -> json.readTree(res.body())                       // permitido true/false
            404 -> throw LicenciaVencidaException("SIN_LICENCIA", "La empresa no tiene PLAFT contratado en Sulotec.")
            400 -> throw IllegalArgumentException(json.readTree(res.body())["mensaje"].asText())
            else -> { log.warn("licencias respondió {} en consumos", res.statusCode()); null }   // 401, 5xx: tratar como caída
        }
    } catch (e: IOException) { log.warn("licencias sin respuesta: {}", e.message); null }
}
```

## 8. Los demás productos

Dónde se engancha cada uno (tecnología, tenant, cupo y tipos) está en la tabla de [`ARQUITECTURA.md` §5](ARQUITECTURA.md#5-el-cliente-que-lleva-cada-producto-mismo-comportamiento-en-todas-las-tecnologías).
GeoMatrix y MiRadar 360 comparten un cliente Node (lo escribe Sulotec en Huancayo-Backend y se reutiliza en Afacop-Backend); Dashboard lo
adapta a NestJS; el Buscador lo pone en su proxy Next.js. Todos cumplen el §5 y la lista del §9.

## 9. Lista de verificación antes de dar por conectado un producto

- [ ] El producto guarda el UUID de Keycloak de cada empresa y lo usa en todas las llamadas.
- [ ] Con el servicio apagado el producto sigue funcionando con la última licencia y encola los consumos; al volver los manda y no duplica.
- [ ] Con 20 tokens de prueba: `aviso` al llegar a 16, `tolerancia` en los consumos 21 y 22, bloqueo (402) en el 23.
- [ ] Repetir una llamada con la misma clave no descuenta dos veces.
- [ ] El Administrador Universal nunca es bloqueado y sus consumos van con `hecho_por_sulotec`.
- [ ] Crear un usuario con el cupo lleno da 409 con el enlace a `/mi-licencia`; crear o desactivar reporta los activos.
- [ ] No queda ninguna pantalla de recarga o configuración de licencias dentro del producto, ni correos propios de licencias.
- [ ] Ningún token en el repositorio: solo en `/opt/sulotec/<kit>.env`.
