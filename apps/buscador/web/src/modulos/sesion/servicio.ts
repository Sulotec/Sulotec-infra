// Servicio de sesion: inicio, recuperacion de contrasena, usuario actual, saldo y menu.
import { api } from '@/lib/api';
import type { MenuRuta, SaldoTokens, Sesion } from './tipos';

export const servicioSesion = {
  iniciar: (usuario: string, clave: string) => api.post<Sesion>('system/auth/login', { UsuarioLogin: usuario, Clave: clave }),
  olvide: (identificador: string) => api.post<{ message: string }>('system/auth/forgot-password', { identificador }),
  restablecer: (token: string, nuevaClave: string) => api.post<{ message: string }>('system/auth/reset-password', { token, nuevaClave }),
  actual: () => api.get<Sesion>('system/auth/check-status'),
  saldo: () => api.get<SaldoTokens>('system/tokens/mi-saldo'),
  menu: () => api.get<MenuRuta[]>('system/home/get-routes'),
  salir: () => fetch('/sesion/salir', { method: 'POST' }),
};
