# Licencias de Sulotec: cómo se construye (una sola lógica para todos los productos)

> Complementa [`LICENCIAS.md`](LICENCIAS.md) (el modelo) con el diseño técnico. Regla de oro: **ningún producto implementa reglas de
> licencia por su cuenta**. Hay un servicio común que decide, y cada producto solo le pregunta y le reporta. Estado: diseño propuesto
> el 2026-11-02 y aprobado ese mismo día («dale»). **Construido:** servicio en `jeliases-informaDev/Licencias-Backend`, kit `apps/licencias`,
> pantallas del portal y ajuste de Keycloak (rama `licencias` de este repo). Falta instalarlo en el servidor y conectar los productos.

## 1. Piezas

| Pieza | Qué es | Dónde vive |
|---|---|---|
| **Servicio Licencias** (`licencias`) | API + tareas programadas. Es **la verdad** de planes, licencias, cupos, bolsas, consumo y avisos. | Contenedor `licencias` en la VM (Node 24 + Express), base `licencias` en el PostgreSQL 16 compartido, kit `apps/licencias` en Sulotec-infra, dominio `api-licencias.sulotec.com` por el túnel. Código en `jeliases-informaDev/Licencias-Backend` (nombre propuesto). |
| **Pantallas en el portal** | `/licencias` (Sulotec: todas las empresas) y `/mi-licencia` (Administrador General: solo su empresa). | Páginas Astro del portal (como `/mis-productos`): HTML estático + JS que llama al servicio con el token de la cuenta Sulotec. El portal **no** tiene backend propio; el servicio es su backend. |
| **Cliente de licencias** (uno por tecnología) | Módulo pequeño, idéntico en comportamiento, que cada producto usa para preguntar y reportar. | Node (GeoMatrix, MiRadar 360, Dashboard), Spring Boot (PLAFT), Next.js (Buscador, en su proxy). Ver §5. |
| **Keycloak** | Identidad: quién es, su empresa (`empresa_uuid`), sus productos (`producto-*`), si es universal (`administrador-general`). | `cuenta.sulotec.com`. **Sin contadores ni planes.** |

## 2. Quién habla con el servicio y cómo se identifica

| Quién | Credencial | Qué puede |
|---|---|---|
| **Cada producto** (servidor a servidor) | Token propio por producto (`LICENCIAS_TOKEN`, en `/opt/sulotec/<producto>.env`; el servicio guarda solo su hash; se rota desde `/licencias`) | Leer **su** licencia de una empresa, descontar consumo, reportar usuarios activos. Un producto no puede tocar la licencia de otro. |
| **Administrador Universal** (persona) | Access token de Keycloak con el rol `administrador-general` | Todo: planes, crear/ampliar/renovar/suspender licencias, reporte de consumo, rotar tokens de productos. Todo queda registrado con su usuario. |
| **Administrador General** (persona) | Access token de Keycloak con `empresa_uuid` | Ver sus licencias y su consumo; pedir ampliación. **Nunca** cambia su propio plan. |
| **Sub-usuarios** | — | No hablan con el servicio: lo hace el producto por ellos. |

Ajuste en Keycloak (en `ajustar-realm.sh`): el claim `roles` y los `empresa_*` deben ir también en el **access token** del cliente `portal`
(hoy `roles` solo va en el id_token) y el token debe llevar la audiencia `licencias`. El servicio valida la firma con el JWKS de
`cuenta.sulotec.com` y no guarda contraseñas.

## 3. Datos (PostgreSQL, base `licencias`)

