# 4. Integración de proyectos — cómo se unen las piezas

> Índice: [Documentación](README.md) · Anterior: [3. Cloudflare](03-cloudflare.md)

## 4.1 Mapa general

```
                         ┌──────────────────────── Cloudflare ────────────────────────┐
Personas ──HTTPS──▶      │ DNS + HTTPS + Access (quién entra) + Túnel "sulotec"       │
                         └───────────────┬────────────────────────────────────────────┘
                                         │ (conexión saliente desde el servidor; sin puertos abiertos)
                 ┌────────────── Servidor Oracle "sulotec-main" (red sulotec_edge) ─────────────┐
                 │  portal  ── sulotec.com            (Astro + nginx)                             │
                 │  cuenta  ── cuenta.sulotec.com     (Keycloak) ──▶ postgres (red sulotec_data) │
                 │  buscador── buscadorinterno…       (Next.js)  ──┐                              │
                 └─────────────────────────────────────────────────┼──────────────────────────────┘
                                                                   │ /backend (servidor a servidor)
                                       ┌───────────── Oficina ─────▼───────────────────┐
                                       │ API Buscador (.NET, servicio Windows)          │
                                       │   └──▶ SQL Server 192.168.1.17 (red interna)   │
                                       └────────────────────────────────────────────────┘
```

- Hoy la API de la oficina se alcanza por **Tailscale Funnel**.
- Lo previsto es un **túnel de Cloudflare en la oficina**, protegido con *Service Auth*. Ver [3. Cloudflare](03-cloudflare.md).

## 4.2 Identidad: quién es quién en cada sistema

Hay **tres capas de identidad**, cada una con su propósito:

| Capa | Dónde | Para qué | Cuentas |
|---|---|---|---|
| **Cloudflare Access** | Delante de las partes sensibles (SSH, `/admin` de cuentas, Buscador) | Primera puerta: correo verificado con código o IP de sede | Listas de correos en las políticas |
| **Keycloak** (`cuenta.sulotec.com`) | sulotec.com: demos y "Mis productos" | Cuentas de clientes y del equipo; rol `administrador-general` | Las crea el equipo (sin registro libre) |
| **Buscador** (API + SQL Server) | `buscadorinterno.sulotec.com` | Usuarios, roles (`ADMIN GENERAL`, `SUPERVISOR`, `GERENCIA`, `Operador`) y tokens de consulta | Las crea un ADMIN GENERAL dentro del Buscador |

**Cómo se conectan hoy**
1. Una persona entra a sulotec.com con su cuenta Keycloak. El token trae `roles`.
2. Si es **Administrador General**, "Mis productos" le muestra **Abrir Buscador Interno**.
3. Al abrirlo, **Cloudflare Access** verifica su correo, o su sede cuando se configure.
4. Luego entra con su **usuario del Buscador**. El front aplica la **regla de sedes**: fuera de las sedes, solo `ADMIN GENERAL`.

**Siguiente paso posible (inicio único):** que el Buscador acepte la identidad de Keycloak, o la de Cloudflare Access (`Cf-Access-Jwt-Assertion`), para no pedir dos inicios de sesión.

## 4.3 Cómo se publica cada cosa

| Qué | Repositorio | Mecanismo | Tiempo |
|---|---|---|---|
| Web de Sulotec | `Sulotec-infra` → `apps/portal` | Workflow `portal.yml` en el runner propio | ~1 min |
| Cuentas (Keycloak) | `Sulotec-infra` → `apps/cuenta` | Workflow `cuenta.yml` (reinicia y aplica `ajustar-realm.sh`) | ~1 min |
| Operación del Buscador | `Sulotec-infra` → `apps/buscador` | Workflow `buscador.yml` (copia scripts y compose) | segundos |
| Buscador (front) | `buscador-interno` → `web/` | El servidor **lee** `main` cada 2 min con una llave de solo lectura y construye; si falla, vuelve a la versión anterior | ~2–5 min |
| Buscador (API) | `buscador-interno` → `api/`, hoy aún el repo viejo | `actualizar.ps1` en el servidor de la oficina, cada 2 min | ~5 min |

**Por qué el Buscador se publica distinto:** el runner del servidor ejecuta lo que diga un workflow. Si los desarrolladores del Buscador tuvieran un workflow con ese runner, podrían ejecutar comandos en el servidor. Por eso el servidor **tira** del código (*pull*) en lugar de que GitHub lo **empuje**.

