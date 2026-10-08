// Servicio de empresas: consulta por RUC y por razon social.
import { api } from '@/lib/api';
import type { ResultadoEmpresa } from './tipos';

export const servicioEmpresas = {
  porRuc: (ruc: string) => api.get<ResultadoEmpresa | null>(`api/empresa/individual/${encodeURIComponent(ruc)}`),
  porRazonSocial: (texto: string) => api.get<ResultadoEmpresa | null>(`api/empresa/razon-social/${encodeURIComponent(texto)}`),
};
