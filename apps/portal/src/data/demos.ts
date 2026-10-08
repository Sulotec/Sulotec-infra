// Datos de EJEMPLO para las demos publicas. Todo es ficticio: nombres, expedientes, empresas y cifras.
// Nunca poner aqui datos reales de clientes.

// ---------- Cuentas Sulotec (Keycloak en cuenta.sulotec.com) ----------
// activa: false -> no se muestra "Iniciar sesion" y la invitacion ofrece avisar por correo.
// registro: false -> no se ofrece "Crear cuenta" (se enciende cuando cuenta.sulotec.com tenga correo de salida).
// En GitHub: variables CUENTA_ACTIVA y CUENTA_REGISTRO (ver .github/workflows/portal.yml).
// Para probar en local: PUBLIC_CUENTA_ACTIVA=true PUBLIC_CUENTA_EMISOR=http://localhost:8180/realms/sulotec npm run build
export const cuenta = {
  activa: import.meta.env.PUBLIC_CUENTA_ACTIVA === 'true',
  registro: import.meta.env.PUBLIC_CUENTA_REGISTRO === 'true',
  emisor: import.meta.env.PUBLIC_CUENTA_EMISOR || 'https://cuenta.sulotec.com/realms/sulotec',
  cliente: 'portal',
};

// Visitante sin sesion: recorre las demos libremente `segundos` (sumados entre todas las demos);
// despues debe iniciar sesion para seguir. Cada `acciones` opciones bloqueadas se le invita antes.
// Con sesion: tras `consulta` segundos se le recomienda agendar una consulta (una vez por visita).
export const invitacion = { acciones: 3, segundos: 120, consulta: 60 };

// ---------- MiRadar360 ----------
export type EstadoAsesor = 'visita' | 'ruta' | 'termino';

export interface Asesor {
  id: string;
  nombre: string;
  zona: string;
  estado: EstadoAsesor;
  hechas: number;
  total: number;
  color: string;
  // Recorrido en el mapa (coordenadas del SVG de 600x400)
  ruta: string;
  posicion: [number, number];
}

export const asesores: Asesor[] = [
  { id: 'a1', nombre: 'Lucía R.', zona: 'San Isidro', estado: 'visita', hechas: 3, total: 8, color: '#1b4589',
    ruta: 'M70 320 C 120 280, 150 240, 210 230 S 300 190, 330 140', posicion: [210, 230] },
  { id: 'a2', nombre: 'Carlos M.', zona: 'Miraflores', estado: 'ruta', hechas: 5, total: 9, color: '#ed1c24',
    ruta: 'M520 340 C 470 300, 430 300, 390 260 S 330 230, 300 250', posicion: [390, 260] },
  { id: 'a3', nombre: 'Rosa Q.', zona: 'Surquillo', estado: 'ruta', hechas: 2, total: 7, color: '#12a150',
    ruta: 'M540 60 C 500 100, 470 120, 430 150 S 380 200, 360 190', posicion: [430, 150] },
  { id: 'a4', nombre: 'Diego T.', zona: 'Lince', estado: 'termino', hechas: 6, total: 6, color: '#5474a7',
    ruta: 'M90 70 C 140 100, 170 120, 200 150 S 250 160, 270 120', posicion: [270, 120] },
];

export const estadosAsesor: Record<EstadoAsesor, string> = {
  visita: 'En visita',
  ruta: 'En ruta',
  termino: 'Terminó su ruta',
};

export const eventos = [
  { hora: '10:42', texto: 'Lucía R. llegó a la visita de Av. Javier Prado 1250', tipo: 'llegada' },
  { hora: '10:31', texto: 'Diego T. terminó su ruta del día (6 de 6 visitas)', tipo: 'fin' },
  { hora: '10:18', texto: 'Carlos M. registró evidencia con foto y GPS', tipo: 'evidencia' },
  { hora: '09:57', texto: 'Rosa Q. reprogramó una visita: cliente no se encontraba', tipo: 'reprogramada' },
];

// ---------- Auditoria de Visitas ----------
export type ResultadoVisita = 'verificada' | 'fuera' | 'pendiente';

export interface VisitaAuditada {
  id: string;
  cliente: string;
  direccion: string;
  auditor: string;
  hora: string;
  resultado: ResultadoVisita;
  distancia: number; // metros entre el domicilio y el punto real de la visita
  punto: [number, number]; // posicion del punto de la visita en el mapa (SVG 320x220; geocerca centrada en 160,110 con radio 70)
  controles: { texto: string; ok: boolean | null }[];
}

export const visitas: VisitaAuditada[] = [
  {
    id: 'EXP-2041', cliente: 'Comercial Los Andes (demo)', direccion: 'Jr. Ica 455, Lima', auditor: 'Lucía R.', hora: '09:14',
    resultado: 'verificada', distancia: 42, punto: [178, 96],
    controles: [
      { texto: 'Ubicación dentro de la geocerca (300 m)', ok: true },
      { texto: 'Foto del domicilio con fecha y hora', ok: true },
      { texto: 'Firma del cliente', ok: true },
      { texto: 'Precisión del GPS menor a 100 m', ok: true },
    ],
  },
  {
    id: 'EXP-2042', cliente: 'Bodega San Martín (demo)', direccion: 'Av. Brasil 2140, Pueblo Libre', auditor: 'Carlos M.', hora: '10:02',
    resultado: 'fuera', distancia: 860, punto: [286, 40],
    controles: [
      { texto: 'Ubicación dentro de la geocerca (300 m)', ok: false },
      { texto: 'Foto del domicilio con fecha y hora', ok: true },
      { texto: 'Firma del cliente', ok: true },
      { texto: 'Precisión del GPS menor a 100 m', ok: true },
    ],
  },
  {
    id: 'EXP-2043', cliente: 'Taller Mecánico Rímac (demo)', direccion: 'Av. Tacna 610, Rímac', auditor: 'Rosa Q.', hora: '—',
    resultado: 'pendiente', distancia: 0, punto: [160, 110],
    controles: [
      { texto: 'Ubicación dentro de la geocerca (300 m)', ok: null },
      { texto: 'Foto del domicilio con fecha y hora', ok: null },
      { texto: 'Firma del cliente', ok: null },
      { texto: 'Precisión del GPS menor a 100 m', ok: null },
    ],
  },
];

export const resultadosVisita: Record<ResultadoVisita, string> = {
  verificada: 'Visita verificada',
  fuera: 'Fuera de la geocerca',
  pendiente: 'Pendiente de visita',
};

// ---------- Prevencion de Lavado de Activos ----------
export const evaluacion = {
  cliente: 'Inversiones Pacífico Sur S.A.C. (demo)',
  ruc: '20600000001',
  riesgo: 58, // 0 a 100
  nivel: 'Medio',
  verificaciones: [
    { texto: 'Listas restrictivas nacionales e internacionales', resultado: 'Sin coincidencias', estado: 'ok' },
    { texto: 'Persona expuesta políticamente (PEP)', resultado: 'No es PEP', estado: 'ok' },
    { texto: 'Operaciones en efectivo de los últimos 6 meses', resultado: '2 operaciones inusuales', estado: 'alerta' },
    { texto: 'Actividad económica declarada', resultado: 'Riesgo medio del sector', estado: 'revisar' },
  ],
  historial: [
    { fecha: '02/10/2026', resultado: 'Riesgo medio', responsable: 'Oficial de cumplimiento' },
    { fecha: '14/07/2026', resultado: 'Riesgo bajo', responsable: 'Oficial de cumplimiento' },
  ],
};
