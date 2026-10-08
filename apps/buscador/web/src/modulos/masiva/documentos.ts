// Lectura de listas de documentos (pegadas o desde .txt/.csv) para la carga masiva.

export const LIMITE_DOCUMENTOS = 10_000;
export const TAMANO_MAXIMO = 4_990_000; // la API acepta hasta 5 MB por peticion (incluye el formulario)

export type TipoLista = 'personas' | 'empresas';

const TIPOS_PERSONAS = [
  { nombre: 'DNI', patron: /^\d{8}$/ },
  { nombre: 'RUC', patron: /^(10|15|16|17|20)\d{9}$/ },
  { nombre: 'Carnet de extranjería', patron: /^\d{9}$/ },
  { nombre: 'Otros documentos', patron: /^[A-Z0-9-]{4,20}$/ },
];
const TIPOS_EMPRESAS = [{ nombre: 'RUC', patron: /^(10|15|16|17|20)\d{9}$/ }];

const ENCABEZADOS = /^(dni|ruc|ce|pasaporte|documento|documentos|nro|numero|número|tipo)$/i;

export interface Analisis {
  validos: string[];
  invalidos: string[];
  duplicados: number;
  porTipo: { nombre: string; cantidad: number }[];
}

export function analizar(texto: string, tipo: TipoLista): Analisis {
  const tipos = tipo === 'empresas' ? TIPOS_EMPRESAS : TIPOS_PERSONAS;
  const vistos = new Set<string>();
  const invalidos: string[] = [];
  const conteo = new Map<string, number>();
  let duplicados = 0;
  for (const bruto of texto.replace(/^﻿/, '').split(/[\s,;|]+/)) {
    const valor = bruto.replace(/["']/g, '').trim().toUpperCase();
    if (!valor || ENCABEZADOS.test(valor)) continue;
    const t = tipos.find((x) => x.patron.test(valor));
    if (!t) { invalidos.push(bruto); continue; }
    if (vistos.has(valor)) { duplicados++; continue; }
    vistos.add(valor);
    conteo.set(t.nombre, (conteo.get(t.nombre) ?? 0) + 1);
  }
  return {
    validos: [...vistos],
    invalidos,
    duplicados,
    porTipo: tipos.filter((t) => conteo.has(t.nombre)).map((t) => ({ nombre: t.nombre, cantidad: conteo.get(t.nombre)! })),
  };
}

// La API recibe un .txt con un documento por linea.
export function crearArchivo(documentos: string[], prefijo: string): File {
  const f = new Date();
  const p = (n: number) => String(n).padStart(2, '0');
  const nombre = `${prefijo}_${f.getFullYear()}${p(f.getMonth() + 1)}${p(f.getDate())}_${p(f.getHours())}${p(f.getMinutes())}.txt`;
  return new File([documentos.join('\r\n') + '\r\n'], nombre, { type: 'text/plain' });
}

export function plantilla(tipo: TipoLista): File {
  const contenido = tipo === 'empresas' ? 'RUC\r\n20100000001\r\n' : 'DNI\r\n12345678\r\n';
  return new File([contenido], tipo === 'empresas' ? 'Plantilla_RUC.txt' : 'Plantilla_DNI.txt', { type: 'text/plain' });
}

export const SECCIONES = [
  { id: 'moviles', nombre: 'Teléfonos', detalle: 'Números, operadoras y planes.' },
  { id: 'sueldos', nombre: 'Información laboral', detalle: 'Empresas e ingresos reportados.' },
  { id: 'deuda', nombre: 'Deudas', detalle: 'Entidades, saldos y períodos.' },
  { id: 'lineas-credito', nombre: 'Líneas de crédito', detalle: 'Montos utilizados y disponibles.' },
  { id: 'calificacion', nombre: 'Calificaciones', detalle: 'Clasificación crediticia reportada.' },
];