| Tabla | Columnas principales | Nota |
|---|---|---|
| `productos` | `clave` (geomatrix, miradar360, plaft, buscador, dashboard), `nombre`, `usa_tokens`, `token_hash`, `token_rotado_en` | Catálogo fijo. |
| `planes` | `id`, `producto`, `nombre`, `usuarios_max`, `tokens_periodo`, `periodo` (`mensual`), `precio`, `activo` | Lo que se vende. |
| `licencias` | `id`, `empresa_uuid`, `producto`, `plan_id`, `usuarios_max`, `tokens_periodo`, `inicio`, `vencimiento`, `estado`, `titular_email`, `titular_nombre`, `creado_por`, `creado_en` | **Una por empresa y producto** (`UNIQUE(empresa_uuid, producto)`). El `empresa_uuid` es el mismo de Keycloak y del producto. |
| `periodos` | `licencia_id`, `periodo` (`2026-11`), `bolsa`, `extra`, `consumidos`, `aviso_80_en` | Contador del mes; se abre solo al primer consumo del periodo. |
| `bolsas_extra` | `licencia_id`, `cantidad`, `restante`, `vence` (12 meses), `creado_por` | Paquetes adicionales; se gastan después de la bolsa del mes. |
| `consumos` | `id`, `licencia_id`, `periodo`, `usuario`, `tipo`, `cantidad`, `hecho_por_sulotec`, `clave_idempotente` (UNIQUE), `detalle` jsonb, `creado_en` | Registro línea a línea: de aquí sale la factura y «Mi licencia». |
| `usuarios_activos` | `licencia_id`, `activos`, `reportado_en` | Lo reporta el producto cada vez que crea o desactiva. |
| `avisos` | `licencia_id`, `tipo` (`80`, `tolerancia`, `bloqueo`, `vence_7`, `vencida`, `suspendida`), `destinatario`, `enviado_en` | Para no repetir avisos. |
| `bitacora` | `quien`, `accion`, `licencia_id`, `antes`, `despues`, `cuando` | Todo lo que hace un universal. |

**Estados de una licencia:** `ACTIVA` → (vence) `SOLO_LECTURA` (7 días) → `SUSPENDIDA`; `CANCELADA` por decisión comercial. Los datos del
producto nunca se borran por licencia.

## 4. Contrato de la API (v1, JSON, igual para todos los productos)

### 4.1 Lo que usan los productos (`Authorization: Bearer <token del producto>`)

| Llamada | Para qué | Respuesta |
|---|---|---|
| `GET /v1/licencias/{empresa_uuid}` | Al iniciar sesión alguien de esa empresa y cada 5 minutos (caché) | `{ estado, plan, usuarios_max, usuarios_activos, puede_crear_usuarios, tokens: { bolsa, extra, consumidos, disponibles, porcentaje, nivel }, vencimiento, dias_para_vencer, titular }`. `404` = la empresa no tiene este producto contratado. |
| `GET /v1/licencias/{empresa_uuid}/cupo` | Justo antes de crear un usuario | `{ puede_crear, activos, usuarios_max }` |
| `PUT /v1/licencias/{empresa_uuid}/usuarios-activos` `{ activos }` | Después de crear, activar o desactivar un usuario | `{ activos, usuarios_max, puede_crear }` |
| `POST /v1/licencias/{empresa_uuid}/consumos` `{ clave_idempotente, tipo, cantidad, usuario, hecho_por_sulotec, detalle }` | En el momento de hacer la consulta que cuesta | `{ permitido: true, nivel: "normal" \| "aviso" \| "tolerancia", disponibles }` o `{ permitido: false, motivo: "BOLSA_AGOTADA" \| "SOLO_LECTURA" \| "SUSPENDIDA" \| "SIN_LICENCIA" }` |
| `DELETE /v1/consumos/{clave_idempotente}` | Si la consulta externa falló después de descontar (p. ej. RENIEC caído) | `200 { anulado: true }`: el consumo se anula y no se cobra |

