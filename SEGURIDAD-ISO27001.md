# Sulotec — controles técnicos de la infraestructura (ISO/IEC 27001:2022, Anexo A)

Evidencia técnica de la plataforma base (Oracle Cloud + Cloudflare). La certificación ISO 27001 es de la
organización (SGSI, políticas, riesgos, auditoría); este documento cubre solo los controles que aporta la
infraestructura y dónde verificarlos. Última revisión: 2026-10-14.

## Arquitectura

```
Usuarios → Cloudflare (DNS, SSL, WAF, Access) → Cloudflare Tunnel "sulotec" → VM Oracle (sa-santiago-1)
                                                                              ├─ cloudflared
                                                                              ├─ PostgreSQL 16  (/data/postgres)
                                                                              ├─ MySQL 8.4      (/data/mysql)
                                                                              └─ apps (un compose por proyecto: portal, cuenta, buscador, miradar, plaft, auditoria)
Object Storage: sulotec-backups (copias diarias) · sulotec-archivos (archivos de las apps) · miradar-archivos · plaft-archivos · huancayo-archivos (uno por producto, con usuario de servicio propio)
```

## Controles

| Control (Anexo A) | Implementación | Dónde se verifica |
|---|---|---|
| 5.15 Control de acceso · 5.18 Derechos de acceso | Acceso administrativo solo por `ssh.sulotec.com` (Cloudflare Access). Política `Administradores` con lista explícita de correos; todo lo demás denegado por defecto. | Cloudflare One → Access controls → Applications → Servidor SSH |
| 5.16 Gestión de identidades | Un usuario Linux por persona (`informaperu2`, `serviciosdigitales`), sin contraseña; no se comparten cuentas. | VM: `getent passwd`, `/etc/sudoers.d/90-*` |
| 8.5 Autenticación segura | Login con código de un solo uso al correo + certificados SSH de corta duración emitidos por Cloudflare (sin llaves permanentes en PCs). Pendiente: exigir MFA en la política y 2FA en las cuentas de Gmail/Cloudflare/Oracle. | VM: `/etc/ssh/sshd_config.d/60-cloudflare-access.conf`, `/etc/ssh/ca.pub` |
| 8.20 Seguridad de redes · 8.22 Segregación | La VM no expone puertos: puerto 22 cerrado (`ssh_enabled = false`), web solo por túnel saliente. Bases sin puertos publicados, solo en la red interna `sulotec_data`. | Terraform `oracle/main.tf` (security list), `vm/docker-compose.yml` |
| 8.24 Uso de criptografía | En tránsito: HTTPS obligatorio, TLS mínimo 1.2, certificado universal de Cloudflare; túnel cifrado. En reposo: discos y buckets cifrados por Oracle (AES-256, llaves gestionadas por Oracle). | Cloudflare → SSL/TLS → Edge Certificates; Oracle → Block Volume / Bucket |
| 8.13 Copias de seguridad | Diario 02:00: `pg_dumpall` + `mysqldump` + archivos de `/data/apps`; 14 días locales en disco del sistema y copia fuera del servidor en `sulotec-backups` (bucket privado con versionado), con permiso propio de la VM (sin llaves). **Prueba de restauración hecha el 2026-10-14 (14:57, hora de Lima):** el respaldo `postgres_2026-10-14_1452.sql.gz` se descargó del bucket `sulotec-backups` (copia fuera del servidor) y se restauró en un contenedor aislado sin red; `keycloak` (101 tablas, 1694 filas) y `miradar` (14 tablas, 2791 filas) quedaron iguales a las bases en vivo; MySQL sin bases de usuario; los archivos de las apps (505 entradas) se leen bien. Repetible con `vm/scripts/probar-restauracion.sh --desde-bucket`; conviene repetirla cada trimestre. | VM: `/etc/cron.d/sulotec-backup`, `/var/log/sulotec-backup.log`; Oracle → Buckets → sulotec-backups |
| 8.14 Redundancia · 5.30 Continuidad TIC | Datos en un disco separado del sistema (se puede conectar a otra VM). Infraestructura reproducible con Terraform + `bootstrap.sh` + `setup-datos.sh`. Sin SLA en el plan actual. | `oracle/`, `vm/` |
| 8.15 Registro · 8.16 Monitoreo | Cloudflare Access registra cada inicio de sesión; Oracle Audit registra cambios en la nube (activo por defecto); `journalctl -u ssh` en la VM; alertas de presupuesto (US$10) al correo. | Cloudflare One → Insights & Logs; Oracle → Audit |
| 8.8 Vulnerabilidades técnicas | `unattended-upgrades` (parches de seguridad automáticos), `fail2ban`, imágenes oficiales de Docker. | VM |
| 8.9 Gestión de la configuración · 8.32 Gestión de cambios | Infraestructura como código (Terraform) y scripts en el repositorio `Sulotec/Sulotec-infra` (organización de la empresa; **hoy es público**, pasarlo a privado está pendiente). Los cambios del portal se publican solo desde `main` con GitHub Actions y un runner propio sin puertos abiertos; cada publicación queda registrada (quién, qué, cuándo). | GitHub → Sulotec-infra → Commits / Actions |
| 5.23 Servicios en la nube | Proveedores: Oracle Cloud (cómputo, discos, Object Storage; región Santiago de Chile) y Cloudflare (DNS, TLS, túnel, Access). | Este documento |
| 5.17 Información de autenticación | Secretos solo en `/opt/sulotec/.env` y `/opt/sulotec/cuenta.env` (root:docker, 640) y en el gestor de contraseñas de la empresa; nunca en Git ni en chats. Rotación con claves generadas en el servidor y sin imprimirse: `vm/scripts/rotar-claves.sh` (bases) y `apps/miradar/deploy/rotar-s3.sh` (clave S3 de `svc-miradar`); rotadas el 2026-10-14. | VM |
| 5.16 · 5.18 · 8.5 Cuentas de clientes y del equipo (cuenta.sulotec.com) | Keycloak en el servidor propio. Sin registro libre: el equipo de Sulotec crea y retira cada cuenta (alta y baja controladas). Correo verificado antes de entrar; contraseñas de 10+ caracteres con historial; bloqueo tras 5 intentos; sesión de 30 min sin uso y 8 h máximo. Los administradores de cuentas (grupo *Administradores Generales*) pueden crear o desactivar cuentas, pero no cambiar la configuración, y deben usar OTP. La consola `/admin` está además detrás de Cloudflare Access. El portal usa OIDC con PKCE y no guarda contraseñas. Las demos no usan datos personales. | Consola → Usuarios / Eventos; `apps/cuenta/` |

