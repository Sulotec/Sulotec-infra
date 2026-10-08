import type { IconName } from '../components/Icon.astro';

// Una entrada por producto. La tarjeta, el menu del pie y todo lo demas se generan desde aqui:
// para agregar un producto nuevo, copia un bloque y cambia sus datos.
export type Estado = 'produccion' | 'implementacion' | 'interno';

export interface Solucion {
  nombre: string;
  descripcion: string;
  estado: Estado;
  plataformas: string[];
  icono: IconName;
  // Cuando el producto este publicado, pon su subdominio (ej. 'https://miradar360.sulotec.com').
  enlace?: string;
}

export const soluciones: Solucion[] = [
  {
    nombre: 'MiRadar360',
    descripcion:
      'Torre de control para tus equipos en campo: rutas del día, estado de cada visita y monitoreo en tiempo real, con evidencias GPS y fotos desde el celular.',
    estado: 'produccion',
    plataformas: ['Web', 'Android', 'iOS'],
    icono: 'radar',
  },
  {
    nombre: 'Auditoría de Visitas',
    descripcion:
      'Comprueba que cada visita ocurrió de verdad: geocerca antifraude, fotos, firma digital y trabajo sin conexión, con un panel web para el seguimiento.',
    estado: 'produccion',
    plataformas: ['Web', 'App móvil'],
    icono: 'mapCheck',
  },
  {
    nombre: 'Prevención de Lavado de Activos',
    descripcion:
      'Plataforma de cumplimiento para apoyar la prevención del lavado de activos y del financiamiento del terrorismo (PLAFT), con trazabilidad y seguridad.',
    estado: 'implementacion',
    plataformas: ['Web', 'App móvil'],
    icono: 'shield',
  },
  {
    nombre: 'Buscador Interno',
    descripcion:
      'Encuentra en segundos la información de tu organización, con búsqueda centralizada y acceso solo para personal autorizado.',
    estado: 'interno',
    plataformas: ['Web'],
    icono: 'search',
  },
];

export const estados: Record<Estado, string> = {
  produccion: 'En producción',
  implementacion: 'En implementación',
  interno: 'Uso interno',
};
