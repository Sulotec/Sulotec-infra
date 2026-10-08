// Marco de las pantallas de acceso (login y recuperacion): panel de marca + formulario.
import { Lock, MapPin, ShieldCheck } from 'lucide-react';
import type { ReactNode } from 'react';
import { Marca } from './marca';

export function MarcoAcceso({ titulo, bajada, children }: { titulo: string; bajada: string; children: ReactNode }) {
  return (
    <div className="grid min-h-dvh lg:grid-cols-[1.05fr_1fr]">
      <aside className="relative hidden overflow-hidden bg-azul-noche p-12 text-white lg:flex lg:flex-col">
        <div className="absolute inset-0 opacity-[.07] [background-image:linear-gradient(#fff_1px,transparent_1px),linear-gradient(90deg,#fff_1px,transparent_1px)] [background-size:44px_44px]" aria-hidden />
        <div className="absolute -right-32 -top-32 size-[28rem] rounded-full bg-azul-claro/30 blur-3xl" aria-hidden />
        <div className="relative"><Marca /></div>
        <div className="relative mt-auto max-w-md">
          <p className="text-3xl font-semibold leading-tight tracking-tight">Consultas de personas y empresas, en un solo lugar.</p>
          <ul className="mt-8 space-y-3 text-sm text-azul-25">
            <li className="flex items-center gap-3"><ShieldCheck className="size-4 text-white" />Cada consulta queda registrada en la auditoría.</li>
            <li className="flex items-center gap-3"><MapPin className="size-4 text-white" />Disponible desde las sedes de Lince y Los Olivos.</li>
            <li className="flex items-center gap-3"><Lock className="size-4 text-white" />Información interna y confidencial.</li>
          </ul>
        </div>
        <svg className="absolute -bottom-1 left-0 w-full" viewBox="0 0 600 60" preserveAspectRatio="none" aria-hidden>
          <path d="M0 60V38C160 6 330 64 600 18V60Z" fill="#eef2f8" /><path d="M0 38C160 6 330 64 600 18" fill="none" stroke="#ed1c24" strokeWidth="4" />
        </svg>
      </aside>
      <main className="flex items-center justify-center px-5 py-12">
        <div className="w-full max-w-sm">
          <div className="mb-8 lg:hidden"><Marca claro={false} /></div>
          <h1 className="text-2xl font-semibold tracking-tight text-texto">{titulo}</h1>
          <p className="mt-1.5 text-sm text-gris">{bajada}</p>
          <div className="mt-8">{children}</div>
        </div>
      </main>
    </div>
  );
}