## 4.4 Dónde vive cada dato y cada secreto

| Qué | Dónde | Respaldo |
|---|---|---|
| Cuentas de sulotec.com | PostgreSQL del servidor, base `keycloak` | Diario (`pg_dumpall`) |
| Datos del Buscador | SQL Server de la oficina (`192.168.1.17`) | Lo gestiona la oficina |
| Historial de cargas masivas | Servidor de la oficina (`C:\Buscador\historial`) | Lo gestiona la oficina |
| Claves del túnel y de las bases | `/opt/sulotec/.env` | Gestor de contraseñas |
| Claves de Keycloak | `/opt/sulotec/cuenta.env` | Gestor de contraseñas |
| Configuración del Buscador (API, sedes, token de Access) | `/opt/sulotec/buscador.env` | Se regenera con `preparar.sh` |
| Llave de solo lectura del Buscador | `/opt/sulotec/buscador-actualizador/llave` | Se puede regenerar |

## 4.5 Sumar o mudar un producto (receta)

Ejemplo: mudar **Auditoría de Visitas** de Render a `auditoria.sulotec.com`.

1. **Código:** repositorio privado en la organización (`Sulotec/auditoria`), sin secretos ni datos reales.
2. **Base de datos:**
   ```bash
   sudo /opt/sulotec/scripts/new-project-db.sh mysql auditoria
   ```
   Guarda la cadena de conexión en el gestor de contraseñas.
3. **Contenedor:** usa un Dockerfile de [`templates/`](../templates) y un compose como [`templates/app-compose.yml`](../templates/app-compose.yml):
   - redes `sulotec_edge` (y `sulotec_data` si usa base)
   - `container_name: auditoria`
   - secretos en `/opt/sulotec/auditoria.env`
4. **Publicación:**
   - **Solo administradores tocan el código:** un workflow en `Sulotec-infra`, como `portal.yml`.
   - **Hay un equipo externo:** el modelo *pull* del Buscador. Copia `apps/buscador/deploy/actualizar.sh` y `instalar-actualizador.sh`, y cambia el nombre del repositorio.
5. **Cloudflare:** ruta `auditoria.sulotec.com` → `http://auditoria:<puerto>`. Si es privada, primero su app de Access.
6. **Portal:** en [`soluciones.ts`](../apps/portal/src/data/soluciones.ts) pon `publicado: true`. El botón "Abrir" de Mis productos y el de la portada apuntarán al subdominio.
7. **Corte:** prueba, cambia el DNS o los enlaces de los clientes, y apaga Render/Vercel.
8. **Documenta** el cambio en estos documentos y en [`SEGURIDAD-ISO27001.md`](../SEGURIDAD-ISO27001.md).

## 4.6 Reglas de integración

- **Un subdominio por aplicación**, de un solo nivel.
- **Nada expuesto sin pasar por el túnel:** las bases y las APIs internas no publican puertos.
- **Lo privado lleva Access**, y además su propia validación dentro de la app (defensa en profundidad).
- **Los navegadores no hablan directo con APIs internas:** pasan por el servidor de su front (como `/backend` del Buscador).
- **Mismos contratos al migrar:** el Buscador pasará su API a TypeScript módulo por módulo sin cambiar el front.

## 4.7 Referencias

| Tema | Referencia |
|---|---|
| Portal | [`apps/portal/README.md`](../apps/portal/README.md) |
| Cuentas | [`apps/cuenta/README.md`](../apps/cuenta/README.md) |
| Operación del Buscador | [`apps/buscador/README.md`](../apps/buscador/README.md) |
| Código del Buscador | [Sulotec/buscador-interno](https://github.com/Sulotec/buscador-interno) |
| Seguridad ISO 27001 | [`SEGURIDAD-ISO27001.md`](../SEGURIDAD-ISO27001.md) |
| Bitácora completa | [`CONTEXTO-PARA-OTRO-CHAT.md`](../CONTEXTO-PARA-OTRO-CHAT.md) |
| Next.js 16 | https://nextjs.org/docs |
| Keycloak | https://www.keycloak.org/documentation |
| Cloudflare Tunnel | https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/ |
| Cloudflare Access | https://developers.cloudflare.com/cloudflare-one/policies/access/ |
| OCI Always Free | https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier.htm |
| OCI Email Delivery | https://docs.oracle.com/en-us/iaas/Content/Email/home.htm |
