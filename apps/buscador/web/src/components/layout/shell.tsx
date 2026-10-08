'use client';
// Armazon de la aplicacion: menu lateral (cajon en celular) + cabecera con usuario y saldo de tokens.
import clsx from 'clsx';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useState, type ReactNode } from 'react';
import {
  Building2, ClipboardList, Coins, FileSpreadsheet, Home, LogOut, Menu, ShieldAlert, UserSearch, Users, X,
} from 'lucide-react';
import { Marca } from './marca';
import { useSesion } from '@/modulos/sesion/proveedor';
import { Aviso, Cargando } from '@/components/ui';

interface Enlace { href: string; texto: string; icono: ReactNode; clave?: string }
interface Grupo { titulo?: string; clave?: string; soloAdmin?: boolean; enlaces: Enlace[] }

const GRUPOS: Grupo[] = [
  { enlaces: [{ href: '/inicio', texto: 'Inicio', icono: <Home className="size-[18px]" /> }] },
  {
    titulo: 'Personas', clave: 'persona',
    enlaces: [
      { href: '/personas', texto: 'Consulta individual', icono: <UserSearch className="size-[18px]" /> },
      { href: '/personas/masiva', texto: 'Carga masiva', icono: <FileSpreadsheet className="size-[18px]" /> },
    ],
  },
  {
    titulo: 'Empresas', clave: 'empresa',
    enlaces: [
      { href: '/empresas', texto: 'Consulta individual', icono: <Building2 className="size-[18px]" /> },
      { href: '/empresas/masiva', texto: 'Carga masiva', icono: <FileSpreadsheet className="size-[18px]" /> },
    ],
  },
  {
    titulo: 'Administración', soloAdmin: true,
    enlaces: [
      { href: '/admin/usuarios', texto: 'Usuarios y tokens', icono: <Users className="size-[18px]" /> },
      { href: '/admin/auditoria', texto: 'Auditoría', icono: <ClipboardList className="size-[18px]" /> },
    ],
  },
];

function Navegacion({ alNavegar }: { alNavegar?: () => void }) {
  const ruta = usePathname();
  const { esAdmin, rutasMenu } = useSesion();
  // La base define que secciones ve cada rol; si no se pudo leer, se muestran las de consulta.
  const visible = (g: Grupo) =>
    g.soloAdmin ? esAdmin : !g.clave || esAdmin || !rutasMenu || rutasMenu.some((r) => r.includes(g.clave!));

  return (
    <nav aria-label="Principal" className="flex flex-col gap-5">
      {GRUPOS.filter(visible).map((g, i) => (
        <div key={g.titulo ?? i}>
          {g.titulo && <p className="mb-1.5 px-3 text-[11px] font-semibold tracking-wide text-azul-50">{g.titulo}</p>}
          <ul className="flex flex-col gap-0.5">
            {g.enlaces.map((e) => {
              const activo = e.href === '/personas' || e.href === '/empresas' ? ruta === e.href : ruta.startsWith(e.href);
              return (
                <li key={e.href}>
                  <Link
                    href={e.href} onClick={alNavegar} aria-current={activo ? 'page' : undefined}
                    className={clsx(
                      'flex items-center gap-3 rounded-lg px-3 py-2 text-sm transition-colors',
                      activo ? 'bg-white font-semibold text-azul shadow-[inset_3px_0_0_var(--color-rojo)]' : 'text-azul-25 hover:bg-white/8 hover:text-white',
                    )}
                  >
                    {e.icono}{e.texto}
                  </Link>
                </li>
              );
            })}
          </ul>
        </div>
      ))}
    </nav>
  );
}

