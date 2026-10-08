import type { IconName } from '../components/Icon.astro';

// Una entrada por producto. La tarjeta, el pie de pagina y todo lo demas se generan desde aqui.
// - Para agregar un producto nuevo: copia un bloque completo ({ ... },) y cambia sus datos.
// - Cuando un producto ya este en linea en su subdominio, cambia `publicado: false` a `true`:
//   el boton de la tarjeta pasa de "Solicitar informacion" a "Ingresar" y lleva a https://<subdominio>.
export type Estado = 'produccion' | 'implementacion' | 'interno';

export interface Solucion {
  nombre: string;
  descripcion: string;
  estado: Estado;
  plataformas: string[];
  icono: IconName;
  subdominio: string; // reservado en Cloudflare para este producto
  publicado: boolean;
}

export const soluciones: Solucion[] = [
  {
    nombre: 'MiRadar360',
    descripcion:
      'Torre de control para tus equipos en campo: rutas del día, estado de cada visita y monitoreo en tiempo real, con evidencias GPS y fotos desde el celular.',
    estado: 'produccion',
    plataformas: ['Web', 'Android', 'iOS'],
    icono: 'radar',
    subdominio: 'miradar360.sulotec.com',
    publicado: false,
  },
  {
    nombre: 'Auditoría de Visitas',
    descripcion:
      'Comprueba que cada visita ocurrió de verdad: geocerca antifraude, fotos, firma digital y trabajo sin conexión, con un panel web para el seguimiento.',
    estado: 'produccion',
    plataformas: ['Web', 'App móvil'],
    icono: 'mapCheck',
    subdominio: 'auditoria.sulotec.com',
    publicado: false,
  },
  {
    nombre: 'Prevención de Lavado de Activos',
    descripcion:
      'Plataforma de cumplimiento para apoyar la prevención del lavado de activos y del financiamiento del terrorismo (PLAFT), con trazabilidad y seguridad.',
    estado: 'implementacion',
    plataformas: ['Web', 'App móvil'],
    icono: 'shield',
    subdominio: 'plaft.sulotec.com',
    publicado: false,
  },
  {
    nombre: 'Buscador Interno',
    descripcion:
      'Encuentra en segundos la información de tu organización, con búsqueda centralizada y acceso solo para personal autorizado.',
    estado: 'interno',
    plataformas: ['Web'],
    icono: 'search',
    subdominio: 'buscador.sulotec.com',
    publicado: false,
  },
];

export const estados: Record<Estado, string> = {
  produccion: 'En producción',
  implementacion: 'En implementación',
  interno: 'Uso interno',
};

// Enlace de cada producto: su subdominio si ya esta publicado; si no, la seccion de contacto.
export const enlaceDe = (s: Solucion) => (s.publicado ? `https://${s.subdominio}` : '#contacto');
