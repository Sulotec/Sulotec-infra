import type { IconName } from '../components/Icon.astro';
import type { RedSocial } from '../components/IconoRed.astro';

// Datos generales del sitio. Cambia aqui textos, correo, menu y secciones; los componentes solo los muestran.
export const sitio = {
  nombre: 'Sulotec',
  url: 'https://sulotec.com',
  correo: 'contacto@sulotec.com',
  ciudad: 'Lima, Perú',
  // Pagina de la cuenta de cada persona (cambiar contrasena, datos): Keycloak en cuenta.sulotec.com
  cuentaUrl: 'https://cuenta.sulotec.com/realms/sulotec/account',
  // Redes sociales: pega el link completo en "url" y el icono aparece solo en el pie de pagina.
  // Las que queden vacias no se muestran.
  redes: [
    { red: 'linkedin', nombre: 'LinkedIn', url: '' },
    { red: 'facebook', nombre: 'Facebook', url: '' },
    { red: 'instagram', nombre: 'Instagram', url: '' },
    { red: 'youtube', nombre: 'YouTube', url: '' },
    { red: 'tiktok', nombre: 'TikTok', url: '' },
    { red: 'x', nombre: 'X', url: '' },
    { red: 'whatsapp', nombre: 'WhatsApp', url: '' },
  ] as { red: RedSocial; nombre: string; url: string }[],
  titulo: 'Sulotec | Soluciones digitales para tu operación',
  descripcion:
    'Plataformas seguras en la nube para monitorear equipos en campo, auditar visitas y prevenir el lavado de activos.',
  menu: [
    { texto: 'Soluciones', href: '#soluciones' },
    { texto: 'Cómo trabajamos', href: '#metodologia' },
    { texto: 'Por qué Sulotec', href: '#pilares' },
  ],
  portada: {
    etiqueta: 'Ecosistema de soluciones en la nube',
    titulo: { antes: 'Soluciones digitales que ', resalte: 'se adaptan', despues: ' a tu operación' },
    texto:
      'Monitorea a tus equipos en campo, audita cada visita y cumple la normativa PLAFT. Todo en un solo lugar, en la web y en el celular.',
  },
  // Franja en movimiento bajo la portada
  capacidades: [
    'Monitoreo en tiempo real',
    'Geolocalización',
    'Evidencias fotográficas',
    'Firma digital',
    'Trabajo sin conexión',
    'Apps Android e iOS',
    'Cifrado de datos',
    'Copias de seguridad diarias',
    'Acceso con verificación',
  ],
};

export interface Paso {
  titulo: string;
  texto: string;
  icono: IconName;
}

export const pasos: Paso[] = [
  { titulo: 'Diagnóstico', texto: 'Entendemos tu operación e identificamos riesgos y necesidades.', icono: 'clipboard' },
  { titulo: 'Implementación', texto: 'Ponemos en marcha la solución, integrada a tus procesos y sistemas.', icono: 'gear' },
  { titulo: 'Mejora continua', texto: 'Medimos, ajustamos y capacitamos a tu equipo para sacarle el máximo.', icono: 'refresh' },
];

export const pilares: Paso[] = [
  { titulo: 'Seguridad', texto: 'Controles basados en ISO/IEC 27001, cifrado en tránsito y en reposo, y servidores sin puertos expuestos.', icono: 'lock' },
  { titulo: 'Nube', texto: 'Infraestructura 100% en la nube con copias de seguridad diarias fuera del servidor principal.', icono: 'cloud' },
  { titulo: 'Movilidad', texto: 'Apps para Android e iOS que funcionan en campo y se actualizan al instante.', icono: 'phone' },
  { titulo: 'Integración', texto: 'Plataformas modulares con APIs que se conectan a tus sistemas, sin rehacer tu operación.', icono: 'plug' },
];
