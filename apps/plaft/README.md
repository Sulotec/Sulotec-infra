# PLAFT (prevención de lavado de activos) en el servidor de Oracle

> Esta carpeta tiene lo necesario para correr PLAFT en `sulotec-main`. Es para administradores: aquí se tocan claves y el servidor.
> El código vive en `jeliases-informaDev/Security-Backend` (Kotlin, MySQL), `Security-FrontEnd` (Next.js), `Security-MachineLearning` (Python) y `Security-App` (Expo).

```
Navegador ──▶ Cloudflare Tunnel ──▶ plaft-web  (Next.js, puerto 3000)
                                └──▶ plaft-api  (Spring Boot, puerto 8081)
                                         ├──▶ MySQL de la VM (base "plaft", red sulotec_data)
                                         ├──▶ Bucket plaft-archivos (Object Storage; llave de svc-plaft)
                                         └──▶ plaft-ml  (IA: personas, prensa, Indira; opcional, solo red interna)
                                                  ├──▶ PostgreSQL de la VM (base "plaft_ml")
                                                  └──▶ plaft-ollama (modelo de lenguaje local; red "ia", solo lo ve plaft-ml)
```

| Dirección | Va a |
|---|---|
| `https://plaft.sulotec.com` | `http://plaft-web:3000` |
| `https://api-plaft.sulotec.com` | `http://plaft-api:8081` |

El servicio de IA (`Security-MachineLearning`: casos en prensa, scoring de personas e Indira) es **opcional**: el backend funciona sin él y esas
pantallas responden "servicio no disponible". Se instala con el paso 8 y `desplegar.sh` lo publica solo si existe su configuración.

## Archivos

| Archivo | Para qué |
|---|---|
| `docker-compose.yml` | API y web: solo lectura, sin privilegios, sin puertos publicados, con memoria limitada |
| `deploy/crear-llave-oci.sh` | Crea en el servidor la llave de API de `svc-plaft` (la privada no sale de aquí) y prueba el bucket |
| `deploy/preparar.sh` | Crea `/opt/sulotec/plaft.env` (claves; solo root y docker lo leen) |
| `deploy/desplegar.sh` | Baja el código, construye, levanta y vuelve a la versión anterior si algo falla |
| `deploy/probar.sh` | Pruebas de humo: salud, rutas cerradas, base, IA (si está instalada), almacenamiento, direcciones públicas y CORS |
| `deploy/preparar-ml.sh` | Crea `/opt/sulotec/plaft-ml.env` de la IA (usa la misma clave interna que ya tiene `plaft.env`) |
| `deploy/restaurar-ml.sh` | Carga en la base `plaft_ml` un respaldo `pg_dump -Fc` de `security_ml` (todo o nada) |
| `deploy/cargar-datos.sh` | Carga las listas (colorimetría), las sancionadas de la SBS (Excel) y las figuras políticas con sus casos en prensa (base de la IA); simula por defecto y respalda antes de escribir |
| `deploy/activar-indira.sh` | Instala Ollama (modelo local), baja el modelo, enciende a Indira y la deteccion de casos en prensa, y prueba una conversación real |
| `deploy/pasar-dev-a-produccion.sh` | Pasa a `plaft` lo valioso de la copia de desarrollo (cuentas con sus roles, personas, listas, consultas, matrices); simula por defecto y respalda antes de escribir |
| `deploy/cargar-operaciones-demo.sh` | Carga 10 registros ficticios en Operaciones (el script de demostración del backend) para probar ese módulo |
| `deploy/ejemplos-para-probar.sh` | Muestra ejemplos reales de lo cargado (qué buscar, qué cuentas, denuncias, operaciones, matrices) para probar cada módulo de la web |
| `deploy/importar-dev.sh` | Trae a este servidor la base de desarrollo de Aiven (el respaldo) en bases `aiven_*` y la compara con producción, sin tocarla |

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

**8. Servicio de IA (opcional, cuando lo anterior ya funciona):**

