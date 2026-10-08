// Servicio de administracion (solo ADMIN GENERAL): usuarios, roles, tokens y auditoria.
import { api } from '@/lib/api';
import type { SaldoTokens } from '@/modulos/sesion/tipos';
import type { CrearUsuario, MovimientoToken, Pagina, RegistroAuditoria, RolListado, UsuarioCreado, UsuarioListado } from './tipos';

const consulta = (p: Record<string, string | number | undefined>) =>
  new URLSearchParams(Object.entries(p).filter(([, v]) => v !== undefined && v !== '').map(([k, v]) => [k, String(v)])).toString();

export interface FiltroAuditoria { desde?: string; hasta?: string; usuario?: string; accion?: string; pagina: number; tamano: number }

export const servicioAdmin = {
  usuarios: (texto: string, pagina: number, tamano: number) =>
    api.get<Pagina<UsuarioListado>>(`system/usuarios?${consulta({ texto: texto.trim(), pagina, tamano })}`),
  roles: () => api.get<RolListado[]>('system/usuarios/roles'),
  crear: (datos: CrearUsuario) => api.post<UsuarioCreado>('system/usuarios', datos),
  cambiarEstado: (codUsuario: number, activo: boolean) => api.put<void>(`system/usuarios/${codUsuario}/estado`, { activo }),
  cambiarRoles: (codUsuario: number, codRoles: number[]) => api.put<void>(`system/usuarios/${codUsuario}/roles`, { codRoles }),
  cerrarSesiones: (codUsuario: number) => api.post<void>(`system/usuarios/${codUsuario}/cerrar-sesiones`),
  asignarTokens: (codUsuario: number, cantidad: number, motivo: string) =>
    api.post<SaldoTokens>('system/tokens/asignar', { codUsuario, cantidad, motivo }),
  movimientos: (codUsuario: number, top = 30) => api.get<MovimientoToken[]>(`system/tokens/${codUsuario}/movimientos?top=${top}`),
  auditoria: (f: FiltroAuditoria) => api.get<Pagina<RegistroAuditoria>>(`system/auditoria?${consulta({ ...f })}`),
};
