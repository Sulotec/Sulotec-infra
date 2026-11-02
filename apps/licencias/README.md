# Kit del servicio de licencias (`licencias`)

El servicio común que decide planes, cupos de usuarios, bolsas de tokens, consumo y avisos para **todos** los productos.
Código: [`jeliases-informaDev/Licencias-Backend`](https://github.com/jeliases-informaDev/Licencias-Backend). Modelo y contrato:
[`docs/licencias/`](../../docs/licencias/). Pantallas en el portal: `sulotec.com/licencias` (Sulotec) y `sulotec.com/mi-licencia` (empresas).

| Qué | Dónde |
|---|---|
| API | `https://api-licencias.sulotec.com` (túnel → `http://licencias:3200`) |
| Contenedor | `licencias` (imagen `licencias:latest`, 256 MB, solo lectura) |
| Base | `licencias` en el PostgreSQL 16 compartido (red `sulotec_data`) |
| Configuración | `/opt/sulotec/licencias.env` (lo crea `preparar.sh`; no entra al respaldo ni al repositorio) |
| Kit en el servidor | `/data/apps/licencias` (`docker-compose.yml` + `deploy/*.sh`; el workflow los copia al hacer push, como los demás kits) |

## Instalar (una sola vez)

En el servidor (https://ssh.sulotec.com):

```
sudo /opt/sulotec/scripts/new-project-db.sh postgres licencias
sudo bash /data/apps/licencias/preparar.sh
sudo bash /data/apps/licencias/desplegar.sh
sudo bash /data/apps/licencias/probar.sh
```

1. `new-project-db.sh` crea la base y el usuario y muestra la cadena **Node**; `preparar.sh` la pide (no se muestra al pegarla) y guarda el `.env`. Ahí mismo se puede configurar el correo de salida (una credencial SMTP **propia** del servicio en OCI, no la de Keycloak).
2. `desplegar.sh` clona `main` del repositorio, construye la imagen y la levanta; si no arranca, vuelve a la anterior. El esquema lo aplica el servicio al arrancar.
3. **Cloudflare:** en el túnel agrega el *Public hostname* `api-licencias.sulotec.com` → `http://licencias:3200`.
4. **Keycloak:** el workflow *Publicar cuenta* corre `ajustar-realm.sh`, que ya deja el access token del portal con la audiencia `licencias` y el claim `roles` (paso 10). Si no se publicó `apps/cuenta` después de ese cambio, córrelo a mano: `sudo docker exec -i cuenta bash -s < /data/apps/cuenta/ajustar-realm.sh`.
5. **Token de cada producto** (se muestra una sola vez; va en el `.env` del producto como `LICENCIAS_TOKEN`):

```
sudo docker exec licencias node scripts/token-producto.js geomatrix
```

   Claves: `geomatrix`, `miradar360`, `plaft`, `buscador`, `dashboard`. Repetir el comando rota el token (el anterior deja de valer).

## Operar

- **Publicar una versión nueva:** `sudo bash /data/apps/licencias/desplegar.sh` (una rama: `RAMA=mi-rama sudo -E bash …`).
- **Ver el log:** `sudo docker logs --tail 100 licencias`. Los correos sin SMTP aparecen como `[correo no configurado]`.
- **Correr los vencimientos a mano:** `sudo docker exec licencias node scripts/tarea.js vencimientos` (es idempotente; el servicio ya lo hace cada hora).
- **Reglas de negocio** (80 %, tolerancia, plazos): desde `sulotec.com/licencias` → Reglas, sin tocar código.
- **Respaldo:** la base entra en el respaldo diario del PostgreSQL compartido; el `.env` no (como todos).