```bash
sudo /opt/sulotec/scripts/new-project-db.sh postgres plaft_ml     # crea la base y el usuario; guarda la clave que muestra
sudo bash /data/apps/plaft/preparar-ml.sh                          # pide esa clave y pregunta si se activa Indira (por defecto no)
sudo bash /data/apps/plaft/restaurar-ml.sh                         # carga el respaldo security_ml (ver abajo)
sudo bash /data/apps/plaft/desplegar.sh                            # construye plaft-ml y lo levanta junto con lo demás
sudo bash /data/apps/plaft/probar.sh                               # ahora también prueba la IA
```

`restaurar-ml.sh` toma `externos/plaft/security_ml.dump` del bucket `sulotec-backups` (con la identidad del servidor) o un archivo local:
`sudo bash /data/apps/plaft/restaurar-ml.sh /ruta/security_ml.dump`. Si la base `plaft_ml` ya tiene tablas se niega a seguir; para reemplazarlas:
`BORRAR_DESTINO=si sudo -E bash /data/apps/plaft/restaurar-ml.sh`. Sin respaldo no hace falta: la IA crea sus tablas vacías al arrancar (migraciones).
Si la IA no arranca, `desplegar.sh` deja la API y la web como estaban y muestra los registros de `plaft-ml`.
**Indira** y la detección de casos en prensa necesitan un modelo de lenguaje local: se instala con el paso 10; mientras `INDIRA_ENABLED=false` el chat responde "no disponible".

**9. Datos de listas (los Excel):** sube `Listas y Colorimetría.xlsx` y `Lista de empresas sancionadas.xlsx` al bucket `sulotec-backups`, carpeta `externos/plaft/`
(consola de Oracle → Object Storage), y corre primero la simulación y, si el resumen se ve bien, la carga:

```bash
sudo bash /data/apps/plaft/cargar-datos.sh              # simula: no escribe nada
sudo bash /data/apps/plaft/cargar-datos.sh --aplicar    # respalda la base (en /var/backups/sulotec) y escribe
```

Usa `tools/cargar_datos.py` del backend (se puede repetir: no duplica y nunca borra). Si existe la IA, también exporta de `plaft_ml` las personas (menos las descartadas)
con sus casos a un JSON y la herramienta las registra como entidades PEP con sus noticias "pendientes de revisión" (el ML no tiene un endpoint de listado, por eso se leen
directo de su base). Para omitirlas: `SIN_POLITICOS=1`. Los Excel y el respaldo de la IA tienen datos de personas: guárdalos solo en el bucket privado.

**10. Indira (modelo de lenguaje local):** `sudo bash /data/apps/plaft/activar-indira.sh`. Revisa memoria y disco, levanta Ollama (`plaft-ollama`, red `ia`),
descarga `qwen2.5:7b` (~5 GB; `llama3.1:8b` a veces devuelve la llamada a la herramienta como texto y Indira no responde), enciende `INDIRA_ENABLED`, sube a 300 s la espera del backend (`ML_CHATTIMEOUTSECONDS`) y hace una pregunta real, midiendo el tiempo.
El modelo corre en CPU: una respuesta puede tardar de decenas de segundos a un par de minutos, y **Cloudflare corta lo que pase de 100 s**. Si la prueba pasa de 90 s, el script avisa;
una alternativa más liviana y rápida: `MODELO=qwen2.5:3b MEM_MIN=4000 sudo -E bash /data/apps/plaft/activar-indira.sh`. El script también detecta si Indira contesta con una llamada a herramienta en bruto y avisa. Apagarla: `sudo bash /data/apps/plaft/activar-indira.sh --apagar`.
La vigilancia diaria de prensa corre a las 6:00 (hora de Lima) y usa el modelo un buen rato; Ollama tiene `cpu_shares` bajos para no quitarle CPU a las demás aplicaciones.

**11. Base de desarrollo (Aiven):** `sudo bash /data/apps/plaft/importar-dev.sh`. Restaura el respaldo más reciente de `/data/backups/externos` en bases `aiven_<nombre>` de la MySQL de la VM
(entran en el respaldo nocturno) y muestra, tabla por tabla, las filas de desarrollo contra las de `plaft`. No toca producción; con esa tabla se decide qué pasa a producción.

