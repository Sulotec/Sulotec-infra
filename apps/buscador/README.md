# Buscador Interno — operación (buscadorinterno.sulotec.com)

> **El código del Buscador está en su propio repositorio:** https://github.com/Sulotec/buscador-interno
> (`web/` React/Next.js y `api/` .NET). Esta carpeta solo tiene cómo corre en el servidor; es para administradores.

```
Desarrolladores ──push a main──▶ Sulotec/buscador-interno
                                        │  (llave de solo lectura, cada 2 min)
Servidor Oracle: actualizar.sh ◀────────┘
   └─ docker build web/ ─▶ contenedor "buscador" (red sulotec_edge)
                               │
Cloudflare Tunnel: buscadorinterno.sulotec.com ─▶ http://buscador:3000
Cloudflare Access: app "buscadorinterno" (Administradores Generales; sedes por IP)
```

| Archivo | Para qué |
|---|---|
| `deploy/docker-compose.yml` | Contenedor `buscador` (solo lectura, 512 MB, red `sulotec_edge`) |
| `deploy/preparar.sh` | Crea `/opt/sulotec/buscador.env`: dirección de la API, IPs de las sedes y token de Cloudflare Access |
| `deploy/instalar-actualizador.sh` | Una sola vez: llave de despliegue de solo lectura + temporizador systemd cada 2 minutos |
| `deploy/actualizar.sh` | Si hay un commit nuevo en `main`, construye la imagen y la cambia; si falla, vuelve a la anterior |

Cada cambio en esta carpeta llega a `/data/apps/buscador` con el workflow *Publicar buscador (operación)*.

## Puesta en marcha (ya hecha la parte 1)

1. ✅ `sudo bash /data/apps/buscador/preparar.sh` → contenedor `buscador` en marcha.
2. **Ruta del túnel:** Cloudflare → Networks → Tunnels → `sulotec` → Add route → `buscadorinterno.sulotec.com` → `http://buscador:3000`.
3. ✅ **Publicación automática** desde el repositorio nuevo (instalada el 2026-10-09; primera publicación `3cb1f71`):
   ```bash
   sudo bash /data/apps/buscador/instalar-actualizador.sh
   ```
   Muestra una llave pública. Agrégala en GitHub:
   - Ruta: `Sulotec/buscador-interno` → **Settings → Deploy keys → Add deploy key**.
   - Title: `servidor-sulotec-main`.
   - **Sin** "Allow write access".

   Luego pulsa Enter.
4. **Sedes:** cuando estén las IPs de Lince y Los Olivos:
   - Vuelve a correr `preparar.sh` con esas IPs.
   - En Cloudflare Access, agrega a la app `buscadorinterno` una política **Sedes** con acción **Bypass** e *Include → IP ranges*.

## Día a día

- **Ver qué versión está publicada:** `sudo cat /opt/sulotec/buscador-actualizador/publicado`
- **Registro de publicaciones:** `sudo tail -f /var/log/buscador-actualizador.log`
- **Forzar una revisión ahora:** `sudo systemctl start buscador-actualizador.service`
- **Volver a una versión anterior a mano:**
  1. `docker images buscador-web` muestra las versiones guardadas.
  2. `docker tag buscador-web:<commit> buscador-web:latest`
  3. `cd /data/apps/buscador && docker compose up -d --force-recreate`
- **Commit que falló:** queda en `/opt/sulotec/buscador-actualizador/fallido` y no se reintenta. El siguiente commit se prueba solo.

## Pendientes

- **Túnel en la oficina:** `cloudflared` como servicio en el servidor de la API, con `api-buscadorinterno.sulotec.com` → `http://localhost:8090`.
  - Protegerla con Access **Service Auth** y pegar el token con `preparar.sh`.
  - Después, apagar Tailscale Funnel y el front de Vercel.
- **API desde el repositorio nuevo:** mover el actualizador de la oficina a `Sulotec/buscador-interno` (ver `api/DESPLIEGUE.md` en ese repositorio).
- **Fase 2:** pasar la API a TypeScript módulo por módulo.