## Pendientes para cerrar brechas
0. ~~Rotar `POSTGRES_PASSWORD` y `MYSQL_ROOT_PASSWORD`~~ **Hecho el 2026-10-14**, junto con la clave del usuario `miradar` y la clave S3 de `svc-miradar` (control 5.17). Falta rotar las claves de otros productos que pasaron por chats (SMTP, `Jwt:Key`, base `irubio`, token de RENIEC y de Vercel).
1. MFA obligatorio en la política de Cloudflare Access y 2FA en `informaperu2@gmail.com`, Cloudflare y Oracle.
2. ~~Prueba de restauración de un backup~~ **Hecha el 2026-10-14** (ver control 8.13). Repetir cada trimestre.
3. Proteger la rama `main` en GitHub (revisión antes de publicar) y activar 2FA obligatorio en la organización `Sulotec`.
4. **Legal/cumplimiento:** los datos residen en Santiago de Chile → flujo transfronterizo según la Ley 29733; clientes supervisados por la SBS pueden exigir evidencias sobre tercerización en la nube. Validar antes de cargar datos reales.
5. Para producción con clientes financieros: evaluar VM de pago (SLA) y separar producción de pruebas.
6. Cuentas: reemplazar `admin-temporal` de Keycloak por un administrador maestro con nombre propio y OTP. Exigir OTP por regla del flujo de inicio de sesión para el rol `administrador-general`; hoy se exige al crear cada cuenta. Aviso de privacidad y consentimiento en el registro (Ley 29733) antes de abrir las cuentas al público.
7. **Repositorios:** hoy todos son públicos (incluido `Sulotec-infra`); pasarlos a privados con llaves de despliegue de solo lectura en el servidor.
8. **PLAFT:** hacer cumplir en el servidor la separación por empresa (hoy la aplica la web) y desactivar las cuentas de prueba antes de cargar datos de clientes.
