# Kit de Indira (`indira`)

Indira es la asistente de Sulotec: un servicio propio que usa el widget de `sulotec.com` (`<indira-asistente>`, PR del portal).
Codigo: [`jeliases-informaDev/Indira-Backend`](https://github.com/jeliases-informaDev/Indira-Backend) (contrato en su `openapi.json`).
Cobra 1 token por mensaje a la licencia `indira` del servicio de licencias.

| Que | Donde |
|---|---|
| API | `https://api-indira.sulotec.com` (tunel → `http://indira:3300`, SSE) |
| Contenedor | `indira` (imagen `indira:latest`, 512 MB, solo lectura, **un solo proceso**) |
| Base | `indira` en el PostgreSQL 16 compartido (red `sulotec_data`) |
| Configuracion | `/opt/sulotec/indira.env` (lo crea `preparar.sh`; no entra al respaldo ni al repositorio) |
| Kit en el servidor | `/data/apps/indira` (`docker-compose*.yml` + `deploy/*.sh`, copiados con el paso 0) |
| Modelo | `INDIRA_PROVEEDOR=falso` (sin costo). `ollama` solo con permiso del dueno. Claude apagado hasta resolver el aviso de privacidad |

## Orden de encendido

Nada de esto se hace sin el dueno. Cada paso se puede repetir.

1. **Unir y desplegar Licencias-Backend#6** (producto `indira`, plan semilla y `GET /v1/empresas/{uuid}/resumen`):
   `sudo bash /data/apps/licencias/desplegar.sh`.
2. **Unir Indira-Backend#1** despues de su revision independiente.
3. **Comprobar que el token del portal trae `sub`.** En `sulotec.com`, con la sesion abierta, pega esto en la consola del
   navegador. Solo muestra nombres de campos:
   ```
   const t=await sulotecCuenta.token();const c=JSON.parse(atob(t.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));console.log(Object.keys(c).join(','),'|',c.typ,'|',c.azp,'|',c.aud)
   ```
   Si no aparece `sub`, hay que agregar al cliente `portal` el scope `basic` antes de seguir.
4. **Keycloak:** unir este kit publica `apps/cuenta/**`. El workflow *Publicar cuenta* corre `ajustar-realm.sh` (paso 12:
   audiencia `indira` en el access token del portal) **y reinicia Keycloak**: elige el momento. A mano:
   `sudo docker exec -i cuenta bash -s < /data/apps/cuenta/ajustar-realm.sh`.
5. **Instalar en el servidor** (https://ssh.sulotec.com). Paso 0, copiar el kit (y cada vez que cambie):
   ```
   sudo mkdir -p /data/apps/indira && sudo rm -rf /tmp/sulotec-infra && sudo git clone --depth 1 https://github.com/Sulotec/Sulotec-infra.git /tmp/sulotec-infra && sudo cp /tmp/sulotec-infra/apps/indira/docker-compose*.yml /tmp/sulotec-infra/apps/indira/deploy/*.sh /data/apps/indira/ && sudo rm -rf /tmp/sulotec-infra && ls /data/apps/indira
   ```
   Luego:
   ```
   sudo /opt/sulotec/scripts/new-project-db.sh postgres indira
   sudo bash /data/apps/indira/preparar.sh
   sudo bash /data/apps/indira/desplegar.sh
   sudo bash /data/apps/indira/probar.sh
   ```
   - `new-project-db.sh` muestra la cadena **Node** una sola vez. Guardala en el gestor de contrasenas, nunca en un chat.
     `preparar.sh` la pide sin mostrarla.
   - `preparar.sh` genera el token del producto `indira` en el servicio de licencias y lo guarda directo en el `.env`,
     sin mostrarlo. Repetirlo con "s" rota el token.
   - `desplegar.sh` clona `main`, construye la imagen y la levanta. Si no arranca, vuelve a la anterior. Para probar una rama:
     `RAMA=feature/primera-entrega sudo -E bash /data/apps/indira/desplegar.sh`.
6. **Cloudflare:** en el tunel agrega el *Public hostname* `api-indira.sulotec.com` → `http://indira:3300`
   ([docs/03-cloudflare.md](../../docs/03-cloudflare.md)). Repite `probar.sh`: la direccion publica y CORS deben dar OK.
7. **Medir el tunel** (Cloudflare corta a los 100 s si no pasa nada). Pon `INDIRA_FALSO_DEMORA_S=160` en
   `/opt/sulotec/indira.env`, corre `desplegar.sh` y luego `probar.sh` con `TOKEN` (instrucciones al inicio de `probar.sh`).
   Consume 1 token. Despues vuelve a 0 y despliega.
8. **Licencia de prueba:** crea en `sulotec.com/licencias` una licencia `indira` para una empresa de prueba.
9. **Encender el widget:** en GitHub, Settings > Variables > Actions, crea `INDIRA_ACTIVA=true` y vuelve a correr *Publicar portal*.
   Para apagarlo, ponla en `false` y vuelve a correrlo.

## Operar

- **Log:** `sudo docker logs --tail 100 indira`. El token y los mensajes no se escriben en el log.
- **Apagar sin borrar:** `cd /data/apps/indira && sudo docker compose stop`. El widget muestra "No pude conectarme".
- **Volver a una version anterior:** `docker images indira` y luego
  `sudo docker tag indira:<version> indira:latest && cd /data/apps/indira && sudo docker compose up -d --force-recreate`.
- **Ollama de PLAFT** (solo con permiso): `sudo touch /data/apps/indira/usar-ollama`, `PROVEEDOR=ollama sudo -E bash preparar.sh`
  y `desplegar.sh`. Comparte CPU con PLAFT: una respuesta puede tardar ~160 s. Para volver atras: borra `usar-ollama`,
  `PROVEEDOR=falso` y despliega.
- **Retencion:** las conversaciones, los turnos terminados y la memoria duran 90 dias (`INDIRA_RETENCION_DIAS`). La purga
  corre sola cada dia. La base entra en el respaldo diario del PostgreSQL compartido; el `.env` no.
- **Claude:** no se enciende desde el kit. Hace falta resolver el aviso de privacidad, poner un tope de gasto en la consola
  de Anthropic y agregar a mano `INDIRA_PROVEEDOR=claude`, `INDIRA_PRIVACIDAD_ACEPTADA=si` y `ANTHROPIC_API_KEY`. Costos
  en el README de Indira-Backend: el peor caso ronda US$ 0,25 por mensaje en Opus.
