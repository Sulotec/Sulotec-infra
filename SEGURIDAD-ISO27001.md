# Sulotec — controles técnicos de la infraestructura (ISO/IEC 27001:2022, Anexo A)

Evidencia técnica de la plataforma base (Oracle Cloud + Cloudflare). La certificación ISO 27001 es de la
organización (SGSI, políticas, riesgos, auditoría); este documento cubre solo los controles que aporta la
infraestructura y dónde verificarlos. Última revisión: 2026-10-07.

## Arquitectura

```
Usuarios → Cloudflare (DNS, SSL, WAF, Access) → Cloudflare Tunnel "sulotec" → VM Oracle (sa-santiago-1)
                                                                              ├─ cloudflared
                                                                              ├─ PostgreSQL 16  (/data/postgres)
                                                                              ├─ MySQL 8.4      (/data/mysql)
                                                                              └─ apps (un compose por proyecto)
Object Storage: sulotec-backups (copias diarias) · sulotec-archivos (archivos de las apps)
```

## Controles

| Control (Anexo A) | Implementación | Dónde se verifica |
|---|---|---|
| 5.15 Control de acceso · 5.18 Derechos de acceso | Acceso administrativo solo por `ssh.sulotec.com` (Cloudflare Access). Política `Administradores` con lista explícita de correos; todo lo demás denegado por defecto. | Cloudflare One → Access controls → Applications → Servidor SSH |
| 5.16 Gestión de identidades | Un usuario Linux por persona (`informaperu2`, `serviciosdigitales`), sin contraseña; no se comparten cuentas. | VM: `getent passwd`, `/etc/sudoers.d/90-*` |
| 8.5 Autenticación segura | Login con código de un solo uso al correo + certificados SSH de corta duración emitidos por Cloudflare (sin llaves permanentes en PCs). Pendiente: exigir MFA en la política y 2FA en las cuentas de Gmail/Cloudflare/Oracle. | VM: `/etc/ssh/sshd_config.d/60-cloudflare-access.conf`, `/etc/ssh/ca.pub` |
| 8.20 Seguridad de redes · 8.22 Segregación | La VM no expone puertos: puerto 22 cerrado (`ssh_enabled = false`), web solo por túnel saliente. Bases sin puertos publicados, solo en la red interna `sulotec_data`. | Terraform `oracle/main.tf` (security list), `vm/docker-compose.yml` |
| 8.24 Uso de criptografía | En tránsito: HTTPS obligatorio, TLS mínimo 1.2, certificado universal de Cloudflare; túnel cifrado. En reposo: discos y buckets cifrados por Oracle (AES-256, llaves gestionadas por Oracle). | Cloudflare → SSL/TLS → Edge Certificates; Oracle → Block Volume / Bucket |
| 8.13 Copias de seguridad | Diario 02:00: `pg_dumpall` + `mysqldump` + archivos de `/data/apps`; 14 días locales en disco del sistema y copia fuera del servidor en `sulotec-backups` (bucket privado con versionado), con permiso propio de la VM (sin llaves). Pendiente: prueba de restauración documentada. | VM: `/etc/cron.d/sulotec-backup`, `/var/log/sulotec-backup.log`; Oracle → Buckets → sulotec-backups |
| 8.14 Redundancia · 5.30 Continuidad TIC | Datos en un disco separado del sistema (se puede conectar a otra VM). Infraestructura reproducible con Terraform + `bootstrap.sh` + `setup-datos.sh`. Sin SLA en el plan actual. | `oracle/`, `vm/` |
| 8.15 Registro · 8.16 Monitoreo | Cloudflare Access registra cada inicio de sesión; Oracle Audit registra cambios en la nube (activo por defecto); `journalctl -u ssh` en la VM; alertas de presupuesto (US$10) al correo. | Cloudflare One → Insights & Logs; Oracle → Audit |
| 8.8 Vulnerabilidades técnicas | `unattended-upgrades` (parches de seguridad automáticos), `fail2ban`, imágenes oficiales de Docker. | VM |
| 8.9 Gestión de la configuración · 8.32 Gestión de cambios | Infraestructura como código (Terraform) y scripts en el repositorio privado `Sulotec/Sulotec-infra` (organización de la empresa). Los cambios del portal se publican solo desde `main` con GitHub Actions y un runner propio sin puertos abiertos; cada publicación queda registrada (quién, qué, cuándo). | GitHub → Sulotec-infra → Commits / Actions |
| 5.23 Servicios en la nube | Proveedores: Oracle Cloud (cómputo, discos, Object Storage; región Santiago de Chile) y Cloudflare (DNS, TLS, túnel, Access). | Este documento |
| 5.17 Información de autenticación | Secretos solo en `/opt/sulotec/.env` (root:docker, 640) y en el gestor de contraseñas de la empresa; nunca en Git ni en chats. | VM |

## Pendientes para cerrar brechas
0. Rotar `POSTGRES_PASSWORD` y `MYSQL_ROOT_PASSWORD` (quedaron expuestas en un chat el 2026-10-07) antes de cargar datos reales (control 5.17).
1. MFA obligatorio en la política de Cloudflare Access y 2FA en `informaperu2@gmail.com`, Cloudflare y Oracle.
2. Prueba de restauración de un backup, con fecha y resultado anotados aquí.
3. Proteger la rama `main` en GitHub (revisión antes de publicar) y activar 2FA obligatorio en la organización `Sulotec`.
4. **Legal/cumplimiento:** los datos residen en Santiago de Chile → flujo transfronterizo según la Ley 29733; clientes supervisados por la SBS pueden exigir evidencias sobre tercerización en la nube. Validar antes de cargar datos reales.
5. Para producción con clientes financieros: evaluar VM de pago (SLA) y separar producción de pruebas.
