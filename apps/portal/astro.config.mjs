import { defineConfig } from 'astro/config';

// Sitio estatico: el build genera HTML/CSS listos para servir con nginx.
export default defineConfig({
  site: 'https://sulotec.com',
  build: { inlineStylesheets: 'always' },
});
