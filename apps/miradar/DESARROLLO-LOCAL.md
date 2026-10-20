# MiRadar 360: levantar el proyecto en tu PC (desarrolladores)

Guía para clonar y correr MiRadar completo en tu computadora, sin tocar producción.
Probada el 2026-10-20 en Windows 11 con Node 24.20 y Docker Desktop.

> Producción corre en el servidor de Oracle (`miradar360.sulotec.com`) y solo la publica el dueño con
> `desplegar.sh` (ver [README.md](README.md)). Aquí todo es local: tu base, tu API, tu web.

## Dónde está cada cosa

| Parte | Repositorio | Tecnología | Corre en |
|---|---|---|---|
| **Backend (API)** | https://github.com/jeliases-informaDev/Afacop-Backend | Node 24, Express, Socket.IO, Prisma, PostgreSQL | http://localhost:4001 |
| **Web (panel de administración)** | https://github.com/jeliases-informaDev/Afacop-FrontEnd | React 19 + Vite | http://localhost:5173 |
| **App móvil (asesores)** | https://github.com/jeliases-informaDev/App-Afacop | React Native con Expo | emulador o celular |
| Kit del servidor (solo administradores) | https://github.com/Sulotec/Sulotec-infra → `apps/miradar/` | Docker Compose | Oracle |

Los tres repos de código son públicos hoy; se clonan sin permisos. (El nombre viejo del producto era AFACOP, por eso los repos se llaman así.)

## 0. Instala una sola vez

