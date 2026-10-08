// Servicio de personas: consulta por DNI, por telefono y datos RENIEC.
import { api } from '@/lib/api';
import type { ResultadoPersona, ResultadoReniec, ResultadoTelefono } from './tipos';

export const servicioPersonas = {
  porDni: (dni: string) => api.post<ResultadoPersona>('api/buscador/buscar', { documento: dni, tipoDocumento: 'DNI' }),
  porTelefono: (telefono: string) => api.post<ResultadoTelefono>('api/buscador/buscar-telefono', { telefono }),
  reniec: (dni: string) => api.get<ResultadoReniec>(`api/buscador/reniec/${encodeURIComponent(dni)}`),
};