**12. De la copia de desarrollo a producción:** `sudo bash /data/apps/plaft/pasar-dev-a-produccion.sh` (simula y muestra qué entraría, incluidas las cuentas con su rol) y, si se ve bien,
con `--aplicar` (respalda `plaft` antes). Reconoce lo que ya existe por su clave natural (usuario o correo, tipo + número de documento, nombre de la lista) y agrega solo lo que falta, reconectando
las relaciones con identificadores nuevos. **No pasa** las cuentas que usan una clave pública conocida (la de la semilla `Admin12345!`) ni, salvo `CON_DENUNCIAS=1`, las denuncias de prueba.

**13. Datos de prueba para todos los módulos:** además de lo anterior, `sudo bash /data/apps/plaft/cargar-operaciones-demo.sh` carga los datos ficticios de Operaciones
(`docs/operaciones-demo.sql` del backend; no se repite si ya hay). Para pasar **toda** la base de desarrollo (incluidas las personas y listas de demostración, las cuentas de prueba y las
denuncias de prueba): `sudo env CON_DENUNCIAS=1 bash /data/apps/plaft/pasar-dev-a-produccion.sh --aplicar`. Antes de salir con clientes reales hay que desactivar las cuentas de prueba.

## Operación

| Qué | Cómo |
|---|---|
| Ver registros | `docker logs -f plaft-api` (y `docker logs -f plaft-ml` para la IA) |
| Versión publicada | `docker images plaft-api` (la etiqueta es el commit) |
| Cambiar una clave | `sudo bash /data/apps/plaft/preparar.sh` (Enter conserva) y luego `desplegar.sh` |
| Rotar la clave de la base | `sudo /opt/sulotec/scripts/rotar-claves.sh` rota `postgres` y `mysql`; para el usuario `plaft` de MySQL: `ALTER USER` y `preparar.sh` |
| Rotar la llave de Oracle | Borrar `/opt/sulotec/plaft-oci/config`, correr `crear-llave-oci.sh` y `desplegar.sh`; después borrar la llave vieja en Oracle |

## Reglas de seguridad de este producto

- La base y la API no publican puertos: todo entra por el túnel.
- La documentación de la API (`/swagger-ui`, `/v3/api-docs`) y los endpoints de `/actuator` salvo `health` quedan **cerrados** (el código los deja públicos por defecto).
- La llave de `svc-plaft` solo la ve el contenedor `plaft-api` (montada en lectura). No se usa la identidad de todo el servidor, para que otro contenedor
  comprometido no llegue a las denuncias.
- La IA (`plaft-ml`) no tiene ruta en Cloudflare ni puertos publicados: solo `plaft-api` le habla, por la red interna y con la clave `X-Internal-Key`
  (`ENTORNO=prod` la exige). Corre sin privilegios, en solo lectura y con memoria limitada. Su base (`plaft_ml`) es un usuario aparte en PostgreSQL.
- El sembrado inicial (`superadmin` con clave conocida de desarrollo) **nunca** se deja encendido: `desplegar.sh` lo apaga tras el primer arranque.

## Hallazgos del código a corregir con el equipo (no son de infraestructura)

1. **Clave de 8 a 12 caracteres en el login**, pero al crear o cambiar un usuario solo se exige mínimo 8: una clave de 13 o más caracteres creada en el sistema
   **no podría iniciar sesión**. Conviene un mínimo de 12 sin tope bajo.
2. **Sin límite de intentos ni bloqueo** en `/api/auth/login`: en Cloudflare conviene una regla de limitación de velocidad para esa ruta.
3. **`ddl-auto: update`**: Hibernate cambia las tablas al arrancar, sin historial de migraciones. Para producción con clientes conviene Flyway o Liquibase.
4. **`show-sql: true`** en el código (aquí se apaga con `SPRING_JPA_SHOW_SQL=false`).
5. Los cuatro repositorios son **públicos**: pasarlos a privados (requiere una llave de despliegue de solo lectura en el servidor).
