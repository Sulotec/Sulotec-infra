# Licencias, planes y usuarios de Sulotec (modelo, noviembre 2026)

> Cómo contrata una empresa, cómo administra sus usuarios y cómo se mide el consumo en todos los productos. Los procesos están en BPMN (`procesos/*.bpmn`,
> se importan en Bizagi Modeler con *Importar → BPMN*). Estado: **modelo propuesto, pendiente de validar reglas y precios con gerencia.**

## 1. Tres niveles de acceso

| Nivel | Quién | Qué puede | Licencia |
|---|---|---|---|
| **Administrador universal** | Sulotec (grupo «Administradores Generales» de Keycloak, máximo 2 personas, con segundo factor) | Entra a todos los productos y a todas las empresas; crea empresas, asigna el plan, invita al administrador de empresa, amplía cupos y bolsas, ve el consumo de todas. Todo lo que hace dentro de una empresa queda registrado. | Fuera de toda licencia: no ocupa cupo ni bolsa. Lo que gasta dentro de una empresa se descuenta de esa empresa, marcado «hecho por Sulotec». Para demos, una empresa propia de Sulotec. |
| **Administrador de empresa** | Uno por empresa cliente, entregado al contratar | Crea y desactiva a sus usuarios con sus roles; reparte topes de tokens si quiere; ve el consumo; pide ampliar | Ocupa un cupo |
| **Usuarios** | Los roles de cada producto (supervisor, auditor, asesor, analista…) | Usan el producto | Ocupan un cupo mientras están activos; consumen de la bolsa de la empresa |

El nombre «Administrador General» queda reservado para Sulotec (así está en Keycloak); el del cliente es **administrador de empresa**.

## 2. Qué se licencia en cada producto

| Producto | Usuarios | Un token es… |
|---|---|---|
| MiRadar 360 | sí | una consulta externa (RENIEC, ubicar una dirección) |
| PLAFT | sí | una búsqueda en listas/PEP, una evaluación de scoring o un mensaje a Indira |
| Buscador Interno | sí | una búsqueda |
| GeoMatrix | sí | solo usuarios por ahora (si se enciende Google, cada ubicación sería un token) |
| Dashboard Empresarial | sí | solo usuarios |

Un token es algo que cuesta o que vale medir. **La bolsa es de la empresa** (la consumen todos sus usuarios); el administrador de empresa puede poner un tope por usuario, opcional. Cada producto se licencia aparte: una persona en dos productos ocupa un cupo en cada uno.

## 3. El pack

Por empresa y producto: **usuarios máximos**, **bolsa de tokens** del periodo, **periodo** (propuesta: mensual, la bolsa se renueva cada mes) y **vencimiento**.
Adicionales: usuario extra, bolsa extra (propuesta: vence a los 12 meses) y subir de plan. Al inicio la factura la emite Sulotec; el sistema mide, avisa y deja el consumo registrado.

## 4. Reglas (propuestas, a confirmar)

- **Cupo de usuarios:** cuentan las cuentas activas por producto; al llegar al límite no se crean más (mensaje claro y «Ampliar plan»); desactivar libera el cupo.
- **Bolsa de tokens:** aviso al 80 %; al 100 % no se corta la operación: tolerancia del 10 % que se factura después; agotada la tolerancia, se bloquea la consulta y se ofrece ampliar.
- **Vencimiento:** aviso 7 días antes; si no renueva, 7 días en solo lectura y luego suspensión; los datos se conservan.
- **Universal:** fuera de licencia, auditado, máximo 2 personas con segundo factor.

## 5. Dónde vive cada cosa

| Pieza | Responsabilidad |
|---|---|
| **Keycloak** (`cuenta.sulotec.com`) | Identidad: quién es cada persona, a qué empresa pertenece (UUID), qué productos tiene (roles `producto-*`), segundo factor, administrador universal. **Sin contadores.** |
| **Portal Sulotec · módulo Licencias** (la verdad) | Plan de cada empresa por producto (cupo, bolsa, periodo, vencimiento); registro de consumo (cada token: empresa, producto, usuario, qué, cuándo); avisos (80 %, vencer, agotar); pantallas «Mi licencia» (empresa) y «Licencias» (Sulotec). |
| **Cada producto** | Recibe su licencia del portal (como hoy recibe el UUID de la empresa), valida el cupo al crear usuarios, descuenta cada consulta y la reporta; sigue funcionando con la última licencia si el portal se cae. |

Modelo de datos mínimo del portal: `planes` (nombre, producto, usuarios_max, tokens_mes, precio), `licencias` (empresa_uuid, producto, plan, usuarios_max, bolsa, tokens_extra, inicio, vencimiento, estado), `consumo_tokens` (empresa_uuid, producto, usuario, tipo, cantidad, fecha, hecho_por_sulotec, clave_idempotente), `usuarios_activos` (lo cuenta cada producto y lo reporta).

## 6. Procesos (BPMN)

| Archivo | Proceso | Carriles |
|---|---|---|
| `P1-contratacion-y-alta.bpmn` | Contratación y alta de licencia | Empresa cliente · Comercial Sulotec · Administrador universal · Plataforma |
| `P2-gestion-de-usuarios.bpmn` | Gestión de usuarios de la empresa (crear con cupo, desactivar y liberar) | Administrador de empresa · Producto · Usuario |
| `P3-consumo-de-tokens.bpmn` | Consumo de tokens (saldo, 80 %, tolerancia, bloqueo) | Usuario · Producto · Administrador de empresa |
| `P4-renovacion-ampliacion-vencimiento.bpmn` | Renovación, ampliación y vencimiento (aviso, cotizar, pagar, actualizar; solo lectura y suspensión) | Plataforma · Administrador de empresa · Comercial · Administrador universal |

Flujo completo: contrato → crear empresa (`empresa.sh`) + licencia + invitar al administrador de empresa (`cuentas.sh`) → el administrador crea usuarios y el producto valida el cupo → cada consulta descuenta de la bolsa y queda registrada → avisos al 80 % y al vencer → renovación o ampliación.

## 7. Etapas

1. **Portal + GeoMatrix:** módulo Licencias (planes, empresas, cupos); GeoMatrix valida el cupo de usuarios; piloto con Caja Huancayo.
2. **Tokens:** bolsa y registro de consumo; PLAFT, MiRadar 360 y Buscador descuentan cada consulta; aviso al 80 % y tolerancia.
3. **Ciclo completo:** vencimiento, solo lectura y suspensión; adicionales y cambio de plan; reporte de consumo para facturar.

**Decisiones pendientes:** plan mensual o prepagado; tolerancia del 10 % o bloqueo al 100 %; precios por pack y adicional; si las cuentas inactivas cuentan en el cupo; periodo de prueba (demo) y su límite.
