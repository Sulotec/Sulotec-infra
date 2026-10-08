# Buscador Interno — buscadorinterno.sulotec.com

Frontend nuevo en **Next.js 16 + React 19 + TypeScript + Tailwind 4**. Reemplaza al front Angular que estaba en Vercel.
Es responsive, usa el diseño de Sulotec y está armado por módulos para que sea fácil de mantener y de ampliar.

```
Navegador ──▶ buscadorinterno.sulotec.com (Next.js, servidor Oracle, contenedor "buscador")
                 │  /backend/...  (intermediario: sesión en cookie segura + regla de sedes)
                 ▼
              API del Buscador (.NET, servidor de la oficina) ──▶ SQL Server 192.168.1.17
```

- El navegador **nunca** conoce la dirección de la API ni el token. El token vive en una cookie `httpOnly`.
- **Regla de sedes:** solo se usa desde las IPs públicas de las sedes (Lince, Los Olivos). El rol **ADMIN GENERAL** puede entrar desde cualquier lugar. Se aplica dos veces:
  1. En el servidor, al iniciar sesión y en cada consulta (`src/lib/sesion-servidor.ts`).
  2. En Cloudflare Access, delante del sitio.

## Estructura

```
web/src/
├── app/                     Rutas: cada pantalla solo arma piezas de los módulos
│   ├── auth/                login, forgot-password, reset-password (mismas direcciones que los correos)
│   ├── (app)/               pantallas con sesión: inicio, personas, empresas, masivas, admin
│   ├── backend/[...ruta]/   intermediario hacia la API (sesión, sedes, token de Cloudflare)
│   └── sesion/salir/        cerrar sesión
├── components/
│   ├── ui/                  componentes base: Boton, Campo, Tarjeta, Tabla, Modal, Pestanas, Aviso…
│   └── layout/              armazón (menú lateral, cabecera), marca, marco de acceso
├── modulos/                 una carpeta por área de negocio
│   ├── sesion/              tipos · servicio · proveedor (usuario, roles, saldo, menú)
│   ├── consultas/           tipos y tablas compartidas (deudas, líneas, calificaciones, laboral, teléfonos)
│   ├── personas/            tipos · servicio (DNI, teléfono, RENIEC) · ficha RENIEC
│   ├── empresas/            tipos · servicio (RUC, razón social)
│   ├── masiva/              tipos · servicio · documentos (validación) · carga masiva · historial
│   └── admin/               tipos · servicio · usuarios · formularios · auditoría
├── lib/                     api.ts (cliente), formato.ts (moneda, fechas, periodos), sesion-servidor.ts
└── proxy.ts                 sin sesión → al login
```

**Agregar una integración nueva** (por ejemplo, otra fuente de datos):
1. Crea `src/modulos/<nombre>/` con `tipos.ts` (lo que devuelve la API) y `servicio.ts` (las llamadas).
2. Arma sus componentes en esa misma carpeta, reutilizando `@/components/ui`.
3. Crea la pantalla en `src/app/(app)/<ruta>/page.tsx` y agrega el enlace en `components/layout/shell.tsx`.

Las pantallas no llaman a la API directamente: siempre pasan por el `servicio.ts` de su módulo. Así, cuando una parte de la API pase de .NET a TypeScript (fase 2), solo cambia el servicio.

## Puesta en marcha (una vez)

1. **GitHub:** al subir esta carpeta, el workflow *Publicar buscador* construye la imagen en el servidor. La primera vez avisa "falta configurar".
2. **Servidor** (https://ssh.sulotec.com):
   ```bash
   sudo bash /data/apps/buscador/preparar.sh
   ```
   - **API:** por ahora, la dirección actual de la oficina (`https://win-hkbui0id607.tail4a0d10.ts.net:8443`).
   - **Sedes:** las IPs públicas de Lince y Los Olivos. Sin ellas, solo entra ADMIN GENERAL.
   - **Token de Cloudflare:** `N` por ahora.
3. **Cloudflare → Networks → Tunnels → sulotec → Published application routes:** `buscadorinterno.sulotec.com` → `http://buscador:3000`.
4. **Cloudflare Access:** la app `buscadorinterno` ya existe, con la política *Administradores Generales*. Cuando estén las IPs de las sedes, agrega una política **Sedes** con acción **Bypass** e *Include → IP ranges* con esas IPs.

## Siguientes pasos

- **Túnel en la oficina:** instalar `cloudflared` como servicio en el servidor de la API, con la ruta `api-buscadorinterno.sulotec.com` → `http://localhost:8090`.
  - Protegerla con Access **Service Auth** y un token de servicio, que se pega con `preparar.sh`.
  - Después: apagar Tailscale Funnel y el front de Vercel. Hasta entonces, la API vieja sigue expuesta como hoy.
- **IP real en la auditoría:** la API debe tomar la IP que envía este intermediario (`X-Forwarded-For`). Con Funnel, la API puede ver la IP del servidor Oracle.
- **Fase 2:** pasar la API a TypeScript módulo por módulo (login y tokens → personas → empresas → masivas), con los mismos contratos.
- **Base de datos:** se queda en SQL Server de la oficina. Los Excel de `reportes/` del repositorio viejo tienen datos reales: no se migran a GitHub.

## Desarrollo local

```bash
cd apps/buscador/web
npm install
BUSCADOR_API_URL=https://<api> SEDES_IPS=<tu-ip> npm run dev
```
