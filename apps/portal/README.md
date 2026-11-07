# Portal sulotec.com

Sitio estatico hecho con [Astro](https://astro.build) y componentes. Estilo visual tomado como referencia del
manual de marca de Informa Peru (azul `#1B4589`, rojo `#ED1C24` solo como acento, Leelawadee UI / Arial).

## Estructura
```
src/data/sitio.ts         textos generales, correo, menu
src/data/soluciones.ts    UN bloque por producto (las tarjetas y el pie se generan de aqui)
src/components/           Header, Hero, ProductCard, Contacto, Footer, Logo, Icon
src/layouts/Base.astro    <head> y estructura comun
src/styles/global.css     colores y estilos base
deploy/                   docker-compose.yml + nginx.conf para el servidor
```

## Agregar o cambiar un producto
Edita `src/data/soluciones.ts`. Cuando el producto este publicado, pon su `enlace` (subdominio) y la tarjeta
mostrara "Ingresar".

## Trabajar y compilar
```bash
npm install
npm run dev      # vista previa en http://localhost:4321
npm run build    # genera dist/
```

## Publicar
En el servidor el sitio vive en `/data/apps/portal` (`deploy/` + carpeta `sitio/` con el contenido de `dist/`):
`docker compose up -d`. En Cloudflare Tunnel: `sulotec.com` y `www.sulotec.com` -> `http://portal:80`.
Mas adelante: despliegue automatico desde el repositorio Git de la empresa.

## Indira (asistente)
`<indira-asistente>` aparece abajo a la derecha en todas las paginas menos `/cuenta/*`. Esta **apagada por defecto**:
se enciende con la variable `INDIRA_ACTIVA=true` de GitHub Actions (`PUBLIC_INDIRA_ACTIVA` al compilar).

```
public/indira.js              el elemento, con Shadow DOM y sin dependencias
public/indira/titere.js       dibujo, expresiones y el UNICO mapa estado -> pose (copia de la demo)
public/indira/widget.css      estilos del panel (dentro del Shadow DOM)
public/indira/invitado.json   respuestas fijas: sin sesion y en los botones (no llaman al modelo ni cuestan)
public/indira/preguntas.json  una pregunta proactiva por pagina, como maximo una cada 24 h
public/indira/*.svg, poses/*.svg   poses (las de poses/ son las fotos vectorizadas). Cambiar una pose es reemplazar el archivo o su nombre en POSES (titere.js); su movimiento va en MOVIMIENTO
herramientas/limpiar-indira.mjs  quita el fondo de un SVG exportado de Figma
```

- Sin sesion no se llama a la API. Con sesion usa `https://api-indira.sulotec.com` (`PUBLIC_INDIRA_API`) con el token
  de la cuenta; cada mensaje escrito cobra la tarifa de la licencia `indira` y el panel lo avisa.
- El texto del modelo se pinta solo con `textContent` y los enlaces salen de una lista cerrada de destinos.
- La CSP de `deploy/nginx.conf` permite `connect-src https://api-indira.sulotec.com`.
- Prueba local: `PUBLIC_INDIRA_ACTIVA=true PUBLIC_INDIRA_API=http://localhost:8000 npm run build`.
