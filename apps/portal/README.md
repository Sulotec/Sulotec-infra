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