Reglas que aplica el servicio en `consumos` (las del modelo, en un solo lugar): `permitido` mientras `consumidos < bolsa + extra`;
al pasar el 80 % responde `nivel: "aviso"` y manda **un** correo al titular; entre el 100 % y el 110 % responde `nivel: "tolerancia"`
(se registra para facturar); desde el 110 % responde `permitido: false`. `hecho_por_sulotec: true` nunca se bloquea y se marca aparte.
La `clave_idempotente` la arma el producto (`<producto>:<empresa>:<id de la consulta>`): repetir la llamada devuelve la misma
respuesta y **no** descuenta dos veces (reintentos seguros).

### 4.2 Lo que usan las personas (access token de Keycloak)

| Llamada | Quién | Para qué |
|---|---|---|
| `GET/POST/PATCH /v1/admin/planes` | Universal | Catálogo de planes |
| `GET/POST /v1/admin/licencias`, `PATCH /v1/admin/licencias/{id}` (`ampliar`, `renovar`, `cambiar_plan`, `suspender`, `reactivar`, `titular`) | Universal | Alta y ciclo de vida; cada cambio va a `bitacora` |
| `POST /v1/admin/licencias/{id}/bolsas-extra` | Universal | Vender un paquete adicional |
| `GET /v1/admin/consumos?desde&hasta&producto&empresa` (JSON y Excel) | Universal | Reporte para facturar, con la tolerancia y lo «hecho por Sulotec» separados |
| `POST /v1/admin/productos/{clave}/token` | Universal | Rotar el token de un producto (se muestra una sola vez) |
| `GET /v1/admin/empresas`, `POST /v1/admin/empresas` | Universal | Empresas de Keycloak (subgrupos de «Empresas»): listar, y crear una nueva con su UUID desde «Nueva licencia» (el servicio usa su cliente `licencias` con cuenta de servicio, por la dirección interna `http://cuenta:8080`). Al crear una licencia la empresa recibe el rol `producto-*`; al cancelarla lo pierde |
| `GET /v1/mi-licencia` | Administrador General | Sus licencias (todas sus productos) con consumo del periodo |
| `GET /v1/mi-licencia/{producto}/consumos?periodo` | Administrador General | Detalle por usuario y tipo |
| `POST /v1/mi-licencia/{producto}/ampliar` `{ que: "usuarios" \| "tokens" \| "plan", cantidad, comentario }` | Administrador General | Pedido de ampliación: correo a `contacto@sulotec.com` y registro |

### 4.3 Tareas programadas (dentro del mismo contenedor)

- **Cada hora (idempotente: los avisos se registran y no se repiten):** licencias que vencen en 7 días o menos → aviso `vence`; vencidas → `SOLO_LECTURA` + aviso; 7 días en solo lectura → `SUSPENDIDA` + aviso. El estado también se calcula por fecha en cada lectura, así que los productos ven la verdad aunque la tarea no haya corrido.
- **Día 1 de cada mes:** nada que «resetear»: el contador vive por `periodo`, el nuevo mes abre su fila sola. Las `bolsas_extra` vencidas se cierran.
- **Correos:** por OCI Email Delivery con una credencial SMTP propia del servicio (no la de Keycloak), remitente `no-reply@sulotec.com`.

## 5. El cliente que lleva cada producto (mismo comportamiento en todas las tecnologías)

Configuración en el `.env` del producto: `LICENCIAS_URL`, `LICENCIAS_TOKEN`, `LICENCIAS_PRODUCTO`. Comportamiento obligatorio:

