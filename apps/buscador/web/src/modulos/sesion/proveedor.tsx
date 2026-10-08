'use client';
// Sesion compartida por todas las pantallas: usuario, roles, saldo de tokens y menu permitido.
import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';
import { ErrorApi } from '@/lib/api';
import { servicioSesion } from './servicio';
import type { MenuRuta, SaldoTokens, Sesion, Usuario } from './tipos';

export const ROL_TOTAL = 'ADMIN GENERAL';

interface Contexto {
  usuario: Usuario | null;
  esAdmin: boolean;
  saldo: SaldoTokens | null;
  rutasMenu: string[] | null; // rutas habilitadas por la base (null = no se pudo leer)
  error: ErrorApi | null;
  actualizarSaldo: () => void;
  salir: () => Promise<void>;
}

const SesionContexto = createContext<Contexto | null>(null);

function aplanar(menu: MenuRuta[]): string[] {
  return menu.flatMap((m) => [m.ruta ?? '', ...aplanar(m.children ?? [])]).filter(Boolean).map((r) => r.toLowerCase());
}

export function ProveedorSesion({ children }: { children: ReactNode }) {
  const [usuario, setUsuario] = useState<Usuario | null>(null);
  const [saldo, setSaldo] = useState<SaldoTokens | null>(null);
  const [rutasMenu, setRutasMenu] = useState<string[] | null>(null);
  const [error, setError] = useState<ErrorApi | null>(null);

  const actualizarSaldo = useCallback(() => {
    servicioSesion.saldo().then(setSaldo).catch(() => setSaldo(null));
  }, []);

  useEffect(() => {
    servicioSesion.actual()
      .then((s) => {
        setUsuario(s.usuario);
        actualizarSaldo();
        servicioSesion.menu().then((m) => setRutasMenu(aplanar(m ?? []))).catch(() => setRutasMenu(null));
      })
      .catch((e: ErrorApi) => setError(e));
  }, [actualizarSaldo]);

  const salir = useCallback(async () => {
    await servicioSesion.salir().catch(() => null);
    location.href = '/auth/login';
  }, []);

  const esAdmin = Boolean(usuario?.roles.some((r) => r.rol.toUpperCase() === ROL_TOTAL));

  return (
    <SesionContexto.Provider value={{ usuario, esAdmin, saldo, rutasMenu, error, actualizarSaldo, salir }}>
      {children}
    </SesionContexto.Provider>
  );
}

export function useSesion() {
  const c = useContext(SesionContexto);
  if (!c) throw new Error('useSesion fuera de ProveedorSesion');
  return c;
}
