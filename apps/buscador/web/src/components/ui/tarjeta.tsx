'use client';
import clsx from 'clsx';
import { type ReactNode } from "react";

export function Tarjeta({ titulo, accion, children, className, sinRelleno }:
  { titulo?: ReactNode; accion?: ReactNode; children: ReactNode; className?: string; sinRelleno?: boolean }) {
  return (
    <section className={clsx('rounded-xl border border-borde bg-white shadow-tarjeta', className)}>
      {(titulo || accion) && (
        <header className="flex flex-wrap items-center justify-between gap-3 border-b border-borde px-5 py-3.5">
          {typeof titulo === 'string' ? <h2 className="text-base font-semibold text-texto">{titulo}</h2> : titulo}
          {accion}
        </header>
      )}
      <div className={clsx(!sinRelleno && 'p-5')}>{children}</div>
    </section>
  );
}

type TonoChip = 'neutro' | 'azul' | 'verde' | 'ambar' | 'peligro';
const TONOS: Record<TonoChip, string> = {
  neutro: 'bg-fondo text-gris', azul: 'bg-azul-10 text-azul', verde: 'bg-verde-10 text-verde',
  ambar: 'bg-ambar-10 text-ambar', peligro: 'bg-peligro-10 text-peligro',
};

export function Encabezado({ titulo, bajada, accion }: { titulo: string; bajada?: string; accion?: ReactNode }) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight text-texto sm:text-[1.7rem]">{titulo}</h1>
        {bajada && <p className="mt-1 max-w-2xl text-sm text-gris">{bajada}</p>}
      </div>
      {accion}
    </div>
  );
}
