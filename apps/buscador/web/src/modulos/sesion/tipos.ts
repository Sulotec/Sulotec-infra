// Tipos del modulo sesion (mismo contrato que la API del Buscador).

export interface Rol { codigoRol: number; rol: string }

export interface Usuario { id: number; usuario: string; nombreCompleto: string; roles: Rol[] }

export interface Sesion { estado: number; usuario: Usuario }

export interface SaldoTokens { codUsuario: number; ilimitado: boolean; saldo: number }

export interface MenuRuta {
  codMenu: number;
  codMenuPadre: number | null;
  nomMenu: string;
  ruta: string;
  icono: string;
  orden: number;
  puedeVer: number;
  children: MenuRuta[];
}