function Saldo() {
  const { saldo } = useSesion();
  if (!saldo) return null;
  return (
    <span className={clsx('numeros inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold',
      saldo.ilimitado ? 'bg-azul-10 text-azul' : saldo.saldo > 0 ? 'bg-verde-10 text-verde' : 'bg-peligro-10 text-peligro')}
      title="Cada consulta descuenta tokens">
      <Coins className="size-3.5" aria-hidden />
      {saldo.ilimitado ? 'Tokens ilimitados' : `${saldo.saldo.toLocaleString('es-PE')} tokens`}
    </span>
  );
}

export function Shell({ children }: { children: ReactNode }) {
  const { usuario, esAdmin, error, salir } = useSesion();
  const [abierto, setAbierto] = useState(false);
  const ruta = usePathname();
  useEffect(() => setAbierto(false), [ruta]);

  const lateral = (
    <div className="flex h-full flex-col gap-8 px-3 py-5">
      <div className="px-2"><Marca /></div>
      <Navegacion alNavegar={() => setAbierto(false)} />
      <p className="mt-auto px-3 text-[11px] leading-relaxed text-azul-50">
        Uso interno. Cada consulta queda registrada en la auditoría.
      </p>
    </div>
  );

  return (
    <div className="min-h-dvh lg:grid lg:grid-cols-[256px_1fr]">
      <aside className="sticky top-0 hidden h-dvh overflow-y-auto bg-azul-noche lg:block">{lateral}</aside>

      {/* Cajon en celular y tablet */}
      <div className={clsx('fixed inset-0 z-40 lg:hidden', abierto ? 'visible' : 'invisible')} aria-hidden={!abierto}>
        <div className={clsx('absolute inset-0 bg-azul-noche/60 transition-opacity', abierto ? 'opacity-100' : 'opacity-0')} onClick={() => setAbierto(false)} />
        <aside className={clsx('absolute inset-y-0 left-0 w-72 max-w-[85%] overflow-y-auto bg-azul-noche transition-transform', abierto ? 'translate-x-0' : '-translate-x-full')}>
          <button onClick={() => setAbierto(false)} className="absolute right-3 top-4 rounded-md p-1.5 text-azul-25 hover:bg-white/10" aria-label="Cerrar menú"><X className="size-5" /></button>
          {lateral}
        </aside>
      </div>

      <div className="min-w-0">
        <header className="sticky top-0 z-30 flex h-16 items-center gap-3 border-b border-borde bg-fondo/90 px-4 backdrop-blur sm:px-6">
          <button onClick={() => setAbierto(true)} className="rounded-md p-2 text-azul hover:bg-azul-10 lg:hidden" aria-label="Abrir menú"><Menu className="size-5" /></button>
          <div className="lg:hidden"><Link href="/inicio" className="font-bold text-azul">Buscador</Link></div>
          <div className="ml-auto flex items-center gap-3">
            <Saldo />
            {usuario && (
              <div className="hidden text-right leading-tight sm:block">
                <p className="text-sm font-semibold text-texto">{usuario.nombreCompleto}</p>
                <p className="text-xs text-gris">{esAdmin ? 'Administrador General' : usuario.roles.map((r) => r.rol).join(', ') || usuario.usuario}</p>
              </div>
            )}
            <button onClick={salir} className="inline-flex items-center gap-2 rounded-lg px-3 py-2 text-sm font-semibold text-gris hover:bg-azul-10 hover:text-azul" title="Cerrar sesión">
              <LogOut className="size-4" /><span className="hidden md:inline">Salir</span>
            </button>
          </div>
        </header>

        <main id="contenido" className="mx-auto w-full max-w-7xl px-4 py-6 sm:px-6 lg:py-8">
          {error?.fueraDeSede ? (
            <div className="mx-auto max-w-xl py-16">
              <Aviso tono="alerta"><p className="flex items-center gap-2 font-semibold"><ShieldAlert className="size-4" />Acceso solo desde las sedes</p><p className="mt-1">{error.message}</p></Aviso>
            </div>
          ) : !usuario ? <Cargando texto="Cargando tu sesión…" /> : children}
        </main>
      </div>
    </div>
  );
}