| Herramienta | Para qué | Comprobar |
|---|---|---|
| [Git](https://git-scm.com/downloads) | clonar | `git --version` |
| [Node.js 24 LTS](https://nodejs.org) | backend y web (ambos piden la 24) | `node -v` → `v24.x` |
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | la base PostgreSQL local | `docker --version` |
| Android Studio (emulador) o la app **Expo Go** en tu celular | solo si vas a tocar la app móvil | |

## 1. Clona los tres repos

```bash
mkdir miradar
cd miradar
git clone https://github.com/jeliases-informaDev/Afacop-Backend.git backend
git clone https://github.com/jeliases-informaDev/Afacop-FrontEnd.git web
git clone https://github.com/jeliases-informaDev/App-Afacop.git app
```

Queda así: `miradar/backend`, `miradar/web`, `miradar/app`.

## 2. Base de datos local (PostgreSQL 16 en Docker)

```bash
docker run -d --name miradar-postgres -e POSTGRES_USER=miradar -e POSTGRES_PASSWORD=miradar -e POSTGRES_DB=miradar -p 5432:5432 postgres:16
```

Crea una base vacía llamada `miradar` con usuario y clave `miradar` (solo existe en tu PC). Las tablas las crea el backend en el paso 3.

- Si te dice `port is already allocated` (otro PostgreSQL usa el 5432): cambia `-p 5432:5432` por `-p 5440:5432` y, en el `.env` del backend del paso 3, cambia `localhost:5432` por `localhost:5440`.
- Después de reiniciar la PC, la base no arranca sola: `docker start miradar-postgres`.
- Para empezar de cero: `docker rm -f miradar-postgres` y repite el comando de arriba.

## 3. Backend (API)

```bash
cd backend
```

**3.1 Crea el archivo `.env`.** Este comando lo escribe completo: genera las dos llaves secretas al azar y una clave para el usuario `admin`, que te muestra una sola vez (queda guardada en el `.env`, que git ignora):

```bash
node -e "const c=require('crypto');const f=require('fs');if(f.existsSync('.env')){console.log('.env ya existe, no lo toco');process.exit(0)}const p='Dev.'+c.randomBytes(6).toString('hex')+'!A1';f.writeFileSync('.env',['NODE_ENV=development','PORT=4001','DATABASE_URL=postgresql://miradar:miradar@localhost:5432/miradar','JWT_SECRET='+c.randomBytes(32).toString('hex'),'MFA_ENCRYPTION_KEY='+c.randomBytes(32).toString('hex'),'INITIAL_ADMIN_USERNAME=admin','INITIAL_ADMIN_PASSWORD='+p,'RESET_INITIAL_ADMIN=false','REQUIRE_MFA=false','MFA_EXEMPT_USERNAMES=admin','FRONTEND_URL=http://localhost:5173','CORS_ALLOW_ALL=false','TRUST_PROXY=false','LOG_LEVEL=info','GEOCODING_PROVIDER=nominatim','GEOCODING_WORKER_ENABLED=false','GEOCODING_BATCH_SIZE=5',''].join('\n'));console.log('Listo: .env creado. Usuario admin, clave: '+p)"
```

Qué deja configurado: API en el puerto **4001** (la web y la app lo buscan ahí), base del paso 2, MFA apagado en local, CORS solo para la web local, geocodificación apagada (para no saturar el servicio gratuito de OpenStreetMap). Si olvidas la clave del admin, está en la línea `INITIAL_ADMIN_PASSWORD` del `.env`.

**3.2 Instala y arranca:**

```bash
npm ci
npm start
```

- `npm ci` instala las dependencias y descarga un Chromium (~170 MB) que la API usa para generar PDF: la primera vez tarda unos minutos.
- `npm start` aplica las migraciones (crea todas las tablas), crea el usuario `admin` y arranca la API. Verás `All migrations have been successfully applied`, `Administrador inicial creado: admin` y `http://localhost:4001`.
- Comprobar: abre http://localhost:4001/health/ready → `{"status":"ready"}`.

Las siguientes veces basta `npm run dev` (arranca sin migrar). Usa `npm start` cuando traigas migraciones nuevas de `main`.

Lo que **no** funciona en local sin configurar más: subir fotos y firmas de las visitas (necesita un bucket; las cinco variables `B2_*` van juntas o ninguna). Si lo necesitas, pide a Sulotec un bucket **de pruebas**; nunca el de producción.

## 4. Web (panel)

En otra terminal:

```bash
cd web
node -e "require('fs').writeFileSync('.env','VITE_API_URL=http://localhost:4001\n')"
npm ci
npm run dev
```

Abre http://localhost:5173 y entra con `admin` y la clave que mostró el paso 3.1. El `.env` apunta la web a tu API local; git lo ignora. No pongas ahí la dirección de producción.

## 5. App móvil (Expo)

```bash
cd app
npm install
```

Crea `app/.env.local` (git lo ignora y manda sobre el `.env` del repo, que apunta a producción) con la dirección de tu API:

- Emulador Android: `EXPO_PUBLIC_API_URL=http://10.0.2.2:4001` (`10.0.2.2` es "la PC" vista desde el emulador).
- Celular físico con Expo Go: `EXPO_PUBLIC_API_URL=http://192.168.1.50:4001`, cambiando `192.168.1.50` por la IP de tu PC en la misma red Wi-Fi (`ipconfig` en Windows, `ifconfig` en Mac). Si Windows pregunta por el firewall al arrancar la API, permite el acceso en redes privadas.

Con el emulador:

```bash
node -e "require('fs').writeFileSync('.env.local','EXPO_PUBLIC_API_URL=http://10.0.2.2:4001\n')"
npx expo start
```

El rol ASESOR solo entra por la app; créalo desde el panel web (Asesores y luego su usuario). Para generar APK se usa EAS (`eas.json`), eso lo hace Sulotec.

## 6. Cómo trabajar y entregar

- Una **rama por tarea** y **Pull Request** a `main`; nadie empuja directo a `main`. Los PR los une el dueño del repo. Mensajes de commit en español.
- Cambios de base de datos: en `backend`, `npx prisma migrate dev --name lo_que_cambias` crea la carpeta en `prisma/migrations`; súbela en el PR. Producción aplica las migraciones sola al desplegar.
- Pruebas del backend: `npm test`.
- Nunca subas `.env`, claves ni datos reales (clientes, DNI, fotos). La base local empieza vacía: carga datos de prueba inventados desde el panel.
- Cuando el PR se une a `main`, el dueño publica en Oracle con `desplegar.sh`; tú no tocas el servidor.

## 7. Si algo falla

| Síntoma | Causa y arreglo |
|---|---|
| `Configuración de entorno inválida: ...` al arrancar | Falta o está mal una variable del `.env`. Borra el `.env` y repite el paso 3.1 |
| `ECONNREFUSED` o `Can't reach database server` | La base no está arriba: `docker start miradar-postgres` (y revisa el puerto si usaste 5440) |
| `EADDRINUSE: 4001` | Otra API en el 4001. Cierra la otra, o cambia `PORT` en el `.env` y `VITE_API_URL` en la web |
| La web dice "Network Error" o error de CORS | La API no está arriba, o abriste la web por otra dirección que no es `http://localhost:5173` |
| `npm warn EBADENGINE` en la web | Es solo un aviso de versión; con Node 24 funciona |
| Olvidaste la clave de `admin` | Está en el `.env`. Para cambiarla: edita `INITIAL_ADMIN_PASSWORD`, pon `RESET_INITIAL_ADMIN=true`, `npm start`, y vuelve a `false` |
| La app no llega a la API | Celular y PC en la misma Wi-Fi, IP correcta en `.env.local`, firewall permitido; reinicia `npx expo start` tras cambiar el `.env.local` |
