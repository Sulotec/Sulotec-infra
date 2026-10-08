import { defineConfig } from 'astro/config';

// Sitio estatico: el build genera HTML/CSS listos para servir con nginx.
export default defineConfig({
  site: 'https://sulotec.com',
  // format 'file': /demo/miradar360 se genera como demo/miradar360.html (sin redirecciones)
  build: { inlineStylesheets: 'always', format: 'file' },
});
