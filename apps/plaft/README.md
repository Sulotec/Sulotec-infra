# PLAFT (prevención de lavado de activos) en el servidor de Oracle

> Esta carpeta tiene lo necesario para correr PLAFT en `sulotec-main`. Es para administradores: aquí se tocan claves y el servidor.
> El código vive en `jeliases-informaDev/Security-Backend` (Kotlin, MySQL), `Security-FrontEnd` (Next.js), `Security-MachineLearning` (Python) y `Security-App` (Expo).

```
Navegador ──▶ Cloudflare Tunnel ──▶ plaft-web  (Next.js, puerto 3000)
                                └──▶ plaft-api  (Spring Boot, puerto 8081)
                                         ├──▶ MySQL de la VM (base "plaft", red sulotec_data)
                                         └──▶ Bucket plaft-archivos (Object Storage; llave de svc-plaft)
```

| Dirección | Va a |
|---|---|
| `https://plaft.sulotec.com` | `http://plaft-web:3000` |
| `https://api-plaft.sulotec.com` | `http://plaft-api:8081` |

**Todavía no incluye** el servicio de IA (`Security-MachineLearning`: Indira, casos en prensa y scoring). El backend funciona sin él; esas pantallas
responden "servicio no disponible". Se agrega en una segunda etapa.

## Archivos

| Archivo | Para qué |
|---|---|
| `docker-compose.yml` | API y web: solo lectura, sin privilegios, sin puertos publicados, con memoria limitada |
| `deploy/crear-llave-oci.sh` | Crea en el servidor la llave de API de `svc-plaft` (la privada no sale de aquí) y prueba el bucket |
| `deploy/preparar.sh` | Crea `/opt/sulotec/plaft.env` (claves; solo root y docker lo leen) |
| `deploy/desplegar.sh` | Baja el código, construye, levanta y vuelve a la versión anterior si algo falla |
| `deploy/probar.sh` | Pruebas de humo: salud, rutas cerradas, base, almacenamiento, direcciones públicas y CORS |

## Puesta en marcha (en este orden)

**1. Copiar el kit al servidor** (desde `ssh.sulotec.com`):

```bash
sudo mkdir -p /data/apps/plaft
sudo git clone --depth 1 https://github.com/Sulotec/Sulotec-infra.git /tmp/sulotec-infra
sudo cp /tmp/sulotec-infra/apps/plaft/docker-compose.yml /tmp/sulotec-infra/apps/plaft/deploy/*.sh /data/apps/plaft/
sudo rm -rf /tmp/sulotec-infra
```

**2. Crear la base** y guardar los datos que muestra (la clave no se vuelve a ver):
`sudo /opt/sulotec/scripts/new-project-db.sh mysql plaft`

**3. Llave de Oracle para los archivos:** `sudo bash /data/apps/plaft/crear-llave-oci.sh`. Muestra una línea para pegar en Cloud Shell,
y pide los dos datos que esa línea devuelve (no son secretos). Prueba subir, leer y borrar un archivo en `plaft-archivos`.
El usuario `svc-plaft` debe tener permiso solo sobre ese bucket (`manage objects` y `read buckets`).

**4. Configuración:** `sudo bash /data/apps/plaft/preparar.sh`. Pide la clave de la base. Si la base es nueva, genera la clave del
administrador (`superadmin`, 12 caracteres: es el máximo que acepta el login) y la muestra **una sola vez**.

**5. Publicar:** `sudo bash /data/apps/plaft/desplegar.sh`. La primera vez tarda varios minutos (compila Kotlin y Next.js).
Con base nueva, al terminar el primer arranque sano apaga sola la "semilla" y borra la clave inicial del archivo de configuración.

**6. Cloudflare:** Networks → Tunnels → `sulotec` → *Published application routes* → Add. Las dos de la tabla de arriba,
tipo HTTP y la URL con `http://` (`http://plaft-web:3000` y `http://plaft-api:8081`).

**7. Comprobar:** `sudo bash /data/apps/plaft/probar.sh`, y entrar a `https://plaft.sulotec.com` con `superadmin`.
**Cambia la clave del administrador en el primer ingreso.**

## Operación

| Qué | Cómo |
|---|---|
| Ver registros | `docker logs -f plaft-api` |
| Versión publicada | `docker images plaft-api` (la etiqueta es el commit) |
| Cambiar una clave | `sudo bash /data/apps/plaft/preparar.sh` (Enter conserva) y luego `desplegar.sh` |
| Rotar la clave de la base | `sudo /opt/sulotec/scripts/rotar-claves.sh` rota `postgres` y `mysql`; para el usuario `plaft` de MySQL: `ALTER USER` y `preparar.sh` |
| Rotar la llave de Oracle | Borrar `/opt/sulotec/plaft-oci/config`, correr `crear-llave-oci.sh` y `desplegar.sh`; después borrar la llave vieja en Oracle |

## Reglas de seguridad de este producto

- La base y la API no publican puertos: todo entra por el túnel.
- La documentación de la API (`/swagger-ui`, `/v3/api-docs`) y los endpoints de `/actuator` salvo `health` quedan **cerrados** (el código los deja públicos por defecto).
- La llave de `svc-plaft` solo la ve el contenedor `plaft-api` (montada en lectura). No se usa la identidad de todo el servidor, para que otro contenedor
  comprometido no llegue a las denuncias.
- El sembrado inicial (`superadmin` con clave conocida de desarrollo) **nunca** se deja encendido: `desplegar.sh` lo apaga tras el primer arranque.

## Hallazgos del código a corregir con el equipo (no son de infraestructura)

1. **Clave de 8 a 12 caracteres en el login**, pero al crear o cambiar un usuario solo se exige mínimo 8: una clave de 13 o más caracteres creada en el sistema
   **no podría iniciar sesión**. Conviene un mínimo de 12 sin tope bajo.
2. **Sin límite de intentos ni bloqueo** en `/api/auth/login`: en Cloudflare conviene una regla de limitación de velocidad para esa ruta.
3. **`ddl-auto: update`**: Hibernate cambia las tablas al arrancar, sin historial de migraciones. Para producción con clientes conviene Flyway o Liquibase.
4. **`show-sql: true`** en el código (aquí se apaga con `SPRING_JPA_SHOW_SQL=false`).
5. Los cuatro repositorios son **públicos**: pasarlos a privados (requiere una llave de despliegue de solo lectura en el servidor).