1. **Caché por empresa** de `GET /v1/licencias/{empresa}` durante 5 minutos. Si el servicio no responde, **se sigue trabajando con la última licencia conocida** (y se registra el aviso). Nunca se bloquea a un cliente por una caída de Sulotec.
2. **Cupo:** antes de crear un usuario, `GET .../cupo`; si `puede_crear` es `false`, el producto muestra «Tu plan llegó al máximo de usuarios» con el enlace a `sulotec.com/mi-licencia`. Después de crear/desactivar, `PUT .../usuarios-activos`.
3. **Consumo:** llamada síncrona con 2 s de espera. Si no hay respuesta, se permite la consulta y el consumo queda en una **cola local de reintento** (la clave idempotente hace seguro reintentar). Si la consulta externa falla, `DELETE` del consumo.
4. **Universal:** si el token de Keycloak trae `administrador-general` (o el rol local equivalente), el consumo va con `hecho_por_sulotec: true` y nunca se bloquea.
5. **Mensajes al usuario** (texto común): al 80 % franja amarilla «Usaste el 80 % de tu bolsa»; en tolerancia franja naranja «Bolsa agotada: estás usando la tolerancia del 10 %, se factura aparte»; bloqueado: «Bolsa agotada» con botón **Ampliar plan**; `SOLO_LECTURA`: «Licencia vencida: puedes ver, no registrar»; `SUSPENDIDA`: pantalla de contacto.
6. **Nada de reglas propias:** el producto no decide porcentajes ni plazos; solo muestra lo que el servicio responde.

### Dónde se engancha en cada producto

| Producto | Tecnología del cliente | Empresa (tenant) | Crear usuarios (cupo) | Consumos (`tipo`) |
|---|---|---|---|---|
| **GeoMatrix** | Node (Huancayo-Backend, módulo `licencias`) | `empresa_uuid` de la tabla `empresas` | módulo `usuarios` (crear, activar, desactivar) | ninguno hoy; `ubicacion_google` si se enciende Google |
| **MiRadar 360** | Node (Afacop-Backend) | UUID de la empresa (sub-productos con marca propia = empresas distintas) | alta de usuarios del panel | `consulta_reniec`, `ubicar_direccion` |
| **PLAFT** | Spring Boot / Kotlin (Security-Backend) | empresa del módulo Administración | Administración → usuarios | `busqueda_listas`, `scoring`, `mensaje_indira` |
| **Buscador Interno** | Next.js (el proxy `web/src/app/backend/[...ruta]`), para no tocar la API .NET de la oficina | una sola empresa (Informa Perú) | personas permitidas en Cloudflare Access (se reportan a mano al inicio) | `busqueda` |
| **Dashboard Empresarial** | NestJS | empresa del tablero | usuarios por empresa | ninguno |

## 6. Orden de construcción (cada paso se puede usar solo)

1. **Servicio + kit + portal** (semana 1): base, tablas, API §4, pantallas `/licencias` y `/mi-licencia`, correos, bitácora. Al terminar, Sulotec ya crea empresas con plan y el Administrador General ve su licencia aunque ningún producto reporte todavía.
2. **Cliente Node + GeoMatrix** (semana 2): cupo de usuarios y pantallas de estado; prueba con Caja Huancayo. El mismo cliente sirve después a MiRadar y, adaptado, a Dashboard.
3. **Tokens** (semana 3): MiRadar 360 (RENIEC y ubicar), PLAFT (cliente Spring) y Buscador (en el proxy). Aviso 80 %, tolerancia y bloqueo reales.
4. **Ciclo completo** (semana 4): tareas de vencimiento, bolsas extra, cambio de plan, reporte Excel para facturar, rotación de tokens.

## 7. Decisiones tomadas el 2026-11-02 (el usuario aprobó lo propuesto)

1. **Nombre del repositorio** del servicio: propongo `jeliases-informaDev/Licencias-Backend` (kit `apps/licencias` en Sulotec-infra).
2. **Credencial de los productos:** token por producto (propuesto, como el resto de kits) o cliente de Keycloak por producto (más formal, más trabajo).
3. **Consumo en línea con tolerancia a caídas** (propuesto en §5.3) o en diferido (el producto manda el consumo después; más simple, pero no puede bloquear a tiempo).
4. Las reglas de negocio pendientes de gerencia (periodo, tolerancia, precios, cuentas inactivas, demo): el servicio las lleva como **parámetros** (`reglas` en la base), así cambiarlas no requiere programar.
