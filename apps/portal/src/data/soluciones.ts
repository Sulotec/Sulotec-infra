import type { IconName } from '../components/Icon.astro';

// Una entrada por producto. La tarjeta, el pie de pagina y todo lo demas se generan desde aqui.
// - Para agregar un producto nuevo: copia un bloque completo ({ ... },) y cambia sus datos.
// - `publico: false` = producto privado de la empresa: NO aparece en el portal (ej. Buscador Interno).
// - Para enlazar YA a la direccion donde hoy funciona el producto, agrega `url: 'https://...'`.
// - Cuando un producto ya este en linea en su subdominio, cambia `publicado: false` a `true`:
//   el boton de la tarjeta pasa de "Solicitar informacion" a "Ingresar" y lleva a https://<subdominio>.
export type Estado = 'produccion' | 'implementacion' | 'interno';

export interface Solucion {
  nombre: string;
  descripcion: string;
  estado: Estado;
  plataformas: string[];
  icono: IconName;
  publico: boolean;    // false = privado de la empresa, no se muestra en el portal
  subdominio: string; // reservado en Cloudflare para este producto
  publicado: boolean;
  url?: string;       // opcional: direccion actual del producto mientras se muda a su subdominio
}

export const soluciones: Solucion[] = [
  {
    nombre: 'MiRadar360',
    descripcion:
      'Torre de control para tus equipos en campo: rutas del día, estado de cada visita y monitoreo en tiempo real, con evidencias GPS y fotos desde el celular.',
    estado: 'produccion',
    plataformas: ['Web', 'Android', 'iOS'],
    icono: 'radar',
    publico: true,
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
    publico: true,
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
    publico: true,
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
    publico: false, // privado: solo administradores generales (Cloudflare Access)
    subdominio: 'buscadorinterno.sulotec.com',
    publicado: false,
  },
];

export const estados: Record<Estado, string> = {
  produccion: 'En producción',
  implementacion: 'En implementación',
  interno: 'Uso interno',
};

// Enlace de cada producto: su `url` actual si la tiene; si no, su subdominio si ya esta publicado;
// si no, la seccion de contacto.
export const tieneAcceso = (s: Solucion) => Boolean(s.url) || s.publicado;
export const enlaceDe = (s: Solucion) => s.url ?? (s.publicado ? `https://${s.subdominio}` : '#contacto');

// Solo los productos publicos se muestran en el portal.
export const solucionesPublicas = soluciones.filter((s) => s.publico);
