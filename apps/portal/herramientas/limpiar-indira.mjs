// Limpia un SVG exportado de Figma (archivo INdira) para public/indira/, sin redibujar nada.
//
//   node herramientas/limpiar-indira.mjs entrada.svg public/indira/salida.svg
//
// 1. Quita solo los fondos: el rect oscuro que Figma pone fuera del frame, el primer rect blanco del grupo
//    y "Rectangle 8". Los demas rect son cuello, ropa o pulsera, y el rect del <clipPath> se conserva.
// 2. Deja en <svg> solo xmlns, viewBox y fill="none" (sin width, height, style ni preserveAspectRatio).
import { readFileSync, writeFileSync } from 'node:fs';

const [entrada, salida] = process.argv.slice(2);
if (!entrada || !salida) {
  console.error('Uso: node herramientas/limpiar-indira.mjs entrada.svg salida.svg');
  process.exit(1);
}

let svg = readFileSync(entrada, 'utf8');
const viewBox = svg.match(/viewBox="([^"]+)"/)?.[1];
if (!viewBox) throw new Error('El SVG no tiene viewBox');

svg = svg.replace(/<svg[^>]*>/, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}" fill="none">`);
const corte = svg.indexOf('<defs>');
let cuerpo = corte < 0 ? svg : svg.slice(0, corte);
const resto = corte < 0 ? '' : svg.slice(corte);
cuerpo = cuerpo
  .replace(/\n?<rect width="[\d.]+" height="[\d.]+" fill="#1E1E1E"\/>/, '')
  .replace(/\n?<rect width="[\d.]+" height="[\d.]+" fill="white"\/>/, '')
  .replace(/\n?<rect id="Rectangle 8"[^>]*\/>/, '');

writeFileSync(salida, cuerpo + resto);
console.log(`Listo: ${salida}`);
